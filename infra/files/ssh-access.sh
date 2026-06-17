#!/usr/bin/env bash
# ssh-access.sh — converge identity-aware SSH for THIS host through Pangolin's
# auth-daemon, headlessly and idempotently. Runs ON the box (uploaded by the
# Terraform `ssh_access` resource). Safe to re-run; safe alongside normal SSH.
#
# Order of operations (each step is idempotent):
#   1. Install a pinned `newt` (the site connector + SSH auth-daemon).
#   2. Ensure a Pangolin "site" for this host exists; persist its newt
#      credentials to /etc/newt/newt.env (root 600) so re-runs reuse them
#      instead of rotating the secret.
#   3. Run newt as a systemd service. In newt >= 1.13 the auth-daemon is on by
#      default; once SSH is active for the site it writes the org CA public key
#      to /etc/ssh/ca.pem.
#   4. Declare the SSH resources via a Pangolin Blueprint (additive/upsert by
#      niceId — never deletes the site/roles/IdP): a PRIVATE resource (alias
#      <site>.internal) and, if a public domain is given, a PUBLIC browser-SSH
#      resource on that domain — both granting the chosen roles.
#   5. Add an ADDITIVE sshd drop-in trusting that CA and asking newt for the
#      principals a user is allowed. Written PROACTIVELY — newt fills in
#      /etc/ssh/ca.pem lazily on the first connection, and sshd tolerates the
#      not-yet-existent file. Validated with `sshd -t`, applied with `reload`
#      (never `restart`), rolled back if the config test fails. Existing
#      password/key auth is never touched: AuthorizedPrincipalsCommand is
#      consulted only during certificate auth.
#
# LICENSE GATE: Pangolin serves SSH private resources only on the Enterprise
# Edition with a registered license key (free for personal use / businesses
# under USD 100k revenue). Until a key is active at the dashboard's
# /admin/license, step 4 returns HTTP 403 and this script stops cleanly with a
# message. Steps 1-3 still converge, so a re-run after licensing finishes the
# job. The web SSO/IdP/RBAC stack is NOT gated — only SSH is.
#
# Usage: ssh-access.sh <stack_dir> <newt_version> <site_name> <ssh_roles_csv> [public_domain] [sudo_cmds]
#   ssh_roles_csv: comma/space list of role NAMES granted SSH (Admin is implicit).
#   public_domain: optional FQDN for a public browser-SSH resource (e.g.
#                  shell.tyo.example.com); empty = private resource only.
#   sudo_cmds:     optional comma/space list of absolute command paths the SSH
#                  roles may sudo (e.g. /usr/sbin/ufw); empty = no sudo.
set -euo pipefail

STACK_DIR=${1:?stack_dir}
NEWT_VERSION=${2:?newt_version}
SITE_NAME=${3:?site_name}
SSH_ROLES=${4:-}
SSH_PUBLIC_DOMAIN=${5:-}
SSH_SUDO_CMDS=${6:-}
RES_NICE=${SITE_NAME}-ssh           # niceId for the private SSH resource
PUB_NICE=${SITE_NAME}-browser-ssh   # niceId for the public browser-SSH resource

# Self-elevate per-command so this works as root or as a sudo user, with no
# external `become` plumbing (keeps the Terraform wiring committable as-is).
SUDO=""
[ "$(id -u)" -eq 0 ] || SUDO="sudo"

# Pangolin creds/org/endpoint come from the stack's sso.conf (already on the
# box from the configure step); the HTTP plumbing (pang/pang_login) is reused
# from lib/pang-bootstrap.sh rather than reimplemented.
set -a; . "$STACK_DIR/sso.conf"; set +a
# shellcheck source=/dev/null
. "$STACK_DIR/lib/pang-bootstrap.sh"

log() { printf '%s\n' "$*" >&2; }

# --- 1. newt binary --------------------------------------------------------
newt_install() {
  if command -v newt >/dev/null 2>&1 && newt version 2>/dev/null | grep -qw "$NEWT_VERSION"; then
    log "= newt $NEWT_VERSION already installed"; return
  fi
  local narch
  case "$(uname -m)" in
    x86_64|amd64) narch=amd64 ;;
    aarch64|arm64) narch=arm64 ;;
    *) log "!! unsupported arch $(uname -m) for a pinned newt build"; return 1 ;;
  esac
  local url="https://github.com/fosrl/newt/releases/download/${NEWT_VERSION}/newt_linux_${narch}"
  local tmp; tmp=$(mktemp)
  curl -fsSL -o "$tmp" "$url"
  $SUDO install -m 755 "$tmp" /usr/local/bin/newt
  rm -f "$tmp"
  log "+ installed newt $NEWT_VERSION ($narch)"
}

# --- 2. Pangolin site + persisted newt credentials -------------------------
site_ensure() {
  local sid
  sid=$(pang GET "/org/${PANGOLIN_ORG_ID}/sites" '^200$' \
    | jq -r --arg n "$SITE_NAME" '.data.sites[]? | select(.name==$n).siteId' | head -n1)

  # Reuse only when BOTH the site and our saved secret exist; a site without
  # the secret (e.g. created out-of-band) is unusable, so recreate it.
  if [[ -n $sid ]] && $SUDO test -f /etc/newt/newt.env; then
    log "= pangolin site $SITE_NAME (id $sid), creds present"
    return
  fi
  if [[ -n $sid ]]; then
    log "~ site $SITE_NAME exists but local secret is missing — recreating"
    pang DELETE "/site/${sid}" '^200$' >/dev/null
  fi

  # Pangolin's auto address-allocation for a newt site stores a BARE ip (it
  # strips the CIDR: createSite.ts `address.split("/")[0]`), which newt's client
  # interface rejects ("invalid IP address format"). Passing an explicit address
  # takes the branch that stores it WITH the org-subnet mask, which newt accepts.
  # Pick a low host in the org's client subnet (avoid the .0 network base).
  local org_subnet base a b c d addr
  org_subnet=$(pang GET /orgs '^200$' \
    | jq -r --arg o "$PANGOLIN_ORG_ID" '.data.orgs[]? | select(.orgId==$o).subnet')
  [[ $org_subnet == */* ]] || { log "!! could not read org subnet for site address"; return 1; }
  base=${org_subnet%/*}
  IFS=. read -r a b c d <<< "$base"
  addr="$a.$b.$c.$((d + 2))"

  local resp newtId secret
  resp=$(pang PUT "/org/${PANGOLIN_ORG_ID}/site" '^20[01]$' \
    "$(jq -nc --arg n "$SITE_NAME" --arg a "$addr" '{name:$n, type:"newt", address:$a}')")
  newtId=$(echo "$resp" | jq -r '.data.newtId')
  secret=$(echo "$resp" | jq -r '.data.secret')
  [[ -n $newtId && -n $secret && $secret != null ]] \
    || { log "!! site create did not return credentials: $resp"; return 1; }

  $SUDO install -d -m 700 /etc/newt
  printf 'PANGOLIN_ENDPOINT=%s\nNEWT_ID=%s\nNEWT_SECRET=%s\n' \
    "$PANGOLIN_DASHBOARD_URL" "$newtId" "$secret" | $SUDO tee /etc/newt/newt.env >/dev/null
  $SUDO chmod 600 /etc/newt/newt.env
  # newt persists its identity to ~/.config/newt-client/config.json and reads it
  # back on boot; a stale copy pins newt to an old/deleted site (so the server
  # never hands it the SSH CA). Clear it so the service re-registers fresh.
  $SUDO rm -f /root/.config/newt-client/config.json
  log "+ pangolin site $SITE_NAME (newt $newtId), creds saved to /etc/newt/newt.env"
}

# --- 3. newt systemd service -----------------------------------------------
newt_service() {
  $SUDO tee /etc/systemd/system/newt.service >/dev/null <<'UNIT'
[Unit]
Description=Newt (Pangolin site connector + SSH auth-daemon)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/newt/newt.env
ExecStart=/usr/local/bin/newt
Restart=always
RestartSec=5
# auth-daemon runs as root: writes /etc/ssh/ca.pem and JIT-provisions Unix users
User=root
AmbientCapabilities=CAP_NET_ADMIN

[Install]
WantedBy=multi-user.target
UNIT
  $SUDO systemctl daemon-reload
  $SUDO systemctl enable newt >/dev/null 2>&1 || true
  $SUDO systemctl restart newt
  log "= newt.service enabled and (re)started"

  # Wait for the site to report online (control channel up). Non-fatal.
  local i online
  for i in $(seq 1 30); do
    online=$(pang GET "/org/${PANGOLIN_ORG_ID}/sites" '^200$' \
      | jq -r --arg n "$SITE_NAME" '.data.sites[]? | select(.name==$n).online' | head -n1)
    [[ $online == true ]] && { log "= site $SITE_NAME online"; return; }
    sleep 1
  done
  log "!! site $SITE_NAME not online after 30s (check: journalctl -u newt)"
}

# --- 4. Declare SSH resources via a Blueprint (LICENSE-GATED) ---------------
# A blueprint is additive/upsert by niceId — it never deletes the site, roles,
# IdP, or other resources — so it is safe to apply next to the imperative SSO
# setup. Sets SSH_LICENSED=0 (without failing) if Pangolin reports the feature
# isn't in the plan, so the caller stops cleanly.
#   - PRIVATE resource: alias <site>.internal, lands on the host's real OpenSSH
#     (full forwarding/sftp -> VS Code Remote-SSH works). pamMode push forces the
#     Linux user to the SSO identity (identifierPath=preferred_username), JIT.
#   - PUBLIC resource (only when SSH_PUBLIC_DOMAIN is set): browser SSH on that
#     domain, SSO-gated to the same roles.
SSH_LICENSED=0
blueprint_apply() {
  local site_nice port roles_yaml yaml resp
  site_nice=$(pang GET "/org/${PANGOLIN_ORG_ID}/sites" '^200$' \
    | jq -r --arg n "$SITE_NAME" '.data.sites[]? | select(.name==$n).niceId' | head -n1)
  port=$($SUDO sshd -T 2>/dev/null | awk '/^port /{print $2; exit}'); port=${port:-22}
  # role NAMES -> YAML flow list (Admin dropped, it's implicit). sed never trips
  # pipefail the way an empty grep match would.
  roles_yaml=$(printf '%s' "$SSH_ROLES" | tr ', ' '\n' | sed '/^Admin$/d;/^$/d' | paste -sd, -)

  # Built without quotes so there is nothing to escape; values are plain YAML
  # scalars (site niceId, IPs, domains, role names have no YAML metacharacters).
  yaml="private-resources:
  ${RES_NICE}:
    name: ${SITE_NAME} SSH
    mode: ssh
    sites: [ ${site_nice} ]
    destination: 127.0.0.1
    destination-port: ${port}
    alias: ${SITE_NAME}.internal
    auth-daemon: { mode: site, pam: push }
    roles: [ ${roles_yaml} ]"
  if [[ -n $SSH_PUBLIC_DOMAIN ]]; then
    yaml="${yaml}
proxy-resources:
  ${PUB_NICE}:
    name: ${SITE_NAME} browser SSH
    mode: ssh
    full-domain: ${SSH_PUBLIC_DOMAIN}
    ssl: true
    targets:
      - site: ${site_nice}
        hostname: 127.0.0.1
        port: ${port}
    auth: { sso-enabled: true, sso-roles: [ ${roles_yaml} ] }
    auth-daemon: { mode: site, pam: push }"
  fi

  resp=$(pang PUT "/org/${PANGOLIN_ORG_ID}/blueprint" '^(200|201|403)$' \
    "$(jq -nc --arg n "ssh-resources" --arg b "$yaml" '{name:$n, blueprint:$b, source:"API"}')")
  if printf '%s' "$resp" | grep -q 'not included in your current plan'; then
    log ""
    log "================================================================"
    log " SSH is gated behind a Pangolin Enterprise Edition license."
    log " Connector (newt) + site are up; register a (free) key, then re-run:"
    log "   app.pangolin.net -> Licenses, then dashboard -> /admin/license."
    log "================================================================"
    SSH_LICENSED=0; return
  fi
  printf '%s' "$resp" | jq -e '.data.succeeded==true' >/dev/null 2>&1 \
    || { log "!! blueprint apply failed: $resp"; return 1; }
  log "+ blueprint applied: ${RES_NICE} (alias ${SITE_NAME}.internal)${SSH_PUBLIC_DOMAIN:+ + ${PUB_NICE} (${SSH_PUBLIC_DOMAIN})}"
  SSH_LICENSED=1
}

# Install the dev-port firewall helper (root-owned 0755) so a role's scoped sudo
# can point at /usr/local/bin/dev-port instead of raw ufw — devs open/close test
# ports without being able to disable the firewall or touch SSH/privileged ports.
# Uploaded next to this script by Terraform; skipped if absent.
install_dev_port() {
  [[ -f "$STACK_DIR/dev-port" ]] || return 0
  $SUDO install -m 755 -o root -g root "$STACK_DIR/dev-port" /usr/local/bin/dev-port
  log "= installed /usr/local/bin/dev-port (least-privilege firewall helper)"
}

# Roles created via the API start with allowSsh=false — attaching a role to an
# SSH resource grants WEB access but the cert-sign stays 403 until the role
# itself permits SSH. For each granted role set the SSH RBAC: allowSsh, a JIT
# home dir, the matching Unix group (lower-cased role name, e.g. Developer ->
# `developer` — must already exist via apply-host.sh with a fixed GID), and a
# scoped sudo policy. SSH_SUDO_CMDS (comma/space list of absolute command paths,
# e.g. /usr/sbin/ufw) -> sshSudoMode=commands; empty -> no sudo.
#
# Admin is deliberately DISABLED for SSH (see admin_ssh_disable below): being a
# Pangolin management-admin must not imply a sudo-capable shell. SSH requires a
# granted role (e.g. Developer); a user who is only Admin is refused. Idempotent;
# endpoint POST /role/{id}.
role_ssh_enable() {
  local roles_json n id group mode cmds_json
  roles_json=$(pang GET "/org/${PANGOLIN_ORG_ID}/roles" '^200$')
  mode="none"; cmds_json="[]"
  if [[ -n ${SSH_SUDO_CMDS:-} ]]; then
    cmds_json=$(printf '%s' "$SSH_SUDO_CMDS" | tr ', ' '\n' | sed '/^$/d' | jq -R . | jq -sc '.')
    mode="commands"
  fi
  for n in $(printf '%s' "$SSH_ROLES" | tr ', ' '\n' | sed '/^Admin$/d;/^$/d'); do
    id=$(echo "$roles_json" | jq -r --arg n "$n" '.data.roles[]? | select(.name==$n).roleId' | head -n1)
    [[ -n $id && $id != null ]] || { log "!! role '$n' not found, can't enable SSH"; continue; }
    group=$(printf '%s' "$n" | tr 'A-Z' 'a-z')
    # systemd-journal: read access to the journal (`journalctl`) WITHOUT sudo —
    # the standard ops "read the logs" grant. It's a system group (always present),
    # added as a supplementary group alongside the role's own group.
    pang POST "/role/${id}" '^200$' \
      "$(jq -nc --arg g "$group" --arg m "$mode" --argjson c "$cmds_json" \
         '{allowSsh:true, sshCreateHomeDir:true, sshUnixGroups:[$g, "systemd-journal"], sshSudoMode:$m, sshSudoCommands:$c}')" >/dev/null
    log "= role $n: SSH enabled (groups $group+systemd-journal, sudo $mode${SSH_SUDO_CMDS:+ [$SSH_SUDO_CMDS]})"
  done
  admin_ssh_disable "$roles_json"
}

# Decouple management-admin from shell access. Pangolin's cert-sign gate checks
# for the signSshKey roleAction among the user's roles (no isAdmin bypass), and
# allowSsh:false DELETES that action — so a user whose only role is Admin is
# refused (403 "does not have permission"). sshSudoMode:none + empty groups also
# zeroes Admin's contribution to the per-connection sudo: Pangolin takes the MAX
# sudo across a user's resource-granted roles, so without this an admin+developer
# user would silently get FULL sudo via Admin. (EE licensing permits editing the
# built-in Admin role's SSH fields; on an unlicensed org the API ignores them.)
admin_ssh_disable() {
  local roles_json=$1 admin_id
  admin_id=$(echo "$roles_json" | jq -r '.data.roles[]? | select(.name=="Admin").roleId' | head -n1)
  [[ -n $admin_id && $admin_id != null ]] || return 0
  pang POST "/role/${admin_id}" '^200$' \
    '{allowSsh:false, sshSudoMode:"none", sshUnixGroups:[], sshSudoCommands:[]}' >/dev/null
  log "= role Admin: SSH disabled (no signSshKey, no sudo) — SSH requires a granted role"
}

# --- 5. Additive sshd CA drop-in (only once ca.pem is real) ----------------
sshd_dropin() {
  # Written PROACTIVELY: newt writes /etc/ssh/ca.pem lazily on the first SSH
  # connection, so we can't wait for it. sshd tolerates a not-yet-existent
  # TrustedUserCAKeys file (read only at auth time); existing password/key login
  # is unaffected (AuthorizedPrincipalsCommand runs only during cert auth).
  local conf=/etc/ssh/sshd_config.d/10-pangolin-ca.conf
  $SUDO tee "$conf" >/dev/null <<'CONF'
# Managed by machine-bootstrap ssh-access.sh — Pangolin auth-daemon CA trust.
# ADDITIVE: only adds certificate trust. Password/pubkey auth is unchanged;
# AuthorizedPrincipalsCommand is consulted ONLY during certificate auth.
# newt writes /etc/ssh/ca.pem on the first `pangolin ssh` connection.
TrustedUserCAKeys /etc/ssh/ca.pem
AuthorizedPrincipalsCommand /usr/local/bin/newt auth-daemon principals --username %u
AuthorizedPrincipalsCommandUser root
CONF

  if $SUDO sshd -t; then
    $SUDO systemctl reload ssh 2>/dev/null || $SUDO systemctl reload sshd
    log "= sshd CA drop-in applied (reloaded; ca.pem fills in on first connect)"
  else
    $SUDO rm -f "$conf"
    log "!! sshd -t failed — drop-in removed, sshd untouched"
    return 1
  fi
}

main() {
  pang_login
  newt_install
  site_ensure
  newt_service
  blueprint_apply
  if [[ $SSH_LICENSED -eq 1 ]]; then
    install_dev_port
    role_ssh_enable
    sshd_dropin
    log ""
    log "SSH access converged (site mode -> this host's real sshd)."
    log "  Private:  pangolin ssh <sso-user>@${RES_NICE}   (alias ${SITE_NAME}.internal)"
    [[ -n $SSH_PUBLIC_DOMAIN ]] && log "  Browser:  https://${SSH_PUBLIC_DOMAIN}  (SSO-gated terminal)"
    log "First private connection writes /etc/ssh/ca.pem."
    log "Install the client: curl -fsSL https://static.pangolin.net/get-cli.sh | bash"
  fi
}

main "$@"

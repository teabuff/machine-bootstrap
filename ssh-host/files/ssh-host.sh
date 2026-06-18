#!/usr/bin/env bash
# ssh-host.sh — box-side identity-aware SSH wiring. The Pangolin site, resources,
# and role policy are created declaratively by access/; this script only runs the
# newt connector with the creds access/ minted and trusts the org SSH CA.
#
# Usage: ssh-host.sh <stack_dir> <newt_version> <dashboard_url> <newt_id> <newt_secret>
set -euo pipefail
STACK_DIR=${1:?stack_dir}
NEWT_VERSION=${2:?newt_version}
PANGOLIN_DASHBOARD_URL=${3:?dashboard_url}
NEWT_ID=${4:?newt_id}
NEWT_SECRET=${5:?newt_secret}
SUDO=""; [ "$(id -u)" -eq 0 ] || SUDO="sudo"
log() { printf '%s\n' "$*" >&2; }

write_newt_env() {
  $SUDO install -d -m 700 /etc/newt
  printf 'PANGOLIN_ENDPOINT=%s\nNEWT_ID=%s\nNEWT_SECRET=%s\n' \
    "$PANGOLIN_DASHBOARD_URL" "$NEWT_ID" "$NEWT_SECRET" | $SUDO tee /etc/newt/newt.env >/dev/null
  $SUDO chmod 600 /etc/newt/newt.env
  $SUDO rm -f /root/.config/newt-client/config.json
  log "= /etc/newt/newt.env written from access creds (newt $NEWT_ID)"
}

# --- newt binary -----------------------------------------------------------
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

# --- newt systemd service --------------------------------------------------
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

  # Wait for the unit to come up. There is no Pangolin API to poll here, so we
  # only check that the local service is active. Non-fatal.
  local i
  for i in $(seq 1 30); do
    if $SUDO systemctl is-active --quiet newt; then
      log "= newt.service active"; return
    fi
    sleep 1
  done
  log "!! newt.service not active after 30s (check: journalctl -u newt)"
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

# --- Additive sshd CA drop-in (only once ca.pem is real) -------------------
sshd_dropin() {
  # Written PROACTIVELY: newt writes /etc/ssh/ca.pem lazily on the first SSH
  # connection, so we can't wait for it. sshd tolerates a not-yet-existent
  # TrustedUserCAKeys file (read only at auth time); existing password/key login
  # is unaffected (AuthorizedPrincipalsCommand runs only during cert auth).
  local conf=/etc/ssh/sshd_config.d/10-pangolin-ca.conf
  $SUDO tee "$conf" >/dev/null <<'CONF'
# Managed by machine-bootstrap ssh-host.sh — Pangolin auth-daemon CA trust.
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
  newt_install
  write_newt_env
  newt_service
  install_dev_port
  sshd_dropin
  log ""
  log "Box-side SSH wiring converged (newt connector + sshd CA trust)."
  log "First private connection writes /etc/ssh/ca.pem."
}

main "$@"

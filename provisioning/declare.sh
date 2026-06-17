# shellcheck shell=bash
# provisioning/declare.sh — tiny idempotent "declarative" host-config engine.
#
# A host manifest sources this file and then calls the verbs below; each verb
# converges one resource to the declared state. Re-running is always safe.
#
#   group        <name> <gid>                 create the group at a fixed GID
#   dir          <path> <owner:group> <mode>  create a (setgid-capable) directory
#   service      <name> <enabled|started>     enable (and optionally start) a unit
#   polkit-units <group> <unit>...            let a group start/stop/restart those
#                                             units via systemctl WITHOUT sudo
#
# The verbs need root (except argument validation). Drive them with apply-host.sh.

group() {
  local name=$1 gid=$2 actual
  if actual=$(getent group "$name" | cut -d: -f3) && [[ -n $actual ]]; then
    # Name already exists. Leave it, but warn if its GID differs from the
    # declaration — a silent mismatch would break cross-host file ownership.
    [[ $actual == "$gid" ]] ||
      echo "WARNING: group $name has GID $actual, declared $gid (fix manually)" >&2
    return 0
  fi
  groupadd --gid "$gid" "$name"
  echo "+ group $name ($gid)"
}

dir() {
  local path=$1 owngrp=$2 mode=$3
  mkdir -p "$path"
  chown "$owngrp" "$path"
  chmod "$mode" "$path"
  echo "= dir $path ($owngrp $mode)"
}

service() {
  local name=$1 want=$2
  case $want in
    enabled) systemctl enable "$name" ;;
    started) systemctl enable --now "$name" ;;
    *) echo "service: unknown state '$want' for $name (want enabled|started)" >&2; return 1 ;;
  esac
  echo "= service $name ($want)"
}

# Grant a Unix group scoped control of specific systemd units WITHOUT sudo, via a
# polkit JS rule. Members of <group> can `systemctl start|stop|restart|reload`
# exactly the listed units (D-Bus authorized by polkit; no entry in sudoers, no
# root). This is the ops-friendly "partial privilege" mechanism — narrower and
# more auditable than a sudo grant, and it leaves sudo for the genuinely-root
# wrapper jobs (e.g. dev-port). The JIT SSH user must be in <group> (set via the
# Pangolin role's sshUnixGroups) and the group must already exist (declare it
# with `group` first). Idempotent: the rule file is rewritten to match each run.
#
# Minimal Debian servers ship without polkit, so this installs `polkitd` on first
# use. Modern polkit (>=0.106 / Debian 12+) reads JS rules from rules.d; the old
# .pkla local-authority backend is not supported here (Debian 13 ships polkit 126).
polkit-units() {
  local group=$1; shift
  local units=("$@") u
  [[ -n ${group:-} && ${#units[@]} -gt 0 ]] ||
    { echo "polkit-units: usage: polkit-units <group> <unit>..." >&2; return 1; }
  getent group "$group" >/dev/null ||
    { echo "polkit-units: group '$group' does not exist — declare it with \`group\` first" >&2; return 1; }

  # Ensure the polkit daemon is present (D-Bus authorization needs it; non-root
  # `systemctl restart` is denied outright when polkit is absent).
  if ! dpkg-query -W -f='${Status}' polkitd 2>/dev/null | grep -q 'install ok installed'; then
    echo "+ installing polkitd (required for non-root unit control)"
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends polkitd >/dev/null
  fi
  local rules_dir=${POLKIT_RULES_DIR:-/etc/polkit-1/rules.d}
  [[ -d $rules_dir ]] ||
    { echo "polkit-units: $rules_dir missing — polkit too old for JS rules" >&2; return 1; }

  # Build the allowed-units JS array literal: ["a.service","b.service"]
  local arr=""
  for u in "${units[@]}"; do arr+="\"${u}\","; done
  arr="[${arr%,}]"

  local file=$rules_dir/49-${group}-units.rules
  # rule prefix <50 so it precedes 50-default.rules; a YES result short-circuits.
  cat > "$file" <<EOF
// Managed by machine-bootstrap apply-host.sh — DO NOT EDIT BY HAND.
// Members of "${group}" may start/stop/restart/reload exactly these units,
// without sudo. Re-applying the host manifest rewrites this file.
polkit.addRule(function(action, subject) {
    if (action.id !== "org.freedesktop.systemd1.manage-units") { return; }
    if (!subject.isInGroup("${group}")) { return; }
    var allowed = ${arr};
    if (allowed.indexOf(action.lookup("unit")) >= 0) { return polkit.Result.YES; }
});
EOF
  chmod 0644 "$file"
  echo "= polkit-units $group -> ${units[*]}"
}

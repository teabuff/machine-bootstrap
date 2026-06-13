# shellcheck shell=bash
# lib/declare.sh — tiny idempotent "declarative" host-config engine.
#
# A host manifest sources this file and then calls the verbs below; each verb
# converges one resource to the declared state. Re-running is always safe.
#
#   group   <name> <gid>                 create the group at a fixed GID
#   dir     <path> <owner:group> <mode>  create a (setgid-capable) directory
#   service <name> <enabled|started>     enable (and optionally start) a unit
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

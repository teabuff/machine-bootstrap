#!/usr/bin/env bash
set -euo pipefail
# Integration smoke test: runs apply-host.sh as root in a throwaway Ubuntu
# container and asserts the declared groups + setgid dirs, idempotency, the
# GID-mismatch warning, and syntax-error fail-fast. Requires Docker.
# (The 'service' verb needs systemd and is verified on a real host, not here.)
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)

docker run --rm -v "$REPO:/repo:ro" ubuntu:24.04 bash -euo pipefail -c '
  m=$(mktemp)
  cat > "$m" <<EOF
group app-dev 8001
group app-ops 8002
dir /data/app-dev root:app-dev 2775
dir /data/app-ops root:app-ops 2775
EOF

  bash /repo/provisioning/apply-host.sh "$m"   # first run: creates
  bash /repo/provisioning/apply-host.sh "$m"   # second run: idempotent, must not error

  for g in app-dev app-ops; do
    getent group "$g" >/dev/null || { echo "missing group $g"; exit 1; }
    d=/data/$g
    got=$(stat -c "%a %U %G" "$d")
    [ "$got" = "2775 root $g" ] || { echo "BAD perms $d: $got"; exit 1; }
  done
  getent group app-dev | grep -q ":8001:" || { echo "BAD gid app-dev"; exit 1; }
  getent group app-ops | grep -q ":8002:" || { echo "BAD gid app-ops"; exit 1; }

  # A pre-existing group at a different GID must warn (stderr), not clobber.
  groupadd --gid 7777 preexist
  m2=$(mktemp); echo "group preexist 8009" > "$m2"
  warn=$(bash /repo/provisioning/apply-host.sh "$m2" 2>&1 >/dev/null)
  echo "$warn" | grep -q "group preexist has GID 7777, declared 8009" \
    || { echo "BAD: expected GID-mismatch warning, got: $warn"; exit 1; }
  getent group preexist | grep -q ":7777:" || { echo "BAD: preexist GID changed"; exit 1; }

  # A syntax-error manifest must fail fast (bash -n) before any mutation.
  m3=$(mktemp); printf "group good 8050\nfi\n" > "$m3"
  if bash /repo/provisioning/apply-host.sh "$m3" >/dev/null 2>&1; then
    echo "BAD: syntax-error manifest should have failed"; exit 1
  fi
  if getent group good >/dev/null; then
    echo "BAD: good group created despite syntax error"; exit 1
  fi

  echo "SMOKE OK"
'

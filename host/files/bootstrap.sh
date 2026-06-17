#!/usr/bin/env bash
# Headless post-deploy bootstrap: seed the Pangolin server admin + activate the
# EE license, over loopback on the box (no public DNS/cert needed). Idempotent.
#   ./bootstrap.sh [stack_dir]
# SSO is provisioned declaratively by the idp/ and access/ planes; this script no
# longer touches Pocket ID or SSO wiring.
set -euo pipefail

stack_dir=${1:-/opt/pangolin-stack}
cd "$stack_dir"

[ -r "$stack_dir/admin.conf" ] || { echo "ERROR: $stack_dir/admin.conf missing" >&2; exit 1; }
set -a; # shellcheck source=/dev/null
source "$stack_dir/admin.conf"; set +a

# pang_license needs jq + curl; a fresh box may have neither.
need_pkg=()
command -v jq   >/dev/null 2>&1 || need_pkg+=(jq)
command -v curl >/dev/null 2>&1 || need_pkg+=(curl)
if [ ${#need_pkg[@]} -gt 0 ]; then
  echo "==> installing ${need_pkg[*]}"
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq && apt-get install -y -qq "${need_pkg[@]}"
  else
    echo "ERROR: need ${need_pkg[*]} but apt-get is unavailable; install them and re-run" >&2; exit 1
  fi
fi

# Wait for Pangolin's API on loopback before driving it.
wait_http() {
  local url=$1 name=$2 waited=0
  echo "==> waiting for $name ($url)"
  until curl -fsS -o /dev/null "$url" 2>/dev/null; do
    [ "$waited" -lt 180 ] || { echo "ERROR: $name not ready after 180s" >&2; exit 1; }
    sleep 3; waited=$((waited + 3))
  done
}
wait_http "${PANGOLIN_URL%/}/api/v1/" pangolin

echo "==> seeding Pangolin server admin ($PANGOLIN_ADMIN_EMAIL)"
docker exec pangolin pangctl set-admin-credentials \
  --email "$PANGOLIN_ADMIN_EMAIL" --password "$PANGOLIN_ADMIN_PASSWORD"

if [ -n "${PANGOLIN_LICENSE_KEY:-}" ]; then
  echo "==> activating Pangolin EE license"
  # shellcheck source=/dev/null
  . "$stack_dir/lib/pang-bootstrap.sh"
  pang_login
  pang_license "$PANGOLIN_LICENSE_KEY"
fi

echo "==> bootstrap done"

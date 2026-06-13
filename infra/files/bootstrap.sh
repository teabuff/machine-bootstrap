#!/usr/bin/env bash
# Headless post-deploy configuration — closes the loop the UI used to require.
# Uploaded and invoked by OpenTofu (null_resource.configure) after deploy.sh has
# the stack running. Idempotent; safe to re-run by hand:
#   ./bootstrap.sh [stack_dir] [enable_sso]
#
# Order: ensure deps -> wait for pangolin (+ pocket-id) -> seed the server admin
# with pangctl -> (optional) run provision-sso.sh over loopback to wire SSO.
# Everything talks to 127.0.0.1, so no public DNS/cert needs to be live yet.
set -euo pipefail

stack_dir=${1:-/opt/pangolin-stack}
enable_sso=${2:-true}
cd "$stack_dir"

# Credentials + endpoints come from the tofu-rendered, root-only sso.conf.
[ -r "$stack_dir/sso.conf" ] || { echo "ERROR: $stack_dir/sso.conf missing" >&2; exit 1; }
set -a; # shellcheck source=/dev/null
source "$stack_dir/sso.conf"; set +a

# provision-sso.sh needs jq + curl; a fresh box may have neither.
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

# Wait for Pangolin's API on loopback before driving it (compose up returns
# before the healthcheck passes).
wait_http() {
  local url=$1 name=$2 waited=0
  echo "==> waiting for $name ($url)"
  until curl -fsS -o /dev/null "$url" 2>/dev/null; do
    [ "$waited" -lt 180 ] || { echo "ERROR: $name not ready after 180s" >&2; exit 1; }
    sleep 3; waited=$((waited + 3))
  done
}
wait_http "${PANGOLIN_URL%/}/api/v1/" pangolin

# Seed the server admin headlessly (idempotent upsert) — replaces "create the
# org/admin in the dashboard".
echo "==> seeding Pangolin server admin ($PANGOLIN_ADMIN_EMAIL)"
docker exec pangolin pangctl set-admin-credentials \
  --email "$PANGOLIN_ADMIN_EMAIL" --password "$PANGOLIN_ADMIN_PASSWORD"

if [ "$enable_sso" = "true" ]; then
  wait_http "${POCKETID_URL%/}/.well-known/openid-configuration" pocket-id
  echo "==> wiring Pangolin <-> Pocket ID SSO"
  bash "$stack_dir/provision-sso.sh" "$stack_dir/sso.conf" "$stack_dir/sso.identity"
else
  echo "==> SSO wiring disabled (enable_sso=false); admin seeded only"
fi

echo "==> bootstrap done"

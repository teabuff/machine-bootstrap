#!/usr/bin/env bash
# Provision Pangolin <-> Pocket ID single sign-on with zero UI clicks.
# Idempotent: safe to re-run to converge a drifted config.
#
#   ./provision-sso.sh <config> <identity-manifest>
#
# <config>           env file of endpoints + credentials (see hosts/example.sso.conf)
# <identity-manifest> declarative groups/users seeded into Pocket ID
#                     (see hosts/example.sso.identity)
#
# What it does, in order (resolving the circular callback dependency between
# the two products without ever touching a web UI):
#   1. Pocket ID  — seed groups + users from the manifest.
#   2. Pocket ID  — ensure the Pangolin OIDC client (deterministic client_id)
#                   and obtain its secret (generated once, then persisted).
#   3. Pangolin   — log in as the pangctl-seeded server admin, create/update
#                   the external OIDC IdP pointing at Pocket ID, and read back
#                   the IdP's redirect URL.
#   4. Pocket ID  — register that redirect URL as the client's callback URL.
#   5. Pangolin   — (optional) map Pocket ID groups onto an org's roles.
set -euo pipefail

[[ $# -eq 2 ]] || { echo "usage: $0 <config> <identity-manifest>" >&2; exit 2; }
config=$1 manifest=$2
[[ -r $config ]]   || { echo "cannot read config: $config" >&2; exit 1; }
[[ -r $manifest ]] || { echo "cannot read manifest: $manifest" >&2; exit 1; }
bash -n "$manifest" || { echo "manifest has syntax errors: $manifest" >&2; exit 1; }

HERE=$(cd "$(dirname "$0")" && pwd)
set -a
# shellcheck source=/dev/null
source "$config"
set +a
# shellcheck source=lib/sso.sh
source "$HERE/lib/sso.sh"

for v in POCKETID_URL POCKETID_API_KEY PANGOLIN_URL PANGOLIN_ADMIN_EMAIL \
         PANGOLIN_ADMIN_PASSWORD OIDC_CLIENT_ID IDP_NAME; do
  [[ -n ${!v:-} ]] || { echo "config is missing required variable: $v" >&2; exit 1; }
done

# --- manifest verbs: accumulate declared identities, seeding Pocket ID ------
declare -A GROUP_IDS
group() { GROUP_IDS[$1]=$(pid_group "$1" "${2:-$1}"); }
user() {
  local username=$1 display=$2 email=$3; shift 3
  local -a gids=() g
  for g in "$@"; do
    [[ -n ${GROUP_IDS[$g]:-} ]] || { echo "user $username: unknown group '$g' (declare it first)" >&2; exit 1; }
    gids+=("${GROUP_IDS[$g]}")
  done
  pid_user "$username" "$display" "$email" "${gids[@]}" >/dev/null
}

echo "==> [1/5] seeding Pocket ID groups + users"
# shellcheck source=/dev/null
source "$manifest"

echo "==> [2/5] ensuring Pocket ID OIDC client '$OIDC_CLIENT_ID'"
# Pre-register any callback we already know (re-runs); first run starts empty.
prior_cb=$(state_get "idp_redirect_${IDP_NAME}")
pid_client "$OIDC_CLIENT_ID" ${prior_cb:+"$prior_cb"}
client_secret=$(pid_client_secret "$OIDC_CLIENT_ID")
auth_url=$(pid_authorize_url); token_url=$(pid_token_url)

echo "==> [3/5] configuring Pangolin external OIDC IdP '$IDP_NAME'"
if [[ -n ${PANGOLIN_CONTAINER:-} ]]; then
  # Idempotent server-admin upsert; needs docker access to the Pangolin host.
  docker exec "$PANGOLIN_CONTAINER" pangctl set-admin-credentials \
    --email "$PANGOLIN_ADMIN_EMAIL" --password "$PANGOLIN_ADMIN_PASSWORD" >/dev/null
  echo "  = pangctl server admin ensured"
fi
pang_login
read -r idp_id redirect_url < <(pang_idp "$IDP_NAME" "$OIDC_CLIENT_ID" \
  "$client_secret" "$auth_url" "$token_url" "openid profile email groups")

echo "==> [4/5] registering Pangolin callback URL back into Pocket ID"
[[ -n $redirect_url && $redirect_url != null ]] \
  || { echo "did not obtain a redirect URL from Pangolin" >&2; exit 1; }
pid_client "$OIDC_CLIENT_ID" "$redirect_url"

echo "==> [5/5] organization + IdP policy"
if [[ -n ${PANGOLIN_ORG_ID:-} ]]; then
  # Without an org + policy, SSO users authenticate but are rejected with
  # "must be added to an organization". Create the org (if absent) and map the
  # IdP into it so every Pocket ID user is auto-added with a default role.
  pang_ensure_org "$PANGOLIN_ORG_ID" "${PANGOLIN_ORG_NAME:-$PANGOLIN_ORG_ID}"
  pang_idp_org "$idp_id" "$PANGOLIN_ORG_ID" \
    "${IDP_ROLE_MAPPING:-\'Member\'}" "${IDP_ORG_MAPPING:-\'true\'}"
else
  echo "  - skipped (PANGOLIN_ORG_ID unset) — SSO users will have no org to join"
fi

echo "==> done — Pangolin authenticates against Pocket ID; no UI was touched"

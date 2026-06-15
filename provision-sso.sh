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
# Membership in this group makes a user a Pocket ID admin (emulates the
# LDAP-only LDAP_ATTRIBUTE_ADMIN_GROUP for our API-driven setup). Declare the
# group like any other; listing it on a user's line flips their isAdmin.
: "${POCKET_ADMIN_GROUP:=pocket-admin}"
declare -A GROUP_IDS GROUP_ROLE   # GROUP_ROLE: group -> Pangolin role (annotated groups only)
declare -a ROLE_ORDER             # annotated groups, in declaration order
# group <name> [friendlyName] [PangolinRole]
# An optional third field maps membership of this Pocket ID group onto a Pangolin
# org role. provision compiles those into the IdP role-mapping (build_role_mapping,
# below) — so the group->role table lives HERE, in the manifest, not in a hand-
# written JMESPath. Groups with no role (e.g. pocket-admin) grant no Pangolin role.
# This is the declarative equivalent of Pangolin's UI "mapping builder": one
# source of truth, no UI drift. (No arrow separator: the manifest is sourced by
# bash, where '>' would be a redirection — give the role as a bare third word,
# with the friendly name present so it can't be mistaken for the role.)
group() {
  local name=$1 friendly=${2:-$1} role=${3:-}
  GROUP_IDS[$name]=$(pid_group "$name" "$friendly")
  # `if` (not `&&`): a role-less group must still return 0, or `set -e` aborts
  # the manifest sourcing on the trailing false test.
  if [[ -n $role ]]; then GROUP_ROLE[$name]=$role; ROLE_ORDER+=("$name"); fi
}
# Compile the `group ... -> Role` annotations into a JMESPath role mapping that
# returns the ARRAY of Pangolin roles a user's groups grant (a user in several
# mapped groups gets all of them — Pangolin unions their resource access),
# falling back to IDP_ROLE_FALLBACK when none match. A non-empty IDP_ROLE_MAPPING
# overrides the whole thing verbatim (manual escape hatch). The `groups &&` guard
# is load-bearing: contains() on an absent claim throws and 500s the login.
build_role_mapping() {
  [[ -n ${IDP_ROLE_MAPPING:-} ]] && { printf '%s' "$IDP_ROLE_MAPPING"; return; }
  local fallback=${IDP_ROLE_FALLBACK:-"['Guest']"}
  [[ ${#ROLE_ORDER[@]} -eq 0 ]] && { printf '%s' "$fallback"; return; }
  local list="" g
  for g in "${ROLE_ORDER[@]}"; do
    [[ -n $list ]] && list+=", "
    list+="groups && contains(groups, '$g') && '${GROUP_ROLE[$g]}'"
  done
  printf '([%s][?@]) || (%s)' "$list" "$fallback"
}
user() {
  local username=$1 display=$2 email=$3; shift 3
  local -a gids=() g
  local is_admin=false
  for g in "$@"; do
    [[ $g == "$POCKET_ADMIN_GROUP" ]] && is_admin=true
    [[ -n ${GROUP_IDS[$g]:-} ]] || { echo "user $username: unknown group '$g' (declare it first)" >&2; exit 1; }
    gids+=("${GROUP_IDS[$g]}")
  done
  pid_user "$username" "$display" "$email" "$is_admin" "${gids[@]}" >/dev/null
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

echo "==> [5/5] organization + roles + IdP policy"
if [[ -n ${PANGOLIN_ORG_ID:-} ]]; then
  # Without an org + policy, SSO users authenticate but are rejected with
  # "must be added to an organization". Create the org (if absent), the custom
  # roles the role-mapping references, and the IdP->org policy so every Pocket ID
  # user is auto-added with the role their groups/email map to.
  pang_ensure_org "$PANGOLIN_ORG_ID" "${PANGOLIN_ORG_NAME:-$PANGOLIN_ORG_ID}"
  for role in ${PANGOLIN_ROLES:-}; do
    pang_ensure_role "$PANGOLIN_ORG_ID" "$role"
  done
  role_mapping=$(build_role_mapping)
  echo "  = idp role mapping: $role_mapping" >&2
  pang_idp_org "$idp_id" "$PANGOLIN_ORG_ID" \
    "$role_mapping" "${IDP_ORG_MAPPING:-\'true\'}"
else
  echo "  - skipped (PANGOLIN_ORG_ID unset) — SSO users will have no org to join"
fi

echo "==> done — Pangolin authenticates against Pocket ID; no UI was touched"

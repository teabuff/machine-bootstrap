# shellcheck shell=bash
# lib/sso.sh — idempotent helpers to wire Pangolin SSO to a Pocket ID OIDC
# provider, entirely over each product's HTTP API (no web UI, ever).
#
# Pocket ID is the source of truth for identities. We seed groups/users and an
# OIDC client there, then point Pangolin at it as an external IdP and map
# Pocket ID groups onto Pangolin roles/orgs. Every function converges one
# resource to the declared state and is safe to re-run.
#
# Auth model (both headless, both verified against the products' source):
#   Pocket ID — set STATIC_API_KEY on the server; we send it as X-API-Key.
#               That key lazily creates a hidden admin principal, so no first-
#               run setup wizard is needed.
#   Pangolin  — `pangctl set-admin-credentials` seeds the server admin, then we
#               log in over HTTP and drive the dashboard's own /api/v1 routes
#               with the session cookie. This sidesteps the Integration API's
#               chicken-and-egg (you can't mint the first /v1 Bearer key
#               headlessly). Non-GET calls need a static CSRF header in prod.
#
# Two values are generated server-side and shown once: the OIDC client secret
# (Pocket ID) and the IdP redirect URL (Pangolin). We persist both to a local
# state file so re-runs stay idempotent without rotating the secret.
#
# Required env (see hosts/example.sso.conf):
#   POCKETID_URL POCKETID_API_KEY
#   PANGOLIN_URL PANGOLIN_ADMIN_EMAIL PANGOLIN_ADMIN_PASSWORD
#   OIDC_CLIENT_ID IDP_NAME
# Optional:
#   PANGOLIN_ORG_ID IDP_ROLE_MAPPING IDP_ORG_MAPPING
#   PANGOLIN_CSRF (default "x-csrf-protection") SSO_STATE_FILE

set -euo pipefail

: "${SSO_STATE_FILE:=$PWD/.sso-state}"
: "${PANGOLIN_CSRF:=x-csrf-protection}"
PANG_COOKIES=$(mktemp)
trap 'rm -f "$PANG_COOKIES"' EXIT

# --- tiny local key=value state store (gitignored) -------------------------
# Holds the read-once client secret and the Pangolin-generated redirect URL so
# re-runs reuse them instead of regenerating (which would rotate the secret).
state_get() {
  local key=$1
  [[ -f $SSO_STATE_FILE ]] || return 0
  sed -n "s/^${key}=//p" "$SSO_STATE_FILE" | tail -n1
}
state_set() {
  local key=$1 val=$2 tmp
  tmp=$(mktemp)
  [[ -f $SSO_STATE_FILE ]] && grep -v "^${key}=" "$SSO_STATE_FILE" > "$tmp" || true
  printf '%s=%s\n' "$key" "$val" >> "$tmp"
  ( umask 077; mv "$tmp" "$SSO_STATE_FILE" )   # secret-bearing: owner-only
}

# --- HTTP plumbing ---------------------------------------------------------
# Each wrapper prints the response body on stdout and fails (non-zero) on any
# 5xx or unexpected status, so `set -e` aborts before we wire half a config.
# Existence probes pass want_status=404 to tolerate "not found".
_http() {
  # _http <jar|nojar> <method> <url> <accept-codes-regex> [json] [extra-header...]
  local jar=$1 method=$2 url=$3 ok=$4 body=${5:-}; shift; shift; shift; shift; [[ $# -gt 0 ]] && shift
  # -g/--globoff: Pocket ID's pagination params contain [ ] which curl would
  # otherwise read as glob ranges ("curl: (3) bad range").
  local -a args=(-sS -g -X "$method" -o /tmp/sso_body.$$ -w '%{http_code}')
  [[ $jar == jar ]] && args+=(-b "$PANG_COOKIES" -c "$PANG_COOKIES")
  local h; for h in "$@"; do args+=(-H "$h"); done
  if [[ -n $body ]]; then args+=(-H 'Content-Type: application/json' -d "$body"); fi
  local code; code=$(curl "${args[@]}" "$url")
  local out; out=$(cat /tmp/sso_body.$$); rm -f /tmp/sso_body.$$
  if [[ $code =~ $ok ]]; then printf '%s' "$out"; return 0; fi
  echo "HTTP $method $url -> $code: $out" >&2
  return 1
}

# ===========================================================================
# Pocket ID
# ===========================================================================
pid() {
  # pid <method> <path> <accept-regex> [json]
  _http nojar "$1" "${POCKETID_URL%/}$2" "$3" "${4:-}" \
    "X-API-Key: ${POCKETID_API_KEY}"
}

# Accumulate every item of a paginated list endpoint (.data[]) across pages.
pid_list_all() {
  local path=$1 page=1 pages body
  while :; do
    body=$(pid GET "${path}?pagination[page]=${page}&pagination[limit]=100" '^200$')
    echo "$body" | jq -c '.data[]'
    pages=$(echo "$body" | jq -r '.pagination.totalPages // 1')
    (( page >= pages )) && break
    page=$(( page + 1 ))
  done
}

# Ensure a group exists with the given friendly name; echo its id. Idempotent
# (match by unique name) and CONVERGENT — a changed friendlyName in the manifest
# is pushed on re-run via PUT, not just set at create time.
pid_group() {
  local name=$1 friendly=${2:-$1} id payload
  payload=$(jq -nc --arg n "$name" --arg f "$friendly" '{name:$n, friendlyName:$f}')
  id=$(pid_list_all /api/user-groups | jq -r --arg n "$name" 'select(.name==$n).id' | head -n1)
  if [[ -z $id ]]; then
    id=$(pid POST /api/user-groups '^20[01]$' "$payload" | jq -r '.id')
    echo "  + pocket-id group $name" >&2
  else
    pid PUT "/api/user-groups/$id" '^200$' "$payload" >/dev/null
    echo "  = pocket-id group $name" >&2
  fi
  echo "$id"
}

# Ensure a user exists with the given group membership; echo its id.
# Args: username display email is_admin [groupId...]. is_admin ("true"/"false")
# sets the Pocket ID admin flag — the caller derives it from group membership
# (Pocket ID has no native group->admin off LDAP). Update path uses PUT (full replace).
pid_user() {
  local username=$1 display=$2 email=$3 is_admin=${4:-false}; shift 4
  local gids; gids=$(printf '%s\n' "$@" | jq -R . | jq -sc 'map(select(length>0))')
  local first last id
  first=${display%% *}; last=${display#* }; [[ $last == "$display" ]] && last=""
  local payload
  payload=$(jq -nc --arg u "$username" --arg e "$email" --arg f "$first" \
    --arg l "$last" --arg d "$display" --argjson g "$gids" --argjson admin "$is_admin" \
    '{username:$u, email:$e, firstName:$f, lastName:$l, displayName:$d,
      emailVerified:true, isAdmin:$admin, disabled:false, userGroupIds:$g}')
  id=$(pid_list_all /api/users | jq -r --arg u "$username" 'select(.username==$u).id' | head -n1)
  if [[ -z $id ]]; then
    id=$(pid POST /api/users '^20[01]$' "$payload" | jq -r '.id')
    echo "  + pocket-id user $username" >&2
  else
    pid PUT "/api/users/$id" '^200$' "$payload" >/dev/null
    echo "  = pocket-id user $username" >&2
  fi
  # Pocket ID (>=2.x) IGNORES userGroupIds on the user create/update body —
  # group membership must be set through this dedicated endpoint (idempotent:
  # it replaces the user's group set with exactly the listed ids).
  pid PUT "/api/users/$id/user-groups" '^200$' \
    "$(jq -nc --argjson g "$gids" '{userGroupIds:$g}')" >/dev/null
  echo "$id"
}

# Ensure the Pangolin OIDC client exists with a deterministic, caller-chosen id
# and the given callback URLs. Idempotent: GET by id, then POST(create)/PUT.
# launchURL (the dashboard URL) makes the app clickable in Pocket ID's portal;
# set PANGOLIN_DASHBOARD_URL to fill it.
pid_client() {
  local id=$1; shift
  local cbs; cbs=$(printf '%s\n' "$@" | jq -R . | jq -sc 'map(select(length>0))')
  local payload
  payload=$(jq -nc --arg n "Pangolin" --argjson cb "$cbs" --arg lu "${PANGOLIN_DASHBOARD_URL:-}" \
    '{name:$n, callbackURLs:$cb, launchURL:(if $lu=="" then null else $lu end),
      logoutCallbackURLs:[],
      isPublic:false, pkceEnabled:true, requiresReauthentication:false}')
  if pid GET "/api/oidc/clients/$id" '^200$' >/dev/null 2>&1; then
    pid PUT "/api/oidc/clients/$id" '^200$' "$payload" >/dev/null
    echo "  = pocket-id oidc client $id" >&2
  else
    pid POST /api/oidc/clients '^20[01]$' \
      "$(echo "$payload" | jq -c --arg i "$id" '. + {id:$i}')" >/dev/null
    echo "  + pocket-id oidc client $id" >&2
  fi
}

# Return a usable client secret: reuse the persisted one, else generate (once)
# and persist it. The plaintext is only ever returned by the generate call.
pid_client_secret() {
  local id=$1 secret
  secret=$(state_get "oidc_secret_${id}")
  if [[ -z $secret ]]; then
    secret=$(pid POST "/api/oidc/clients/$id/secret" '^20[01]$' '' | jq -r '.secret')
    state_set "oidc_secret_${id}" "$secret"
    echo "  + generated oidc client secret for $id" >&2
  fi
  echo "$secret"
}

# OIDC endpoints, read from Pocket ID's discovery doc (robust to path changes).
pid_authorize_url() {
  curl -sS "${POCKETID_URL%/}/.well-known/openid-configuration" \
    | jq -r '.authorization_endpoint'
}
pid_token_url() {
  curl -sS "${POCKETID_URL%/}/.well-known/openid-configuration" \
    | jq -r '.token_endpoint'
}

# ===========================================================================
# Pangolin
# ===========================================================================
# UPSTREAM (fosrl/pangolin#1895): Pangolin Blueprints (declarative YAML applied
# via `PUT /v1/org/{orgId}/blueprint` or `newt --blueprint-file`) currently
# CANNOT declare identity providers — only resources/sites/targets and
# per-resource auth (sso-enabled/sso-roles/sso-users). That's why the IdP is
# created imperatively below via the session-cookie /api/v1 route. If #1895
# lands (declarative IdP support in blueprints), `pang_idp` / `pang_idp_org`
# could be replaced by emitting a blueprint, dropping the login + CSRF dance.
# Watch: https://github.com/fosrl/pangolin/issues/1895
pang() {
  # pang <method> <path> <accept-regex> [json] — session-cookie + CSRF header
  _http jar "$1" "${PANGOLIN_URL%/}/api/v1$2" "$3" "${4:-}" \
    "x-csrf-token: ${PANGOLIN_CSRF}"
}

# Log in as the server admin (seeded by pangctl) and capture the session cookie.
pang_login() {
  pang POST /auth/login '^200$' \
    "$(jq -nc --arg e "$PANGOLIN_ADMIN_EMAIL" --arg p "$PANGOLIN_ADMIN_PASSWORD" \
       '{email:$e, password:$p}')" >/dev/null
  grep -q 'p_session_token' "$PANG_COOKIES" \
    || { echo "pangolin login did not set a session cookie" >&2; return 1; }
  echo "  = pangolin logged in as $PANGOLIN_ADMIN_EMAIL" >&2
}

# Create a ROOT Integration API key via the session API (server-admin only).
# Echoes "<apiKeyId> <apiKeySecret>" (space-separated). The usable Bearer token
# is the two joined by a dot: "<apiKeyId>.<apiKeySecret>". The secret is shown
# ONCE by this call and never again — callers must persist it.
pang_create_api_key() {
  local name=$1 resp
  resp=$(pang PUT /api-key '^20[01]$' "$(jq -nc --arg n "$name" '{name:$n}')")
  local id secret
  id=$(echo "$resp" | jq -r '.data.apiKeyId')
  secret=$(echo "$resp" | jq -r '.data.apiKey')
  [[ -n $id && $id != null && -n $secret && $secret != null ]] \
    || { echo "api-key create: unexpected response shape (missing apiKeyId/apiKey)" >&2; return 1; }
  echo "  + pangolin root api key $id" >&2
  echo "$id $secret"
}

# Grant a root API key its action set (REQUIRED — a key with no actions is 403
# on every Integration API route, even when isRoot). actionIds is a JSON array
# string. Idempotent: this REPLACES the key's action set each call.
pang_set_api_key_actions() {
  local api_key_id=$1 action_ids_json=$2
  pang POST "/api-key/${api_key_id}/actions" '^200$' \
    "$(jq -nc --argjson a "$action_ids_json" '{actionIds:$a}')" >/dev/null
  echo "  = pangolin api key $api_key_id actions set" >&2
}

# Activate a Pangolin Enterprise Edition license headlessly (idempotent). The
# /license/* routes exist ONLY on the ee- image and require a SERVER admin (the
# bootstrap admin is one). Skips when a key is already valid, so re-runs are a
# no-op. NB: SSH/private-resource features still depend on the activated tier
# including them — if a resource later 403s, the licensed tier is too low.
pang_license() {
  local key=$1
  [[ -z $key ]] && return 0
  # Already valid? /license/keys lists keys with a boolean `valid` (single-host,
  # single-license here, so any valid key means we're licensed).
  if pang GET /license/keys '^200$' 2>/dev/null \
       | jq -e '[.data[]? | select(.valid==true)] | length > 0' >/dev/null 2>&1; then
    echo "  = pangolin license already active" >&2
    return 0
  fi
  # Activation binds the key to an instance. After a DB reset the license server
  # reports the key as already activated on the (now-gone) prior instance, 500-ing
  # this call. That must NOT brick provisioning — the stack runs unlicensed (web +
  # SSO work; only EE features like identity-aware SSH 403). Tolerate that one case
  # loudly; fail on anything else.
  local resp
  if resp=$(pang POST /license/activate '^20[01]$' \
              "$(jq -nc --arg k "$key" '{licenseKey:$k}')" 2>&1); then
    echo "  + pangolin license activated" >&2
  elif printf '%s' "$resp" | grep -qiE 'already been activated|already activated'; then
    echo "  ! license already activated on a different instance — running UNLICENSED." >&2
    echo "    EE features (identity-aware SSH) are gated until you release the key at" >&2
    echo "    https://app.pangolin.net (Licenses) and re-apply. SSO/web are unaffected." >&2
  else
    echo "  license activation failed: $resp" >&2
    return 1
  fi
}

# Ensure the external OIDC IdP exists and echo "<idpId> <redirectUrl>".
# The callback is "<dashboard>/auth/idp/<id>/oidc/callback"; Pangolin only
# returns it at create time, so we DERIVE it from PANGOLIN_DASHBOARD_URL when
# set — that way it tracks a changed dashboard host (falling back to the
# create-time value persisted in state).
pang_idp() {
  local name=$1 client_id=$2 client_secret=$3 auth_url=$4 token_url=$5 scopes=$6
  local idp_id redirect resp
  idp_id=$(pang GET /idp '^200$' | jq -r --arg n "$name" '.data.idps[] | select(.name==$n).idpId' | head -n1)
  local body
  body=$(jq -nc --arg n "$name" --arg ci "$client_id" --arg cs "$client_secret" \
    --arg au "$auth_url" --arg tu "$token_url" --arg sc "$scopes" \
    '{name:$n, clientId:$ci, clientSecret:$cs, authUrl:$au, tokenUrl:$tu,
      identifierPath:"preferred_username", emailPath:"email", namePath:"name",
      scopes:$sc, autoProvision:true, variant:"oidc"}')
  if [[ -z $idp_id ]]; then
    resp=$(pang PUT /idp/oidc '^20[01]$' "$body")
    idp_id=$(echo "$resp" | jq -r '.data.idpId')
    redirect=$(echo "$resp" | jq -r '.data.redirectUrl')
    state_set "idp_redirect_${name}" "$redirect"
    echo "  + pangolin oidc idp $name (id $idp_id)" >&2
  else
    pang POST "/idp/$idp_id/oidc" '^200$' "$body" >/dev/null
    redirect=$(state_get "idp_redirect_${name}")
    echo "  = pangolin oidc idp $name (id $idp_id)" >&2
  fi
  # Derive from the current dashboard URL so a changed host is picked up; keeps
  # the Pocket ID callback in sync without trusting a stale state file.
  if [[ -n ${PANGOLIN_DASHBOARD_URL:-} ]]; then
    redirect="${PANGOLIN_DASHBOARD_URL%/}/auth/idp/${idp_id}/oidc/callback"
    state_set "idp_redirect_${name}" "$redirect"
  fi
  echo "$idp_id $redirect"
}

# Ensure an organization exists; create it (with auto-picked subnets) if missing.
# Idempotent — orgs are the bootstrap an IdP user needs to belong to before they
# can log in ("No policies matched ... must be added to an organization").
pang_ensure_org() {
  local org_id=$1 name=${2:-$1}
  if pang GET /orgs '^200$' | jq -e --arg o "$org_id" '.data.orgs[]? | select(.orgId==$o)' >/dev/null 2>&1; then
    echo "  = pangolin org $org_id" >&2
    return 0
  fi
  local d sn us
  d=$(pang GET /pick-org-defaults '^200$')
  sn=$(echo "$d" | jq -r '.data.subnet')
  us=$(echo "$d" | jq -r '.data.utilitySubnet')
  pang PUT /org '^20[01]$' \
    "$(jq -nc --arg i "$org_id" --arg n "$name" --arg s "$sn" --arg u "$us" \
       '{orgId:$i, name:$n, subnet:$s, utilitySubnet:$u}')" >/dev/null
  echo "  + pangolin org $org_id" >&2
}

# Ensure a custom role exists in the org (Admin + Member are built in). Idempotent.
# Match by exact name — that's also what the IdP roleMapping JMESPath returns.
# New roles start with no resource permissions; grant them per-resource later.
pang_ensure_role() {
  local org_id=$1 name=$2 desc=${3:-$2}
  if pang GET "/org/$org_id/roles" '^200$' | jq -e --arg n "$name" '.data.roles[]? | select(.name==$n)' >/dev/null 2>&1; then
    echo "  = pangolin role $name" >&2
    return 0
  fi
  pang PUT "/org/$org_id/role" '^20[01]$' \
    "$(jq -nc --arg n "$name" --arg d "$desc" '{name:$n, description:$d}')" >/dev/null
  echo "  + pangolin role $name" >&2
}

# Map IdP claims onto a Pangolin org's roles/membership (JMESPath expressions).
# NB: values are JMESPath — a default role/org needs quoted literals ('Member',
# 'true'), not bare words (which are read as claim lookups -> null -> no match).
pang_idp_org() {
  local idp_id=$1 org_id=$2 role_map=$3 org_map=$4 body
  body=$(jq -nc --arg r "$role_map" --arg o "$org_map" '{roleMapping:$r, orgMapping:$o}')
  # PUT creates the policy (and 400s if it already exists); POST updates it.
  # Pick by whether a policy for this org already exists, so re-runs converge.
  if pang GET "/idp/$idp_id/org" '^200$' | jq -e --arg o "$org_id" '.data.policies[]? | select(.orgId==$o)' >/dev/null 2>&1; then
    pang POST "/idp/$idp_id/org/$org_id" '^200$' "$body" >/dev/null
    echo "  = pangolin idp $idp_id -> org $org_id mapping" >&2
  else
    pang PUT "/idp/$idp_id/org/$org_id" '^20[01]$' "$body" >/dev/null
    echo "  + pangolin idp $idp_id -> org $org_id mapping" >&2
  fi
}

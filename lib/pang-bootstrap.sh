# shellcheck shell=bash
# lib/pang-bootstrap.sh — Pangolin bootstrap primitives: mint the first
# Integration API key and activate the EE license, run on the box over loopback.
#
# Auth model: `pangctl set-admin-credentials` seeds the server admin; we then
# log in over HTTP and drive the dashboard's own /api/v1 routes with the session
# cookie + static CSRF header. This sidesteps the Integration API's chicken-and-
# egg (you can't mint the first /v1 Bearer key headlessly). Once minted, callers
# persist the Bearer token and use the Integration API for everything else.
#
# Required env:
#   PANGOLIN_URL PANGOLIN_ADMIN_EMAIL PANGOLIN_ADMIN_PASSWORD
# Optional:
#   PANGOLIN_CSRF (default "x-csrf-protection")

set -euo pipefail

: "${PANGOLIN_CSRF:=x-csrf-protection}"
PANG_COOKIES=$(mktemp)
trap 'rm -f "$PANG_COOKIES"' EXIT

# --- HTTP plumbing ---------------------------------------------------------
# Each wrapper prints the response body on stdout and fails (non-zero) on any
# 5xx or unexpected status, so `set -e` aborts before we wire half a config.
# Existence probes pass want_status=404 to tolerate "not found".
_http() {
  # _http <jar|nojar> <method> <url> <accept-codes-regex> [json] [extra-header...]
  local jar=$1 method=$2 url=$3 ok=$4 body=${5:-}; shift; shift; shift; shift; [[ $# -gt 0 ]] && shift
  # -g/--globoff: pagination params contain [ ] which curl would otherwise read
  # as glob ranges ("curl: (3) bad range").
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
# Pangolin
# ===========================================================================
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

#!/usr/bin/env bash
set -euo pipefail
# Offline dry-run of provision-sso.sh against a mock that impersonates both the
# Pocket ID and Pangolin HTTP APIs. No network, no servers. It exercises the
# full ordered flow and asserts the right requests go out with the right
# payloads (deterministic client_id, group claims scope, redirect-URL wiring,
# JMESPath org mapping). Pure control-flow/payload verification.
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
LOG="$WORK/requests.log"; : > "$LOG"
export MOCK_LOG="$LOG"

# --- a fake `curl` covering every endpoint the library calls ----------------
cat > "$WORK/curl" <<'MOCK'
#!/usr/bin/env bash
# Minimal curl impersonator. Understands the flags lib/sso.sh actually uses.
out="" method="GET" data="" cookiejar="" want_code="" url=""
while [[ $# -gt 0 ]]; do
  case $1 in
    -o) out=$2; shift 2;;
    -X) method=$2; shift 2;;
    -d) data=$2; shift 2;;
    -c) cookiejar=$2; shift 2;;
    -w) want_code=1; shift 2;;       # value is always %{http_code} here
    -b|-H) shift 2;;
    -sS|-s|-S) shift;;
    -*) shift;;                       # ignore any other flag (no value)
    *) url=$1; shift;;
  esac
done

code=200; body='{}'
case "$method $url" in
  *"/.well-known/openid-configuration"*)
    body='{"authorization_endpoint":"https://id.test/authorize","token_endpoint":"https://id.test/api/oidc/token"}';;
  "GET "*"/api/user-groups"*)   body='{"data":[],"pagination":{"totalPages":1}}';;
  "POST "*"/api/user-groups")   code=201; body='{"id":"grp-001"}';;
  "GET "*"/api/users"*)         body='{"data":[],"pagination":{"totalPages":1}}';;
  "POST "*"/api/users")         code=201; body='{"id":"usr-001"}';;
  "GET "*"/api/oidc/clients/"*)                                            # 404 until created, then 200
    if [[ -f "${MOCK_LOG%/*}/client_created" ]]; then body='{"id":"pangolin"}'; else code=404; body='{"error":"not found"}'; fi;;
  "POST "*"/api/oidc/clients")  touch "${MOCK_LOG%/*}/client_created"; code=201; body='{"id":"pangolin"}';;
  "PUT "*"/api/oidc/clients/"*) body='{"id":"pangolin"}';;
  "POST "*"/api/oidc/clients/"*"/secret") code=201; body='{"secret":"S3CR3T-xyz"}';;
  "POST "*"/auth/login")        [[ -n $cookiejar ]] && printf 'p_session_token\tabc123\n' > "$cookiejar"; body='{"success":true}';;
  "GET "*"/api/v1/idp")         body='{"data":{"idps":[]}}';;
  "GET "*"/api/v1/idp/"*"/org") body='{"data":{"policies":[]}}';;   # no policy yet -> PUT
  "PUT "*"/api/v1/idp/oidc")    code=201; body='{"data":{"idpId":7,"redirectUrl":"https://pang.test/auth/idp/7/oidc/callback"}}';;
  "GET "*"/api/v1/orgs"*)       body='{"data":{"orgs":[]}}';;
  "GET "*"/api/v1/pick-org-defaults"*) body='{"data":{"subnet":"100.90.0.0/20","utilitySubnet":"100.96.0.0/20"}}';;
  "PUT "*"/api/v1/org")         code=201; body='{"success":true,"data":{"orgId":"org-main"}}';;
  "GET "*"/api/v1/org/"*"/roles"*) body='{"data":{"roles":[]}}';;   # no custom roles -> PUT
  "PUT "*"/api/v1/org/"*"/role") code=201; body='{"success":true,"data":{"roleId":9}}';;
  "PUT "*"/api/v1/idp/"*"/org/"*) body='{"success":true}';;
  *) code=200; body='{}';;
esac

# Record the request (method, path, payload) for post-run assertions.
printf '%s %s :: %s\n' "$method" "$url" "$data" >> "$MOCK_LOG"

if [[ -n $out ]]; then printf '%s' "$body" > "$out"; fi
if [[ -n $want_code ]]; then printf '%s' "$code"
elif [[ -z $out ]]; then printf '%s' "$body"; fi
MOCK
chmod +x "$WORK/curl"

# config + identity manifest for the run
cat > "$WORK/test.sso.conf" <<EOF
POCKETID_URL=https://id.test
POCKETID_API_KEY=0123456789abcdef0123
PANGOLIN_URL=http://127.0.0.1:3000
PANGOLIN_DASHBOARD_URL=https://pang.test
PANGOLIN_ADMIN_EMAIL=admin@test
PANGOLIN_ADMIN_PASSWORD=hunter2hunter2
OIDC_CLIENT_ID=pangolin
IDP_NAME=pocket-id
PANGOLIN_ORG_ID=org-main
PANGOLIN_ROLES="Developer Guest"
IDP_ROLE_MAPPING="contains(groups, 'admins') && 'Admin' || 'Member'"
IDP_ORG_MAPPING=true
SSO_STATE_FILE=$WORK/.sso-state
EOF
cat > "$WORK/test.sso.identity" <<EOF
group admins "Administrators"
group staff  "Staff"
user  jdoe   "Jane Doe"    jane@test   admins staff
user  asmith "Alice Smith" alice@test  staff
EOF

# Run with the mock curl ahead of the real one on PATH.
PATH="$WORK:$PATH" bash "$REPO/provision-sso.sh" "$WORK/test.sso.conf" "$WORK/test.sso.identity" >"$WORK/out.log" 2>&1 \
  || { echo "FAIL: provision-sso.sh exited non-zero"; cat "$WORK/out.log"; exit 1; }

# --- assertions -------------------------------------------------------------
fail() { echo "FAIL: $1"; echo "--- requests ---"; cat "$LOG"; echo "--- output ---"; cat "$WORK/out.log"; exit 1; }
has() { grep -qF "$1" "$LOG" || fail "expected request not found: $1"; }
hasre() { grep -qE "$1" "$LOG" || fail "expected request pattern not found: $1"; }

# Two groups created, then two users, each carrying resolved group ids.
[[ $(grep -c 'POST https://id.test/api/user-groups ' "$LOG") -eq 2 ]] || fail "expected 2 group creates"
[[ $(grep -c 'POST https://id.test/api/users ' "$LOG") -eq 2 ]] || fail "expected 2 user creates"
hasre 'POST https://id.test/api/users .*"userGroupIds":\["grp-001","grp-001"\]'   # jdoe in 2 groups
hasre 'POST https://id.test/api/users .*"username":"asmith".*"userGroupIds":\["grp-001"\]'

# OIDC client created with the deterministic, caller-chosen id.
hasre 'POST https://id.test/api/oidc/clients .*"id":"pangolin"'
hasre 'POST https://id.test/api/oidc/clients .*"launchURL":"https://pang.test"'   # clickable portal tile
has   'POST https://id.test/api/oidc/clients/pangolin/secret :: '

# Pangolin: login, then IdP created with the generated secret + group scope.
has   'POST http://127.0.0.1:3000/api/v1/auth/login '
hasre 'PUT http://127.0.0.1:3000/api/v1/idp/oidc .*"clientId":"pangolin"'
hasre 'PUT http://127.0.0.1:3000/api/v1/idp/oidc .*"clientSecret":"S3CR3T-xyz"'
hasre 'PUT http://127.0.0.1:3000/api/v1/idp/oidc .*"scopes":"openid profile email groups"'
hasre 'PUT http://127.0.0.1:3000/api/v1/idp/oidc .*"identifierPath":"preferred_username"'
hasre 'PUT http://127.0.0.1:3000/api/v1/idp/oidc .*"autoProvision":true'

# Callback wiring: Pangolin's redirect URL registered back as the client callback.
hasre 'PUT https://id.test/api/oidc/clients/pangolin .*"callbackURLs":\["https://pang.test/auth/idp/7/oidc/callback"\]'

# Org auto-created (subnets from pick-org-defaults) before the IdP policy is set.
hasre 'GET http://127.0.0.1:3000/api/v1/pick-org-defaults'
hasre 'PUT http://127.0.0.1:3000/api/v1/org .*"orgId":"org-main".*"subnet":"100.90.0.0/20"'
# Custom roles created (so the role mapping can reference them).
hasre 'PUT http://127.0.0.1:3000/api/v1/org/org-main/role .*"name":"Developer"'
hasre 'PUT http://127.0.0.1:3000/api/v1/org/org-main/role .*"name":"Guest"'
# Org/role mapping applied with the JMESPath expression.
hasre 'PUT http://127.0.0.1:3000/api/v1/idp/7/org/org-main .*"roleMapping":"contains\(groups'

# Secret persisted to state for idempotent re-runs.
grep -q '^oidc_secret_pangolin=S3CR3T-xyz$' "$WORK/.sso-state" || fail "secret not persisted to state"
grep -q '^idp_redirect_pocket-id=https://pang.test/auth/idp/7/oidc/callback$' "$WORK/.sso-state" || fail "redirect not persisted"

# --- idempotency: a second run with existing resources must not recreate ----
cat > "$WORK/curl" <<'MOCK2'
#!/usr/bin/env bash
out="" method="GET" data="" cookiejar="" want_code="" url=""
while [[ $# -gt 0 ]]; do
  case $1 in
    -o) out=$2; shift 2;; -X) method=$2; shift 2;; -d) data=$2; shift 2;;
    -c) cookiejar=$2; shift 2;; -w) want_code=1; shift 2;;
    -b|-H) shift 2;; -sS|-s|-S) shift;; -*) shift;; *) url=$1; shift;;
  esac
done
code=200; body='{}'
case "$method $url" in
  *"/.well-known/openid-configuration"*) body='{"authorization_endpoint":"https://id.test/authorize","token_endpoint":"https://id.test/api/oidc/token"}';;
  "GET "*"/api/user-groups"*) body='{"data":[{"id":"grp-001","name":"admins"},{"id":"grp-001","name":"staff"}],"pagination":{"totalPages":1}}';;
  "GET "*"/api/users"*) body='{"data":[{"id":"usr-001","username":"jdoe"},{"id":"usr-001","username":"asmith"}],"pagination":{"totalPages":1}}';;
  "PUT "*"/api/users/"*) body='{"id":"usr-001"}';;
  "GET "*"/api/oidc/clients/"*) body='{"id":"pangolin"}';;        # exists now -> PUT path
  "PUT "*"/api/oidc/clients/"*) body='{"id":"pangolin"}';;
  "POST "*"/auth/login") [[ -n $cookiejar ]] && printf 'p_session_token\tabc\n' > "$cookiejar"; body='{"success":true}';;
  "GET "*"/api/v1/idp") body='{"data":{"idps":[{"idpId":7,"name":"pocket-id"}]}}';;  # exists -> update path
  "GET "*"/api/v1/idp/"*"/org") body='{"data":{"policies":[{"idpId":7,"orgId":"org-main"}]}}';;  # policy exists -> POST update
  "GET "*"/api/v1/orgs"*) body='{"data":{"orgs":[{"orgId":"org-main","name":"org-main"}]}}';;  # exists -> skip create
  "GET "*"/api/v1/org/"*"/roles"*) body='{"data":{"roles":[{"roleId":9,"name":"Developer"},{"roleId":10,"name":"Guest"}]}}';;  # exist -> skip
  "POST "*"/api/v1/idp/"*"/oidc") body='{"success":true}';;
  "POST "*"/api/v1/idp/"*"/org/"*) body='{"success":true}';;
  "PUT "*"/api/v1/idp/"*"/org/"*) body='{"success":true}';;
  *) body='{}';;
esac
printf '%s %s :: %s\n' "$method" "$url" "$data" >> "$MOCK_LOG"
[[ -n $out ]] && printf '%s' "$body" > "$out"
if [[ -n $want_code ]]; then printf '%s' "$code"; elif [[ -z $out ]]; then printf '%s' "$body"; fi
MOCK2
chmod +x "$WORK/curl"
: > "$LOG"
PATH="$WORK:$PATH" bash "$REPO/provision-sso.sh" "$WORK/test.sso.conf" "$WORK/test.sso.identity" >"$WORK/out2.log" 2>&1 \
  || { echo "FAIL: second (idempotent) run exited non-zero"; cat "$WORK/out2.log"; exit 1; }

# No creates on the second run; updates instead.
grep -q 'POST https://id.test/api/user-groups ' "$LOG" && fail "re-run recreated a group"
grep -q 'POST https://id.test/api/users ' "$LOG" && fail "re-run recreated a user"
grep -q '/api/oidc/clients/pangolin/secret' "$LOG" && fail "re-run rotated the client secret"
grep -q 'PUT http://127.0.0.1:3000/api/v1/idp/oidc' "$LOG" && fail "re-run recreated the IdP"
grep -qE 'PUT http://127.0.0.1:3000/api/v1/org ' "$LOG" && fail "re-run recreated the org"
grep -qE 'PUT http://127.0.0.1:3000/api/v1/org/org-main/role ' "$LOG" && fail "re-run recreated a role"
grep -qE 'PUT http://127.0.0.1:3000/api/v1/idp/7/org/' "$LOG" && fail "re-run PUT (create) an existing IdP-org policy -> would 400"
hasre 'POST http://127.0.0.1:3000/api/v1/idp/7/org/org-main ' # update, not create
hasre 'POST http://127.0.0.1:3000/api/v1/idp/7/oidc '   # update, not create
hasre 'PUT https://id.test/api/users/usr-001 '          # update existing user

echo "DRYRUN OK"

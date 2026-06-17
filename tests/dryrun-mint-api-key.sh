#!/usr/bin/env bash
set -euo pipefail
# Offline dry-run of mint-api-key.sh against a fake Pangolin session API.
# Asserts: login, create-key (PUT /api-key), grant-actions (POST
# /api-key/{id}/actions), and that the emitted token is "<id>.<secret>".
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
LOG="$WORK/requests.log"; : > "$LOG"
export MOCK_LOG="$LOG"

cat > "$WORK/curl" <<'MOCK'
#!/usr/bin/env bash
out="" method="GET" data="" cookiejar="" url=""
while [[ $# -gt 0 ]]; do
  case $1 in
    -o) out=$2; shift 2;;
    -X) method=$2; shift 2;;
    -d) data=$2; shift 2;;
    -c) cookiejar=$2; shift 2;;
    -w) shift 2;;
    -b|-H) shift 2;;
    -sS|-s|-S) shift;;
    -*) shift;;
    *) url=$1; shift;;
  esac
done
code=200; body='{}'
case "$method $url" in
  "POST "*"/auth/login")          [[ -n $cookiejar ]] && printf 'p_session_token\tabc123\n' > "$cookiejar"; body='{"success":true}';;
  "PUT "*"/api/v1/api-key")        code=201; body='{"data":{"apiKeyId":"key-123","apiKey":"secret-xyz","name":"bootstrap"}}';;
  "POST "*"/api/v1/api-key/"*"/actions") body='{"success":true}';;
  *) code=200; body='{}';;
esac
[[ -n $out ]] && printf '%s' "$body" > "$out"
printf '%s %s :: %s\n' "$method" "$url" "$data" >> "$MOCK_LOG"
printf '%s' "$code"
MOCK
chmod +x "$WORK/curl"
export PATH="$WORK:$PATH"

# Minimal admin.conf the script sources.
cat > "$WORK/admin.conf" <<EOF
PANGOLIN_URL="http://127.0.0.1:3000"
PANGOLIN_ADMIN_EMAIL="admin@test.local"
PANGOLIN_ADMIN_PASSWORD="pw"
EOF

# Run the script; it should print {"api_key":"key-123.secret-xyz"} on stdout.
TOKEN_JSON=$(STACK_DIR="$WORK" ADMIN_CONF="$WORK/admin.conf" \
  bash "$REPO/infra/files/mint-api-key.sh" "$REPO/infra/files/pangolin-actions.json")

fail() { echo "FAIL: $1" >&2; echo "--- requests ---" >&2; cat "$LOG" >&2; exit 1; }

echo "$TOKEN_JSON" | jq -e '.api_key == "key-123.secret-xyz"' >/dev/null \
  || fail "token not assembled as <id>.<secret> (got: $TOKEN_JSON)"
grep -q "POST .*/auth/login" "$LOG"               || fail "no admin login"
grep -q "PUT .*/api/v1/api-key " "$LOG"            || fail "no create-key PUT"
grep -q "POST .*/api/v1/api-key/key-123/actions"   "$LOG" || fail "no grant-actions POST"
# Idempotency: a second run with the token already persisted must NOT create again.
: > "$LOG"
TOKEN_JSON2=$(STACK_DIR="$WORK" ADMIN_CONF="$WORK/admin.conf" \
  bash "$REPO/infra/files/mint-api-key.sh" "$REPO/infra/files/pangolin-actions.json")
echo "$TOKEN_JSON2" | jq -e '.api_key == "key-123.secret-xyz"' >/dev/null \
  || fail "second run did not return the persisted token"
grep -q "PUT .*/api/v1/api-key " "$LOG" && fail "second run re-created the key (not idempotent)"

echo "PASS: mint-api-key.sh dry-run"

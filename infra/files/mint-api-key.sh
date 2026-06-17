#!/usr/bin/env bash
# Mint (once) a root Pangolin Integration API key via the session API and print
# it as {"api_key":"<apiKeyId>.<secret>"} on stdout. Idempotent: the token is
# persisted to $STACK_DIR/.integration-api-key (owner-only) and reused on re-run.
#   ./mint-api-key.sh <actions-json-file>
set -euo pipefail

actions_file=${1:?usage: mint-api-key.sh <actions-json-file>}
stack_dir=${STACK_DIR:-/opt/pangolin-stack}
admin_conf=${ADMIN_CONF:-$stack_dir/admin.conf}
token_file="$stack_dir/.integration-api-key"

# Re-emit the persisted token if present (idempotent fast path).
if [[ -s $token_file ]]; then
  jq -nc --arg k "$(cat "$token_file")" '{api_key:$k}'
  exit 0
fi

[[ -r $admin_conf ]] || { echo "cannot read admin.conf: $admin_conf" >&2; exit 1; }
set -a; # shellcheck source=/dev/null
source "$admin_conf"; set +a
# shellcheck source=lib/pang-bootstrap.sh
source "$stack_dir/lib/pang-bootstrap.sh" 2>/dev/null || source "$(dirname "$0")/../../lib/pang-bootstrap.sh"

action_ids=$(cat "$actions_file")

pang_login
key_pair=$(pang_create_api_key "pangolin-terraform")
read -r api_key_id api_key_secret <<< "$key_pair"
pang_set_api_key_actions "$api_key_id" "$action_ids"

token="${api_key_id}.${api_key_secret}"
( umask 077; printf '%s' "$token" > "$token_file" )
jq -nc --arg k "$token" '{api_key:$k}'

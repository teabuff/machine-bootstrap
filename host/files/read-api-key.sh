#!/usr/bin/env bash
# Terraform external data source program. Reads a JSON query on stdin:
#   {"host":..,"user":..,"port":..,"key_path":..,"stack_dir":..}
# SSHes to the box and prints {"api_key":"<token>"} (the file mint-api-key.sh
# persisted). Fails loudly if the token file is absent.
set -euo pipefail
q=$(cat)
host=$(echo "$q"      | jq -r '.host')
user=$(echo "$q"      | jq -r '.user')
port=$(echo "$q"      | jq -r '.port')
key_path=$(echo "$q"  | jq -r '.key_path')
stack_dir=$(echo "$q" | jq -r '.stack_dir')

key_path="${key_path/#\~/$HOME}"   # expand a leading ~ without eval
token=$(ssh -i "$key_path" -p "$port" \
  -o StrictHostKeyChecking=accept-new -o BatchMode=yes \
  "${user}@${host}" "cat '${stack_dir}/.integration-api-key'")
[[ -n $token ]] || { echo "empty integration api key on box" >&2; exit 1; }
jq -nc --arg k "$token" '{api_key:$k}'

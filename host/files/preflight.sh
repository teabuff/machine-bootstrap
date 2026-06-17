#!/usr/bin/env bash
# Pre-flight DNS check (ADVISORY — runs as Terraform external data source).
# Checks that hostnames resolve to the server IP via a public resolver.
# Emits a single JSON object on stdout; always exits 0.
#   preflight.sh <base_domain> <dashboard_host> <pocket_id_host> <server_ip>
# Needs: jq (always), dig (optional).
set -uo pipefail

base=${1:?}
dash=${2:?}
pid=${3:?}
ip=${4:?}
R=1.1.1.1

ok="true"
message=""

if ! command -v dig >/dev/null 2>&1; then
  jq -nc --arg ok "true" --arg msg "preflight skipped (no dig)" '{ok:$ok, message:$msg}'
  exit 0
fi

bad=()
for h in "$dash" "$pid"; do
  got=$(dig +short A "$h" "@$R" 2>/dev/null | tail -1)
  if [ "$got" != "$ip" ]; then
    bad+=("$h -> ${got:-(no answer)} (expected $ip)")
  fi
done

if [ "${#bad[@]}" -eq 0 ]; then
  ok="true"
  ns=$(dig +short NS "$base" "@$R" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')
  message="DNS ready: $dash and $pid -> $ip (NS: ${ns:-unknown})"
else
  ok="false"
  message="DNS not ready: $(IFS='; '; echo "${bad[*]}")"
fi

jq -nc --arg ok "$ok" --arg msg "$message" '{ok:$ok, message:$msg}'
exit 0

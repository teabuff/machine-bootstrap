#!/usr/bin/env bash
# Pre-flight DNS check (ADVISORY — never fails the apply). Runs on the operator
# machine via a PUBLIC resolver, so it sees what the world sees (not a stale
# local cache). Warns if the hostnames don't yet point at this server — catching
# the "apply succeeded but nothing is reachable because DNS isn't delegated"
# trap before the deploy instead of after.
#   preflight.sh <base_domain> <dashboard_host> <pocket_id_host> <server_ip>
# Needs: dig, curl.
set -uo pipefail # NOT -e: advisory only

base=${1:?}
dash=${2:?}
pid=${3:?}
ip=${4:?}
R=1.1.1.1

command -v dig >/dev/null 2>&1 || { echo "==> pre-flight skipped (no 'dig' on this machine)"; exit 0; }

echo "==> pre-flight DNS check via $R (advisory)"
echo "    authoritative NS for $base: $(dig +short NS "$base" "@$R" 2>/dev/null | tr '\n' ' ')"
warn=0
for h in "$dash" "$pid"; do
  got=$(dig +short A "$h" "@$R" 2>/dev/null | tail -1)
  if [ "$got" = "$ip" ]; then
    echo "    OK  $h -> $ip"
  else
    echo "    !!  $h -> ${got:-(no answer)} (expected $ip) — DNS not delegated/propagated;"
    echo "        the deploy will still configure the box, but users can't reach it until this resolves here."
    warn=1
  fi
done
[ "$warn" -eq 0 ] && echo "    DNS looks ready." || echo "    (continuing — pre-flight is advisory)"
exit 0

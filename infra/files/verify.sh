#!/usr/bin/env bash
# Post-deploy endpoint verification (ADVISORY — runs as Terraform external data source).
# Proves the box serves each endpoint with a valid Let's Encrypt cert, forcing
# the server IP via --resolve so result is immune to local/ISP DNS cache.
# Emits a single JSON object on stdout; always exits 0.
#   verify.sh <dashboard_host> <pocket_id_host> <server_ip>
# Needs: curl, jq. dig optional (for public DNS note).
set -uo pipefail

dash=${1:?}
pid=${2:?}
ip=${3:?}
R=1.1.1.1

# Returns "ok:<code>" or "fail:<code>" for a given host+path.
check_endpoint() {
  local host=$1 path=${2:-/} code=""
  for _ in $(seq 1 24); do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 \
      --resolve "$host:443:$ip" "https://$host$path" 2>/dev/null || true)
    case $code in 2??|3??) echo "ok:$code"; return ;; esac
    sleep 5
  done
  echo "fail:${code:-no-response}"
}

r1=$(check_endpoint "$dash" "/")
r2=$(check_endpoint "$pid" "/setup")

ok="true"
fails=()

case $r1 in
  fail:*) ok="false"; fails+=("https://$dash/ -> ${r1#fail:} (cert not valid? check 'docker logs traefik')") ;;
esac
case $r2 in
  fail:*) ok="false"; fails+=("https://$pid/setup -> ${r2#fail:} (cert not valid? check 'docker logs traefik')") ;;
esac

if [ "$ok" = "true" ]; then
  c1=${r1#ok:}
  c2=${r2#ok:}
  message="endpoints OK: https://$dash/ -> $c1, https://$pid/setup -> $c2 (valid LE cert, forced to $ip)"
else
  message="endpoint failures: $(IFS='; '; echo "${fails[*]}")"
fi

jq -nc --arg ok "$ok" --arg msg "$message" '{ok:$ok, message:$msg}'
exit 0

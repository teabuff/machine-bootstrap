#!/usr/bin/env bash
# Post-deploy verification (ADVISORY — never fails the apply). Proves the box
# actually serves each endpoint with a VALID Let's Encrypt cert (curl with no
# -k, so a bad/default cert fails), forcing the server IP via --resolve so the
# result is immune to local/ISP DNS cache. Also reports whether PUBLIC DNS
# resolves here yet (the thing that gates real user reachability).
#   verify.sh <dashboard_host> <pocket_id_host> <server_ip>
# Needs: curl (dig optional, for the public-DNS note).
set -uo pipefail # NOT -e: advisory only

dash=${1:?}
pid=${2:?}
ip=${3:?}
R=1.1.1.1

# Poll https://<host> (forced to $ip) until it returns a healthy code with a
# valid cert, or ~120s elapses. Echo a clear ✅/❌ and a public-DNS note.
check() {
  local host=$1 path=${2:-/} code="" pub=""
  command -v dig >/dev/null 2>&1 && pub=$(dig +short A "$host" "@$R" 2>/dev/null | tail -1)
  for _ in $(seq 1 24); do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 \
      --resolve "$host:443:$ip" "https://$host$path" 2>/dev/null || true)
    case $code in 2??|3??) break ;; esac
    sleep 5
  done
  case $code in
    2??|3??) echo "    OK  https://$host$path -> $code (valid LE cert on $ip)" ;;
    *)       echo "    FAIL https://$host$path -> ${code:-no-response} on $ip (cert not yet valid? check 'docker logs traefik')" ;;
  esac
  if [ -n "$pub" ] && [ "$pub" != "$ip" ]; then
    echo "        note: public DNS still resolves $host to ${pub:-?}, not $ip — not user-reachable until it does (NS delegation / TTL)."
  fi
}

echo "==> verifying live endpoints (forcing $ip; cert checked via public path)"
check "$dash"
check "$pid" /setup
echo "==> verify done (advisory)"
exit 0

#!/usr/bin/env bash
# Provision code-server for an EXISTING user, behind the zero-trust proxy.
# Binds to the docker bridge gateway so a Dockerized proxy (with
# extra_hosts: host.docker.internal:host-gateway) reaches it at
# http://host.docker.internal:<port>.
#
# User creation is handled elsewhere; this script fails if the user is missing.
# Idempotent: safe to re-run; restarts the service only when config changed.
# Usage: sudo ./setup-code-server.sh [username] [port]
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "❌ run as root: sudo $0" >&2; exit 1; }

echo "=== Code-Server Per-User Provisioning ==="

# 1. Prerequisites: code-server's systemd template and the docker bridge
if ! systemctl list-unit-files 'code-server@.service' | grep -q '^code-server@.service'; then
  echo "❌ code-server@.service not found. Install code-server first:" >&2
  echo "   curl -fsSL https://code-server.dev/install.sh | sh" >&2
  exit 1
fi
# host.docker.internal (host-gateway) resolves to the docker bridge gateway,
# not 127.0.0.1 — bind there so bridged containers can actually connect.
DOCKER_GW=$(ip -4 -o addr show docker0 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
[ -n "$DOCKER_GW" ] || { echo "❌ docker0 bridge not found; is docker running?" >&2; exit 1; }

# 2. Gather inputs (args preferred, prompts as fallback)
CS_USER=${1:-}
CS_PORT=${2:-}
[ -n "$CS_USER" ] || read -rp "Username (must already exist, e.g. dev): " CS_USER
[ -n "$CS_PORT" ] || read -rp "Port to bind on $DOCKER_GW (e.g. 8083): " CS_PORT

[[ "$CS_PORT" =~ ^[0-9]+$ ]] && [ "$CS_PORT" -ge 1024 ] && [ "$CS_PORT" -le 65535 ] ||
  { echo "❌ invalid port: $CS_PORT" >&2; exit 1; }
id "$CS_USER" &>/dev/null ||
  { echo "❌ user '$CS_USER' does not exist; create it first." >&2; exit 1; }

CS_GROUP=$(id -gn "$CS_USER")
USER_HOME=$(getent passwd "$CS_USER" | cut -d: -f6)
CONFIG="$USER_HOME/.config/code-server/config.yaml"

# 3. Refuse a port already claimed by another user's code-server
for other in /home/*/.config/code-server/config.yaml; do
  [ -e "$other" ] && [ "$other" != "$CONFIG" ] || continue
  if grep -q ":$CS_PORT\$" "$other"; then
    echo "❌ port $CS_PORT is already used by $other" >&2
    exit 1
  fi
done

# 4. Make the template wait for docker0 so the bind address exists at boot
install -d /etc/systemd/system/code-server@.service.d
cat > /etc/systemd/system/code-server@.service.d/10-docker-bridge.conf <<'EOF'
# bind-addr lives on docker0; don't start before the bridge is up
[Unit]
After=docker.service
Wants=docker.service
EOF
systemctl daemon-reload

# 5. Converge the config (auth handled by the zero-trust proxy)
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
cat > "$TMP" <<EOF
bind-addr: $DOCKER_GW:$CS_PORT
auth: none
cert: false
EOF
if [ -f "$CONFIG" ] && cmp -s "$TMP" "$CONFIG"; then
  echo "✅ Config already up to date: $CONFIG"
  CHANGED=0
else
  echo "⚙️  Writing $CONFIG..."
  install -d -o "$CS_USER" -g "$CS_GROUP" "$USER_HOME/.config" "$USER_HOME/.config/code-server"
  install -m 0644 -o "$CS_USER" -g "$CS_GROUP" "$TMP" "$CONFIG"
  CHANGED=1
fi

# 6. Enable at boot; restart only if config changed or it isn't running
systemctl enable "code-server@$CS_USER"
if [ "$CHANGED" -eq 1 ] || ! systemctl is-active --quiet "code-server@$CS_USER"; then
  echo "🚀 Restarting code-server@$CS_USER..."
  systemctl restart "code-server@$CS_USER"
fi

# 7. Final output
echo "------------------------------------------------------"
echo "🎉 code-server ready for '$CS_USER'."
echo "🟢 Service Status: $(systemctl is-active "code-server@$CS_USER")"
echo ""
echo "Add this resource to your proxy dashboard pointing to:"
echo "👉 http://host.docker.internal:$CS_PORT"
echo "------------------------------------------------------"

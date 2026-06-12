#!/usr/bin/env bash
# Provision a zellij web server for an EXISTING user, behind the zero-trust
# proxy. Binds to the docker bridge gateway so a Dockerized proxy (with
# extra_hosts: host.docker.internal:host-gateway) reaches it at
# https://host.docker.internal:<port>.
#
# Zellij refuses plain HTTP on non-loopback binds, so a self-signed cert is
# generated per user; point the proxy at https:// with upstream TLS verify
# off, or have it trust /etc/zellij-web/<user>/cert.pem.
#
# User creation is handled elsewhere; this script fails if the user is missing.
# Idempotent: safe to re-run; restarts the service only when config changed.
# Usage: sudo ./setup-zellij-web.sh [username] [port]
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "❌ run as root: sudo $0" >&2; exit 1; }

ZELLIJ_BIN=/usr/local/bin/zellij
ETC_DIR=/etc/zellij-web
UNIT=/etc/systemd/system/zellij-web@.service

echo "=== Zellij Web Per-User Provisioning ==="

# 1. Prerequisites: the system-wide zellij binary (installed by bootstrap.sh
# via a dedicated Nix profile) and the docker bridge
[ -x "$ZELLIJ_BIN" ] ||
  { echo "❌ $ZELLIJ_BIN not found; run bootstrap.sh first." >&2; exit 1; }
# host.docker.internal (host-gateway) resolves to the docker bridge gateway,
# not 127.0.0.1 — bind there so bridged containers can actually connect.
DOCKER_GW=$(ip -4 -o addr show docker0 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
[ -n "$DOCKER_GW" ] || { echo "❌ docker0 bridge not found; is docker running?" >&2; exit 1; }

# 2. Gather inputs (args preferred, prompts as fallback)
ZW_USER=${1:-}
ZW_PORT=${2:-}
[ -n "$ZW_USER" ] || read -rp "Username (must already exist, e.g. dev): " ZW_USER
[ -n "$ZW_PORT" ] || read -rp "Port to bind on $DOCKER_GW (e.g. 8092): " ZW_PORT

[[ "$ZW_PORT" =~ ^[0-9]+$ ]] && [ "$ZW_PORT" -ge 1024 ] && [ "$ZW_PORT" -le 65535 ] ||
  { echo "❌ invalid port: $ZW_PORT" >&2; exit 1; }
id "$ZW_USER" &>/dev/null ||
  { echo "❌ user '$ZW_USER' does not exist; create it first." >&2; exit 1; }

ZW_GROUP=$(id -gn "$ZW_USER")
USER_HOME=$(getent passwd "$ZW_USER" | cut -d: -f6)
ENV_FILE="$ETC_DIR/$ZW_USER.env"
CERT_DIR="$ETC_DIR/$ZW_USER"

# 3. Refuse a port claimed by another zellij-web or any code-server instance
for other in "$ETC_DIR"/*.env; do
  [ -e "$other" ] && [ "$other" != "$ENV_FILE" ] || continue
  if grep -q "^ZW_PORT=$ZW_PORT\$" "$other"; then
    echo "❌ port $ZW_PORT is already used by $other" >&2
    exit 1
  fi
done
for cfg in /home/*/.config/code-server/config.yaml; do
  [ -e "$cfg" ] || continue
  if grep -q ":$ZW_PORT\$" "$cfg"; then
    echo "❌ port $ZW_PORT is already used by code-server ($cfg)" >&2
    exit 1
  fi
done

# 4. Seed the default zellij config if the user has none (a fresh account
# without one makes the web server exit silently right after startup;
# never overwrite an existing config — it's the user's personal file)
ZW_CFG="$USER_HOME/.config/zellij/config.kdl"
if [ ! -f "$ZW_CFG" ]; then
  echo "⚙️  Seeding default zellij config at $ZW_CFG..."
  install -d -o "$ZW_USER" -g "$ZW_GROUP" \
    "$USER_HOME/.config" "$USER_HOME/.config/zellij"
  "$ZELLIJ_BIN" setup --dump-config > "$ZW_CFG"
  chown "$ZW_USER:$ZW_GROUP" "$ZW_CFG"
fi

# 5. Converge the systemd template unit (zellij ships none)
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
cat > "$TMP" <<EOF
[Unit]
Description=Zellij web server (%i)
# bind address lives on docker0; don't start before the bridge is up
After=network.target docker.service
Wants=docker.service

[Service]
User=%i
# new sessions inherit the server's cwd; "~" = home of User= (%h would not be)
WorkingDirectory=~
EnvironmentFile=$ETC_DIR/%i.env
ExecStart=$ZELLIJ_BIN web --ip \${ZW_IP} --port \${ZW_PORT} --cert \${ZW_CERT} --key \${ZW_KEY}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
CHANGED=0
if ! { [ -f "$UNIT" ] && cmp -s "$TMP" "$UNIT"; }; then
  echo "⚙️  Writing $UNIT..."
  install -m 0644 "$TMP" "$UNIT"
  systemctl daemon-reload
  CHANGED=1
fi

# 6. Self-signed cert (zellij always enforces HTTPS on non-loopback binds)
install -d -m 0755 "$ETC_DIR"
install -d -m 0750 -o root -g "$ZW_GROUP" "$CERT_DIR"
if [ ! -f "$CERT_DIR/cert.pem" ]; then
  echo "⚙️  Generating self-signed cert in $CERT_DIR..."
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
    -keyout "$CERT_DIR/key.pem" -out "$CERT_DIR/cert.pem" -days 3650 \
    -subj "/CN=host.docker.internal" \
    -addext "subjectAltName=DNS:host.docker.internal,IP:$DOCKER_GW" 2>/dev/null
  chown "$ZW_USER:$ZW_GROUP" "$CERT_DIR/key.pem"
  chmod 0600 "$CERT_DIR/key.pem"
  chmod 0644 "$CERT_DIR/cert.pem"
  CHANGED=1
fi

# 7. Converge the per-user env file
cat > "$TMP" <<EOF
ZW_IP=$DOCKER_GW
ZW_PORT=$ZW_PORT
ZW_CERT=$CERT_DIR/cert.pem
ZW_KEY=$CERT_DIR/key.pem
EOF
if [ -f "$ENV_FILE" ] && cmp -s "$TMP" "$ENV_FILE"; then
  echo "✅ Config already up to date: $ENV_FILE"
else
  echo "⚙️  Writing $ENV_FILE..."
  install -m 0644 "$TMP" "$ENV_FILE"
  CHANGED=1
fi

# 8. Web login token: create one on first provision (plaintext is only
# available at creation time; zellij stores it hashed and can't re-show it)
NEW_TOKEN=""
if [ -z "$(sudo -H -u "$ZW_USER" "$ZELLIJ_BIN" web --list-tokens 2>/dev/null)" ]; then
  NEW_TOKEN=$(sudo -H -u "$ZW_USER" "$ZELLIJ_BIN" web --create-token | tail -1)
fi

# 9. Let the user manage their own instance (exact unit names only — no
# wildcards, so they can't touch other users' services; status needs no sudo)
cat > "$TMP" <<EOF
$ZW_USER ALL=(root) NOPASSWD: /usr/bin/systemctl start zellij-web@$ZW_USER.service, /usr/bin/systemctl stop zellij-web@$ZW_USER.service, /usr/bin/systemctl restart zellij-web@$ZW_USER.service
EOF
visudo -cf "$TMP" >/dev/null
install -m 0440 "$TMP" "/etc/sudoers.d/zellij-web-${ZW_USER//./_}"

# 10. Enable at boot; restart only if something changed or it isn't running
systemctl enable "zellij-web@$ZW_USER"
if [ "$CHANGED" -eq 1 ] || ! systemctl is-active --quiet "zellij-web@$ZW_USER"; then
  echo "🚀 Restarting zellij-web@$ZW_USER..."
  systemctl restart "zellij-web@$ZW_USER"
fi

# 11. Final output
echo "------------------------------------------------------"
echo "🎉 zellij web ready for '$ZW_USER'."
echo "🟢 Service Status: $(systemctl is-active "zellij-web@$ZW_USER")"
echo ""
echo "Add this resource to your proxy dashboard pointing to:"
echo "👉 https://host.docker.internal:$ZW_PORT"
echo ""
if [ -n "$NEW_TOKEN" ]; then
  echo "🔑 Login token (shown ONCE — send it to the developer):"
  echo "   ${NEW_TOKEN##*: }"
else
  echo "🔑 User already has a login token. To issue another one:"
  echo "   sudo -u $ZW_USER zellij web --create-token"
fi
echo ""
echo "To attach to sessions started in a terminal, the user needs"
echo "web_sharing \"on\" in ~/.config/zellij/config.kdl."
echo "------------------------------------------------------"

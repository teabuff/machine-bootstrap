#!/usr/bin/env bash
# Lock the host firewall down to only what this stack needs (ufw). Idempotent.
# SSH-SAFE: the SSH port is allowed BEFORE the firewall is enabled, so an apply
# can never lock you out. Run as root.
#   ./firewall.sh <ssh_port> [enabled]      enabled defaults to "true"
#
# NOTE on Docker: Docker publishes container ports via its own iptables rules
# that BYPASS ufw, so the 80/443/51820/21820 allows below are belt-and-suspenders
# — Docker exposes exactly what docker-compose publishes regardless of ufw. What
# ufw actually guarantees here: SSH stays reachable and *host* services are
# default-denied (matters most on a fresh box with no firewall at all). To
# restrict the Docker-published ports themselves (e.g. by source IP) you'd need
# DOCKER-USER rules — out of scope.
set -euo pipefail

ssh_port=${1:?usage: firewall.sh <ssh_port> [enabled]}
enabled=${2:-true}
[ "$enabled" = "true" ] || { echo "==> firewall management disabled (manage_firewall=false)"; exit 0; }

if ! command -v ufw >/dev/null 2>&1; then
  echo "==> installing ufw"
  apt-get update -qq && apt-get install -y -qq ufw
fi

ufw allow "${ssh_port}/tcp" comment 'ssh'            # FIRST — must precede enable
ufw allow 80/tcp            comment 'http / acme'
ufw allow 443/tcp           comment 'https'
ufw allow 51820/udp         comment 'wireguard (gerbil)'
ufw allow 21820/udp         comment 'gerbil relay'
ufw default deny incoming
ufw default allow outgoing
ufw --force enable

echo "==> firewall active:"
ufw status verbose

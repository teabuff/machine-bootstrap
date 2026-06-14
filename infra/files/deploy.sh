#!/usr/bin/env bash
# Idempotent: install Docker if missing, then converge the Pangolin + Pocket ID
# stack. Uploaded and invoked by OpenTofu/Terraform; safe to run by hand too.
#   ./deploy.sh [stack_dir]   (default /opt/pangolin-stack)
set -euo pipefail

stack_dir=${1:-/opt/pangolin-stack}
cd "$stack_dir"

if ! command -v docker >/dev/null 2>&1; then
  echo "==> installing Docker (get.docker.com)"
  curl -fsSL https://get.docker.com | sh
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "ERROR: the Docker Compose v2 plugin is not available." >&2
  echo "       Install it (e.g. 'apt-get install docker-compose-plugin') and re-run." >&2
  exit 1
fi

# Traefik stores its ACME state here; the dir must exist before first start.
mkdir -p config/letsencrypt

echo "==> pulling images"
docker compose pull --quiet

echo "==> converging stack"
# --force-recreate so bind-mounted config changes (config.yml, traefik configs)
# actually take effect — compose otherwise only recreates on service-spec changes.
# This script only runs when Terraform sees a config/script change, so it isn't
# churning on no-op applies.
docker compose up -d --remove-orphans --force-recreate

echo "==> current state"
docker compose ps

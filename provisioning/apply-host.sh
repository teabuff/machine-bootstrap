#!/usr/bin/env bash
# Apply a declarative host manifest (idempotent; safe to re-run).
# Usage: sudo provisioning/apply-host.sh <manifest>
set -euo pipefail

[[ $# -eq 1 ]] || { echo "usage: sudo provisioning/apply-host.sh <manifest>" >&2; exit 2; }
manifest=$1

[[ $(id -u) -eq 0 ]] || { echo "run as root: sudo $0 $manifest" >&2; exit 1; }
[[ -r $manifest ]] || { echo "cannot read manifest: $manifest" >&2; exit 1; }

# Fail fast on a malformed manifest before mutating anything.
bash -n "$manifest" || { echo "manifest has syntax errors: $manifest" >&2; exit 1; }

# shellcheck source=declare.sh
source "$(cd "$(dirname "$0")" && pwd)/declare.sh"

echo "==> applying $manifest"
# shellcheck source=/dev/null
source "$manifest"
echo "==> done"

#!/usr/bin/env bash
# Bootstrap a fresh Ubuntu machine:
#   - zsh as default shell for new and existing human users
#   - Determinate Nix (multi-user daemon install)
#   - direnv + nix-direnv system-wide, hooked into zsh for everyone
#   - zellij system-wide (per-user setup lives in setup-zellij-web.sh)
#
# Idempotent: safe to re-run on an already-bootstrapped machine.
# Usage: sudo ./bootstrap.sh
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo $0" >&2; exit 1; }

NIX=/nix/var/nix/profiles/default/bin/nix
DIRENV_PROFILE=/nix/var/nix/profiles/direnv
ZELLIJ_PROFILE=/nix/var/nix/profiles/zellij

echo "==> 1/8 Base packages (zsh, curl, git)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -qy zsh curl git

echo "==> 2/8 Determinate Nix (multi-user)"
if [ ! -x "$NIX" ]; then
  curl -fsSL https://install.determinate.systems/nix | sh -s -- install --no-confirm
else
  echo "already installed: $($NIX --version)"
fi

echo "==> 3/8 Default shell for newly created users"
sed -i 's|^#\?\s*DSHELL=.*|DSHELL=/usr/bin/zsh|' /etc/adduser.conf
useradd -D -s /usr/bin/zsh

echo "==> 4/8 direnv + nix-direnv in a dedicated system-wide Nix profile"
# Dedicated profile (not Determinate's managed default profile) so nix
# upgrades never touch it; profiles are GC roots so it survives GC.
if [ ! -e "$DIRENV_PROFILE/share/nix-direnv/direnvrc" ]; then
  "$NIX" profile add --profile "$DIRENV_PROFILE" nixpkgs#direnv nixpkgs#nix-direnv
fi
ln -sf "$DIRENV_PROFILE/bin/direnv" /usr/local/bin/direnv

echo "==> 5/8 zellij in a dedicated system-wide Nix profile"
# Shared binary so the zellij-web@ systemd template (setup-zellij-web.sh)
# and every user's terminal run the same version (client/server must match).
# Pinned to 0.44.1: the web client in 0.44.2-0.44.3 doesn't deliver Escape
# (https://github.com/zellij-org/zellij/issues/5190). Unpin when fixed.
ZELLIJ_VERSION=0.44.1
ZELLIJ_NIXPKGS=github:NixOS/nixpkgs/01fbdeef22b76df85ea168fbfe1bfd9e63681b30
if [ "$("$ZELLIJ_PROFILE/bin/zellij" --version 2>/dev/null)" != "zellij $ZELLIJ_VERSION" ]; then
  "$NIX" profile remove --profile "$ZELLIJ_PROFILE" zellij 2>/dev/null || true
  "$NIX" profile add --profile "$ZELLIJ_PROFILE" "$ZELLIJ_NIXPKGS#zellij"
fi
ln -sf "$ZELLIJ_PROFILE/bin/zellij" /usr/local/bin/zellij

echo "==> 6/8 direnv zsh hook for all users"
if ! grep -q 'direnv hook zsh' /etc/zsh/zshrc; then
  cat >> /etc/zsh/zshrc <<'EOF'

# direnv (system-wide; hook is idempotent, safe alongside per-user hooks)
command -v direnv >/dev/null && eval "$(direnv hook zsh)"
EOF
fi

echo "==> 7/8 Seed /etc/skel for future users"
mkdir -p /etc/skel/.config/direnv
echo "source $DIRENV_PROFILE/share/nix-direnv/direnvrc" > /etc/skel/.config/direnv/direnvrc
# Baseline user zshrc (also stops zsh-newuser-install prompting on first login).
# skel is system-owned, so overwrite on every run to converge with the repo.
install -m 0644 "$(cd "$(dirname "$0")" && pwd)/skel/zshrc" /etc/skel/.zshrc

echo "==> 8/8 Backfill existing human users (uid 1000-29999 with a home dir)"
awk -F: '$3 >= 1000 && $3 < 30000 && $6 ~ /^\/home\// {print $1":"$6}' /etc/passwd |
while IFS=: read -r user home; do
  [ -d "$home" ] || continue
  # Only treat bash/zsh accounts as human; anything else (sh, nologin, false)
  # is a service account (e.g. linuxbrew) whose shell choice is deliberate.
  shell=$(getent passwd "$user" | cut -d: -f7)
  case "$shell" in
    */zsh) ;;
    */bash) chsh -s /usr/bin/zsh "$user"; echo "  $user: shell -> zsh" ;;
    *) echo "  $user: skipping service account (shell $shell)"; continue ;;
  esac
  # nix-direnv config (don't overwrite an existing one)
  if [ ! -f "$home/.config/direnv/direnvrc" ]; then
    install -d -o "$user" -g "$(id -gn "$user")" "$home/.config" "$home/.config/direnv"
    echo "source $DIRENV_PROFILE/share/nix-direnv/direnvrc" > "$home/.config/direnv/direnvrc"
    chown "$user:$(id -gn "$user")" "$home/.config/direnv/direnvrc"
    echo "  $user: direnvrc created"
  fi
done

echo "==> Done. Verification:"
grep '^DSHELL' /etc/adduser.conf
useradd -D | grep -i shell
/usr/local/bin/direnv --version
/usr/local/bin/zellij --version
tail -2 /etc/zsh/zshrc
echo "New users: adduser <name>  ->  zsh + nix + direnv ready. Per-repo: direnv allow."

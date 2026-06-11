#!/usr/bin/env bash
# Bootstrap a fresh Ubuntu machine:
#   - zsh as default shell for new and existing human users
#   - Determinate Nix (multi-user daemon install)
#   - direnv + nix-direnv system-wide, hooked into zsh for everyone
#
# Idempotent: safe to re-run on an already-bootstrapped machine.
# Usage: sudo ./bootstrap.sh
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo $0" >&2; exit 1; }

NIX=/nix/var/nix/profiles/default/bin/nix
DIRENV_PROFILE=/nix/var/nix/profiles/direnv

echo "==> 1/7 Base packages (zsh, curl, git)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -qy zsh curl git

echo "==> 2/7 Determinate Nix (multi-user)"
if [ ! -x "$NIX" ]; then
  curl -fsSL https://install.determinate.systems/nix | sh -s -- install --no-confirm
else
  echo "already installed: $($NIX --version)"
fi

echo "==> 3/7 Default shell for newly created users"
sed -i 's|^#\?\s*DSHELL=.*|DSHELL=/usr/bin/zsh|' /etc/adduser.conf
useradd -D -s /usr/bin/zsh

echo "==> 4/7 direnv + nix-direnv in a dedicated system-wide Nix profile"
# Dedicated profile (not Determinate's managed default profile) so nix
# upgrades never touch it; profiles are GC roots so it survives GC.
if [ ! -e "$DIRENV_PROFILE/share/nix-direnv/direnvrc" ]; then
  "$NIX" profile install --profile "$DIRENV_PROFILE" nixpkgs#direnv nixpkgs#nix-direnv
fi
ln -sf "$DIRENV_PROFILE/bin/direnv" /usr/local/bin/direnv

echo "==> 5/7 direnv zsh hook for all users"
if ! grep -q 'direnv hook zsh' /etc/zsh/zshrc; then
  cat >> /etc/zsh/zshrc <<'EOF'

# direnv (system-wide; hook is idempotent, safe alongside per-user hooks)
command -v direnv >/dev/null && eval "$(direnv hook zsh)"
EOF
fi

echo "==> 6/7 Seed /etc/skel for future users"
mkdir -p /etc/skel/.config/direnv
echo "source $DIRENV_PROFILE/share/nix-direnv/direnvrc" > /etc/skel/.config/direnv/direnvrc
# An existing .zshrc (even minimal) stops zsh-newuser-install prompting on first login
[ -f /etc/skel/.zshrc ] || cat > /etc/skel/.zshrc <<'EOF'
# Default user zshrc. direnv and Nix are configured system-wide
# (/etc/zsh/zshrc and /etc/profile.d/nix.sh); add personal config below.
EOF

echo "==> 7/7 Backfill existing human users (uid 1000-29999 with a home dir)"
awk -F: '$3 >= 1000 && $3 < 30000 && $6 ~ /^\/home\// {print $1":"$6}' /etc/passwd |
while IFS=: read -r user home; do
  [ -d "$home" ] || continue
  # shell -> zsh (skip service-ish accounts that deliberately use nologin/false)
  shell=$(getent passwd "$user" | cut -d: -f7)
  case "$shell" in
    */nologin|*/false) echo "  $user: skipping (shell $shell)"; continue ;;
    */zsh) ;;
    *) chsh -s /usr/bin/zsh "$user"; echo "  $user: shell -> zsh" ;;
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
tail -2 /etc/zsh/zshrc
echo "New users: adduser <name>  ->  zsh + nix + direnv ready. Per-repo: direnv allow."

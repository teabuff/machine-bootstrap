# machine-bootstrap

One-script setup for a fresh Ubuntu machine: zsh as the default shell for
everyone, [Determinate Nix](https://determinate.systems) (multi-user), and
direnv + [nix-direnv](https://github.com/nix-community/nix-direnv) available
system-wide so every user — existing or newly created — gets `use flake`
caching with zero per-user setup.

## Usage

```sh
git clone <this-repo> && cd machine-bootstrap
sudo ./bootstrap.sh
```

Idempotent — re-run any time (e.g. after adding users manually, or to converge
a drifted machine).

## What it configures

| Layer | Mechanism |
|---|---|
| zsh for new users | `DSHELL` in `/etc/adduser.conf` + `useradd -D -s` |
| zsh for existing users | `chsh` for human accounts (uid 1000–29999 currently on bash/zsh; service accounts on sh/nologin/false are left alone) |
| Nix | Determinate installer, multi-user daemon; PATH via `/etc/profile.d` |
| direnv + nix-direnv | Dedicated Nix profile `/nix/var/nix/profiles/direnv` (GC root, untouched by Determinate's managed default profile); binary symlinked to `/usr/local/bin/direnv` |
| direnv zsh hook | `/etc/zsh/zshrc` (all users, idempotent) |
| New-user defaults | `/etc/skel/.zshrc` + `/etc/skel/.config/direnv/direnvrc` |

Deliberately untouched: root stays on bash; per-repo `direnv allow` remains
manual (direnv's security gate).

## Declarative host provisioning

`apply-host.sh` converges a machine to a small declarative manifest — shared
Unix groups (with fixed, cross-host GIDs), setgid group-owned `/data/<group>`
directories, and enabled services:

```sh
sudo ./apply-host.sh hosts/<name>.host
```

A manifest is a list of idempotent verbs (`group`, `dir`, `service`); see
`hosts/example.host`. Re-run any time. Fixed GIDs keep `/data/<group>`
ownership identical on every host, so users provisioned into a group share
files cleanly. The engine is `lib/declare.sh`.

Smoke test (needs Docker): `bash tests/smoke-apply-host.sh`.

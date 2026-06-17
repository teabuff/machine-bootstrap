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

## Pangolin + Pocket ID (remote, zero-touch)

A self-hosted [Pangolin](https://docs.pangolin.net) reverse proxy + [Pocket ID](https://pocket-id.org)
OIDC provider on a remote box, brought up and configured with **no UI clicks**.

## Terraform roots

Three OpenTofu roots, applied in order, with a one-directional dependency:

| Root      | Layer            | Owns                                                       | Reads                            |
| --------- | ---------------- | ---------------------------------------------------------- | -------------------------------- |
| `host/`   | machine          | box, DNS, certs, docker compose, API-key mint              | —                                |
| `idp/`    | Pocket ID (IdP)  | OIDC client, groups, users                                 | `host`                           |
| `access/` | Pangolin (proxy) | org, roles, OIDC IdP registration + org/role mapping       | `host`, `idp` (client id/secret) |

Apply order: `host` → `idp` → `access`. The group **name** is the only policy
contract between `idp` and `access`. For multi-env state on Cloudflare R2, each
root takes `*_state_backend`/`*_state_config` (see each root's `example.tfvars`).

### Host SSH prep (one-time, manual)

`host/` connects as **root** and runs privileged steps directly (no `sudo`
wrapping), so the box must accept key-based root SSH with your deploy key. This
is deliberately **not** automated — set it up once on a fresh box, as its
initial sudo user:

```sh
# 1. authorize your deploy public key for root
sudo install -d -m700 /root/.ssh
echo 'ssh-ed25519 AAAA…your-deploy-key' | sudo tee -a /root/.ssh/authorized_keys >/dev/null
sudo chmod 600 /root/.ssh/authorized_keys

# 2. key/cert-only SSH policy, in one authoritative drop-in
sudo tee /etc/ssh/sshd_config.d/10-ssh-auth.conf >/dev/null <<'EOF'
PermitRootLogin prohibit-password
PubkeyAuthentication yes
PasswordAuthentication no
EOF
sudo sshd -t && sudo systemctl reload ssh
```

Then set `ssh_user = "root"` in `terraform.tfvars`. (Pangolin's own JIT SSH users
authenticate by short-lived CA cert, so `PasswordAuthentication no` doesn't affect
them.)

Beyond that host prep, the only provisioning step that needs a human is enrolling a
login **passkey** once at Pocket ID's `/setup` — admin, OIDC client, IdP, and org
mapping need no passkey and no UI.

### Identity-aware SSH (Enterprise Edition)

`host/` also runs Pangolin's **Enterprise Edition** image and, with
`enable_ssh_access` (on by default), provisions identity-aware SSH. EE is **free**
for personal use / businesses under USD 100k revenue but is **required** for SSH:
set `pangolin_license_key` in tfvars and it is activated headlessly on apply
(`fosrl/pangolin:ee-…`). A host-native [`newt`](https://github.com/fosrl/newt)
runs as the auth-daemon, and a Pangolin **blueprint** declares a private SSH
resource (`pangolin ssh <user>@<host>-ssh`, alias `<host>.internal`) plus an
optional public browser-SSH resource (`shell.<domain>`). A user authenticates
with their Pocket ID identity, gets a 5-minute CA-signed cert, and is
JIT-provisioned as a Linux user (= their email local-part, prefixed `p-`) with
per-role RBAC: a fixed-GID Unix **group** (via `apply-host.sh`), scoped **sudo**
(e.g. `ufw`), and a home dir. See [`host/SSH-ACCESS.md`](host/SSH-ACCESS.md).

**`newt-site/`** is an optional add-on: a Dockerized [Newt](https://github.com/fosrl/newt)
connector for a homelab/site host that self-registers with a provisioning key (and can
continuously apply a resource blueprint). Not needed by the hub itself.

> Why bash behind OpenTofu and not Terraform resources? There is no provider for Pangolin/
> Pocket ID *application* objects (admin, OIDC client, IdP) — the closest, blueprint-declared
> IdPs, is unshipped upstream (fosrl/pangolin#1895). So `host/` owns the infra-shaped,
> stateful work and calls idempotent bash for the API dance.

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
OIDC provider on a remote box, brought up and configured with **no UI clicks**. Two layers:

- **`infra/`** — OpenTofu/Terraform (works with `tofu` or `terraform`). Owns the
  infra + deploy: Cloudflare DNS (apex + `*.wildcard`), generated secrets, renders the
  compose stack (`pangolin` + `gerbil` + `traefik` + `pocket-id`), ships it to a
  bring-your-own server over SSH, and runs it. Then a `configure` step closes the loop —
  see below. Start at [`infra/README.md`](infra/README.md):

  ```sh
  cd infra && cp example.tfvars terraform.tfvars   # edit it
  tofu init && tofu apply -var-file=terraform.tfvars
  ```

- **`provision-sso.sh`** + **`lib/sso.sh`** — the headless config-plane invoked by `infra/`
  (or by hand). Seeds the Pangolin admin (`pangctl`), then wires Pangolin ⇄ Pocket ID SSO
  entirely over each product's HTTP API: Pocket ID's `STATIC_API_KEY` → a hidden admin →
  deterministic OIDC client; Pangolin's `/api/v1` driven with a session cookie + CSRF →
  identity provider + the two-pass redirect callback. Idempotent; realm config lives in
  private `hosts/*.sso.{conf,identity}` (gitignored; see the `example.*`).

  ```sh
  ./provision-sso.sh hosts/<realm>.sso.conf hosts/<realm>.sso.identity   # standalone use
  bash tests/dryrun-provision-sso.sh                                     # offline test
  ```

The only step that still needs a human is enrolling a login **passkey** once at Pocket ID's
`/setup` — provisioning (admin, OIDC client, IdP, org mapping) needs no passkey and no UI.

**`newt-site/`** is an optional add-on: a Dockerized [Newt](https://github.com/fosrl/newt)
connector for a homelab/site host that self-registers with a provisioning key (and can
continuously apply a resource blueprint). Not needed by the hub itself.

> Why bash behind OpenTofu and not Terraform resources? There is no provider for Pangolin/
> Pocket ID *application* objects (admin, OIDC client, IdP) — the closest, blueprint-declared
> IdPs, is unshipped upstream (fosrl/pangolin#1895). So `infra/` owns the infra-shaped,
> stateful work and calls idempotent bash for the API dance.

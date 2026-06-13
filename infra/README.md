# infra — Pangolin + Pocket ID on a remote server

OpenTofu/Terraform that stands up [Pangolin](https://docs.pangolin.net) (self-hosted
tunneled reverse proxy) and [Pocket ID](https://pocket-id.org) (OIDC / passkey provider)
on a server **you already created**.

It is **bring-your-own-server**: it does not create the VM, so it works the same on
Bandwagon, V.PS, Hetzner, or anything else with SSH. It manages three things:

1. **Cloudflare DNS** — an apex record and a `*.<base_domain>` wildcard, both DNS-only.
2. **The stack** — renders the Pangolin + Pocket ID compose stack and configs from your
   variables, pushes them over SSH, and runs an idempotent deploy.
3. **Secrets** — Pangolin's `server.secret` and Pocket ID's `ENCRYPTION_KEY` are generated
   automatically and kept in local state (never prompted, never committed).

## Why a wildcard record (and not subdomain delegation)

A single DNS-only `*.<base_domain>` → server record means every hostname under
`<base_domain>` already resolves to the box. Add a resource in Pangolin's UI at
`anything.<base_domain>` and Traefik issues its cert (HTTP-01) automatically — **zero
further Cloudflare changes**. Records are DNS-only because Pangolin needs the raw IP for
its WireGuard tunnels and terminates TLS itself; that also keeps you on Cloudflare's free
tier (proxied wildcards are Enterprise-only). True NS delegation would require running
your own authoritative DNS server, which Pangolin has no use for — so it's intentionally
not used.

## Prerequisites

- A server with a public IPv4, SSH access (key-based), and ports **80, 443, 51820/udp,
  21820/udp** reachable from the internet.
- A domain on Cloudflare; note its **Zone ID** (zone Overview page) and create an API
  token with **Zone → DNS → Edit** on that zone.
- `tofu` (or `terraform`) locally. This config is provider-pinned and works with either.

## Usage

```sh
cd infra
cp example.tfvars terraform.tfvars   # then edit terraform.tfvars
tofu init
tofu apply -var-file=terraform.tfvars
```

`apply` is idempotent — re-run any time to converge DNS or redeploy the stack. State is
local and gitignored; **back up `terraform.tfstate`** (it holds the generated secrets).

To pin versions for reproducibility, set `pangolin_version` / `gerbil_version` /
`pocket_id_version` in `terraform.tfvars`. Keep `badger_version` matched to the Pangolin
release (bump them together).

## Headless admin + SSO (no UI)

`apply` does more than deploy — a `null_resource.configure` step runs on the box (over
loopback, so no public DNS/cert needs to be live) and:

1. **Seeds the Pangolin server admin** with `pangctl set-admin-credentials`
   (`pangolin_admin_email` / `pangolin_admin_password`) — no setup wizard.
2. **Wires SSO** (when `enable_sso = true`, the default) by running `../provision-sso.sh`:
   Pocket ID's `STATIC_API_KEY` creates a hidden admin, the deterministic OIDC client
   `pangolin` is created, and Pangolin gets an identity provider pointing at it — including
   the two-pass redirect-URL callback. Optionally seeds groups/users from
   `sso_identity_file` and maps group claims onto an org (`pangolin_org_id`).

The mechanics live in `provision-sso.sh` / `lib/sso.sh` (Pangolin drives its own `/api/v1`
with a session cookie + CSRF; Pocket ID uses `X-API-Key`); see the repo root
[provisioning docs](../README.md). The dry-run test (`tests/dryrun-provision-sso.sh`)
exercises the full flow offline.

### The only human step

Passkeys can't be provisioned headlessly: open `https://id.<base_domain>/setup` **once** to
enrol your admin passkey, then log into `https://pangolin.<base_domain>` (via Pocket ID if
SSO is on). `tofu output next_steps` prints exactly this.

Set `enable_sso = false` to deploy + seed the admin only and wire SSO later.

## Adding a service behind Pangolin

In the Pangolin dashboard create a **resource** with hostname `foo.<base_domain>`. It works
immediately — the wildcard already resolves and Traefik issues the cert. No DNS or
OpenTofu change needed.

## Where these configs come from (and regenerating with geo/CrowdSec)

The `files/` templates are vendored from the official `fosrl/pangolin` source
(`config/config.example.yml`, `config/traefik/*.yml`, `docker-compose.example.yml`) with
the upstream `{{.Placeholders}}` swapped for OpenTofu `${...}` vars and a Pocket ID router
added. Badger is pinned to `v1.4.1` and Traefik to `v3.6` to match the Pangolin release —
bump `badger_version` / `*_version` together when you upgrade.

This is the installer's **no-geo** output. The official installer (a Go binary that embeds
these same templates) can also wire in **CrowdSec** (behavioral IPS + community blocklist)
and **MaxMind** (geo-blocking). To adopt them later without hand-porting, regenerate a
baseline and re-vendor it:

```sh
# On a throwaway/staging box (the installer wants ports 80/443 free and runs docker).
# Get the binary: fosrl/pangolin releases, or the repo's install/get-installer.sh.
sudo ./installer --crowdsec           # prompts for domain/email/etc; --crowdsec opts in

# It writes ./config/{config.yml,docker-compose.yml,traefik/*} (+ crowdsec/ if enabled).
# Diff those against infra/files/, copy in the new bits, and re-introduce the ${...} vars:
#   example.com           -> ${base_domain}
#   pangolin.example.com  -> ${dashboard_host}
#   the generated secret  -> ${pangolin_secret}
#   the Let's Encrypt mail -> ${letsencrypt_email}
# Keep the Pocket ID service + pocket-id-router/service block from dynamic_config.yml.
```

The installer also runs non-interactively (pipe answers to stdin — it auto-detects non-TTY
and reads them in order), but that answer order is release-specific and brittle, so prefer
running it once interactively and vendoring the result.

## Layout

```
infra/
  versions.tf      providers + version pins (tofu/terraform compatible)
  variables.tf     all inputs
  main.tf          secrets, Cloudflare records, SSH deploy
  outputs.tf       URLs + next steps
  example.tfvars   template (committed); terraform.tfvars is gitignored
  files/
    docker-compose.yml.tftpl
    deploy.sh                         install Docker + compose up -d (idempotent)
    config/config.yml.tftpl           Pangolin config
    config/traefik/traefik_config.yml.tftpl   static Traefik (Badger, ACME)
    config/traefik/dynamic_config.yml.tftpl   routers (dashboard + Pocket ID)
```

This is a single-host layout. When you add a second realm/region, lift `main.tf`'s deploy
block and the `files/` templates into a reusable module and call it once per realm.

# config — declarative SSO for Pangolin + Pocket ID

A second OpenTofu root (separate state from `../infra`). It reads the bootstrap's
outputs via `terraform_remote_state` and uses the native `pangolin` + `pocketid`
providers to declaratively create:

- the Pocket ID OIDC client `pangolin` (with a wildcard callback),
- the Pangolin org + custom roles,
- the Pangolin → Pocket ID OIDC IdP + org/role mapping.

This replaces the imperative `provision-sso.sh`. Unlike the bash (which ran on the
box over loopback), these providers run from your machine against the **public**
Pangolin/Pocket ID endpoints — so the stack must already be up with valid TLS.

## Prerequisite

Apply `../infra` first (it deploys the stack, seeds the admin, mints the Integration
API key, and now has `enable_sso = false`). The endpoints must serve valid certs.

## Usage

```sh
cd ../infra && tofu apply            # bring up the stack + mint the key
cd ../config
cp example.tfvars terraform.tfvars   # set org_name (+ optional overrides)
tofu init
tofu apply -var-file=terraform.tfvars
```

State is **local** for now; Plan 3 moves both roots to Cloudflare R2 and a
dir-per-env layout.

## The cycle-break

The Pocket ID client registers a scoped path-wildcard callback
`https://<dashboard>/auth/idp/*/oidc/callback`, so it does not depend on the
server-assigned IdP id — the OIDC-client ↔ IdP dependency cycle disappears.

# envs/example — per-environment template (copy into your PRIVATE envs repo)

A template for running one environment as two thin roots that consume the public
`machine-bootstrap` `host/` + `config/` as **pinned git modules**, with per-env
state in **Cloudflare R2**. Copy this directory into a private repo (e.g.
`machine-bootstrap-envs`) as `production/<realm>/<env>/` and fill in real values —
**real domains, IPs, and the R2 account id stay in the private repo, never here.**

```
production/<realm>/<env>/
  bootstrap/   deploy + mint key   (state key …/<env>/bootstrap.tfstate)
  config/      declarative SSO     (state key …/<env>/config.tfstate)
```

## One-time setup

1. R2 bucket (e.g. `machine-bootstrap-tfstate`) + an R2 API token. Put the token
   in `~/.aws/credentials` under a `[r2]` profile (the backends use `profile = "r2"`).
2. In every `backend.tf` and in `config/variables.tf`, replace `ACCOUNT_ID` with
   your Cloudflare account id, `production/EXAMPLE` with your real env path, and
   `?ref=REF` with a pinned release tag (e.g. `?ref=v0.3.0`).
3. `cp .envrc.example .envrc`, fill the `TF_VAR_*` secrets, and `source .envrc`.

## Apply order (bootstrap, then config)

```sh
cd bootstrap
cp terraform.tfvars.example terraform.tfvars   # set server_ip/base_domain/etc.
tofu init && tofu apply

cd ../config
cp terraform.tfvars.example terraform.tfvars   # set org_name
tofu init && tofu apply   # reads the bootstrap state from R2 and wires SSO
```

The endpoints must be up with valid TLS before `config/ apply` (the providers call
the public Pangolin/Pocket ID over HTTPS). Add more envs by copying the dir and
changing the per-env values + the two state `key`s.

## Notes

- State + locking: R2 via the `s3` backend with `use_lockfile = true` (native
  locking, validated on R2 — no DynamoDB).
- `bootstrap/` runs with `enable_sso = false` / `enable_ssh_access = false`; the
  declarative `config/` owns SSO. Identity-aware SSH returns in a later plan.
- Secrets never live in committed files: app secrets via `TF_VAR_*`, R2 creds via
  the `[r2]` profile.

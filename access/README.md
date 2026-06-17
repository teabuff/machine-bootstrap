# access/ — Pangolin access plane

Creates the org, custom roles, and the external OIDC IdP pointing at Pocket ID,
plus the IdP↔org binding (role/org mapping).

**Reads** the `host/` state (Pangolin URL + API key + org id + root domain +
Pocket ID URL) and the `idp/` state (`client_id` + `client_secret` — the only
cross-module data handoff). Configures `pangolin_idp` from those two strings; it
does not call Pocket ID at apply time.

## Contract with idp/
`group_roles` keys are Pocket ID group **names** declared in `idp/`. The IdP
asserts group membership via the `groups` claim at login; this module maps those
names to Pangolin roles.

## Usage
```bash
cd access
cp example.tfvars terraform.tfvars   # edit org_name / group_roles
tofu init && tofu apply
```
Standalone reads sibling `host/` and `idp/` local states. For multi-env, set
`host_state_backend`/`idp_state_backend = "s3"` + the matching `*_state_config`.

## Apply order
`host` → `idp` → **`access`** (access depends on idp's outputs).

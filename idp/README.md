# idp/ — Pocket ID identity plane

Creates the Pangolin OIDC client (deterministic id `pangolin`, scoped wildcard
callback that breaks the client↔IdP cycle) and the declarative group/user roster.

**Reads** the `host/` state for the Pocket ID base URL + STATIC_API_KEY and the
Pangolin dashboard URL (callback). **Exports** `client_id` and `client_secret`
(sensitive) for the `access/` plane to consume.

## Contract with access/
The group **name** is the interface. Declare groups here; map those same names to
Pangolin roles in `access/`'s `group_roles`. This module never references Pangolin
roles.

## Usage
```bash
cd idp
cp example.tfvars terraform.tfvars   # edit groups/users
tofu init && tofu apply
```
Standalone reads the sibling `host/terraform.tfstate`. For multi-env, set
`host_state_backend = "s3"` + `host_state_config` (see example.tfvars).

## Apply order
`host` → **`idp`** → `access`.

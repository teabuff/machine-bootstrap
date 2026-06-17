locals {
  dashboard_url = local.bootstrap.pangolin_dashboard_url # https://pangolin.<base_domain>
  pocket_id_url = local.bootstrap.pocket_id_base_url     # https://id.<base_domain>
  org_id        = local.bootstrap.org_id
  root_domain   = local.bootstrap.root_domain

  # Scoped path-wildcard callback: matches https://<dashboard>/auth/idp/<N>/oidc/callback
  # for any server-assigned IdP id N, WITHOUT depending on pangolin_idp — this is
  # what breaks the OIDC-client <-> IdP cycle. Verified: the pocketid provider's URL
  # validator allows '*', and Pocket ID matches it at authorize+token time.
  pangolin_callback = "${local.dashboard_url}/auth/idp/*/oidc/callback"

  # Pocket ID OIDC endpoints (stable paths).
  pid_auth_url  = "${local.pocket_id_url}/authorize"
  pid_token_url = "${local.pocket_id_url}/api/oidc/token"

  # IdP role mapping: default = Member for company (@root_domain) emails, else Guest.
  # Array form ['Member'] matches Pangolin's multi-role return type. Guards the email
  # claim (ends_with on a null claim throws -> 500 login).
  default_role_fallback = "email && ends_with(email, '@${local.root_domain}') && ['Member'] || ['Guest']"

  # Compile group->role from var.groups (the bash build_role_mapping equivalent):
  # a user in several mapped groups gets all those roles; unmatched -> fallback.
  mapped_groups = [for g in var.groups : g if g.pangolin_role != ""]
  compiled_role_mapping = length(local.mapped_groups) > 0 ? format(
    "([%s][?@]) || (%s)",
    join(", ", [for g in local.mapped_groups : "groups && contains(groups, '${g.name}') && '${g.pangolin_role}'"]),
    local.default_role_fallback,
  ) : local.default_role_fallback

  # Verbatim override wins; else the compiled mapping.
  role_mapping = var.idp_role_mapping != "" ? var.idp_role_mapping : local.compiled_role_mapping

  # Org membership: must return the org id (or true) to admit. Default = admit all.
  org_mapping = var.idp_org_mapping != "" ? var.idp_org_mapping : "'${local.org_id}'"
}

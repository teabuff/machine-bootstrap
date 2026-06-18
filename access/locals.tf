locals {
  host = data.terraform_remote_state.host.outputs
  idp  = data.terraform_remote_state.idp.outputs

  dashboard_url = local.host.pangolin_dashboard_url # https://pangolin.<base_domain>
  pocket_id_url = local.host.pocket_id_base_url     # https://id.<base_domain>
  org_id        = local.host.org_id
  root_domain   = local.host.root_domain

  # Pocket ID OIDC endpoints (stable paths).
  pid_auth_url  = "${local.pocket_id_url}/authorize"
  pid_token_url = "${local.pocket_id_url}/api/oidc/token"

  # IdP role mapping: default = Member for company (@root_domain) emails, else Guest.
  # Array form ['Member'] matches Pangolin's multi-role return type. Guards the email
  # claim (ends_with on a null claim throws -> 500 login).
  default_role_fallback = "email && ends_with(email, '@${local.root_domain}') && ['Member'] || ['Guest']"

  # Compile group->role from var.group_roles (group NAME => Pangolin role — the
  # contract with the idp module, which creates the groups). A user in several
  # mapped groups gets all those roles; unmatched -> fallback. Empty role ignored.
  mapped_groups = [for name, role in var.group_roles : { name = name, role = role } if role != ""]
  compiled_role_mapping = length(local.mapped_groups) > 0 ? format(
    "([%s][?@]) || (%s)",
    join(", ", [for g in local.mapped_groups : "groups && contains(groups, '${g.name}') && '${g.role}'"]),
    local.default_role_fallback,
  ) : local.default_role_fallback

  # Verbatim override wins; else the compiled mapping.
  role_mapping = var.idp_role_mapping != "" ? var.idp_role_mapping : local.compiled_role_mapping

  # Org membership: must return the org id (or true) to admit. Default = admit all.
  org_mapping = var.idp_org_mapping != "" ? var.idp_org_mapping : "'${local.org_id}'"
}

# --- Identity-aware SSH plane (gated by var.enable_ssh_access) ----------------
locals {
  ssh_enabled   = var.enable_ssh_access
  ssh_roles     = local.ssh_enabled ? toset([for r in var.ssh_access_roles : r if r != "Admin"]) : toset([])
  ssh_site_name = var.ssh_site_name != "" ? var.ssh_site_name : "${split(".", local.host.base_domain)[0]}-host"
  # The stackopshq provider v1.4.0 only accepts none/full/restricted for ssh_sudo_mode,
  # but the Pangolin API (ee-1.19.2) wants none/full/commands — no overlap for scoped
  # command sudo. So Pangolin manages NO sudo here ("none"); the scoped dev-port sudo is
  # a box sudoers drop-in in ssh-host/ (var.ssh_sudo_commands feeds that, not the role).
  ssh_sudo_mode = "none"
}

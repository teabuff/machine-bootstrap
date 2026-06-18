locals {
  access      = data.terraform_remote_state.access.outputs
  enabled     = var.enable_ssh_access && try(local.access.ssh_enabled, false)
  newt_id     = try(local.access.ssh_newt_id, null)
  newt_secret = try(local.access.ssh_newt_secret, null)
  site_name   = try(local.access.ssh_site_name, "")
  dashboard   = data.terraform_remote_state.host.outputs.pangolin_dashboard_url

  # Scoped sudo policy from access/ (the provider can't set the role's "commands"
  # sudo mode, so we enforce it as a box sudoers drop-in). CSV for the script args.
  sudo_commands = try(join(",", local.access.ssh_sudo_commands), "")
  sudo_groups   = try(join(",", local.access.ssh_sudo_groups), "")
}

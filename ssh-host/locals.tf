locals {
  access      = data.terraform_remote_state.access.outputs
  enabled     = var.enable_ssh_access && try(local.access.ssh_enabled, false)
  newt_id     = try(local.access.ssh_newt_id, null)
  newt_secret = try(local.access.ssh_newt_secret, null)
  site_name   = try(local.access.ssh_site_name, "")
  dashboard   = data.terraform_remote_state.host.outputs.pangolin_dashboard_url
}

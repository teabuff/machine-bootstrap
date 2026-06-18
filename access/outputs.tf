output "idp_id" {
  description = "Server-assigned Pangolin IdP id."
  value       = pangolin_idp.pocket_id.id
}

output "idp_redirect_url" {
  description = "The IdP's OAuth callback URL (covered by the idp client's wildcard callback)."
  value       = pangolin_idp.pocket_id.redirect_url
}

output "ssh_enabled" {
  description = "Whether the SSH plane is active."
  value       = local.ssh_enabled
}
output "ssh_newt_id" {
  description = "newt connector id for the host site (consumed by ssh-host/)."
  value       = local.ssh_enabled ? pangolin_site.host[0].newt_id : null
}
output "ssh_newt_secret" {
  description = "newt connector secret for the host site (consumed by ssh-host/)."
  value       = local.ssh_enabled ? pangolin_site.host[0].newt_secret : null
  sensitive   = true
}
output "ssh_site_name" {
  value = local.ssh_enabled ? pangolin_site.host[0].name : null
}

# Scoped sudo is enforced box-side (ssh-host writes a sudoers drop-in), since the
# provider can't set the Pangolin role's "commands" sudo mode. access/ is the single
# source: it derives the policy, ssh-host/ enforces it.
output "ssh_sudo_commands" {
  description = "Absolute command paths the SSH roles may sudo (box sudoers, applied by ssh-host/)."
  value       = local.ssh_enabled ? var.ssh_sudo_commands : []
}
output "ssh_sudo_groups" {
  description = "Unix groups granted the scoped sudo (lower-cased SSH role names)."
  value       = local.ssh_enabled ? [for r in local.ssh_roles : lower(r)] : []
}

output "ssh_browser_url" {
  description = "Public browser-SSH URL (blueprint-applied; null when disabled)."
  value       = local.ssh_public_enabled ? "https://${local.ssh_public_domain}" : null
}

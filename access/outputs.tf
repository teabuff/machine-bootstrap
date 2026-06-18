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
output "ssh_site_nice_id" {
  value = local.ssh_enabled ? pangolin_site.host[0].nice_id : null
}

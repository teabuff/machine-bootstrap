output "idp_id" {
  description = "Server-assigned Pangolin IdP id."
  value       = pangolin_idp.pocket_id.id
}

output "idp_redirect_url" {
  description = "The IdP's OAuth callback URL (covered by the idp client's wildcard callback)."
  value       = pangolin_idp.pocket_id.redirect_url
}

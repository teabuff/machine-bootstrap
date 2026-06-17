output "idp_id" {
  description = "Server-assigned Pangolin IdP id."
  value       = pangolin_idp.pocket_id.id
}

output "idp_redirect_url" {
  description = "The IdP's OAuth callback URL (covered by the client's wildcard callback)."
  value       = pangolin_idp.pocket_id.redirect_url
}

output "pangolin_client_id" {
  description = "Deterministic Pocket ID OIDC client_id ('pangolin') consumed by the Pangolin IdP."
  value       = pocketid_client.pangolin.client_id
}

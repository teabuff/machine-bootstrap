output "client_id" {
  description = "Deterministic Pocket ID OIDC client_id ('pangolin') consumed by the access module's Pangolin IdP."
  value       = pocketid_client.pangolin.client_id
}

output "client_secret" {
  description = "Pocket ID-issued OIDC client secret consumed by the access module's Pangolin IdP."
  value       = pocketid_client.pangolin.client_secret
  sensitive   = true
}

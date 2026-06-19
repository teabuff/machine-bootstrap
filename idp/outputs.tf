output "client_id" {
  description = "Deterministic Pocket ID OIDC client_id ('pangolin') consumed by the access module's Pangolin IdP."
  value       = pocketid_client.pangolin.client_id
}

output "client_secret" {
  description = "Pocket ID-issued OIDC client secret consumed by the access module's Pangolin IdP."
  value       = pocketid_client.pangolin.client_secret
  sensitive   = true
}

output "enrollment_links" {
  description = "One-time Pocket ID login links per user for first-passkey enrolment. Single-use; expire after enrollment_link_ttl. Read with `tofu output -json enrollment_links` and send each NEW user their link (links for already-enrolled users are stale/harmless)."
  value = {
    for username, t in pocketid_one_time_access_token.enroll :
    username => "${local.pocket_id_url}/lc/${t.token}"
  }
  sensitive = true
}

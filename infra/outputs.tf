output "pangolin_dashboard_url" {
  description = "Pangolin dashboard. Create the first admin org here."
  value       = "https://${local.dashboard_host}"
}

output "pocket_id_url" {
  description = "Pocket ID. Visit /setup once to create the first admin via passkey."
  value       = "https://${local.pocket_id_host}/setup"
}

output "server_ip" {
  value = var.server_ip
}

output "next_steps" {
  description = "One-time manual wiring (passkeys can't be provisioned headlessly)."
  value       = <<-EOT
    1. Open ${"https://${local.pocket_id_host}/setup"} and register the first admin passkey.
    2. Open ${"https://${local.dashboard_host}"} and create your Pangolin org/admin.
    3. (Optional SSO) In Pocket ID create an OIDC client for Pangolin, then add it
       as an identity provider in Pangolin → Server Admin → Identity Providers.
       See infra/README.md for the exact fields.
  EOT
}

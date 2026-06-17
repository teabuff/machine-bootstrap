output "pangolin_dashboard_url" {
  description = "Pangolin dashboard. The server admin is already seeded headlessly."
  value       = "https://${local.dashboard_host}"
}

output "pocket_id_url" {
  description = "Pocket ID. The OIDC client + Pangolin IdP are already wired; visit /setup only to enrol a login passkey."
  value       = "https://${local.pocket_id_host}/setup"
}

output "server_ip" {
  value = var.server_ip
}

output "pangolin_api_key" {
  description = "Root Pangolin Integration API key (Bearer token) for the Phase-2 provider. Null when read_api_key = false."
  value       = var.read_api_key ? data.external.pangolin_api_key[0].result.api_key : null
  sensitive   = true
}

output "pocket_id_static_api_key" {
  description = "Pocket ID STATIC_API_KEY — the pocketid provider's api_token."
  value       = random_id.pocket_id_static_api_key.hex
  sensitive   = true
}

output "org_id" {
  description = "Derived Pangolin org slug (config/ creates and binds the IdP to it)."
  value       = local.org_id
}

output "root_domain" {
  description = "Registrable root domain (used by the default IdP role-mapping)."
  value       = local.root_domain
}

output "base_domain" {
  value = var.base_domain
}

output "pocket_id_base_url" {
  description = "Public Pocket ID base URL (the pocketid provider's base_url)."
  value       = "https://${local.pocket_id_host}"
}

output "next_steps" {
  description = "What apply already did, and the only step that needs a human."
  value       = <<-EOT
    Provisioned with no UI by `null_resource.configure` (over loopback on the box):
      - Pangolin server admin (${var.pangolin_admin_email}) seeded via pangctl.
      - EE license activated (if pangolin_license_key is set).
    SSO wiring is owned declaratively by the idp/ (Pocket ID) and access/ (Pangolin) Terraform planes.

    Only human step (passkeys can't be provisioned headlessly):
      - Open https://${local.pocket_id_host}/setup once and enrol your admin passkey,
        then log into https://${local.dashboard_host}.
  EOT
}

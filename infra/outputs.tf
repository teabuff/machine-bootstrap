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

output "next_steps" {
  description = "What apply already did, and the only step that needs a human."
  value       = <<-EOT
    Provisioned with no UI by `null_resource.configure` (over loopback on the box):
      - Pangolin server admin (${var.pangolin_admin_email}) via pangctl.
      ${var.enable_sso ? "- Pocket ID OIDC client 'pangolin' + Pangolin identity provider 'pocket-id' (provision-sso.sh)." : "- SSO wiring skipped (enable_sso = false)."}

    Only human step (passkeys can't be provisioned headlessly):
      - Open https://${local.pocket_id_host}/setup once and enrol your admin passkey,
        then log into https://${local.dashboard_host} — via Pocket ID if SSO is on.
  EOT
}

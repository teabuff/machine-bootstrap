# Pocket ID email / self-service login. Only managed when SMTP is configured
# (smtp_host set). pocketid_application_config is a SINGLETON that MERGES — the
# provider preserves any field we don't set — so this touches only SMTP + the
# email-login flags, leaving appName/session/etc. intact.
locals {
  smtp_enabled = var.smtp_host != ""
}

resource "pocketid_application_config" "this" {
  count = local.smtp_enabled ? 1 : 0

  smtp_host     = var.smtp_host
  smtp_port     = var.smtp_port
  smtp_from     = var.smtp_from
  smtp_user     = var.smtp_user
  smtp_password = var.smtp_password
  smtp_tls      = var.smtp_tls

  # Self-service: an unauthenticated user enters their email on the login page and
  # Pocket ID emails them a one-time login link (then they enrol a passkey). Roster
  # emails are admin-curated, so treat them as verified.
  email_one_time_access_as_unauthenticated_enabled = "true"
  emails_verified                                  = "true"
}

# --- Declarative identity manifest (Pocket ID) -------------------------------
# The group NAME is the contract with the access module's group_roles policy.
variable "groups" {
  type = list(object({
    name          = string
    friendly_name = string
  }))
  description = "Groups seeded into Pocket ID. A group named 'pocket-admin' flips its members' Pocket ID isAdmin. Names must match the access module's group_roles keys."
  default     = []
}

variable "users" {
  type = list(object({
    username     = string
    display_name = string
    email        = string
    groups       = optional(list(string), [])
  }))
  description = "Users pre-seeded into Pocket ID. username = email local-part by convention. groups lists group names (must be declared in `groups`)."
  default     = []
}

# --- Where to read the host (machine) state from -----------------------------
variable "host_state_backend" {
  type        = string
  description = "Backend type for reading the host state ('local' standalone, 's3' for R2 multi-env)."
  default     = "local"
}

variable "host_state_config" {
  type        = any
  description = "terraform_remote_state config for the host state. Default reads the sibling local state. For R2, pass the s3 config object {bucket, key, region, profile, endpoints = {s3 = ...}, skip_*, use_path_style} with host_state_backend = \"s3\"."
  default = {
    path = "../host/terraform.tfstate"
  }
}

variable "issue_enrollment_links" {
  type        = bool
  description = "Mint a one-time Pocket ID login link per user so first-time users can self-enrol a passkey (the only Pocket ID step that can't be declared). Off = no links."
  default     = true
}

variable "enrollment_link_ttl" {
  type        = string
  description = "Lifetime of each enrolment link (Go duration, e.g. 24h, 72h). The link is also single-use (consumed on first login)."
  default     = "72h"
}

# --- SMTP / email login (optional) -------------------------------------------
# Set smtp_host to turn on Pocket ID email: users self-serve a one-time login link
# by entering their email at the login page (then enrol a passkey) — no admin relay.
# Leave smtp_host = "" to keep email off and use the enrollment_links output instead.
# Secrets (smtp_password) via TF_VAR_. application_config is a merge (it preserves
# fields you don't set), so this only touches the SMTP + email-login settings.
variable "smtp_host" {
  type        = string
  description = "SMTP server host. Empty = email off."
  default     = ""
}
variable "smtp_port" {
  type    = string
  default = "587"
}
variable "smtp_from" {
  type        = string
  description = "Sender address for Pocket ID emails (required when smtp_host is set)."
  default     = ""
}
variable "smtp_user" {
  type    = string
  default = ""
}
variable "smtp_password" {
  type      = string
  sensitive = true
  default   = ""
}
variable "smtp_tls" {
  type        = string
  description = "SMTP TLS mode: none | starttls | tls."
  default     = "starttls"
}

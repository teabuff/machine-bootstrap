# ---------------------------------------------------------------------------
# Headless bootstrap (admin) + SSO wiring — runs on the box after deploy, over
# loopback, so there is no UI/passkey step for provisioning. A human still
# enrols a passkey once if they intend to log in interactively.
# ---------------------------------------------------------------------------

variable "pangolin_admin_email" {
  type        = string
  description = "First Pangolin server admin, seeded via `pangctl set-admin-credentials`. Use a lower-case address (pangctl mishandles upper-case)."
  validation {
    condition     = var.pangolin_admin_email == lower(var.pangolin_admin_email)
    error_message = "pangolin_admin_email must be lower-case."
  }
}

variable "pangolin_admin_password" {
  type        = string
  description = "Password for the Pangolin server admin. Kept in state, never committed."
  sensitive   = true
}

variable "pangolin_org_id" {
  type        = string
  description = "Pangolin org slug to create (if absent) and map the IdP into, so SSO users have an org to join. Empty = derive from the first label of base_domain (e.g. 'tyo' from tyo.example.com)."
  default     = ""
}

# ---------------------------------------------------------------------------
# Enterprise Edition license (REQUIRED — this stack runs the ee- image)
# ---------------------------------------------------------------------------
# The stack always runs fosrl/pangolin:ee-<version> (the community tag has no
# SSH and no /license routes), so a license key is required. A FREE key covers
# personal use / businesses under USD 100k revenue: get it at
# https://app.pangolin.net -> Licenses. The key is registered headlessly during
# the configure step, so there is no /admin/license UI visit.

variable "pangolin_license_key" {
  type        = string
  description = "Pangolin Enterprise Edition license key — REQUIRED when pangolin_version is an `ee-` tag (the Enterprise build, needed for identity-aware SSH); leave empty for a community tag. Free for personal use / <USD 100k rev. Activated headlessly on apply (a no-op when empty); kept in state, never committed."
  sensitive   = true
  default     = ""
  # The conditional "ee- requires a key" rule is enforced by the
  # terraform_data.license_check precondition (a variable validation can't
  # reference pangolin_version on Terraform/OpenTofu < 1.9).
}

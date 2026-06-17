variable "org_name" {
  type        = string
  description = "Display name for the Pangolin org (org_id comes from bootstrap state)."
}

variable "org_subnet" {
  type        = string
  description = "CIDR for the org (the bash auto-picked this via /pick-org-defaults; the provider requires it explicitly). Must not overlap other orgs."
  default     = "100.90.0.0/24"
}

variable "org_utility_subnet" {
  type        = string
  description = "Utility CIDR for the org."
  default     = "100.96.0.0/24"
}

variable "role_names" {
  type        = list(string)
  description = "Custom org roles to create (Admin + Member are built in). The IdP role-mapping may only return names that exist."
  default     = ["Developer", "Guest"]
}

variable "idp_role_mapping" {
  type        = string
  description = "Verbatim JMESPath override for the IdP role mapping. Empty = use the default fallback (Member for company emails, else Guest)."
  default     = ""
}

variable "idp_org_mapping" {
  type        = string
  description = "JMESPath deciding org membership; must return the org id (or true) to admit. Empty = admit everyone (returns the org-id literal)."
  default     = ""
}

# --- Where to read the bootstrap (host/) state from --------------------------
# Default reads the sibling local state (standalone use). For multi-env, the
# per-env config/ root passes backend = "s3" + the R2 config of its bootstrap key.
variable "bootstrap_state_backend" {
  type        = string
  description = "Backend type for reading the bootstrap state ('local' standalone, 's3' for R2 multi-env)."
  default     = "local"
}

variable "bootstrap_state_config" {
  type        = any
  description = "terraform_remote_state config for the bootstrap state. Default reads the sibling local state (standalone). For R2, pass the s3 config object {bucket, key, region, profile, endpoints = {s3=...}, skip_*, use_path_style, ...} along with bootstrap_state_backend = \"s3\"."
  default = {
    path = "../host/terraform.tfstate"
  }
}

# --- Declarative identity manifest (replaces the bash group/user seeding) -----
# Groups seeded into Pocket ID. pangolin_role (optional) compiles into the IdP
# role mapping (the single source of truth for group->role). A group named
# "pocket-admin" flips its members' Pocket ID isAdmin (no role).
variable "groups" {
  type = list(object({
    name          = string
    friendly_name = string
    pangolin_role = optional(string, "")
  }))
  default = []
}

# Users pre-seeded into Pocket ID. username = email local-part by convention.
# groups lists group names (must be declared in `groups`).
variable "users" {
  type = list(object({
    username     = string
    display_name = string
    email        = string
    groups       = optional(list(string), [])
  }))
  default = []
}

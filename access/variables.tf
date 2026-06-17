variable "org_name" {
  type        = string
  description = "Display name for the Pangolin org (org_id comes from host state)."
}

variable "org_subnet" {
  type        = string
  description = "CIDR for the org (the provider requires it explicitly). Must not overlap other orgs."
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

# --- group->role policy (the access team's mapping) --------------------------
# Keys are Pocket ID group NAMES (must match the idp module's groups[].name). The
# value is the Pangolin role to grant members of that group. Compiles into the IdP
# role_mapping. A "" value is ignored (membership-only group).
variable "group_roles" {
  type        = map(string)
  description = "Map of Pocket ID group name => Pangolin role. Names must match the idp module's declared groups."
  default     = {}
}

variable "idp_role_mapping" {
  type        = string
  description = "Verbatim JMESPath override for the IdP role mapping. Empty = use the compiled group_roles mapping (and the default fallback)."
  default     = ""
}

variable "idp_org_mapping" {
  type        = string
  description = "JMESPath deciding org membership; must return the org id (or true) to admit. Empty = admit everyone (returns the org-id literal)."
  default     = ""
}

# --- Where to read the host state from ---------------------------------------
variable "host_state_backend" {
  type        = string
  description = "Backend type for reading the host state ('local' standalone, 's3' for R2 multi-env)."
  default     = "local"
}

variable "host_state_config" {
  type        = any
  description = "terraform_remote_state config for the host state. Default reads the sibling local state. For R2, pass the s3 config object with host_state_backend = \"s3\"."
  default = {
    path = "../host/terraform.tfstate"
  }
}

# --- Where to read the idp state from ----------------------------------------
variable "idp_state_backend" {
  type        = string
  description = "Backend type for reading the idp state ('local' standalone, 's3' for R2 multi-env)."
  default     = "local"
}

variable "idp_state_config" {
  type        = any
  description = "terraform_remote_state config for the idp state (provides client_id + client_secret). Default reads the sibling local state. For R2, pass the s3 config object with idp_state_backend = \"s3\"."
  default = {
    path = "../idp/terraform.tfstate"
  }
}

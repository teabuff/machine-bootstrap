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

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

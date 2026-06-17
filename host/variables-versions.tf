# ---------------------------------------------------------------------------
# Image versions
# ---------------------------------------------------------------------------
# Pin these for reproducibility. badger_version MUST match the Pangolin image
# (bump them together). traefik_version is the version Pangolin is tested with.

variable "pangolin_version" {
  type        = string
  description = "Full fosrl/pangolin image tag. Use `ee-<version>` for the Enterprise build (REQUIRED for identity-aware SSH) or `<version>` for community (web + SSO only). Pinned (not 'latest') for reproducibility; verified with ee-1.19.2 + gerbil 1.4.2 + badger v1.4.1."
  default     = "ee-1.19.2"
}

variable "gerbil_version" {
  type        = string
  description = "fosrl/gerbil image tag. Keep in step with the pangolin release."
  default     = "1.4.2"
}

variable "traefik_version" {
  type        = string
  description = "traefik image tag (must be the version Pangolin targets)."
  default     = "v3.6"
}

variable "badger_version" {
  type        = string
  description = "fosrl/badger Traefik plugin version. MUST match the Pangolin release."
  default     = "v1.4.1"
}

variable "pocket_id_version" {
  type        = string
  description = "ghcr.io/pocket-id/pocket-id image tag. Headless SSO REQUIRES >= 2.2.0 — STATIC_API_KEY was added in 2.2.0 (the :v1 tag is 1.16.x and silently 401s every API call). Verified end-to-end on 2.8.0."
  default     = "v2.8.0"

  validation {
    condition     = !can(regex("^v?1[.:]", var.pocket_id_version))
    error_message = "pocket_id_version must be >= 2.2.0 (Pocket ID 1.x lacks STATIC_API_KEY, so headless SSO can't authenticate)."
  }
}

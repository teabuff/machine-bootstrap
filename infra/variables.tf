# ---------------------------------------------------------------------------
# Server (bring-your-own — provider-agnostic)
# ---------------------------------------------------------------------------
# You create the VPS yourself (Bandwagon, V.PS, Hetzner, a Pi — anything with
# SSH). This config converges it; it never creates the box.

variable "server_ip" {
  type        = string
  description = "Public IPv4 of the server. Used for the Cloudflare A records and, by default, for SSH."

  validation {
    condition     = can(regex("^\\d{1,3}(\\.\\d{1,3}){3}$", var.server_ip))
    error_message = "server_ip must be a dotted-quad IPv4 address."
  }
}

variable "ssh_host" {
  type        = string
  description = "Host to SSH into, if different from server_ip (e.g. a jump hostname). Empty = use server_ip."
  default     = ""
}

variable "ssh_user" {
  type        = string
  description = "SSH user with sudo/root on the server."
  default     = "root"
}

variable "ssh_port" {
  type        = number
  description = "SSH port."
  default     = 22
}

variable "ssh_private_key_path" {
  type        = string
  description = "Path to the private key used to SSH into the server."
  default     = "~/.ssh/id_ed25519"
}

# ---------------------------------------------------------------------------
# DNS (Cloudflare)
# ---------------------------------------------------------------------------

variable "cloudflare_api_token" {
  type        = string
  description = "Cloudflare API token with Zone:DNS:Edit on the zone below. Keep out of git."
  sensitive   = true
}

variable "cloudflare_zone_id" {
  type        = string
  description = "Cloudflare Zone ID of the registered domain (e.g. the zone for example.com). Found on the zone's Overview page."
}

variable "base_domain" {
  type        = string
  description = "The realm/parent domain Pangolin owns, e.g. frt.example.com. A `*.<base_domain>` wildcard is created so every resource routes through Pangolin with zero further DNS changes."
}

variable "dashboard_subdomain" {
  type        = string
  description = "Subdomain (under base_domain) for the Pangolin dashboard."
  default     = "pangolin"
}

variable "pocket_id_subdomain" {
  type        = string
  description = "Subdomain (under base_domain) for Pocket ID."
  default     = "id"
}

variable "letsencrypt_email" {
  type        = string
  description = "Contact email for Let's Encrypt (Traefik ACME)."
}

# ---------------------------------------------------------------------------
# Image versions
# ---------------------------------------------------------------------------
# Pin these for reproducibility. badger_version MUST match the Pangolin image
# (bump them together). traefik_version is the version Pangolin is tested with.

variable "pangolin_version" {
  type        = string
  description = "fosrl/pangolin image tag. Pin to a release for reproducibility."
  default     = "latest"
}

variable "gerbil_version" {
  type        = string
  description = "fosrl/gerbil image tag."
  default     = "latest"
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
  description = "ghcr.io/pocket-id/pocket-id image tag."
  default     = "latest"
}

# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

variable "stack_dir" {
  type        = string
  description = "Absolute directory on the server where the compose stack lives."
  default     = "/opt/pangolin-stack"
}

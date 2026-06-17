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

variable "acme_dns_challenge" {
  type        = bool
  description = "Use the Let's Encrypt DNS-01 challenge to issue a WILDCARD cert (*.base_domain) instead of per-host HTTP-01. Hides hostnames from CT logs and dodges rate limits, but puts the Cloudflare DNS token on the box (Traefik writes _acme-challenge TXT records). Requires DNS on Cloudflare; the token needs Zone:Read + DNS:Edit."
  default     = false
}

variable "read_api_key" {
  type        = bool
  description = "Read the minted Integration API key back from the box (one SSH per plan). Set false for offline/CI plans that don't need the key output."
  default     = true
}

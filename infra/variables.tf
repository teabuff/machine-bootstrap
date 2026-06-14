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
  description = "fosrl/pangolin image tag. Pinned (not 'latest') for reproducibility; verified working with gerbil 1.4.2 + badger v1.4.1."
  default     = "1.19.2"
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

# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

variable "stack_dir" {
  type        = string
  description = "Absolute directory on the server where the compose stack lives."
  default     = "/opt/pangolin-stack"
}

variable "manage_firewall" {
  type        = bool
  description = "Install/converge ufw to allow only ssh_port + 80/443/51820·udp/21820·udp (SSH-safe). Set false if a firewall is managed elsewhere. NB: Docker-published ports bypass ufw regardless."
  default     = true
}

variable "acme_dns_challenge" {
  type        = bool
  description = "Use the Let's Encrypt DNS-01 challenge to issue a WILDCARD cert (*.base_domain) instead of per-host HTTP-01. Hides hostnames from CT logs and dodges rate limits, but puts the Cloudflare DNS token on the box (Traefik writes _acme-challenge TXT records). Requires DNS on Cloudflare; the token needs Zone:Read + DNS:Edit."
  default     = false
}

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

variable "enable_sso" {
  type        = bool
  description = "Wire Pangolin <-> Pocket ID SSO headlessly after deploy (provision-sso.sh over loopback). The admin is always seeded regardless."
  default     = true
}

variable "sso_identity_file" {
  type        = string
  description = "Optional path to a provision-sso identity manifest (groups/users seeded into Pocket ID). Empty = wire SSO only; users auto-provision on first login. Keep realm specifics out of git."
  default     = ""
}

variable "pangolin_org_id" {
  type        = string
  description = "Pangolin org slug to create (if absent) and map the IdP into, so SSO users have an org to join. Empty = derive from the first label of base_domain (e.g. 'tyo' from tyo.example.com)."
  default     = ""
}

variable "pangolin_org_name" {
  type        = string
  description = "Display name for the org. Empty = same as the org id."
  default     = ""
}

variable "pangolin_roles" {
  type        = list(string)
  description = "Custom org roles to create (Admin + Member are built in). The role-mapping must only return names that exist. New roles start with no resource permissions — grant per-resource later."
  default     = ["Developer", "Guest"]
}

variable "idp_role_mapping" {
  type        = string
  description = "JMESPath returning the role NAME for an SSO user. Empty = a group-based default (admins->Admin, developers->Developer, guests->Guest; @<root-domain> emails -> Member; everyone else -> Guest). Quote literals ('Admin'); bare words are claim lookups."
  default     = ""
}

variable "idp_org_mapping" {
  type        = string
  description = "JMESPath deciding org membership; must return the org id (or boolean true) to ADMIT the user — a bare string like 'true' is NEITHER and admits nobody. Empty = admit everyone (returns the org-id literal). For domain-gating use e.g. ends_with(email,'@example.com') && '<org-id>'."
  default     = ""
}

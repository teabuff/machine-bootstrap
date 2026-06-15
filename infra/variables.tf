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
  description = "SSH user the deploy connects as — must be root (privileged steps run directly, no sudo wrapping). The box must accept key-based root SSH with your deploy key in root's authorized_keys (configure that out of band)."
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
  description = "Verbatim full-expression OVERRIDE for the IdP role mapping. Empty (default) = provision-sso.sh COMPILES the mapping from the identity manifest's `group <name> -> <Role>` annotations, falling back to idp_role_fallback. Set this only to bypass the manifest with a hand-written JMESPath. Quote literals ('Admin'); guard absent claims ('groups && contains(groups,...)') — contains() on a missing claim throws and 500s the login; no backtick array literals (sourced by bash)."
  default     = ""
}

variable "idp_role_fallback" {
  type        = string
  description = "JMESPath for the role(s) an SSO user gets when their groups match NO `-> Role` annotation in the manifest. Empty = Member for @<root-domain> emails, else Guest. Return an array (['Member']) to match the compiled mapping's multi-role type. Guard the email claim ('email && ends_with(...)'); no backticks (sourced by bash)."
  default     = ""
}

variable "idp_org_mapping" {
  type        = string
  description = "JMESPath deciding org membership; must return the org id (or boolean true) to ADMIT the user — a bare string like 'true' is NEITHER and admits nobody. Empty = admit everyone (returns the org-id literal). For domain-gating use e.g. ends_with(email,'@example.com') && '<org-id>'."
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

# ---------------------------------------------------------------------------
# Identity-aware SSH (Pangolin auth-daemon) — on by default (EE stack).
# ---------------------------------------------------------------------------
# Installs newt as a host systemd service (connector + SSH auth-daemon),
# registers an SSH private resource for THIS host, grants roles SSH access, and
# adds an additive sshd CA drop-in. Users then `pangolin ssh <host>-ssh` and get
# a short-lived, CA-signed cert; their Linux username is their Pocket ID
# preferred_username, JIT-provisioned on first login.
#
# REQUIRES a Pangolin Enterprise Edition license (free for personal use /
# businesses under USD 100k revenue): SSH private resources return HTTP 403
# until a key is registered at the dashboard's /admin/license. The connector
# (newt + site) still comes up unlicensed; only the resource/cert path is gated.
# Apply for the free key at https://app.pangolin.net (Licenses), register it,
# then re-apply — ssh-access.sh detects the 403 and stops cleanly until then.

variable "enable_ssh_access" {
  type        = bool
  description = "Provision identity-aware SSH for this host via Pangolin's auth-daemon (newt on systemd + SSH resource + sshd CA drop-in). On by default; relies on the EE license above. Set false to skip SSH and run only the web stack."
  default     = true
}

variable "newt_version" {
  type        = string
  description = "fosrl/newt release tag for the host connector/auth-daemon. >= 1.13.0 runs the auth-daemon by default. Pinned for reproducibility."
  default     = "1.13.0"
}

variable "ssh_access_roles" {
  type        = list(string)
  description = "Org role NAMEs granted SSH access to this host (Admin is implicit and filtered out). Must match roles that exist (see pangolin_roles)."
  default     = ["Developer"]
}

variable "ssh_site_name" {
  type        = string
  description = "Name of the Pangolin site representing this host (the newt connector). Empty = derive from the dashboard subdomain + base domain's first label."
  default     = ""
}

variable "ssh_public_subdomain" {
  type        = string
  description = "Subdomain (under base_domain) for an optional PUBLIC browser-SSH resource, e.g. 'shell' -> shell.<base_domain>, SSO-gated to ssh_access_roles and served over the wildcard cert. Empty = private (pangolin ssh) resource only."
  default     = ""
}

variable "ssh_sudo_commands" {
  type        = list(string)
  description = "Absolute command paths the ssh_access_roles may run via sudo (sshSudoMode=commands), e.g. [\"/usr/sbin/ufw\"]. Empty = no sudo. Each SSH role also lands its JIT users in a fixed-GID Unix group named after the role, lower-cased (Developer -> `developer`) — create those groups via apply-host.sh (see hosts/example.host). Admin is implicit (full sudo) and managed separately."
  default     = []
}

# Copy to terraform.tfvars (gitignored) and fill in. Real domains/IPs/tokens
# must NEVER be committed — terraform.tfvars and *.auto.tfvars are ignored.

# --- Server (you create it; this just converges it) ---
server_ip            = "203.0.113.10"
ssh_user             = "root"
ssh_private_key_path = "~/.ssh/id_ed25519"
# ssh_host           = ""           # only if SSH host differs from server_ip
# ssh_port           = 22

# --- Cloudflare ---
cloudflare_api_token = "cf-token-with-Zone.DNS.Edit"
cloudflare_zone_id   = "your-zone-id-from-cloudflare-overview"

# --- Domains ---
base_domain         = "frt.example.com" # Pangolin gets frt.example.com + *.frt.example.com
dashboard_subdomain = "pangolin"        # -> pangolin.frt.example.com
pocket_id_subdomain = "id"              # -> id.frt.example.com
letsencrypt_email   = "you@example.com"

# --- Pin images for reproducibility (recommended over "latest") ---
# pangolin_version  = "ee-1.19.2"   # full tag; ee- = Enterprise (needed for SSH), bare = community/web-only
# gerbil_version    = "1.x.x"
# pocket_id_version = "v2.8.0"   # MUST be >= 2.2.0 for headless SSO (STATIC_API_KEY)
# traefik_version   = "v3.6"
# badger_version    = "v1.4.1"   # MUST match the pangolin release

# --- Pangolin EE license ---
# REQUIRED when pangolin_version is an ee- tag (the default — needed for
# identity-aware SSH). Free at https://app.pangolin.net -> Licenses. Leave empty
# ("") for a community (non-ee-) tag (web + SSO only, no SSH).
pangolin_license_key = "FILL_ME"

# --- Headless admin (provisioned over loopback after deploy) ---
pangolin_admin_email    = "admin@example.com" # lower-case; seeded via pangctl
pangolin_admin_password = "change-me-strong"  # avoid " and $ ; kept in state only
#
# Org id is derived from the root domain (tyo.example.com -> "example-com") and
# exposed as the `org_id` output for the access/ SSO plane. Override if needed:
# pangolin_org_id = "example-com"

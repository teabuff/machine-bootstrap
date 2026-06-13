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
# pangolin_version  = "1.x.x"
# gerbil_version    = "1.x.x"
# pocket_id_version = "vX.Y.Z"
# traefik_version   = "v3.6"
# badger_version    = "v1.4.1"   # MUST match the pangolin release

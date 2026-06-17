# DNS: apex + wildcard records pointing to the server IP (DNS-only, not proxied).
# --- DNS: apex + wildcard, both DNS-only (Pangolin needs the raw IP) ---

resource "cloudflare_dns_record" "apex" {
  zone_id = var.cloudflare_zone_id
  name    = var.base_domain
  type    = "A"
  content = var.server_ip
  ttl     = 300
  proxied = false
  comment = "machine-bootstrap: Pangolin realm apex"
}

resource "cloudflare_dns_record" "wildcard" {
  zone_id = var.cloudflare_zone_id
  name    = "*.${var.base_domain}"
  type    = "A"
  content = var.server_ip
  ttl     = 300
  proxied = false
  comment = "machine-bootstrap: Pangolin routes everything under here"
}

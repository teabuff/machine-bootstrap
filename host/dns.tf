# DNS: apex + wildcard records pointing to the server IP (DNS-only, not proxied).
# --- DNS: apex + wildcard, both DNS-only (Pangolin needs the raw IP) ---
locals {
  dns_records = {
    apex     = { name = var.base_domain, comment = "Pangolin realm apex" }
    wildcard = { name = "*.${var.base_domain}", comment = "Pangolin routes everything under here" }
  }
}

resource "cloudflare_dns_record" "this" {
  for_each = local.dns_records
  zone_id  = var.cloudflare_zone_id
  name     = each.value.name
  type     = "A"
  content  = var.server_ip
  ttl      = 300
  proxied  = false
  comment  = "machine-bootstrap: ${each.value.comment}"
}

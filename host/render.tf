# Locals: render all configs and derive computed values from inputs.
locals {
  dashboard_host = "${var.dashboard_subdomain}.${var.base_domain}"
  pocket_id_host = "${var.pocket_id_subdomain}.${var.base_domain}"
  ssh_host       = var.ssh_host != "" ? var.ssh_host : var.server_ip

  # Org slug consumed by the org_id output (used by access/ to create and bind the
  # IdP into). Defaults to the root (registrable) domain with dots hyphenated:
  # tyo.example.com -> "example-com" (last two labels; override pangolin_org_id
  # for multi-part TLDs like .co.uk).
  base_labels = split(".", var.base_domain)
  root_domain = join(".", slice(local.base_labels, length(local.base_labels) - 2, length(local.base_labels)))
  org_id      = var.pangolin_org_id != "" ? var.pangolin_org_id : replace(local.root_domain, ".", "-")

  # Image tag is pangolin_version verbatim. Use an `ee-` tag (e.g. ee-1.19.2) for
  # the Enterprise build — REQUIRED for identity-aware SSH and the /license routes;
  # the bare `<version>` community build is web + SSO only. pangolin_license_key is
  # required and activated headlessly in configure (a no-op on the community tag).
  pangolin_image = "fosrl/pangolin:${var.pangolin_version}"

  # Render every config the box needs from one place, so the deploy resource
  # can both upload them and key its re-run trigger off their content.
  compose = templatefile("${path.module}/files/docker-compose.yml.tftpl", {
    pangolin_image           = local.pangolin_image
    gerbil_version           = var.gerbil_version
    traefik_version          = var.traefik_version
    pocket_id_version        = var.pocket_id_version
    pocket_id_host           = local.pocket_id_host
    pocket_id_encryption_key = random_id.pocket_id_encryption_key.b64_std
    pocket_id_static_api_key = random_id.pocket_id_static_api_key.hex
    dns_challenge            = var.acme_dns_challenge
    cloudflare_dns_token     = var.cloudflare_api_token # only embedded when dns_challenge
  })

  # Admin credentials for bootstrap.sh (seeds the server admin + activates the EE
  # license over loopback). SSO wiring is now owned by the idp/ and access/ planes declaratively.
  # Endpoints are loopback because configure runs ON the box (no public DNS/cert
  # needed at apply time). Avoid " and $ in the password.
  # Admin + license bootstrap config (loopback). Also carries PANGOLIN_DASHBOARD_URL
  # + PANGOLIN_ORG_ID for ssh-access.sh, which drives the Pangolin API for SSH RBAC.
  admin_conf = <<-EOT
    PANGOLIN_URL="http://127.0.0.1:3000"
    PANGOLIN_DASHBOARD_URL="https://${local.dashboard_host}"
    PANGOLIN_ADMIN_EMAIL="${var.pangolin_admin_email}"
    PANGOLIN_ADMIN_PASSWORD="${var.pangolin_admin_password}"
    PANGOLIN_LICENSE_KEY="${var.pangolin_license_key}"
    PANGOLIN_ORG_ID="${local.org_id}"
  EOT

  pangolin_config = templatefile("${path.module}/files/config/config.yml.tftpl", {
    dashboard_host  = local.dashboard_host
    base_domain     = var.base_domain
    pangolin_secret = random_id.pangolin_secret.hex
    dns_challenge   = var.acme_dns_challenge
  })

  traefik_config = templatefile("${path.module}/files/config/traefik/traefik_config.yml.tftpl", {
    letsencrypt_email = var.letsencrypt_email
    badger_version    = var.badger_version
    dns_challenge     = var.acme_dns_challenge
  })

  dynamic_config = templatefile("${path.module}/files/config/traefik/dynamic_config.yml.tftpl", {
    dashboard_host = local.dashboard_host
    pocket_id_host = local.pocket_id_host
  })
}

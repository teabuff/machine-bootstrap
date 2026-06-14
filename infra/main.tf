locals {
  dashboard_host = "${var.dashboard_subdomain}.${var.base_domain}"
  pocket_id_host = "${var.pocket_id_subdomain}.${var.base_domain}"
  ssh_host       = var.ssh_host != "" ? var.ssh_host : var.server_ip

  # Org slug SSO users join. Defaults to the first label of base_domain
  # (tyo.example.com -> "tyo"), giving a clean per-realm org.
  org_id   = var.pangolin_org_id != "" ? var.pangolin_org_id : split(".", var.base_domain)[0]
  org_name = var.pangolin_org_name != "" ? var.pangolin_org_name : local.org_id

  # Render every config the box needs from one place, so the deploy resource
  # can both upload them and key its re-run trigger off their content.
  compose = templatefile("${path.module}/files/docker-compose.yml.tftpl", {
    pangolin_version         = var.pangolin_version
    gerbil_version           = var.gerbil_version
    traefik_version          = var.traefik_version
    pocket_id_version        = var.pocket_id_version
    pocket_id_host           = local.pocket_id_host
    pocket_id_encryption_key = random_id.pocket_id_encryption_key.b64_std
    pocket_id_static_api_key = random_id.pocket_id_static_api_key.hex
    dns_challenge            = var.acme_dns_challenge
    cloudflare_dns_token     = var.cloudflare_api_token # only embedded when dns_challenge
  })

  # provision-sso.sh config, rendered from vars. Endpoints are loopback because
  # the configure step runs ON the box (no public DNS/cert needed at apply time).
  # JMESPath/password values are double-quoted; avoid " and $ in the password.
  sso_conf = <<-EOT
    POCKETID_URL="http://127.0.0.1:1411"
    POCKETID_API_KEY="${random_id.pocket_id_static_api_key.hex}"
    PANGOLIN_URL="http://127.0.0.1:3000"
    PANGOLIN_ADMIN_EMAIL="${var.pangolin_admin_email}"
    PANGOLIN_ADMIN_PASSWORD="${var.pangolin_admin_password}"
    OIDC_CLIENT_ID="pangolin"
    IDP_NAME="pocket-id"
    SSO_STATE_FILE="${var.stack_dir}/.sso-state"
    PANGOLIN_ORG_ID="${local.org_id}"
    PANGOLIN_ORG_NAME="${local.org_name}"
    IDP_ROLE_MAPPING="${var.idp_role_mapping}"
    IDP_ORG_MAPPING="${var.idp_org_mapping}"
  EOT

  # Optional identity manifest (groups/users seeded into Pocket ID). Empty by
  # default → SSO is wired but users auto-provision on first login.
  sso_identity = var.sso_identity_file != "" ? file(pathexpand(var.sso_identity_file)) : "# no identities declared — users auto-provision on first OIDC login\n"

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

# --- Generated secrets (stored in local state; never prompted, never in git) ---

resource "random_id" "pangolin_secret" {
  byte_length = 32 # -> 64 hex chars, equivalent to `openssl rand -hex 32`
}

resource "random_id" "pocket_id_encryption_key" {
  byte_length = 32 # -> base64, equivalent to `openssl rand -base64 32`
}

resource "random_id" "pocket_id_static_api_key" {
  byte_length = 24 # -> 48 hex chars (well over Pocket ID's >=16 minimum)
}

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

# --- Pre-flight: advisory DNS check from the operator machine (never blocks) ---
resource "null_resource" "preflight" {
  triggers = { always = timestamp() } # re-check every apply
  provisioner "local-exec" {
    command = "${path.module}/files/preflight.sh ${var.base_domain} ${local.dashboard_host} ${local.pocket_id_host} ${var.server_ip}"
  }
}

# --- Provision: push the stack to the box and converge it (idempotent) ---

resource "null_resource" "deploy" {
  # Re-runs whenever any rendered config, the deploy script, or the target host
  # changes. docker compose up -d makes re-application converge, not duplicate.
  triggers = {
    compose         = sha1(local.compose)
    pangolin_config = sha1(local.pangolin_config)
    traefik_config  = sha1(local.traefik_config)
    dynamic_config  = sha1(local.dynamic_config)
    deploy_script   = filesha1("${path.module}/files/deploy.sh")
    firewall_script = filesha1("${path.module}/files/firewall.sh")
    manage_firewall = var.manage_firewall
    host            = local.ssh_host
    stack_dir       = var.stack_dir
  }

  connection {
    type        = "ssh"
    host        = local.ssh_host
    user        = var.ssh_user
    port        = var.ssh_port
    private_key = file(pathexpand(var.ssh_private_key_path))
  }

  # 1. Ensure the directory tree exists before uploading into it.
  provisioner "remote-exec" {
    inline = [
      "mkdir -p ${var.stack_dir}/config/traefik ${var.stack_dir}/config/letsencrypt",
    ]
  }

  # 2. Upload rendered configs.
  provisioner "file" {
    content     = local.compose
    destination = "${var.stack_dir}/docker-compose.yml"
  }
  provisioner "file" {
    content     = local.pangolin_config
    destination = "${var.stack_dir}/config/config.yml"
  }
  provisioner "file" {
    content     = local.traefik_config
    destination = "${var.stack_dir}/config/traefik/traefik_config.yml"
  }
  provisioner "file" {
    content     = local.dynamic_config
    destination = "${var.stack_dir}/config/traefik/dynamic_config.yml"
  }
  provisioner "file" {
    source      = "${path.module}/files/deploy.sh"
    destination = "${var.stack_dir}/deploy.sh"
  }
  provisioner "file" {
    source      = "${path.module}/files/firewall.sh"
    destination = "${var.stack_dir}/firewall.sh"
  }

  # 3. Lock down the firewall (SSH-safe), install Docker if missing, bring it up.
  provisioner "remote-exec" {
    inline = [
      "chmod +x ${var.stack_dir}/firewall.sh ${var.stack_dir}/deploy.sh",
      "${var.stack_dir}/firewall.sh ${var.ssh_port} ${var.manage_firewall}",
      "${var.stack_dir}/deploy.sh ${var.stack_dir}",
    ]
  }

  depends_on = [
    null_resource.preflight,
    cloudflare_dns_record.apex,
    cloudflare_dns_record.wildcard,
  ]
}

# --- Configure: headless admin + SSO, over loopback on the box (no UI) ---
# This is what removes the old "create the admin / wire SSO in the dashboard"
# manual steps. The app-plane has no Terraform provider, so we drive each
# product's API with idempotent bash (provision-sso.sh) invoked here.
resource "null_resource" "configure" {
  # Re-run only when the config-plane inputs change, NOT on every redeploy
  # (admin + SSO are idempotent; depends_on still orders us after deploy on the
  # first apply). A version bump no longer re-runs the whole SSO dance.
  triggers = {
    sso_conf     = sha1(local.sso_conf)
    sso_identity = sha1(local.sso_identity)
    bootstrap    = filesha1("${path.module}/files/bootstrap.sh")
    provision    = filesha1("${path.module}/../provision-sso.sh")
    sso_lib      = filesha1("${path.module}/../lib/sso.sh")
    enable_sso   = var.enable_sso
  }

  connection {
    type        = "ssh"
    host        = local.ssh_host
    user        = var.ssh_user
    port        = var.ssh_port
    private_key = file(pathexpand(var.ssh_private_key_path))
  }

  # The SSO library lives under lib/ next to provision-sso.sh on the box.
  provisioner "remote-exec" {
    inline = ["mkdir -p ${var.stack_dir}/lib"]
  }

  provisioner "file" {
    source      = "${path.module}/files/bootstrap.sh"
    destination = "${var.stack_dir}/bootstrap.sh"
  }
  provisioner "file" {
    source      = "${path.module}/../provision-sso.sh"
    destination = "${var.stack_dir}/provision-sso.sh"
  }
  provisioner "file" {
    source      = "${path.module}/../lib/sso.sh"
    destination = "${var.stack_dir}/lib/sso.sh"
  }
  provisioner "file" {
    content     = local.sso_conf # holds admin password + api key
    destination = "${var.stack_dir}/sso.conf"
  }
  provisioner "file" {
    content     = local.sso_identity
    destination = "${var.stack_dir}/sso.identity"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 600 ${var.stack_dir}/sso.conf",
      "chmod +x ${var.stack_dir}/bootstrap.sh ${var.stack_dir}/provision-sso.sh",
      "${var.stack_dir}/bootstrap.sh ${var.stack_dir} ${var.enable_sso}",
    ]
  }

  depends_on = [null_resource.deploy]
}

# --- Verify: prove the endpoints actually serve a valid cert (never blocks) ---
# Runs on the operator machine, forces the server IP (immune to local DNS cache),
# and checks each endpoint returns a healthy code with a valid Let's Encrypt cert.
resource "null_resource" "verify" {
  triggers   = { always = timestamp() } # re-verify every apply
  depends_on = [null_resource.configure]
  provisioner "local-exec" {
    command = "${path.module}/files/verify.sh ${local.dashboard_host} ${local.pocket_id_host} ${var.server_ip}"
  }
}

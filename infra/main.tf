locals {
  dashboard_host = "${var.dashboard_subdomain}.${var.base_domain}"
  pocket_id_host = "${var.pocket_id_subdomain}.${var.base_domain}"
  ssh_host       = var.ssh_host != "" ? var.ssh_host : var.server_ip

  # Render every config the box needs from one place, so the deploy resource
  # can both upload them and key its re-run trigger off their content.
  compose = templatefile("${path.module}/files/docker-compose.yml.tftpl", {
    pangolin_version         = var.pangolin_version
    gerbil_version           = var.gerbil_version
    traefik_version          = var.traefik_version
    pocket_id_version        = var.pocket_id_version
    pocket_id_host           = local.pocket_id_host
    pocket_id_encryption_key = random_id.pocket_id_encryption_key.b64_std
  })

  pangolin_config = templatefile("${path.module}/files/config/config.yml.tftpl", {
    dashboard_host  = local.dashboard_host
    base_domain     = var.base_domain
    pangolin_secret = random_id.pangolin_secret.hex
  })

  traefik_config = templatefile("${path.module}/files/config/traefik/traefik_config.yml.tftpl", {
    letsencrypt_email = var.letsencrypt_email
    badger_version    = var.badger_version
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

  # 3. Install Docker if missing, then bring the stack up.
  provisioner "remote-exec" {
    inline = [
      "chmod +x ${var.stack_dir}/deploy.sh",
      "${var.stack_dir}/deploy.sh ${var.stack_dir}",
    ]
  }

  depends_on = [
    cloudflare_dns_record.apex,
    cloudflare_dns_record.wildcard,
  ]
}

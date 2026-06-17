locals {
  dashboard_host = "${var.dashboard_subdomain}.${var.base_domain}"
  pocket_id_host = "${var.pocket_id_subdomain}.${var.base_domain}"
  ssh_host       = var.ssh_host != "" ? var.ssh_host : var.server_ip

  # Org slug consumed by the org_id output (used by config/ to create and bind the
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
  # license over loopback). SSO wiring is now owned by config/ declaratively.
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

# --- Input validation: an ee- (Enterprise) image needs a license key; a
# community image must not require one. Done as a precondition (not a variable
# validation) so it can reference pangolin_version on Terraform/OpenTofu >= 1.6.
resource "terraform_data" "license_check" {
  lifecycle {
    precondition {
      condition     = !startswith(var.pangolin_version, "ee-") || (var.pangolin_license_key != "" && var.pangolin_license_key != "FILL_ME")
      error_message = "pangolin_version is an Enterprise (ee-) tag, so pangolin_license_key is required (free at https://app.pangolin.net -> Licenses). Use a community tag (e.g. 1.19.2) to run license-free — but identity-aware SSH won't be available."
    }
  }
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

  # 1. Ensure the directory tree exists and is writable by the SSH user so the
  #    file provisioner (scp, runs as that user) can upload into it.
  provisioner "remote-exec" {
    inline = [
      "mkdir -p ${var.stack_dir}/config/traefik ${var.stack_dir}/config/letsencrypt",
      "chown -R ${var.ssh_user} ${var.stack_dir}",
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

# --- Configure: headless admin + EE license, over loopback on the box (no UI) ---
# Seeds the Pangolin server admin and activates the license. SSO is owned by the
# declarative config/ Terraform plane; this step no longer touches Pocket ID.
resource "null_resource" "configure" {
  # Re-run only when the config-plane inputs change, NOT on every redeploy
  # (admin + SSO are idempotent; depends_on still orders us after deploy on the
  # first apply). A version bump no longer re-runs the whole SSO dance.
  triggers = {
    admin_conf     = sha1(local.admin_conf)
    bootstrap      = filesha1("${path.module}/files/bootstrap.sh")
    pang_bootstrap = filesha1("${path.module}/../lib/pang-bootstrap.sh")
  }

  connection {
    type        = "ssh"
    host        = local.ssh_host
    user        = var.ssh_user
    port        = var.ssh_port
    private_key = file(pathexpand(var.ssh_private_key_path))
  }

  # The bootstrap library lives under lib/ on the box.
  provisioner "remote-exec" {
    inline = ["mkdir -p ${var.stack_dir}/lib"]
  }

  provisioner "file" {
    source      = "${path.module}/files/bootstrap.sh"
    destination = "${var.stack_dir}/bootstrap.sh"
  }
  provisioner "file" {
    source      = "${path.module}/../lib/pang-bootstrap.sh"
    destination = "${var.stack_dir}/lib/pang-bootstrap.sh"
  }
  provisioner "file" {
    content     = local.admin_conf # holds admin credentials + license key
    destination = "${var.stack_dir}/admin.conf"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 600 ${var.stack_dir}/admin.conf",
      "chmod +x ${var.stack_dir}/bootstrap.sh",
      "${var.stack_dir}/bootstrap.sh ${var.stack_dir}",
    ]
  }

  depends_on = [null_resource.deploy]
}

# --- Mint a root Integration API key headlessly (for the Phase-2 provider) ---
# Uploads the actions list + mint script and runs it on the box (idempotent;
# persists the token to $stack_dir/.integration-api-key). Depends on configure
# so the server admin + lib/pang-bootstrap.sh are already in place.
resource "null_resource" "mint_api_key" {
  triggers = {
    mint_script = filesha1("${path.module}/files/mint-api-key.sh")
    actions     = filesha1("${path.module}/files/pangolin-actions.json")
    host        = local.ssh_host
    stack_dir   = var.stack_dir
  }

  connection {
    type        = "ssh"
    host        = local.ssh_host
    user        = var.ssh_user
    port        = var.ssh_port
    private_key = file(pathexpand(var.ssh_private_key_path))
  }

  provisioner "file" {
    source      = "${path.module}/files/mint-api-key.sh"
    destination = "${var.stack_dir}/mint-api-key.sh"
  }
  provisioner "file" {
    source      = "${path.module}/files/pangolin-actions.json"
    destination = "${var.stack_dir}/pangolin-actions.json"
  }
  provisioner "remote-exec" {
    inline = [
      "chmod +x ${var.stack_dir}/mint-api-key.sh",
      "STACK_DIR=${var.stack_dir} ${var.stack_dir}/mint-api-key.sh ${var.stack_dir}/pangolin-actions.json >/dev/null",
    ]
  }

  depends_on = [null_resource.configure]
}

# Surface the minted key as an output. The `query.dep` ties this read AFTER the
# mint resource (forces ordering on a data source). Runs read-api-key.sh locally,
# which SSHes in and cats the persisted token.
# NOTE: after the first apply the resource id is in state, so this runs on every
# `tofu plan` (an SSH into the box per plan); the box must be reachable for plan.
data "external" "pangolin_api_key" {
  program = ["bash", "${path.module}/files/read-api-key.sh"]
  query = {
    host      = local.ssh_host
    user      = var.ssh_user
    port      = tostring(var.ssh_port)
    key_path  = var.ssh_private_key_path
    stack_dir = var.stack_dir
    dep       = null_resource.mint_api_key.id
  }
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

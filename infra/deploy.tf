# Deploy: push the stack to the box and converge it (idempotent).
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
    cloudflare_dns_record.this,
  ]
}

# --- Identity-aware SSH via Pangolin's auth-daemon (optional) ---------------
# Kept in its own file so it stays independent of any local-only edits in
# main.tf. Off unless enable_ssh_access = true. The script self-elevates
# (sudo when not root), so this needs no `become` plumbing.
#
# LICENSE: SSH private resources require a Pangolin EE license (free for
# personal use). ssh-access.sh brings up the connector regardless and stops
# cleanly at the resource step with a 403 until a key is registered; re-running
# after licensing finishes the job. See variables.tf for the full note.

locals {
  ssh_site_name = var.ssh_site_name != "" ? var.ssh_site_name : "${split(".", var.base_domain)[0]}-host"
  # Optional public browser-SSH resource on <subdomain>.<base_domain> (covered by
  # the wildcard cert). Empty subdomain = private resource only.
  ssh_public_domain = var.ssh_public_subdomain != "" ? "${var.ssh_public_subdomain}.${var.base_domain}" : ""
}

resource "null_resource" "ssh_access" {
  count = var.enable_ssh_access ? 1 : 0

  triggers = {
    script        = filesha1("${path.module}/files/ssh-access.sh")
    dev_port      = filesha1("${path.module}/files/dev-port")
    sso_lib       = filesha1("${path.module}/../lib/sso.sh")
    newt_version  = var.newt_version
    site_name     = local.ssh_site_name
    roles         = join(",", var.ssh_access_roles)
    public_domain = local.ssh_public_domain
    sudo_cmds     = join(",", var.ssh_sudo_commands)
    host          = local.ssh_host
    stack_dir     = var.stack_dir
  }

  connection {
    type        = "ssh"
    host        = local.ssh_host
    user        = var.ssh_user
    port        = var.ssh_port
    private_key = file(pathexpand(var.ssh_private_key_path))
  }

  provisioner "file" {
    source      = "${path.module}/files/ssh-access.sh"
    destination = "${var.stack_dir}/ssh-access.sh"
  }

  provisioner "file" {
    source      = "${path.module}/files/dev-port"
    destination = "${var.stack_dir}/dev-port"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x ${var.stack_dir}/ssh-access.sh",
      "${var.stack_dir}/ssh-access.sh ${var.stack_dir} ${var.newt_version} ${local.ssh_site_name} '${join(",", var.ssh_access_roles)}' '${local.ssh_public_domain}' '${join(",", var.ssh_sudo_commands)}'",
    ]
  }

  # Needs the stack deployed and SSO/admin configured (sso.conf + lib/sso.sh on
  # the box, org + roles created) before it can drive the Pangolin API.
  depends_on = [null_resource.configure]
}

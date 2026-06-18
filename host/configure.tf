# Configure: headless admin bootstrap and EE license activation over loopback.
# --- Configure: headless admin + EE license, over loopback on the box (no UI) ---
# Seeds the Pangolin server admin and activates the license. SSO is owned by the
# idp/ (Pocket ID) and access/ (Pangolin) planes; this step no longer touches Pocket ID.
resource "null_resource" "configure" {
  # Re-run only when the config-plane inputs change, NOT on every redeploy
  # (admin + SSO are idempotent; depends_on still orders us after deploy on the
  # first apply). A version bump no longer re-runs the whole SSO dance.
  triggers = {
    admin_conf     = sha1(local.admin_conf)
    bootstrap      = filesha1("${path.module}/files/bootstrap.sh")
    pang_bootstrap = filesha1("${path.module}/lib/pang-bootstrap.sh")
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
    source      = "${path.module}/lib/pang-bootstrap.sh"
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

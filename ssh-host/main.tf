resource "null_resource" "ssh_host" {
  count = local.enabled ? 1 : 0
  triggers = {
    script       = filesha1("${path.module}/files/ssh-host.sh")
    dev_port     = filesha1("${path.module}/files/dev-port")
    newt_version = var.newt_version
    newt_id      = local.newt_id
    sshd_port    = var.ssh_sshd_port
    stack_dir    = var.stack_dir
    sudo_groups  = local.sudo_groups
    sudo_cmds    = local.sudo_commands
  }
  connection {
    type        = "ssh"
    host        = var.server_ip
    user        = var.ssh_user
    port        = var.ssh_port
    private_key = file(pathexpand(var.ssh_private_key_path))
  }
  provisioner "file" {
    source      = "${path.module}/files/ssh-host.sh"
    destination = "${var.stack_dir}/ssh-host.sh"
  }
  provisioner "file" {
    source      = "${path.module}/files/dev-port"
    destination = "${var.stack_dir}/dev-port"
  }
  provisioner "remote-exec" {
    inline = [
      "chmod +x ${var.stack_dir}/ssh-host.sh",
      "${var.stack_dir}/ssh-host.sh ${var.stack_dir} ${var.newt_version} '${local.dashboard}' '${local.newt_id}' '${local.newt_secret}' '${local.sudo_groups}' '${local.sudo_commands}'",
    ]
  }
}

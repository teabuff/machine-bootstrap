# Keymint: mint a root Integration API key headlessly and surface it as a data source.
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
  count   = var.read_api_key ? 1 : 0
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

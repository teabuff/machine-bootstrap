# Reads the bootstrap (infra/) state for the minted key, the Pocket ID static
# key, the public URLs, and the org id. Default = the sibling LOCAL state
# (standalone use). For multi-env, pass bootstrap_state_backend = "s3" and
# bootstrap_state_config = the R2 config of THIS env's bootstrap state key.
data "terraform_remote_state" "bootstrap" {
  backend = var.bootstrap_state_backend
  config = var.bootstrap_state_config != null ? var.bootstrap_state_config : {
    path = "${path.module}/../infra/terraform.tfstate"
  }
}

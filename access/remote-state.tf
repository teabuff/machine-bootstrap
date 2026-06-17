# Reads the host (machine) state for the Pangolin URL + API key + org id + root
# domain + Pocket ID URL, and the idp state for the OIDC client_id + client_secret
# (the one cross-module data handoff). Defaults = sibling LOCAL states (standalone).
# Multi-env passes *_state_backend = "s3" + each env's R2 config.
data "terraform_remote_state" "host" {
  backend = var.host_state_backend
  config  = var.host_state_config
}

data "terraform_remote_state" "idp" {
  backend = var.idp_state_backend
  config  = var.idp_state_config
}

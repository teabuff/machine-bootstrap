# Reads the host (machine) state for the Pocket ID URL + STATIC_API_KEY and the
# Pangolin dashboard URL (for the static wildcard callback). Default = sibling
# LOCAL state (standalone). Multi-env passes host_state_backend = "s3" + the R2
# config of THIS env's host state key.
data "terraform_remote_state" "host" {
  backend = var.host_state_backend
  config  = var.host_state_config
}

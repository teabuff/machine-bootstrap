variable "org_name" { type = string }

# The R2 config of THIS env's bootstrap.tfstate, so config/ can read it via
# terraform_remote_state. Mirror this env's bootstrap/backend.tf values; only the
# `key` differs (…/bootstrap.tfstate). No use_lockfile here — reads don't lock.
variable "bootstrap_state_config" {
  type = any
  default = {
    bucket                      = "machine-bootstrap-tfstate"
    key                         = "production/EXAMPLE/bootstrap.tfstate"
    region                      = "auto"
    profile                     = "r2"
    endpoints                   = { s3 = "https://ACCOUNT_ID.r2.cloudflarestorage.com" }
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    use_path_style              = true
    skip_s3_checksum            = true
  }
}

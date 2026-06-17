# Per-env declarative-SSO state in R2 — a SEPARATE key from the bootstrap state.
terraform {
  backend "s3" {
    bucket                      = "machine-bootstrap-tfstate"
    key                         = "production/EXAMPLE/config.tfstate" # distinct from bootstrap.tfstate
    region                      = "auto"
    profile                     = "r2"
    endpoints                   = { s3 = "https://ACCOUNT_ID.r2.cloudflarestorage.com" }
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    use_path_style              = true
    skip_s3_checksum            = true
    use_lockfile                = true
  }
}

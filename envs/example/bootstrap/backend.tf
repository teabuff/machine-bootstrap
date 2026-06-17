# Per-env bootstrap state in Cloudflare R2 (S3-compatible). This exact block
# (incl. use_lockfile native locking) is validated against R2.
# Fill `bucket` + the <ACCOUNT_ID> in the endpoint (or pass them at init via
# -backend-config). Credentials come from the [r2] profile in ~/.aws/credentials.
terraform {
  backend "s3" {
    bucket                      = "machine-bootstrap-tfstate"
    key                         = "production/EXAMPLE/bootstrap.tfstate" # one unique key per env
    region                      = "auto"
    profile                     = "r2"
    endpoints                   = { s3 = "https://ACCOUNT_ID.r2.cloudflarestorage.com" }
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    use_path_style              = true
    skip_s3_checksum            = true
    use_lockfile                = true # native S3 locking (OpenTofu >= 1.10)
  }
}

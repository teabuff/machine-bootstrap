# Reads the bootstrap (infra/) state for the minted key, the Pocket ID static
# key, the public URLs, and the org id. LOCAL backend for now — Plan 3 moves both
# roots to R2 and this switches to the s3 backend config.
data "terraform_remote_state" "bootstrap" {
  backend = "local"
  config = {
    path = "${path.module}/../infra/terraform.tfstate"
  }
}

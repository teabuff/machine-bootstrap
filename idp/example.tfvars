# idp/ — Pocket ID identity. Standalone uses the sibling host/ local state.
# Group NAMEs here are the contract with access/'s group_roles map.
groups = [
  { name = "engineering", friendly_name = "Engineering" },
  { name = "pocket-admin", friendly_name = "Pocket ID Admins" },
]

users = [
  { username = "alice", display_name = "Alice Example", email = "alice@example.com", groups = ["engineering", "pocket-admin"] },
]

# Multi-env (R2): point at this env's host state key instead of the sibling local file.
# host_state_backend = "s3"
# host_state_config = {
#   bucket         = "machine-bootstrap-tfstate"
#   key            = "production/<org>/<region>/host.tfstate"
#   region         = "auto"
#   profile        = "r2"
#   use_path_style = true
#   skip_s3_checksum            = true
#   skip_credentials_validation = true
#   skip_region_validation      = true
#   skip_requesting_account_id  = true
#   skip_metadata_api_check     = true
#   endpoints = { s3 = "https://<account>.r2.cloudflarestorage.com" }
# }

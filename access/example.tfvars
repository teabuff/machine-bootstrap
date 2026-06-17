# access/ — Pangolin org, roles, and the IdP registration. Standalone uses the
# sibling host/ and idp/ local states.
org_name = "Example Org"

role_names = ["Developer", "Guest"]

# group name => Pangolin role. Names MUST match idp/'s groups[].name.
group_roles = {
  engineering = "Developer"
}

# Multi-env (R2): point at this env's host AND idp state keys.
# host_state_backend = "s3"
# host_state_config  = { bucket = "machine-bootstrap-tfstate", key = "production/<org>/<region>/host.tfstate", region = "auto", profile = "r2", use_path_style = true, skip_s3_checksum = true, skip_credentials_validation = true, skip_region_validation = true, skip_requesting_account_id = true, skip_metadata_api_check = true, endpoints = { s3 = "https://<account>.r2.cloudflarestorage.com" } }
# idp_state_backend  = "s3"
# idp_state_config   = { bucket = "machine-bootstrap-tfstate", key = "production/<org>/<region>/idp.tfstate", region = "auto", profile = "r2", use_path_style = true, skip_s3_checksum = true, skip_credentials_validation = true, skip_region_validation = true, skip_requesting_account_id = true, skip_metadata_api_check = true, endpoints = { s3 = "https://<account>.r2.cloudflarestorage.com" } }

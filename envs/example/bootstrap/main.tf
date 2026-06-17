# Bootstrap (deploy + mint key) for one env, consuming the public infra/ as a
# pinned git module. Per-env values below; secrets come from TF_VAR_* env vars
# (see ../../.envrc.example). SSO + SSH are off — the declarative config/ owns SSO.
module "bootstrap" {
  source = "git::https://github.com/teabuff/machine-bootstrap.git//infra?ref=REF"

  server_ip            = var.server_ip
  base_domain          = var.base_domain
  dashboard_subdomain  = var.dashboard_subdomain
  cloudflare_api_token = var.cloudflare_api_token
  cloudflare_zone_id   = var.cloudflare_zone_id
  letsencrypt_email    = var.letsencrypt_email
  ssh_port             = var.ssh_port
  ssh_private_key_path = var.ssh_private_key_path

  pangolin_admin_email    = var.pangolin_admin_email
  pangolin_admin_password = var.pangolin_admin_password
  pangolin_license_key    = var.pangolin_license_key

  enable_sso        = false # declarative config/ owns SSO
  enable_ssh_access = false # identity-aware SSH returns in a later plan
}

# Re-export what this env's config/ root reads via terraform_remote_state.
output "org_id" { value = module.bootstrap.org_id }
output "root_domain" { value = module.bootstrap.root_domain }
output "pangolin_dashboard_url" { value = module.bootstrap.pangolin_dashboard_url }
output "pocket_id_base_url" { value = module.bootstrap.pocket_id_base_url }
output "pangolin_api_key" {
  value     = module.bootstrap.pangolin_api_key
  sensitive = true
}
output "pocket_id_static_api_key" {
  value     = module.bootstrap.pocket_id_static_api_key
  sensitive = true
}

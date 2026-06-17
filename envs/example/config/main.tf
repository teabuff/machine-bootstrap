# Declarative SSO for one env, consuming the public config/ as a pinned git
# module. Reads THIS env's bootstrap state from R2 (the bootstrap.tfstate key).
module "config" {
  source = "git::https://github.com/teabuff/machine-bootstrap.git//config?ref=REF"

  org_name = var.org_name

  bootstrap_state_backend = "s3"
  bootstrap_state_config  = var.bootstrap_state_config
}

output "idp_redirect_url" { value = module.config.idp_redirect_url }

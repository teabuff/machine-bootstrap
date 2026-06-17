locals {
  bootstrap = data.terraform_remote_state.bootstrap.outputs
}

provider "pangolin" {
  url     = local.bootstrap.pangolin_url
  api_key = local.bootstrap.pangolin_api_key
  org_id  = local.bootstrap.org_id
}

provider "pocketid" {
  base_url  = local.bootstrap.pocket_id_base_url
  api_token = local.bootstrap.pocket_id_static_api_key
}

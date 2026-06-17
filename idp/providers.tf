provider "pocketid" {
  base_url  = local.host.pocket_id_base_url
  api_token = local.host.pocket_id_static_api_key
}

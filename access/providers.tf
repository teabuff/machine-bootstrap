provider "pangolin" {
  url     = local.host.pangolin_dashboard_url
  api_key = local.host.pangolin_api_key
  org_id  = local.host.org_id
}

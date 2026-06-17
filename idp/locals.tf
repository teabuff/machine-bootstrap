locals {
  host          = data.terraform_remote_state.host.outputs
  dashboard_url = local.host.pangolin_dashboard_url # https://pangolin.<base_domain>
  pocket_id_url = local.host.pocket_id_base_url     # https://id.<base_domain>

  # Scoped path-wildcard callback: matches https://<dashboard>/auth/idp/<N>/oidc/callback
  # for any server-assigned IdP id N, WITHOUT depending on the Pangolin IdP — this is
  # what breaks the OIDC-client <-> IdP cycle. The pocketid provider's URL validator
  # allows '*', and Pocket ID matches it at authorize+token time. dashboard_url is the
  # host's KNOWN Pangolin URL (not anything from the access module), so no cycle.
  pangolin_callback = "${local.dashboard_url}/auth/idp/*/oidc/callback"
}

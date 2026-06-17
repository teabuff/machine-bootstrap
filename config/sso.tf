# Pangolin's external OIDC IdP pointing at Pocket ID. Consumes the client's id +
# secret (one-directional: idp depends on the client, the client's wildcard
# callback does NOT depend on the idp). identifier_path/scopes match the legacy
# bash. redirect_url is exported by the provider for reference/debugging.
resource "pangolin_idp" "pocket_id" {
  name            = "pocket-id"
  client_id       = pocketid_client.pangolin.client_id
  client_secret   = pocketid_client.pangolin.client_secret
  auth_url        = local.pid_auth_url
  token_url       = local.pid_token_url
  identifier_path = "preferred_username"
  email_path      = "email"
  name_path       = "name"
  scopes          = "openid profile email groups"
  auto_provision  = true
  # NB: do NOT set `variant` — the stackops provider's OIDC create endpoint does
  # not echo it back, so an explicit value triggers "inconsistent result after
  # apply". Omitting it lets the (Optional+Computed) default stand. The IdP is
  # created via the /idp/oidc endpoint, so it is OIDC regardless.
}

# Bind the IdP to the org with the role/org mapping so SSO users land in the org
# with the right role. Without this, users authenticate but are rejected with
# "must be added to an organization".
resource "pangolin_idp_org" "pocket_id" {
  idp_id       = pangolin_idp.pocket_id.id
  org_id       = local.org_id
  role_mapping = local.role_mapping
  org_mapping  = local.org_mapping

  depends_on = [pangolin_org.main, pangolin_role.custom]
}

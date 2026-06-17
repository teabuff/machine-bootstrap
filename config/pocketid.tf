# The Pangolin OIDC client in Pocket ID. Deterministic client_id "pangolin"
# (matches the legacy bash). callback_urls is a single scoped wildcard so it does
# NOT depend on the Pangolin IdP — breaking the cycle. client_secret is generated
# once by Pocket ID and exported (sensitive) for the IdP to consume.
resource "pocketid_client" "pangolin" {
  name          = "Pangolin"
  client_id     = "pangolin"
  callback_urls = [local.pangolin_callback]
  is_public     = false
  pkce_enabled  = true
}

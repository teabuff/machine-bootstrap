# Reads the bootstrap (host/) state for the minted key, the Pocket ID static
# key, the public URLs, and the org id. Default = the sibling LOCAL state
# (standalone use). For multi-env, pass bootstrap_state_backend = "s3" and
# bootstrap_state_config = the R2 config of THIS env's bootstrap state key.
# No conditional: the variable's default IS the sibling-local-state config, and
# the multi-env caller overrides it with the R2 config. (A ternary between the
# two different object shapes errors with "inconsistent conditional result types".)
data "terraform_remote_state" "bootstrap" {
  backend = var.bootstrap_state_backend
  config  = var.bootstrap_state_config
}

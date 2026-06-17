# Secrets: generated random values stored in local state; never prompted, never in git.
# --- Generated secrets (stored in local state; never prompted, never in git) ---

resource "random_id" "pangolin_secret" {
  byte_length = 32 # -> 64 hex chars, equivalent to `openssl rand -hex 32`
}

resource "random_id" "pocket_id_encryption_key" {
  byte_length = 32 # -> base64, equivalent to `openssl rand -base64 32`
}

resource "random_id" "pocket_id_static_api_key" {
  byte_length = 24 # -> 48 hex chars (well over Pocket ID's >=16 minimum)
}

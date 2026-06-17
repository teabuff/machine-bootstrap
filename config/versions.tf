terraform {
  required_version = ">= 1.7.0"

  # No backend block: as a standalone root this defaults to local state; as a
  # module (per-env dir in the private envs repo) the calling root supplies the
  # R2 backend. A child module must not declare a backend.

  required_providers {
    pangolin = {
      source  = "stackopshq/pangolin"
      version = "~> 1.4"
    }
    pocketid = {
      source  = "trozz/pocketid"
      version = "~> 2.2"
    }
  }
}

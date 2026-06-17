terraform {
  required_version = ">= 1.7.0"

  # No backend block: standalone defaults to local state; a multi-env caller
  # supplies the R2 backend (a child module must not declare a backend).

  required_providers {
    pocketid = {
      source  = "trozz/pocketid"
      version = "~> 2.2"
    }
  }
}

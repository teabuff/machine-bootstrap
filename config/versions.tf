terraform {
  required_version = ">= 1.7.0"

  backend "local" {} # Plan 3 swaps this for the R2 (s3) backend.

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

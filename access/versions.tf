terraform {
  required_version = ">= 1.7.0"

  # No backend block: standalone defaults to local state; a multi-env caller
  # supplies the R2 backend (a child module must not declare a backend).

  required_providers {
    pangolin = {
      source  = "stackopshq/pangolin"
      version = "~> 1.4"
    }
  }
}

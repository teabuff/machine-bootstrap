# Checks: license validation, pre-flight DNS advisory, and post-deploy endpoint verification.
# --- Input validation: an ee- (Enterprise) image needs a license key; a
# community image must not require one. Done as a precondition (not a variable
# validation) so it can reference pangolin_version on Terraform/OpenTofu >= 1.6.
resource "terraform_data" "license_check" {
  lifecycle {
    precondition {
      condition     = !startswith(var.pangolin_version, "ee-") || (var.pangolin_license_key != "" && var.pangolin_license_key != "FILL_ME")
      error_message = "pangolin_version is an Enterprise (ee-) tag, so pangolin_license_key is required (free at https://app.pangolin.net -> Licenses). Use a community tag (e.g. 1.19.2) to run license-free — but identity-aware SSH won't be available."
    }
  }
}

# --- Pre-flight: advisory DNS check from the operator machine (never blocks) ---
check "dns_preflight" {
  data "external" "preflight" {
    program = ["bash", "${path.module}/files/preflight.sh", var.base_domain, local.dashboard_host, local.pocket_id_host, var.server_ip]
  }
  assert {
    condition     = data.external.preflight.result.ok == "true"
    error_message = data.external.preflight.result.message
  }
}

# --- Verify: prove the endpoints actually serve a valid cert (never blocks) ---
# Runs on the operator machine, forces the server IP (immune to local DNS cache),
# and checks each endpoint returns a healthy code with a valid Let's Encrypt cert.
check "endpoints" {
  data "external" "verify" {
    program = ["bash", "${path.module}/files/verify.sh", local.dashboard_host, local.pocket_id_host, var.server_ip]
  }
  assert {
    condition     = data.external.verify.result.ok == "true"
    error_message = data.external.verify.result.message
  }
}

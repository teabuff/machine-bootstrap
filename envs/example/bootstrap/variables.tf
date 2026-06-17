# Per-env inputs. Non-secrets go in terraform.tfvars; the three sensitive ones
# come from TF_VAR_* env vars (see ../../.envrc.example) — keep them out of files.
variable "server_ip" { type = string }
variable "base_domain" { type = string }
variable "dashboard_subdomain" {
  type    = string
  default = "pangolin"
}
variable "cloudflare_zone_id" { type = string }
variable "letsencrypt_email" { type = string }
variable "ssh_port" {
  type    = number
  default = 22
}
variable "ssh_private_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519"
}

variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}
variable "pangolin_admin_email" { type = string }
variable "pangolin_admin_password" {
  type      = string
  sensitive = true
}
variable "pangolin_license_key" {
  type      = string
  sensitive = true
}

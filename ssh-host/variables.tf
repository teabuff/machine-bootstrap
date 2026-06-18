variable "enable_ssh_access" {
  type        = bool
  description = "Converge the box-side SSH wiring (newt daemon + sshd CA). Off = no-op."
  default     = false
}
variable "newt_version" {
  type        = string
  description = "Pinned newt version (the site connector + SSH auth-daemon)."
  default     = "1.13.0"
}
variable "ssh_sshd_port" {
  type        = number
  description = "The box's sshd port (must match access's resource tcp_port_range)."
  default     = 22
}
variable "stack_dir" {
  type        = string
  description = "Stack directory on the box (where scripts are uploaded), matching host/."
  default     = "/opt/pangolin-stack"
}
variable "server_ip" { type = string }
variable "ssh_user" {
  type    = string
  default = "root"
}
variable "ssh_port" {
  type    = number
  default = 22
}
variable "ssh_private_key_path" { type = string }
variable "access_state_backend" {
  type    = string
  default = "local"
}
variable "access_state_config" {
  type    = any
  default = { path = "../access/terraform.tfstate" }
}
variable "host_state_backend" {
  type    = string
  default = "local"
}
variable "host_state_config" {
  type    = any
  default = { path = "../host/terraform.tfstate" }
}

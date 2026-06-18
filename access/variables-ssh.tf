variable "enable_ssh_access" {
  type        = bool
  description = "Create the Pangolin SSH plane (site + resources + role SSH policy). The box-side daemon lives in ssh-host/."
  default     = false
}
variable "ssh_access_roles" {
  type        = list(string)
  description = "Role NAMEs granted SSH (must exist in role_names / group_roles). Admin is never SSH-enabled."
  default     = ["Developer"]
}
variable "ssh_site_name" {
  type        = string
  description = "Pangolin site name for the host (newt connector). Empty = <first label of base_domain>-host."
  default     = ""
}
variable "ssh_public_subdomain" {
  type        = string
  description = "Subdomain for the public browser-SSH resource (e.g. 'shell'). Empty = private SSH only."
  default     = ""
}
variable "ssh_sudo_commands" {
  type        = list(string)
  description = "Absolute command paths the SSH roles may sudo (e.g. /usr/local/bin/dev-port). Empty = no sudo."
  default     = []
}
variable "ssh_sshd_port" {
  type        = number
  description = "The box's real sshd port (the private SSH resource targets 127.0.0.1:this)."
  default     = 22
}

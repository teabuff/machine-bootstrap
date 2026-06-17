# ---------------------------------------------------------------------------
# Server (bring-your-own — provider-agnostic)
# ---------------------------------------------------------------------------
# You create the VPS yourself (Bandwagon, V.PS, Hetzner, a Pi — anything with
# SSH). This config converges it; it never creates the box.

variable "server_ip" {
  type        = string
  description = "Public IPv4 of the server. Used for the Cloudflare A records and, by default, for SSH."

  validation {
    condition     = can(regex("^\\d{1,3}(\\.\\d{1,3}){3}$", var.server_ip))
    error_message = "server_ip must be a dotted-quad IPv4 address."
  }
}

variable "ssh_host" {
  type        = string
  description = "Host to SSH into, if different from server_ip (e.g. a jump hostname). Empty = use server_ip."
  default     = ""
}

variable "ssh_user" {
  type        = string
  description = "SSH user the deploy connects as — must be root (privileged steps run directly, no sudo wrapping). The box must accept key-based root SSH with your deploy key in root's authorized_keys (configure that out of band)."
  default     = "root"
}

variable "ssh_port" {
  type        = number
  description = "SSH port."
  default     = 22
}

variable "ssh_private_key_path" {
  type        = string
  description = "Path to the private key used to SSH into the server."
  default     = "~/.ssh/id_ed25519"
}

# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

variable "stack_dir" {
  type        = string
  description = "Absolute directory on the server where the compose stack lives."
  default     = "/opt/pangolin-stack"
}

variable "manage_firewall" {
  type        = bool
  description = "Install/converge ufw to allow only ssh_port + 80/443/51820·udp/21820·udp (SSH-safe). Set false if a firewall is managed elsewhere. NB: Docker-published ports bypass ufw regardless."
  default     = true
}

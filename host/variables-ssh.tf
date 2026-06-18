# ---------------------------------------------------------------------------
# Identity-aware SSH (Pangolin auth-daemon) — on by default (EE stack).
# ---------------------------------------------------------------------------
# Installs newt as a host systemd service (connector + SSH auth-daemon),
# registers an SSH private resource for THIS host, grants roles SSH access, and
# adds an additive sshd CA drop-in. Users then `pangolin ssh <host>-ssh` and get
# a short-lived, CA-signed cert; their Linux username is their Pocket ID
# preferred_username, JIT-provisioned on first login.
#
# REQUIRES a Pangolin Enterprise Edition license (free for personal use /
# businesses under USD 100k revenue): SSH private resources return HTTP 403
# until a key is registered at the dashboard's /admin/license. The connector
# (newt + site) still comes up unlicensed; only the resource/cert path is gated.
# Apply for the free key at https://app.pangolin.net (Licenses), register it,
# then re-apply — ssh-access.sh detects the 403 and stops cleanly until then.

variable "enable_ssh_access" {
  type        = bool
  description = "Provision identity-aware SSH for this host via Pangolin's auth-daemon (newt on systemd + SSH resource + sshd CA drop-in). On by default; relies on the EE license above. Set false to skip SSH and run only the web stack. Disabled during the bash->provider migration; identity-aware SSH returns declaratively in a later plan."
  default     = false
}

variable "newt_version" {
  type        = string
  description = "fosrl/newt release tag for the host connector/auth-daemon. >= 1.13.0 runs the auth-daemon by default. Pinned for reproducibility."
  default     = "1.13.0"
}

variable "ssh_access_roles" {
  type        = list(string)
  description = "Org role NAMEs granted SSH access to this host (Admin is implicit and filtered out). Must match roles created in the access/ plane (var.role_names)."
  default     = ["Developer"]
}

variable "ssh_site_name" {
  type        = string
  description = "Name of the Pangolin site representing this host (the newt connector). Empty = derive from the dashboard subdomain + base domain's first label."
  default     = ""
}

variable "ssh_public_subdomain" {
  type        = string
  description = "Subdomain (under base_domain) for an optional PUBLIC browser-SSH resource, e.g. 'shell' -> shell.<base_domain>, SSO-gated to ssh_access_roles and served over the wildcard cert. Empty = private (pangolin ssh) resource only."
  default     = ""
}

variable "ssh_sudo_commands" {
  type        = list(string)
  description = "Absolute command paths the ssh_access_roles may run via sudo (sshSudoMode=commands), e.g. [\"/usr/sbin/ufw\"]. Empty = no sudo. Each SSH role also lands its JIT users in a fixed-GID Unix group named after the role, lower-cased (Developer -> `developer`) — create those groups via apply-host.sh (see provisioning/manifests/example.host). Admin is implicit (full sudo) and managed separately."
  default     = []
}

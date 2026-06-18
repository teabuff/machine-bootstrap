# Identity-aware SSH (Pangolin plane). Gated by var.enable_ssh_access. The
# box-side newt daemon + sshd live in ssh-host/, which reads the outputs here.
resource "pangolin_site" "host" {
  count = local.ssh_enabled ? 1 : 0
  name  = local.ssh_site_name
}

# Private SSH resource — lands on the host's real OpenSSH. alias <site>.internal.
# mode = "host": L4 host tunnel (the provider only accepts host/cidr/http; "ssh"
# is not a mode). auth_daemon_mode = "site" makes it the identity-aware SSH daemon.
# host mode requires `alias` and shapes traffic with tcp_port_range (the box's
# real sshd port); destination_port is ignored for host mode.
resource "pangolin_site_resource" "ssh" {
  count            = local.ssh_enabled ? 1 : 0
  site_id          = pangolin_site.host[0].id
  name             = "${local.ssh_site_name} SSH"
  mode             = "host"
  alias            = "${local.ssh_site_name}.internal"
  auth_daemon_mode = "site"
  destination      = "127.0.0.1"
  tcp_port_range   = tostring(var.ssh_sshd_port)
}

resource "pangolin_site_resource_role" "ssh" {
  for_each         = local.ssh_roles
  site_resource_id = pangolin_site_resource.ssh[0].id
  role_id          = pangolin_role.custom[each.value].id
}

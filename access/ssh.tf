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

# Public browser-SSH terminal at <subdomain>.<base_domain>. The provider has NO
# mode:ssh proxy resource and only a READ-ONLY pangolin_blueprint data source, so
# we apply the browser-SSH blueprint via the Integration API (PUT /org/{org}/blueprint
# with a base64-encoded JSON document — the same path the Pangolin UI uses).
#
# TODO: replace this terraform_data + local-exec with a real `pangolin_blueprint`
# RESOURCE once stackopshq/pangolin ships one (v1.4.0 has only data-sources/blueprint).
# That restores drift detection + clean destroy. Track:
#   https://registry.terraform.io/providers/stackopshq/pangolin (blueprint resource)
#
# NB: Pangolin blueprints are append-only (no DELETE). Disabling browser-SSH removes
# this terraform_data but NOT the live Pangolin resource — delete that via the UI/API.
resource "terraform_data" "ssh_browser" {
  count            = local.ssh_public_enabled ? 1 : 0
  triggers_replace = local.ssh_browser_blueprint

  provisioner "local-exec" {
    interpreter = ["/usr/bin/env", "bash", "-c"]
    command     = "curl -fsS -X PUT -H \"Authorization: Bearer $API_KEY\" -H 'Content-Type: application/json' \"$URL/v1/org/$ORG/blueprint\" --data-raw \"$BODY\" >/dev/null && echo 'browser-SSH blueprint applied'"
    environment = {
      API_KEY = local.host.pangolin_api_key
      URL     = local.dashboard_url
      ORG     = local.org_id
      BODY    = jsonencode({ blueprint = local.ssh_browser_blueprint })
    }
  }
}

output "ssh_active" {
  description = "Whether the box-side SSH wiring ran."
  value       = local.enabled
}
output "ssh_private_alias" {
  description = "Internal SSH alias (reach the host as <user>@<alias> through the connector)."
  value       = local.enabled ? "${local.site_name}.internal" : null
}

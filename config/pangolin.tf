# The org SSO users join. org_id comes from bootstrap state (derived from the
# base domain); subnet/utility_subnet are explicit (the provider requires them).
resource "pangolin_org" "main" {
  org_id         = local.org_id
  name           = var.org_name
  subnet         = var.org_subnet
  utility_subnet = var.org_utility_subnet
}

# Custom roles the IdP role-mapping may reference (Admin + Member are built in).
# New roles start with no resource permissions — grant per-resource later.
resource "pangolin_role" "custom" {
  for_each = toset(var.role_names)

  name        = each.value
  description = each.value

  depends_on = [pangolin_org.main]
}

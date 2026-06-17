# Copy to terraform.tfvars (gitignored) and fill in.
org_name = "Acme Corp" # display name; org_id is derived in the bootstrap

# Subnets for the org (must not overlap other orgs on the box):
# org_subnet         = "100.90.0.0/24"
# org_utility_subnet = "100.96.0.0/24"

# role_names = ["Developer", "Guest"]
# idp_role_mapping = "contains(groups, 'pangolin-admin') && ['Admin'] || ['Member']"
# idp_org_mapping  = "ends_with(email, '@acme.com') && 'acme-com'"

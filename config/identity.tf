# Declarative Pocket ID identities (replaces lib/sso.sh's pid_group/pid_user).
resource "pocketid_group" "this" {
  for_each      = { for g in var.groups : g.name => g }
  name          = each.value.name
  friendly_name = each.value.friendly_name
}

resource "pocketid_user" "this" {
  for_each     = { for u in var.users : u.username => u }
  username     = each.value.username
  email        = each.value.email
  display_name = each.value.display_name
  # Membership in the pocket-admin group flips the Pocket ID admin shield.
  is_admin = contains(each.value.groups, "pocket-admin")
  groups   = [for g in each.value.groups : pocketid_group.this[g].id]
}

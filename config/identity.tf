# Declarative Pocket ID identities (replaces the deleted bash pid_group/pid_user helpers).
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
  # The provider returns "" (not null) for unset first/last names -> "inconsistent
  # result after apply". Set them explicitly, derived from display_name like the
  # legacy bash (first word = first name, remainder = last name).
  first_name = split(" ", each.value.display_name)[0]
  last_name  = join(" ", slice(split(" ", each.value.display_name), 1, length(split(" ", each.value.display_name))))
  # Membership in the pocket-admin group flips the Pocket ID admin shield.
  is_admin = contains(each.value.groups, "pocket-admin")
  groups   = [for g in each.value.groups : pocketid_group.this[g].id]
}

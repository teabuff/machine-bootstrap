# First-login bootstrap: a one-time Pocket ID access token (login link) per user.
# Enrolling a passkey is the ONE Pocket ID step that can't be declared — a freshly
# added user has no credential to log in with. This mints a single-use link per user
# so the admin can send it; the user opens it, lands logged-in, and enrols a passkey.
#
# The token is write-only and consumed-on-use; the provider's Read is a no-op, so
# each token is created ONCE (when the user is added) and never churns on re-apply.
# Re-issue (link expired before enrolment): `tofu apply -replace` the user's token,
# or bump var.enrollment_link_ttl (recreates all).
resource "pocketid_one_time_access_token" "enroll" {
  for_each = var.issue_enrollment_links ? { for u in var.users : u.username => u } : {}

  user_id = pocketid_user.this[each.key].id
  ttl     = var.enrollment_link_ttl
}

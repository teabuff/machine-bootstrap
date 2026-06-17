# Identity-aware SSH (Pangolin auth-daemon)

Optional component that gives a host **SSO-gated SSH**: a user runs
`pangolin ssh <host>-ssh`, authenticates with their Pocket ID identity, and
receives a short-lived (5-minute) CA-signed certificate. Their Linux username is
their Pocket ID `preferred_username`, JIT-provisioned on first login. Access is
controlled by Pangolin org **roles**, not by `authorized_keys`.

On by default (this stack runs the EE image). Set `enable_ssh_access = false` to
run only the web stack.

## ⚠️ Requires a Pangolin Enterprise Edition license

SSH **private resources are an EE-licensed feature**, so this stack runs the
**Enterprise build** (`fosrl/pangolin:ee-<version>`) and a license key is
**required** (`pangolin_license_key`). The community `fosrl/pangolin:<version>`
tag is a different image with no license routes and no SSH — it returns
`403 "SSH private resources are not included in your current plan"`. **A free
license** covers personal use and businesses under USD 100k gross annual
revenue.

This is automated — you don't visit `/admin/license`:

1. Apply for the free key at <https://app.pangolin.net> → **Licenses**.
2. Set `pangolin_license_key` in `terraform.tfvars`.
3. `tofu apply`.

The configure step (`bootstrap.sh` → `pang_license`) registers the key
headlessly via `POST /api/v1/license/activate` (idempotent — skipped when
already valid). The first apply against a box previously on the community image
recreates the pangolin container and runs the EE DB migrations on the existing
volume. The web SSO / IdP / RBAC stack is **not** gated; only SSH (and a few
other premium features) are.

`ssh-access.sh` is also license-aware: it brings up the connector regardless,
and if the resource step still hits a 403 (e.g. the licensed tier doesn't
include private resources) it prints guidance and exits cleanly (exit 0) so the
apply doesn't fail. Re-running after the license is active finishes the job.

## What it does (all idempotent, in order)

1. Installs a pinned `newt` (`newt_version`, default `1.13.0`) to
   `/usr/local/bin/newt`. In ≥1.13 the SSH auth-daemon runs by default.
2. Ensures a Pangolin **site** for this host (`ssh_site_name`) and persists its
   newt credentials to `/etc/newt/newt.env` (root, `600`) so re-runs reuse the
   secret instead of rotating it.
3. Runs `newt` as a systemd service (`newt.service`) — the site connector *and*
   the auth-daemon in one process. It writes the org CA to `/etc/ssh/ca.pem`
   **lazily, on the first `pangolin ssh` connection** (not at boot).
4. Creates a private **SSH resource** (`mode: ssh`, `authDaemonMode: site`,
   `pamMode: push`, destination `127.0.0.1:<sshd-port>`) and grants
   `ssh_access_roles` SSH access (`Admin` is implicit and filtered out).
   `site` mode lands the user on this host's **real OpenSSH** (so VS Code
   Remote-SSH / port-forwarding / sftp all work); `push` forces the Linux
   username to the SSO `preferred_username`.
5. Adds an **additive**, PROACTIVE sshd drop-in at
   `/etc/ssh/sshd_config.d/10-pangolin-ca.conf`:

   ```
   TrustedUserCAKeys /etc/ssh/ca.pem
   AuthorizedPrincipalsCommand /usr/local/bin/newt auth-daemon principals --username %u
   AuthorizedPrincipalsCommandUser root
   ```

   Written up front (sshd tolerates the not-yet-existent `ca.pem`, which newt
   fills on first connect), validated with `sshd -t`, applied with `systemctl
   reload` (never `restart`). Purely additive: `AuthorizedPrincipalsCommand` is
   consulted **only during certificate auth**, so existing password/key login is
   unaffected. If `sshd -t` fails the drop-in is removed and sshd is left
   untouched.

## Connecting (end user)

```sh
curl -fsSL https://static.pangolin.net/get-cli.sh | bash   # install the client
pangolin ssh <sso-username>@<host>-ssh                     # e.g. jdoe@tyo-host-ssh
pangolin ssh <sso-username>@<host>-ssh -p 2222             # non-default sshd port
```

Because `site` mode terminates on real OpenSSH, **VS Code Remote-SSH works**
(via a `pangolin` `ProxyCommand` in `~/.ssh/config`). newt's *native* SSH mode
would NOT — its embedded server only supports `session` channels, no
`direct-tcpip` port forwarding, which VS Code requires. That's the reason this
component uses `site` mode rather than `native`.

## Variables

| variable | default | meaning |
|---|---|---|
| `pangolin_license_key` | (required) | EE license key; runs the ee- image, auto-activated |
| `enable_ssh_access` | `true` | provision SSH (set `false` to skip) |
| `newt_version` | `1.13.0` | pinned fosrl/newt release |
| `ssh_access_roles` | `["Developer"]` | org roles granted SSH (must exist) |
| `ssh_site_name` | `<base_domain first label>-host` | the Pangolin site for this host |

## Per-role RBAC (Unix groups + sudo)

`role_ssh_enable` configures each `ssh_access_roles` role with: `allowSsh`, a JIT
home dir, a Unix **group** named after the role lower-cased (`Developer` →
`developer`), and a scoped **sudo** policy from `ssh_sudo_commands` (e.g.
`["/usr/sbin/ufw"]` → `sshSudoMode=commands`; empty → no sudo). Admin is implicit
(`sshSudoMode=full`) and managed out of band.

Those Unix groups must exist on the host **first, at fixed GIDs** (so `/data`
ownership stays consistent across hosts) — create them with the host manifest,
which is not wired into `tofu` (run it once per host):

```
sudo ./apply-host.sh hosts/<realm>.host     # e.g.  group developer 8002
```

newt applies the group membership + sudoers entry at *connection* time, so a
user must reconnect after a policy change to pick it up.

## Topology note

This component targets a **single VPS**: newt-on-systemd is both the site
connector and the host-native auth-daemon (which must be host-native to write
`/etc/ssh/ca.pem` and `useradd`). One process, one unit — no split needed.

A **homelab / multi-machine** target is a different topology (newt in Docker,
which can't touch the host's `/etc/ssh` or run `useradd`). There you'd use
`authDaemonMode: remote`: Docker `newt` proxies to a standalone host-native
auth-daemon per target (port 22123, shared pre-shared key), and users still land
on each host's real OpenSSH. Not what this component sets up.

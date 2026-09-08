# Lab secret rotation

Changing encrypted SOPS data updates files during activation. Each consumer has
its own reload behavior; a changed file alone does not establish that a running
service accepts the new credential. This inventory describes repository wiring,
not a completed live rotation.

## Consumer inventory

| Consumer | Credential delivery | Rotation behavior |
| --- | --- | --- |
| Vaultwarden | Rendered `vaultwarden.env` | The template restarts `docker-vaultwarden.service`, recreating the NixOS-managed container with the new environment. |
| Cloudflare Tunnel | `cloudflare-tunnel-credentials` file | The secret restarts `cloudflared-tunnel-bandit-lab.service`; verify the tunnel reconnects and the expected route works. |
| AiiA Ghost | Rendered `aiia.env` | Manual coordinated rotation below; this file combines provider keys and the database password. |
| AiiA MySQL | Rendered `aiia-mysql.env` | Bootstrap inputs only; existing SQL accounts must be changed in MySQL. |
| Grafana | Admin password file mounted by the Portainer stack | Initializes a new database only; for an existing database, change the stored account password below. |
| Mrija archive app | Rendered `mrija-archive.env`, external Portainer deployment | Recreate the app container through its owning stack after rendering the new environment; no NixOS app unit is declared here. |
| Mrija archive sync | Same file through systemd `EnvironmentFile` | Each new `mrija-archive-sync.service` invocation reads the current file. No restart hook: restarting would interrupt or trigger a sync. |

Host account password changes use the NixOS activation path (`neededForUsers`).
SSH key files are consumed by SSH; identities already loaded into an agent may
need refreshing. Cachix's shell wrapper reads its token for each invocation.
Shell-exported API keys require refreshing the relevant shell/client. Shodan's
wrapper initializes its separate CLI credential file only when absent: update
that stored credential through Shodan's supported initialization command when
rotating the SOPS source. None of these justify restarting unrelated daemons.

## AiiA database passwords

MySQL stores users in `/srv/containers/aiia/mysql`. The container's
`MYSQL_PASSWORD` and `MYSQL_ROOT_PASSWORD` initialize an empty data directory;
they do not update accounts in an existing database. See the
[MySQL container initialization documentation](https://dev.mysql.com/doc/refman/8.4/en/docker-mysql-more-topics.html).

Use a maintenance window with working database administration access and a
verified backup. Pause automatic lab apply while coordinating SQL and SOPS so an
unrelated activation cannot install half of the change. Record whether the
apply timer was active and restore that state afterward.

1. Identify the actual `ghost` account and its MySQL `Host` value. Confirm the
   account used by Ghost; do not assume every account named `ghost` is equivalent.
2. Stop `docker-aiia-ghost.service` for a simple downtime rotation. Change the
   identified SQL account password using an authenticated administrative session.
   Supply credentials through a secure interactive mechanism, avoiding shell
   arguments, history, logs and committed files.
3. Update `aiia-mysql-password` using SOPS and activate the matching configuration.
   The new value must match the SQL account exactly. Both rendered templates use
   this same secret; neither automatically restarts a service.
4. Start `docker-aiia-ghost.service` and verify a fresh database connection,
   application readiness and a normal application read/write operation. Keep
   order mode `draft`; do not use a live purchase as a health check.
5. Restore the updater's prior timer state after validation. If validation fails,
   keep Ghost stopped while restoring a matching SQL password and SOPS value;
   rolling back the configuration alone does not undo a SQL password change.

Rotate the root account separately through MySQL, then update
`aiia-mysql-root-password` to match and verify a fresh administrative login.
Restarting MySQL or deleting its data directory is not a password rotation.

For a provider-only change, keep the SQL password unchanged, coordinate the
provider's key/webhook overlap rules, update SOPS and activate, then run
`sudo systemctl restart docker-aiia-ghost.service`. This recreates the container
with the new environment. Verify the relevant integration in test/draft mode
before retiring the previous provider credential. A plain `docker restart` does
not reload an environment file into an existing container.

## Grafana's stored admin password

Grafana's `admin_password` setting is applied only on first run, as documented in
the [Grafana configuration reference](https://grafana.com/docs/grafana/latest/setup-grafana/configure-grafana/#admin_password).
The monitoring stack persists Grafana's database under
`/srv/containers/monitoring/grafana`; confirm the actual mounted volume in
Portainer if the deployment predates this layout.

Change the existing user's password through Grafana's authenticated account
management. If locked out, use the supported Grafana admin password reset CLI
against the running deployment's actual configuration and persistent database.
Update `grafana-admin-password` in SOPS to match the intended bootstrap/recovery
credential and activate it. Verify a new login session; a still-authenticated
browser session does not prove the new password works. Changing the secret file,
recreating the container or restarting Docker does not reset the stored account.
Preserve the database and dashboards.

## Mrija archive coordination

Let any active sync finish, then pause `mrija-archive-sync.timer` for the rotation
window, recording its prior state. Update the API key and/or login password in
SOPS, activate, and recreate only the archive application container through its
Portainer stack so its environment matches the rendered file. Verify a fresh
web login and an authenticated API request with the new values before restoring
the timer's prior state. The next sync invocation reads the updated API key.
Avoid restarting the Docker daemon or guessing an application systemd unit.

## Verification boundary

Inspect rendered paths, ownership and unit configuration without printing secret
contents. Validate service readiness and new authentication independently after
rotation. Local Nix evaluation and lifecycle fixtures verify wiring; successful
production authentication, provider revocation and database password changes
require these operator checks on the deployed services.

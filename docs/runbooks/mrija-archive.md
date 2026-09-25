# Mrija archive on bandit-lab

The canonical reviewed Compose asset is
[`hosts/bandit-lab/services/mrija-archive/compose.yml`](../../hosts/bandit-lab/services/mrija-archive/compose.yml),
with the existing live project name `deploy`. It preserves the live image, loopback
port, mounts, labels, `proxy` network, direct `MRIJA_*` variables and
`/run/secrets/rendered/mrija-archive.env` env file. Portainer remains the
live owner until an explicitly approved handoff is deployed.

Nix exposes the asset at `/etc/bandit-lab/mrija-archive.compose.yml` and
declares the initially disabled manual `compose-mrija-archive` unit. Its
`start`/`stop` lifecycle does not create or reconcile containers.

## Safe inspection and lifecycle

Run status and start/stop only during approved maintenance when the host
procedure owns the project:

```bash
sudo docker compose --project-name deploy \
  --file /etc/bandit-lab/mrija-archive.compose.yml ps
sudo systemctl start compose-mrija-archive.service
sudo systemctl stop compose-mrija-archive.service
```

An apply is a separate, explicitly approved maintenance action because it can
reconcile containers. It must not pull or build:

```bash
sudo docker compose --project-name deploy \
  --file /etc/bandit-lab/mrija-archive.compose.yml \
  up -d --pull never --no-build
```

For rollback, stop the project, restore the previously reviewed Git/Nix
revision, activate it through the normal signed deployment process, and
recheck the project before starting it again. Never use `down -v`, prune
volumes/networks, or remove `/srv/containers/mrija-archive`.

## Credentials and verification

The `MRIJA_API_KEY` and `MRIJA_PASSWORD` direct variables remain intentionally
unchanged for this adoption revision. Migration to `MRIJA_API_KEY_FILE` and
`MRIJA_PASSWORD_FILE` is deferred until the application image and deployment
procedure support it; do not remove the current env file first.

Verify the image, project name, env-file path, loopback listener, mounts,
network, labels, authenticated login/API, archive data and scheduled sync
separately. Source and local unit checks do not prove live deployment or
authentication.

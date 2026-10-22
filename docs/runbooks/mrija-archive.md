# Mrija archive on bandit-lab

Since phase 4 the archive runs as the quadlet container `mrija-archive`
([`hosts/bandit-lab/services/mrija-archive/default.nix`](../../hosts/bandit-lab/services/mrija-archive/default.nix)):
the locally built image `localhost/mrija-archive:latest` (never pulled), the
same mounts under `/srv/containers/mrija-archive`, the TheHost SSH key read-only,
the loopback port `127.0.0.1:8081`, running as the data owner (`vino`) on the
podman `proxy` network. Traefik routes `mail-archive.bandit-lab.mrija.org` to
that port through its file provider; the daily `mrija-archive-sync` unit calls
it on loopback. The Compose project `deploy` is gone.

## Image updates

The image is built on the host, not pulled. Load a new build into Podman's
store (it is separate from Docker's), then restart the unit:

```bash
sudo podman load < mrija-archive.tar
sudo systemctl restart mrija-archive.service
```

## Operate

```bash
systemctl status mrija-archive.service mrija-archive-sync.timer
sudo podman logs --tail 50 mrija-archive
sudo systemctl start mrija-archive-sync.service   # manual sync
```

Never remove `/srv/containers/mrija-archive`; a Nix rollback restores the unit,
not the data.

## Credentials and verification

The `MRIJA_API_KEY` and `MRIJA_PASSWORD` direct variables remain intentionally
unchanged for this adoption revision. Migration to `MRIJA_API_KEY_FILE` and
`MRIJA_PASSWORD_FILE` is deferred until the application image and deployment
procedure support it; do not remove the current env file first.

Verify the image, project name, env-file path, loopback listener, mounts,
network, labels, authenticated login/API, archive data and scheduled sync
separately. Source and local unit checks do not prove live deployment or
authentication.

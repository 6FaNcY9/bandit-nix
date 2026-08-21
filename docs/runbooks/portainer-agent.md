# Portainer Agent on bandit-lab

Portainer Server manages the local Docker engine through Portainer Agent at
`portainer-agent:9001`. Both containers share the private, internal
`portainer-control` Docker network. Server also joins `proxy` so Traefik can
reach its UI, while Agent has no published host port.

## Trust boundary

Portainer Server does not mount `/var/run/docker.sock`. Agent is the only
Portainer component that mounts the socket, along with Docker's volumes path
and a read-only host-root view. Docker socket access is effectively host-root
access, so Agent must remain private, version-matched to Server, and reachable
only through `portainer-control`.

Evaluated NixOS assertions in `hosts/bandit-lab/webhost.nix` enforce both sides
of the contract: Server must not receive the socket and Agent must retain it.
This reduces Server's direct privilege, but it does not make the Agent itself
unprivileged.

## Expected state

- Portainer Server and Agent use the same pinned image version.
- `portainer` mounts `/var/lib/portainer` at `/data` and no Docker socket.
- `portainer-agent` mounts `/var/run/docker.sock`,
  `/srv/containers/docker/volumes`, and `/:/host:ro`.
- Both containers join `portainer-control`; only Server also joins `proxy`.
- Portainer shows the `bandit-lab` environment as **Up**, connection type
  **Agent**, URL `portainer-agent:9001`.

The UI's separate **Disconnected** label refers to the optional live-connect
session. It does not contradict the green **Up** environment status.

## Read-only preflight

Before changing Portainer environment metadata, verify the existing
containers, networks, mounts, and version match:

```bash
sudo docker inspect -f '{{.Name}} {{.Config.Image}} {{.State.Status}}' \
  portainer portainer-agent
sudo docker inspect -f '{{range $name, $_ := .NetworkSettings.Networks}}{{println $name}}{{end}}' \
  portainer portainer-agent
sudo docker inspect -f '{{range .Mounts}}{{println .Source "->" .Destination .RW}}{{end}}' \
  portainer portainer-agent
sudo docker network inspect portainer-control
```

Record the visible stacks, containers, networks, and any named volumes in the
old environment. Also verify application bind-mount data on the host; Portainer
environment deletion must never be used as a reason to remove Docker objects or
host data.

## Recreate the saved environment

Portainer does not change an existing environment's connection method in
place. Perform this as a metadata-only UI operation:

1. In **Environments**, remove the old socket-connected environment. Do not
   select or perform any action that removes Docker containers, volumes,
   networks, or host data.
2. Add an environment using **Docker Standalone → Agent**.
3. Set the environment address to `portainer-agent:9001`, without `http://` or
   `https://`, and save it.
4. Confirm the environment is green **Up** and reports **Agent**.
5. Open **Stacks**, choose **Show all orphaned stacks**, and associate every
   prior stack with the new environment.
6. Open each reassociated stack and confirm its existing containers and normal
   actions are present before removing Server's socket mount in Nix.

Removing a saved Portainer environment can orphan Portainer's stack metadata;
it does not itself remove the underlying Docker containers or bind-mounted
application data. Reassociation restores management of those existing stacks.

## Verify after activation

After `sudo lab-update apply` or a direct NixOS switch, run:

```bash
sudo bandit-lab-health
systemctl --no-pager --full status \
  docker-portainer.service docker-portainer-agent.service
sudo docker inspect -f '{{range .Mounts}}{{println .Source "->" .Destination}}{{end}}' \
  portainer
sudo docker inspect -f '{{range .Mounts}}{{println .Source "->" .Destination}}{{end}}' \
  portainer-agent
sudo docker inspect -f '{{json .NetworkSettings.Networks}}' \
  portainer | jq
sudo docker inspect -f '{{json .NetworkSettings.Networks}}' \
  portainer-agent | jq
```

Then verify in the UI:

- `bandit-lab` is **Up**, **Agent**, at `portainer-agent:9001`.
- The expected stack and container counts are present.
- Each reassociated stack opens and controls its existing containers.
- Application-specific health checks pass, especially the monitoring checks in
  [monitoring.md](monitoring.md).

## Rollback

If the Agent environment fails before deploying the socket-removal
configuration, recreate a Docker Standalone **Socket** environment in Portainer
and reassociate the orphaned stacks. The still-mounted Server socket provides
the temporary fallback.

If the failure occurs after activation:

1. Preserve all running containers, volumes, networks, `/var/lib/portainer`,
   and application data directories.
2. Switch to the previous NixOS generation with
   `sudo nixos-rebuild switch --rollback`, or deploy a reviewed configuration
   that temporarily restores Server's socket mount.
3. Recreate the Socket environment and reassociate orphaned stacks if the
   Agent environment is unusable.
4. Diagnose and repair the Agent path before attempting the migration again.

Rollback changes the Nix generation and Portainer metadata only. Do not delete
or redeploy application containers merely to restore the management
connection.

## References

- [Change an environment connection without losing stacks](https://docs.portainer.io/sts/faqs/troubleshooting/agents-and-environment-management/how-do-i-change-the-way-i-connect-to-an-environment-without-losing-my-existing-stacks)
- [Add a Docker Standalone environment using the Agent](https://docs.portainer.io/2.27/admin/environments/add/docker/agent)

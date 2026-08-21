# Portainer Agent Migration Design

**Date:** 2026-08-21

## Goal

Remove Portainer Server's direct Docker socket mount on `bandit-lab` while
preserving the existing Portainer environment, stacks, containers, volumes,
and networks. Portainer Agent remains the only Portainer component with Docker
socket access.

## Current State

The evaluated `hosts/bandit-lab/webhost.nix` configuration declares Portainer
Server and Portainer Agent on the internal `portainer-control` Docker network.
It declares the Agent Docker-socket mount and Server's legacy local-environment
socket mount. These are declarative configuration facts, not confirmation of
the deployed runtime state. Task 2's read-only live checks must establish that
both containers and their control network are runtime-ready before the UI
migration; removing Server's mount before changing Portainer's saved
environment connection would otherwise break the local environment.

The Docker socket is effectively host-root access. Moving that access from the
internet-facing management UI container to the private Agent reduces the
number of socket holders and creates a clearer trust boundary. The Agent is
still privileged infrastructure and must remain private.

## Approved Architecture

```text
browser -> Cloudflare/Traefik -> Portainer Server
                                  |
                                  | internal portainer-control network
                                  v
                           Portainer Agent :9001
                                  |
                                  v
                         /var/run/docker.sock
```

- Portainer Server keeps its `/data` volume and HTTPS listener, but has no
  Docker socket mount.
- Portainer Agent keeps the Docker socket, Docker volumes path, and read-only
  host mount.
- `portainer-control` remains internal and shared only by Server and Agent.
- The saved Portainer environment connects to `portainer-agent:9001`.

## Migration Sequence

1. Confirm both containers are running and attached to `portainer-control`.
2. In Portainer, remove the existing socket-connected environment. This
   orphans Portainer's stack metadata; it does not remove the running Docker
   resources.
3. Add a Docker Standalone Agent environment with address
   `portainer-agent:9001`.
4. Show orphaned stacks and associate every existing stack with the new
   environment.
5. Verify containers, volumes, networks, stack control, and monitoring.
6. Only after that checkpoint, remove Server's socket mount declaratively.

This follows Portainer's documented connection-method migration procedure:

- https://docs.portainer.io/sts/faqs/troubleshooting/agents-and-environment-management/how-do-i-change-the-way-i-connect-to-an-environment-without-losing-my-existing-stacks
- https://docs.portainer.io/2.27/admin/environments/add/docker/agent

## Safety Contract

A NixOS assertion checks the evaluated container configuration:

- Portainer Server must not mount `/var/run/docker.sock`.
- Portainer Agent must retain `/var/run/docker.sock`.

This makes a later accidental regression fail evaluation instead of silently
restoring direct socket access or disabling Agent management.

## Rollback

Before the declarative switch, Server retains its socket mount, so the old
socket environment can be recreated if the Agent environment fails. After the
switch, restore the prior generation or re-add the Server socket mount only as
a temporary recovery measure, then recreate the socket-connected environment.
Running Docker resources and `/var/lib/portainer` are not intentionally removed
by this migration.

## Validation

- Read-only live checks prove container/network readiness before UI changes.
- A red/green assertion test proves the socket ownership contract.
- Alejandra, deadnix, statix, `nix flake check`, and a `bandit-lab` dry-run
  validate the repository configuration.
- Post-activation checks must confirm Portainer Server has no socket mount,
  Agent still has it, both services are healthy, and the reassociated stacks
  remain manageable.

## Non-Goals

- Replacing Portainer or Docker.
- Changing container images, public routing, or authentication.
- Recreating stacks, volumes, or application data.
- Claiming that Agent isolation removes Docker socket privilege; it only
  narrows where that privilege exists.

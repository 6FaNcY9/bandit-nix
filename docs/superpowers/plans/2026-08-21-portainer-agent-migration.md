# Portainer Agent Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate the live `bandit-lab` Portainer environment to its private
Agent and remove Portainer Server's Docker socket mount without losing stack
management or application data.

**Architecture:** Portainer Server reaches `portainer-agent:9001` only through
the internal `portainer-control` network. Agent is the sole Portainer component
that mounts `/var/run/docker.sock`. Evaluated NixOS assertions enforce both
sides of this boundary.

**Tech Stack:** NixOS modules, Docker-compatible OCI containers, Portainer EE,
systemd, Alejandra, deadnix, statix

**Spec:**
[docs/superpowers/specs/2026-08-21-portainer-agent-migration-design.md](../specs/2026-08-21-portainer-agent-migration-design.md)

## Global Constraints

- Run repository and Nix commands through `rtk`.
- Preserve unrelated changes in the main checkout.
- Do not delete or recreate containers, stacks, networks, or volumes from the
  shell.
- Keep Server's socket mount until the user confirms the live Portainer Agent
  environment and orphaned stacks are working.
- Never commit plaintext secrets.
- Push only after showing the atomic commits and receiving explicit approval.

---

## Task 1: Record the approved migration design

**Files:**

- Create:
  `docs/superpowers/specs/2026-08-21-portainer-agent-migration-design.md`
- Create: `docs/superpowers/plans/2026-08-21-portainer-agent-migration.md`

- [x] Document the current risk, final architecture, migration order,
  validation boundary, and rollback.
- [x] Work on isolated branch `chore/portainer-agent-migration`.

## Task 2: Prove the live Agent path is ready

**Live host:** `bandit-lab`

- [ ] Read-only inspect `portainer`, `portainer-agent`, and
  `portainer-control`.
- [ ] Confirm both containers are running and attached to the private network.
- [ ] Confirm `portainer` can resolve `portainer-agent` and record any probe
  limitation honestly.
- [ ] Stop and report if the Agent path is not ready.

## Task 3: Migrate Portainer environment metadata

**Live UI:** existing Portainer instance

- [ ] Remove the legacy socket-connected environment in Portainer.
- [ ] Add a Docker Standalone Agent environment at
  `portainer-agent:9001` (no URL scheme).
- [ ] Use **Show all orphaned stacks** and associate every prior stack.
- [ ] Verify containers, volumes, networks, stack actions, and monitoring.
- [ ] Obtain explicit user confirmation before changing Nix configuration.

## Task 4: Add the evaluated socket-ownership contract

**Files:**

- Modify: `hosts/bandit-lab/webhost.nix`

- [ ] Add an assertion that fails while Portainer Server still mounts the
  Docker socket.
- [ ] Run a focused `bandit-lab` evaluation and capture the expected failure
  (RED).
- [ ] Add an assertion that Agent must retain the Docker socket.
- [ ] Remove only Server's Docker socket mount and its temporary migration
  comment.
- [ ] Re-run the focused evaluation and confirm success (GREEN).
- [ ] Mutation-check both assertions by temporarily violating each condition,
  then restore the intended source.

## Task 5: Update operational documentation

**Files:**

- Modify: `README.md`
- Create: `docs/runbooks/portainer-agent.md`
- Modify: `docs/runbooks/monitoring.md`
- Modify: `docs/runbooks/bandit-lab-updates.md`

- [ ] Explain the final trust boundary and link the runbook from README.
- [ ] Document official UI migration, verification, and rollback steps.
- [ ] Document monitoring-stack reassociation and data-preservation checks.
- [ ] Document post-`lab-update apply` socket and service checks.

## Task 6: Validate the repository

- [ ] Run `rtk nix run nixpkgs#alejandra -- --check` on changed Nix files.
- [ ] Run `rtk nix run nixpkgs#deadnix -- --fail .`.
- [ ] Run `rtk nix run nixpkgs#statix -- check .`.
- [ ] Run `rtk nix flake check --no-update-lock-file`.
- [ ] Run a dry build of the `bandit-lab` toplevel without updating the lock.
- [ ] Run `rtk git diff --check` and review the final diff.

## Task 7: Create reviewable atomic commits

- [ ] Read and apply the `caveman-commit` skill.
- [ ] Stage only files owned by this migration; force-add the ignored
  Superpowers plan/spec explicitly.
- [ ] Split commits by coherent concern if the final diff supports it.
- [ ] Show commit subjects, changed files, validation evidence, and clean
  branch status.
- [ ] Push only after the user's explicit approval.

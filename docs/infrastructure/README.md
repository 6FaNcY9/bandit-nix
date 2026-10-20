# Infrastructure

This is the entry point for the `bandit` and `bandit-lab` infrastructure
record. It links to evidence and operational runbooks without duplicating
service definitions.

## Start here

- [Service inventory and dependency map](../services.md)
- [Monitoring runbook](../runbooks/monitoring.md)
- [Mrija archive runbook](../runbooks/mrija-archive.md)
- [Beszel pilot runbook](../runbooks/beszel-pilot.md)
- [Minecraft administration](https://github.com/6FaNcY9/bandit-craft/blob/main/docs/runbooks/minecraft/ADMIN.md) (bandit-craft)
- [Cloudflare access boundaries](../runbooks/cloudflare-access.md)
- [Archive](../archive/README.md): retired Portainer and Wazuh runbooks, the
  2026-09-21 bandit-lab audit evidence and other historical records

## Hosts

- **bandit** is the Framework 13 workstation, declared in
  [`hosts/bandit/default.nix`](../../hosts/bandit/default.nix) with hardware in
  [`hosts/bandit/hardware.nix`](../../hosts/bandit/hardware.nix).
- **bandit-lab** is the NixOS homelab server, declared in
  [`hosts/bandit-lab/default.nix`](../../hosts/bandit-lab/default.nix); service
  ownership is split into its [`services/`](../../hosts/bandit-lab/services/)
  declarations.

## Beszel

Beszel is an active host-metrics pilot on `bandit-lab`, declared in
[`hosts/bandit-lab/services/beszel/default.nix`](../../hosts/bandit-lab/services/beszel/default.nix).
The hub and agent stay on loopback with Docker access disabled and resource
limits applied. They were observed active on 2026-09-25; host metrics, retained
history, service restart recovery and an in-app alert were verified. Container
metrics remain intentionally disabled.

## Evidence conventions

- **Declared** means present in repository source. It describes intended
  ownership and boundaries, not activation or runtime state.
- **Observed** means confirmed by a dated, scoped live check, recorded in the
  [service inventory](../services.md) or a runbook.
- Do not infer deployment, reachability, authentication, or data recovery from
  a source declaration.

## Operating rule

Treat live checks as time-scoped evidence. Source declarations explain
ownership and intended boundaries; they do not prove that a service is
running, reachable, authenticated, backed up, or recoverable.

The current inventory records those distinctions and lists the remaining
verification gaps. Update it when a service, route, backup, or security
boundary changes.

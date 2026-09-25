# Infrastructure

This is the entry point for the `bandit` and `bandit-lab` infrastructure
record. It links to evidence and operational runbooks without duplicating
service definitions.

## Start here

- [Service inventory and dependency map](../services.md)
- [Monitoring runbook](../runbooks/monitoring.md)
- [Wazuh runbook](../runbooks/wazuh.md)
- [Minecraft administration](../runbooks/minecraft/ADMIN.md)
- [Cloudflare access boundaries](../runbooks/cloudflare-access.md)
- [Bandit-lab audit evidence](../runbooks/bandit-lab-audit-2026-09-21.md)

## Operating rule

Treat live checks as time-scoped evidence. Source declarations explain
ownership and intended boundaries; they do not prove that a service is
running, reachable, authenticated, backed up, or recoverable.

The current inventory records those distinctions and lists the remaining
verification gaps. Update it when a service, route, backup, or security
boundary changes.

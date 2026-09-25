# Beszel

Beszel is a source-declared host-metrics pilot for `bandit-lab`. The exact
declaration is
[`hosts/bandit-lab/services/beszel/default.nix`](../../../../hosts/bandit-lab/services/beszel/default.nix),
and the host imports it from
[`hosts/bandit-lab/default.nix`](../../../../hosts/bandit-lab/default.nix).

The declaration keeps the hub and agent on loopback, disables Docker access,
and applies resource limits. This note describes repository intent only:
Beszel is not activated by this documentation patch, and no deployment claim
is made here.

For bootstrap, checks, rollback, and the boundary for any future container
metrics design, use the [Beszel pilot runbook](../../../runbooks/beszel-pilot.md).
The canonical [service inventory](../../../services.md) remains authoritative
for declared-versus-observed service evidence.

## Related notes

- [Infrastructure notes](../README.md)
- [bandit-lab host note](../hosts/bandit-lab.md)
- [Infrastructure entry point](../../README.md)
- [Service inventory](../../../services.md)

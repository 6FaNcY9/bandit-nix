# bandit-lab

`bandit-lab` is the NixOS homelab server. Its canonical host declaration is
[`hosts/bandit-lab/default.nix`](../../../../hosts/bandit-lab/default.nix);
service ownership is split into the host's
[`services/`](../../../../hosts/bandit-lab/services/) declarations.

The [Beszel service declaration](../../../../hosts/bandit-lab/services/beszel/default.nix)
is imported by this host. Beszel is source-declared and is not activated by
this documentation patch. Runtime and rollout steps remain in the
[Beszel pilot runbook](../../../runbooks/beszel-pilot.md).

## Related notes

- [Infrastructure notes](../README.md)
- [Infrastructure entry point](../../README.md)
- [Service inventory](../../../services.md)
- [Beszel service note](../services/beszel.md)

# Infrastructure notes

This directory is the Obsidian vault entry point for repository-backed
infrastructure notes. The repository root is the vault; these are ordinary
relative Markdown links, not a second inventory.

## Evidence conventions

- **Declared** means present in repository source. It describes intended
  ownership and boundaries, not activation or runtime state.
- **Observed** means confirmed by a dated, scoped live check. Use the
  canonical [service inventory](../../services.md) and operational runbooks
  for those claims.
- Do not infer deployment, reachability, authentication, or data recovery from
  a source declaration.

## Notes

- [bandit](hosts/bandit.md)
- [bandit-lab](hosts/bandit-lab.md)
- [Beszel](services/beszel.md)

## Related notes

- [Infrastructure entry point](../README.md)
- [Service inventory](../../services.md)
- [Beszel pilot runbook](../../runbooks/beszel-pilot.md)

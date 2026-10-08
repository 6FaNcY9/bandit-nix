---
name: ship-and-environment
description: How to ship to bandit-lab (no ship-claude yet), laptop quirks, and which files the owner's checkout must never leak
metadata:
  type: reference
---

A push to `main` deploys to bandit-lab within about an hour (signed
fast-forwards only). Ship from a clean `git worktree` on `origin/main`:
`git cherry-pick -S <sha>`, check the signature, build the committed revision
(`nix build "git+file://$PWD?rev=<sha>#nixosConfigurations.bandit-lab.config.system.build.toplevel" --no-link --no-update-lock-file`),
then the owner runs `git push origin HEAD:main`. Full procedure in
`docs/runbooks/minecraft/HANDOFF-2026-10-08.md`.

Laptop quirks: `cp`/`rm`/`mv` aliased to `-i` (use `\cp`); `nrs` =
`sudo nixos-rebuild switch --flake .#bandit`; `~/src/bandit-nix` has the owner's
uncommitted `flake.lock` (never commit it, never `nix flake update`); do work in
a separate worktree. Hub worker: `nix run .#mcbots-worker -- bot5`. Dashboard
via tailnet: `https://bandit-lab.tail7facc9.ts.net:8445`, hub on `:8446`.

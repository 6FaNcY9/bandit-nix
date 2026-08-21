# Hyprland Native Lua Migration

## Problem

Hyprland 0.56 warns that support for the legacy `.conf` configuration format will be removed in 0.57. The warning is caused by `home/desktop/hyprland.nix` explicitly setting Home Manager's Hyprland `configType` to `"hyprlang"`, which generates `~/.config/hypr/hyprland.conf`.

The flake currently pins Hyprland 0.56.2 and a Home Manager revision that supports `wayland.windowManager.hyprland.configType = "lua"`. That mode generates `~/.config/hypr/hyprland.lua` using Hyprland's native Lua API.

## Decision

Migrate the Home Manager module to native Lua now, while the pinned Hyprland release still supports both formats.

A one-line `configType = "lua"` change is not sufficient. Home Manager's Lua renderer deliberately ignores legacy string entries in bindings, submaps, and rules. The configuration therefore needs structured `_args` entries and explicit Lua expressions for dispatchers.

The migration will:

- keep Nix as the source of truth;
- generate `hyprland.lua` through Home Manager;
- preserve the current keyboard, mouse, media, workspace, startup, submap, layout, and window-rule behavior;
- use only dispatcher APIs present in the pinned Hyprland 0.56.2 Lua stubs/source;
- document the generated path and the structured-entry requirement; and
- stop before activation, because switching the live NixOS generation is a separate privileged action.

## Alternatives Considered

### Leave the warning in place

Rejected because Hyprland 0.57 is expected to remove the format and turn a warning into a configuration failure.

### Change only `configType`

Rejected because the generated Lua would omit legacy string-based bindings, submaps, and window rules. Evaluation could succeed while most desktop controls silently disappear.

### Manage a handwritten Lua file outside Home Manager

Rejected because it would split ownership and bypass the repository's declarative Home Manager architecture.

## Mapping Strategy

- Regular settings become one structured `hl.config({ ... })` call.
- Monitor configuration becomes `hl.monitor({ ... })`.
- Startup commands run from a `hyprland.start` event handler.
- Each binding uses a structured `hl.bind(key_combo, dispatcher, options?)` call.
- Commands use `hl.dsp.exec_cmd(...)`; arguments are JSON-escaped by Nix before entering Lua.
- Repeating resize bindings use the Lua bind option `repeating = true`.
- Mouse bindings use the Lua bind option `mouse = true`.
- Window rules become structured `hl.window_rule({ ... })` calls.
- Resize mode becomes a structured submap whose exit bindings dispatch to the `reset` submap.

## Verification Contract

The change is accepted only if all of the following succeed against the pinned flake:

1. The old Home Manager output `hypr/hyprland.conf` is absent and `hypr/hyprland.lua` is present.
2. The generated Lua contains the expected config, bindings, event handler, window rules, and resize submap.
3. Hyprland's native config verifier accepts the generated Lua where the environment permits it.
4. The changed Nix file is formatted.
5. `nix flake check --no-update-lock-file` succeeds.
6. A dry-run of the `bandit` system closure succeeds.

The permanent test surface remains the existing flake evaluation/checks; the old/new generated-file assertions are reproducible migration checks rather than a new repository test target.

## Activation Boundary

This repository change does not switch the running system. After review, activation requires:

```bash
sudo nixos-rebuild switch --flake .#bandit
```

Hyprland must then be restarted (normally by logging out and back in) before the warning disappears from the running session.

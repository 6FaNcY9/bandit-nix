# bandit palette: the single colour source for both hosts.
#
# Neutral grey ramp (no warm or cool cast) plus five accents, each with one
# meaning everywhere: ok = green, warn/focus = amber, crit = red,
# info/link = cyan, ops (security engagement context) = magenta.
#
# Everything else derives from here: the Stylix base16 scheme (laptop and lab
# console), serverPalette (lab shell, editor, Cockpit, Vaultwarden) and the
# semantic roles home modules consume via `config.bandit.theme.roles`.
# Hex literals belong in this file only; ci/theme-contract.nix enforces it.
let
  variants = {
    dark = {
      grey = {
        g0 = "121212"; # canvas
        g1 = "1a1a1a"; # surface (bars, panels)
        g2 = "242424"; # raised (selection, hover)
        g3 = "2e2e2e"; # inactive borders
        g4 = "3a3a3a"; # structure lines
        g5 = "6e6e6e"; # muted text, comments
        g6 = "9a9a9a"; # dim text
        g7 = "cfcfcf"; # foreground
        g8 = "ececec"; # bright foreground
      };
      accent = {
        ok = "7fd962";
        warn = "f2b33d";
        crit = "ff5c57";
        info = "5ccfe6";
        ops = "d97ff0";
        # Syntax-only helpers (base09/0C/0F); never used for state.
        orange = "ff8f40";
        teal = "66d9c0";
        rust = "b05a3c";
      };
    };
    # Same roles, inverted ramp; accents darkened to keep contrast on paper.
    light = {
      grey = {
        g0 = "f4f4f4";
        g1 = "e9e9e9";
        g2 = "dcdcdc";
        g3 = "cccccc";
        g4 = "b8b8b8";
        g5 = "7a7a7a";
        g6 = "555555";
        g7 = "262626";
        g8 = "111111";
      };
      accent = {
        ok = "3d8a26";
        warn = "a86b00";
        crit = "c8302b";
        info = "137f99";
        ops = "9a3db3";
        orange = "b8560f";
        teal = "1f8a73";
        rust = "8a3f25";
      };
    };
  };

  base16 = variant: let
    v = variants.${variant};
    g = v.grey;
    a = v.accent;
  in {
    base00 = g.g0;
    base01 = g.g1;
    base02 = g.g2;
    base03 = g.g5;
    base04 = g.g6;
    base05 = g.g7;
    base06 = g.g8;
    base07 = g.g8;
    base08 = a.crit;
    base09 = a.orange;
    base0A = a.warn;
    base0B = a.ok;
    base0C = a.teal;
    base0D = a.info;
    base0E = a.ops;
    base0F = a.rust;
  };

  # Semantic roles. Modules pick a role, never a base slot, so every accent
  # means the same thing in waybar, rofi, mako, hyprland, kitty and the lab.
  roles = variant: let
    v = variants.${variant};
    g = v.grey;
    a = v.accent;
  in {
    bg = g.g0;
    surface = g.g1;
    raised = g.g2;
    borderInactive = g.g3;
    line = g.g4;
    muted = g.g5;
    dim = g.g6;
    fg = g.g7;
    bright = g.g8;
    accent = a.warn; # focus: active workspace, focused border, selection
    inherit (a) ok warn crit info ops;
  };

  hashed = builtins.mapAttrs (_: c: "#${c}");
in {
  inherit variants;
  base16 = variant:
    {
      scheme = "bandit ${variant}";
      author = "bandit-nix";
      slug = "bandit-${variant}";
    }
    // base16 variant;
  # "#rrggbb" forms for CSS, shell prompts and Lua.
  base16Hashed = variant: hashed (base16 variant);
  roles = variant: hashed (roles variant);
}

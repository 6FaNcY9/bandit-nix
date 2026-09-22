{
  pkgs,
  lib,
  repoConfig,
}: let
  theme = repoConfig.workstationTheme;
  actualColorKeys = lib.sort builtins.lessThan (builtins.attrNames theme.colors);
  expectedColorKeys = lib.sort builtins.lessThan [
    "active"
    "canvas"
    "critical"
    "foreground"
    "info"
    "muted"
    "primary"
    "raised"
    "secondary"
    "shadow"
    "structure"
    "success"
    "surface"
  ];
in
  assert lib.assertMsg (theme.name == "Gruvbox") "workstationTheme.name must stay Gruvbox";
  assert lib.assertMsg (builtins.pathExists ../themes/gruvbox-light.yaml) "themes/gruvbox-light.yaml missing (light specialisation)";
  assert lib.assertMsg (actualColorKeys == expectedColorKeys) "workstationTheme.colors keys drifted from the contract";
  assert lib.assertMsg (theme.geometry.unit == 4) "workstationTheme.geometry.unit must stay 4";
  assert lib.assertMsg (theme.geometry.radius == 0) "workstationTheme.geometry.radius must stay 0";
  assert lib.assertMsg ((repoConfig.mkStylixTheme pkgs).base16Scheme == ../themes/gruvbox-dark.yaml) "mkStylixTheme must use themes/gruvbox-dark.yaml";
  assert lib.assertMsg (theme.fonts.shell.name == "Departure Mono") "workstationTheme shell font changed";
  assert lib.assertMsg (theme.fonts.technical.name == "JetBrainsMono Nerd Font Mono") "workstationTheme technical font changed";
  assert lib.assertMsg (theme.fonts.interface.name == "Noto Sans") "workstationTheme interface font changed";
  assert lib.assertMsg (theme.icons.name == "Papirus-Dark") "workstationTheme icon theme changed";
  assert lib.assertMsg (theme.cursor.name == "Bibata-Modern-Ice") "workstationTheme cursor theme changed";
    pkgs.runCommand "bandit-nix-theme-contract" {} ''
      touch "$out"
    ''

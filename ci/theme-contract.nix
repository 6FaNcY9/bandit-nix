# Theme contract: themes/palette.nix is the only colour source.
# - both variants define the same grey and accent keys
# - every semantic role resolves to "#rrggbb" in both variants
# - no hex colour literal appears in Nix, CSS, SCSS, Lua or rasi sources
#   outside themes/palette.nix (hand-themed modules read
#   config.bandit.theme.roles; the lab reads repoConfig.palette.roles)
{
  pkgs,
  lib,
  repoConfig,
}: let
  pal = repoConfig.palette;
  keysOf = v: {
    grey = lib.attrNames pal.variants.${v}.grey;
    accent = lib.attrNames pal.variants.${v}.accent;
  };
  isHex = c: builtins.match "#[0-9a-f]{6}" c != null;
  rolesOk = v: lib.all isHex (lib.attrValues (pal.roles v));
  base16Ok = v: lib.all (c: builtins.match "[0-9a-f]{6}" c != null) (lib.attrValues (removeAttrs (pal.base16 v) ["scheme" "author" "slug"]));
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [../home ../hosts ../nixos ../lib ../themes];
  };
in
  assert lib.assertMsg (keysOf "dark" == keysOf "light") "themes/palette.nix: dark and light variants must define the same keys";
  assert lib.assertMsg (rolesOk "dark" && rolesOk "light") "themes/palette.nix: every role must be a lowercase #rrggbb colour";
  assert lib.assertMsg (base16Ok "dark" && base16Ok "light") "themes/palette.nix: base16 slots must be lowercase rrggbb";
  assert lib.assertMsg (lib.length (lib.attrNames (pal.base16 "dark")) == 19) "themes/palette.nix: base16 must define base00..base0F plus scheme metadata";
    pkgs.runCommand "bandit-nix-theme-contract" {nativeBuildInputs = [pkgs.ripgrep];} ''
      cd ${src}
      if rg -n --no-heading -g '*.{nix,css,scss,hbs,lua,rasi}' -g '!themes/palette.nix' '#[0-9a-fA-F]{6}\b' .; then
        echo "hex colour literals found outside themes/palette.nix; use config.bandit.theme.roles or repoConfig.palette.roles" >&2
        exit 1
      fi
      touch "$out"
    ''

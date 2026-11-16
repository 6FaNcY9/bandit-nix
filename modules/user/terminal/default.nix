{
  lib,
  bandit,
  ...
}: let
  # The phone (hosts/pong) has no desktop terminal and no ~/src/sec house.
  desktop = !(bandit.isPhone or false);
in {
  # Order kept as before so the laptop's evaluation is unchanged.
  imports =
    lib.optional desktop ./kitty.nix
    ++ [
      ./starship.nix
      ./tools.nix
      ./automation.nix
      ./zsh.nix
    ]
    ++ lib.optional desktop ./sec-lab.nix;

  # kimi-code CLI is installed imperatively under ~/.kimi-code by its own
  # installer, outside nix. Its installer appends a PATH export to ~/.zshrc,
  # but Home Manager owns the shell config (ZDOTDIR), so that file is never
  # read and the export dies on every rebuild. Own the PATH entry here so it
  # survives nixos-rebuild / home-manager switch.
  home.sessionPath = ["${bandit.workstation.homeDirectory}/.kimi-code/bin"];
}

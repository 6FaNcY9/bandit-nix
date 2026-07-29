_: {
  imports = [
    ./fish.nix
    ./kitty.nix
    ./starship.nix
    ./tools.nix
    ./automation.nix
    ./zsh.nix
  ];

  # kimi-code CLI is installed imperatively under ~/.kimi-code by its own
  # installer, outside nix. Its installer appends a PATH export to ~/.zshrc,
  # but Home Manager owns the shell config (ZDOTDIR), so that file is never
  # read and the export dies on every rebuild. Own the PATH entry here so it
  # survives nixos-rebuild / home-manager switch.
  home.sessionPath = ["/home/vino/.kimi-code/bin"];
}

# ../../nixos/*.nix entries are not yet ported (phase 2); order matters for
# list-typed options, so legacy files stay in place until replaced.
{
  imports = [
    ../../nixos/theme.nix
    ../../nixos/graphics.nix
    ../../nixos/power.nix
    ../../nixos/dev.nix
    ../../nixos/gaming.nix
    ../../nixos/security-tools.nix
    ../../nixos/audio.nix
    ../../nixos/desktop.nix
  ];
}

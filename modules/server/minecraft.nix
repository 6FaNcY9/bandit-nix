# nix-minecraft module and package overlay (phase 5). Only makes the options and
# packages available; the servers themselves are defined in bandit-craft.
{inputs, ...}: {
  imports = [inputs.nix-minecraft.nixosModules.minecraft-servers];
  nixpkgs.overlays = [inputs.nix-minecraft.overlay];
}

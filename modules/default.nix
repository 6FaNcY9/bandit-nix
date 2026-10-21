# Laptop root for the new module tree. legacyNixos lists the old nixos/
# files not yet ported; it shrinks per phase-2 task and disappears at the end.
{
  config,
  inputs,
  ...
}: let
  legacyNixos = [
    ../nixos/sops.nix
    ../nixos/secrets-workstation.nix
    ../nixos/restic-peer-server.nix
    ../nixos/backup-peer.nix
    ../nixos/lab-apply.nix
    # pc-admin: admin on the gaming PCs only with the finger (bandit-craft tools/winpc/README.md)
    inputs.bandit-craft.nixosModules.pc-admin
    ../nixos/mcp.nix
    ../nixos/cli-tools.nix
    ../nixos/core.nix
    ../nixos/theme.nix
    ../nixos/boot.nix
    ../nixos/hardening.nix
    ../nixos/network.nix
    ../nixos/graphics.nix
    ../nixos/firmware.nix
    ../nixos/power.nix
    ../nixos/dev.nix
    ../nixos/gaming.nix
    ../nixos/security-tools.nix
    ../nixos/audio.nix
    ../nixos/desktop.nix
    ../nixos/users.nix
    ../nixos/health-check.nix
  ];
in {
  imports = [./options.nix ./system ./desktop] ++ legacyNixos;

  home-manager = {
    users.${config.bandit.workstation.username} = import ./user;
    extraSpecialArgs.bandit = config.bandit;
  };
}

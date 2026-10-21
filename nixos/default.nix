# Import order is grouped (system, then desktop) to match modules/, the
# phase-2 replacement tree; list-typed options such as systemPackages follow it.
{inputs, ...}: {
  imports = [
    ./sops.nix
    ./secrets-workstation.nix
    ./restic-peer-server.nix
    ./backup-peer.nix
    ./lab-apply.nix
    # pc-admin: admin on the gaming PCs only with the finger (bandit-craft tools/winpc/README.md)
    inputs.bandit-craft.nixosModules.pc-admin
    ./mcp.nix
    ./cli-tools.nix
    ./core.nix
    ./boot.nix
    ./hardening.nix
    ./network.nix
    ./firmware.nix
    ./users.nix
    ./health-check.nix
    ./theme.nix
    ./graphics.nix
    ./power.nix
    ./dev.nix
    ./gaming.nix
    ./security-tools.nix
    ./audio.nix
    ./desktop.nix
  ];
}

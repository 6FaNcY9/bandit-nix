# ../../nixos/*.nix entries are not yet ported (phase 2); order matters for
# list-typed options, so legacy files stay in place until replaced.
{inputs, ...}: {
  imports = [
    ./sops.nix
    ./secrets-workstation.nix
    ../../nixos/restic-peer-server.nix
    ../../nixos/backup-peer.nix
    ../../nixos/lab-apply.nix
    # pc-admin: admin on the gaming PCs only with the finger (bandit-craft tools/winpc/README.md)
    inputs.bandit-craft.nixosModules.pc-admin
    ../../nixos/mcp.nix
    ./cli-tools.nix
    ./core.nix
    ./boot.nix
    ./hardening.nix
    ./network.nix
    ./firmware.nix
    ./users.nix
    ../../nixos/health-check.nix
  ];
}

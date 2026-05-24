_: {
  # Disable sops file validation during CI builds where no age key is
  # available. Secrets are only decryptable on the real machine.
  # This prevents the entire build from failing due to missing keys.
  sops.validateSopsFiles = false;

  imports = [
    ./sops.nix
    ./core.nix
    ./boot.nix
    ./network.nix
    ./graphics.nix
    ./firmware.nix
    ./power.nix
    ./dev.nix
    ./audio.nix
    ./desktop.nix
    ./users.nix
  ];
}

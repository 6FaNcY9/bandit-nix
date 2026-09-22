{
  lib,
  ...
}: {
  sops.validateSopsFiles = false;
  virtualisation.sharedDirectories = lib.mkForce {};
}

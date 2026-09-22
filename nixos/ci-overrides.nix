{
  lib,
  config,
  ...
}:
{
  sops.validateSopsFiles = false;
}
// lib.mkIf ((config.virtualisation or {}) ? sharedDirectories) {
  virtualisation.sharedDirectories = lib.mkForce {};
}

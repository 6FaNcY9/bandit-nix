{
  lib,
  options,
  ...
}:
{
  sops.validateSopsFiles = false;
}
// lib.optionalAttrs (lib.hasAttrByPath ["virtualisation" "sharedDirectories"] options) {
  virtualisation.sharedDirectories = lib.mkForce {};
}

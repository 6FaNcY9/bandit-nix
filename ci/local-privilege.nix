# Local privilege contract: no process running as the workstation user may
# reach root without a password. Evaluation-time assertions only.
{
  pkgs,
  lib,
  hosts,
}: let
  sudoRulesWithNopasswd = config:
    lib.filter (rule: lib.any (cmd: lib.elem "NOPASSWD" (cmd.options or [])) (rule.commands or []))
    config.security.sudo.extraRules;

  checkHost = name: config:
    assert lib.assertMsg (!(lib.hasInfix "NOPASSWD" config.security.sudo.extraConfig))
    "${name}: security.sudo.extraConfig must not grant NOPASSWD (a NOPASSWD nixos-rebuild is passwordless root via --flake /tmp/x)";
    assert lib.assertMsg (sudoRulesWithNopasswd config == [])
    "${name}: security.sudo.extraRules must not contain NOPASSWD commands";
    assert lib.assertMsg config.security.sudo.wheelNeedsPassword
    "${name}: wheel members must need a password for sudo";
    assert lib.assertMsg (lib.unique config.nix.settings.trusted-users == ["root"])
    "${name}: nix trusted-users must be [\"root\"] (a trusted Nix user is root-equivalent)"; true;
in
  assert lib.all (name: checkHost name hosts.${name}.config) (lib.attrNames hosts);
    pkgs.writeText "local-privilege" "ok\n"

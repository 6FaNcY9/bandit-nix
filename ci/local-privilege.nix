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

  # Polkit uses the first rule that returns a result. Take the text after the
  # first mention of the libvirt manage action; authentication must be demanded
  # before the first auto-approval (Result.YES) that follows it.
  libvirtRequiresAuth = rules: let
    mentions = lib.splitString "org.libvirt.unix.manage" rules;
  in
    lib.length mentions
    == 1
    || lib.hasInfix "AUTH_ADMIN" (lib.head (lib.splitString "Result.YES" (lib.elemAt mentions 1)));

  checkHost = name: config:
    assert lib.assertMsg (!(lib.hasInfix "NOPASSWD" config.security.sudo.extraConfig))
    "${name}: security.sudo.extraConfig must not grant NOPASSWD (a NOPASSWD nixos-rebuild is passwordless root via --flake /tmp/x)";
    assert lib.assertMsg (sudoRulesWithNopasswd config == [])
    "${name}: security.sudo.extraRules must not contain NOPASSWD commands";
    assert lib.assertMsg config.security.sudo.wheelNeedsPassword
    "${name}: wheel members must need a password for sudo";
    assert lib.assertMsg (libvirtRequiresAuth config.security.polkit.extraConfig)
    "${name}: the first polkit rule mentioning org.libvirt.unix.manage must demand authentication (NixOS's own libvirtd rule auto-approves it; ours must come first)";
    assert lib.assertMsg (lib.unique config.nix.settings.trusted-users == ["root"])
    "${name}: nix trusted-users must be [\"root\"] (a trusted Nix user is root-equivalent)"; true;
  mcpNames = ["context7-mcp" "firecrawl-mcp"];
  mcpIn = host: lib.filter (p: lib.elem (lib.getName p) mcpNames) hosts.${host}.config.environment.systemPackages;
in
  assert lib.all (name: checkHost name hosts.${name}.config) (lib.attrNames hosts);
  assert lib.assertMsg (lib.length (mcpIn "bandit") == 2)
  "bandit must ship both MCP wrappers (nixos/mcp.nix)";
  assert lib.assertMsg (mcpIn "bandit-lab" == [])
  "bandit-lab must not ship the laptop's MCP wrappers (it has neither their secrets nor a use for them)";
    pkgs.runCommand "local-privilege" {nativeBuildInputs = [pkgs.gnugrep];} ''
      # The MCP wrappers must run inside the bubblewrap helper and must never
      # fetch code at run time.
      for w in ${lib.concatMapStringsSep " " (p: "${p}/bin/*") (mcpIn "bandit")}; do
        grep -q mcp-sandbox "$w" || { echo "$w does not use mcp-sandbox" >&2; exit 1; }
        if grep -qE 'npx|nix shell' "$w"; then echo "$w fetches code at run time" >&2; exit 1; fi
      done
      touch "$out"
    ''

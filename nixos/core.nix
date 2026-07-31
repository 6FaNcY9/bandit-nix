{
  lib,
  pkgs,
  repoConfig,
  ...
}: let
  context7Mcp = pkgs.writeShellScriptBin "context7-mcp" ''
    set -euo pipefail

    secret=/run/secrets/context7_api_key
    if [[ ! -r "$secret" ]]; then
      printf 'context7-mcp: missing readable secret %s\n' "$secret" >&2
      exit 1
    fi

    export CONTEXT7_API_KEY
    CONTEXT7_API_KEY="$(< "$secret")"

    exec ${lib.getExe pkgs.nix} shell nixpkgs#nodejs --command \
      npx -y @upstash/context7-mcp@3.2.2 "$@"
  '';
in {
  nixpkgs.config.allowUnfreePredicate = repoConfig.allowUnfreePredicate;
  environment.systemPackages = with pkgs; [
    bubblewrap
    context7Mcp
  ];

  i18n.defaultLocale = "en_US.UTF-8";
  time.timeZone = "Europe/Vienna";

  console = {
    keyMap = "de-latin1-nodeadkeys";
    font = "Lat2-Terminus16";
    earlySetup = true;
  };

  nix = {
    settings = {
      experimental-features = ["nix-command" "flakes"];
      allowed-users = [repoConfig.workstation.username];
      trusted-users = ["root" repoConfig.workstation.username];
      # Avoid multiplying memory-heavy builds across all 12 logical CPUs.
      max-jobs = lib.mkDefault 1;
      cores = lib.mkDefault 6;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
    optimise = {
      automatic = true;
      dates = ["weekly"];
    };
  };

  services.journald.extraConfig = "SystemMaxUse=500M";

  # LSM: enable AppArmor. NixOS ships only a small default profile set, so
  # this mostly confines suid helpers; killUnconfinedConfinables stays off
  # until the profile coverage has been audited.
  security.apparmor.enable = true;

  # IP-based NTP fallbacks so timesyncd can sync even when DNS is broken (e.g. after RTC reset from removing battery)
  services.timesyncd.servers = [
    "162.159.200.1" # Cloudflare
    "162.159.200.123" # Cloudflare
    "216.239.35.0" # Google
    "216.239.35.4" # Google
  ];
}

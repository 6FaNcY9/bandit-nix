{
  lib,
  pkgs,
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
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "cheatsheet.nvim"
      "cuda_nvml_dev"
      "nvidia-kernel-modules"
      "nvidia-persistenced"
      "nvidia-settings"
      "nvidia-x11"
    ];
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
      allowed-users = ["vino"];
      trusted-users = ["root"];
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

  # IP-based NTP fallbacks so timesyncd can sync even when DNS is broken (e.g. after RTC reset from removing battery)
  services.timesyncd.servers = [
    "162.159.200.1" # Cloudflare
    "162.159.200.123" # Cloudflare
    "216.239.35.0" # Google
    "216.239.35.4" # Google
  ];
}

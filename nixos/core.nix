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

  firecrawlMcp = pkgs.writeShellScriptBin "firecrawl-mcp" ''
    set -euo pipefail

    secret=/run/secrets/firecrawl-api-key
    if [[ ! -r "$secret" ]]; then
      printf 'firecrawl-mcp: missing readable secret %s\n' "$secret" >&2
      exit 1
    fi

    export FIRECRAWL_API_KEY
    FIRECRAWL_API_KEY="$(< "$secret")"

    exec ${lib.getExe pkgs.nix} shell nixpkgs#nodejs --command \
      npx -y firecrawl-mcp@3.23.3 "$@"
  '';
in {
  nixpkgs.config.allowUnfreePredicate = repoConfig.allowUnfreePredicate;
  environment.systemPackages = with pkgs; [
    bubblewrap
    context7Mcp
    firecrawlMcp
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
      # Pull prebuilt paths from the public github-bandit-nix Cachix cache
      # in addition to the official cache.nixos.org (kept via module defaults).
      substituters = [
        "https://github-bandit-nix.cachix.org"
      ];
      trusted-public-keys = [
        "github-bandit-nix.cachix.org-1:iaqre/ibQyXnNT8oRzHQHJ4UQfzvGAaFooRXs8v+Hks="
      ];
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

  services.journald.settings.Journal.SystemMaxUse = "500M";
}

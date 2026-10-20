{
  lib,
  repoConfig,
  ...
}: {
  nixpkgs.config.allowUnfreePredicate = repoConfig.allowUnfreePredicate;

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
      # Only root is trusted: a trusted Nix user is root-equivalent (it can add
      # its own substituters and import unsigned store paths). Builds, devshells
      # and `nh os switch` work for untrusted users through the daemon.
      trusted-users = ["root"];
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

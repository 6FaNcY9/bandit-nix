_: {
  # Allow unfree packages (e.g. firmware blobs, steam, vscode)
  nixpkgs.config.allowUnfree = true;
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
      auto-optimise-store = true;
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
}

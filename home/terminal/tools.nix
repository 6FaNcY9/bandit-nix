{pkgs, ...}: {
  programs = {
    nix-index = {
      enable = true;
      enableFishIntegration = true;
    };

    eza.enable = true;
    bat.enable = true;

    btop = {
      enable = true;
      settings = {
        vim_keys = true;
        update_ms = 1000;
        proc_tree = false;
        proc_per_core = true;
        show_battery = true;
      };
    };

    zoxide = {
      enable = true;
      enableFishIntegration = true;
    };

    fzf = {
      enable = true;
      enableFishIntegration = true;
      # Colors managed by Stylix (tomorrow-night-eighties)
    };
  };

  # Wire docker-compose as a Docker CLI plugin so `docker compose`
  # works with podman-dockerCompat. User-level path keeps NixOS pure.
  home.file.".config/docker/cli-plugins/docker-compose".source = "${pkgs.docker-compose}/bin/docker-compose";
}

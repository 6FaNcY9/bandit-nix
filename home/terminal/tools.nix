{
  config,
  pkgs,
  ...
}: let
  serenaMcp = pkgs.writeShellApplication {
    name = "serena-mcp";
    text = ''
      # Nix Python applications can populate PYTHONPATH for their own runtime.
      # Do not let those packages override Serena's uv-managed environment.
      unset PYTHONPATH _PYTHON_HOST_PLATFORM _PYTHON_SYSCONFIGDATA_NAME
      export PYTHONNOUSERSITE=1
      export UV_PYTHON_DOWNLOADS=never
      export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1

      exec "${config.home.homeDirectory}/.local/bin/serena" "$@"
    '';
  };
in {
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
      # Colors managed by Stylix.
    };
  };

  home = {
    file = {
      # Wire docker-compose as a Docker CLI plugin so `docker compose`
      # works with the rootless Docker daemon. User-level path keeps NixOS pure.
      ".config/docker/cli-plugins/docker-compose".source = "${pkgs.docker-compose}/bin/docker-compose";

      # Serena's Rust backend only searches conventional user-local paths on
      # Linux, not NixOS profile paths. Point it at the real package instead of
      # the rustup proxy, which requires an imperatively selected toolchain.
      ".local/bin/rust-analyzer".source = "${pkgs.rust-analyzer}/bin/rust-analyzer";
    };

    packages = [
      serenaMcp
      pkgs.playwright-driver
      pkgs.python313
      pkgs.uv
      pkgs.rustup
      pkgs.go
      pkgs.gopls
    ];
  };
}

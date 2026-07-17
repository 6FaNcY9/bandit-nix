{pkgs, ...}: let
  aider-ollama = pkgs.writeShellScriptBin "aider-coder" ''
    OLLAMA_API_BASE=http://192.168.1.2:11434 \
    exec ${pkgs.aider-chat}/bin/aider \
      --model ollama/qwen3-coder:30b \
      --no-auto-commits \
      "$@"
  '';

  qwen-summarize = pkgs.writeShellScriptBin "qwen-summarize" ''
    exec ${pkgs.nodejs}/bin/node ${../../tools/qwen-mcp.mjs} summarize "$@"
  '';

  bandit-qwen = pkgs.writeShellScriptBin "bandit-qwen" ''
    exec ${pkgs.nodejs}/bin/node ${../../tools/qwen-mcp.mjs} "$@"
  '';

  qwen-review = pkgs.writeShellScriptBin "qwen-review" ''
    exec ${pkgs.nodejs}/bin/node ${../../tools/qwen-mcp.mjs} review "$@"
  '';

  qwen-ask = pkgs.writeShellScriptBin "qwen-ask" ''
    exec ${pkgs.nodejs}/bin/node ${../../tools/qwen-mcp.mjs} ask "$@"
  '';

  qwen-compress = pkgs.writeShellScriptBin "qwen-compress" ''
    exec ${pkgs.nodejs}/bin/node ${../../tools/qwen-mcp.mjs} compress "$@"
  '';

  qwen-diff = pkgs.writeShellScriptBin "qwen-diff" ''
    exec ${pkgs.nodejs}/bin/node ${../../tools/qwen-mcp.mjs} diff "$@"
  '';

  qwen-log = pkgs.writeShellScriptBin "qwen-log" ''
    exec ${pkgs.nodejs}/bin/node ${../../tools/qwen-mcp.mjs} log "$@"
  '';

  qwen-extract = pkgs.writeShellScriptBin "qwen-extract" ''
    exec ${pkgs.nodejs}/bin/node ${../../tools/qwen-mcp.mjs} extract "$@"
  '';

  qwen-commit = pkgs.writeShellScriptBin "qwen-commit" ''
    exec ${pkgs.nodejs}/bin/node ${../../tools/qwen-mcp.mjs} commit "$@"
  '';
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

    aider-chat = {
      enable = true;
      settings = {
        model = "ollama/qwen3-coder:30b";
        weak-model = "ollama/dolphincoder:15b";
        editor-model = "ollama/dolphincoder:15b";
        no-auto-commits = true;
        architect = true;
        edit-format = "diff";
        model-settings-file = "~/.config/aider/model-settings.yml";
        suggest-shell-commands = true;
        detect-urls = true;
      };
    };
  };

  home = {
    sessionVariables.OLLAMA_API_BASE = "http://192.168.1.2:11434";

    file = {
      ".config/aider/model-settings.yml".source = ./aider-model-settings.yml;

      # Wire docker-compose as a Docker CLI plugin so `docker compose`
      # works with the rootless Docker daemon. User-level path keeps NixOS pure.
      ".config/docker/cli-plugins/docker-compose".source = "${pkgs.docker-compose}/bin/docker-compose";
    };

    packages = [
      aider-ollama
      bandit-qwen
      qwen-ask
      qwen-commit
      qwen-compress
      qwen-diff
      qwen-extract
      qwen-log
      qwen-review
      qwen-summarize
      pkgs.playwright-driver
      pkgs.python313
      pkgs.uv
    ];
  };
}

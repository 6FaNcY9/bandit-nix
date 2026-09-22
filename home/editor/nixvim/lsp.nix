{repoConfig, ...}: {
  programs.nixvim.plugins = {
    # LSP — language servers
    lsp = {
      enable = true;
      servers = {
        nixd = {
          enable = true;
          settings = {
            nixpkgs.expr = "import <nixpkgs> {}";
            options = {
              nixos.expr = "(builtins.getFlake \"${repoConfig.workstation.repoPath}\").nixosConfigurations.bandit.options";
              home_manager.expr = "(builtins.getFlake \"${repoConfig.workstation.repoPath}\").nixosConfigurations.bandit.options.home-manager.users.type.getSubOptions {}";
            };
          };
        };
        pyright.enable = true;
        bashls.enable = true;
        lua_ls.enable = true;
        ts_ls.enable = true;
        marksman.enable = true;
        jsonls.enable = true;
        yamlls.enable = true;
        rust_analyzer = {
          enable = true;
          # Rust toolchain provided per-project via direnv/devenv.
          installCargo = false;
          installRustc = false;
        };
        gopls.enable = true;
      };
      keymaps = {
        silent = true;
        lspBuf = {
          "K" = "hover";
          "gd" = "definition";
          "gD" = "declaration";
          "gi" = "implementation";
          "gr" = "references";
          "<leader>ca" = "code_action";
          "<leader>rn" = "rename";
        };
        diagnostic = {
          "[d" = "goto_prev";
          "]d" = "goto_next";
          "<leader>cd" = "open_float";
        };
      };
    };

    # JSON Schema Store catalog — schema-validated completion/hover in
    # jsonls and yamlls for package.json, GitHub Actions, docker-compose,
    # and hundreds of other known formats. Auto-wires into the jsonls/
    # yamlls settings above; no manual schema list needed.
    schemastore.enable = true;

    # Auto-detects which YAML schema applies from file content (e.g. a
    # Kubernetes manifest vs a GitHub Actions workflow) without manual
    # `# yaml-language-server: $schema=` comments.
    yaml-schema-detect.enable = true;
  };
}

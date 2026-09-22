{
  pkgs,
  inputs,
  repoConfig,
  ...
}: {
  imports = [
    ./completion.nix
    ./dap.nix
    ./keymaps.nix
    ./lsp.nix
    ./lualine.nix
    ./plugins.nix
  ];

  programs.nixvim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    nixpkgs = {
      source = inputs.nixpkgs;
      config.allowUnfreePredicate = repoConfig.allowUnfreePredicate;
    };

    # ─── Core options ─────────────────────────────────────
    globals.mapleader = " ";
    globals.maplocalleader = " ";

    opts = {
      number = true;
      relativenumber = true;
      signcolumn = "yes";
      cursorline = true;
      termguicolors = true;
      expandtab = true;
      shiftwidth = 2;
      tabstop = 2;
      smartindent = true;
      wrap = false;
      ignorecase = true;
      smartcase = true;
      updatetime = 250;
      timeoutlen = 300;
      undofile = true;
      scrolloff = 8;
      splitright = true;
      splitbelow = true;
    };

    # ─── Clipboard Manager ──────────────────────────────────────────
    clipboard = {
      register = "unnamedplus";
      providers.wl-copy.enable = true;
    };

    # ─── Custom Plugin Cheatsheet ──────────────────────────────────────────
    extraPlugins = [
      pkgs.vimPlugins.nvim-gdb
      pkgs.vimPlugins.cheatsheet-nvim
    ];
    extraConfigLua = ''
      require('cheatsheet').setup({
        bundled_cheatsheets = true,
        bundled_plugin_cheatsheets = true,
      })

      vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
        pattern = { "*/secrets/*", "*.age", "*.env", "*.env.*" },
        callback = function()
          vim.opt_local.undofile = false
          vim.opt_local.swapfile = false
          vim.opt_local.backup = false
          vim.opt_local.writebackup = false
        end,
      })
    '';

    extraPackages = with pkgs; [
      bashdb
      # Formatters for conform-nvim
      ruff
      shfmt
      stylua
      prettier
      prettierd
    ];
  };
}

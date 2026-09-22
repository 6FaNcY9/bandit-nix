_: {
  # ─── Keymaps ──────────────────────────────────────────
  programs.nixvim.keymaps = [
    # General
    {
      mode = "n";
      key = "<leader>e";
      action = "<cmd>Neotree toggle<CR>";
      options.desc = "Toggle file tree";
    }
    {
      mode = "n";
      key = "<leader>w";
      action = "<cmd>w<CR>";
      options.desc = "Save";
    }
    {
      mode = "n";
      key = "<leader>q";
      action = "<cmd>q<CR>";
      options.desc = "Quit";
    }
    {
      mode = "n";
      key = "<Esc>";
      action = "<cmd>nohlsearch<CR>";
      options.desc = "Clear search highlight";
    }

    # Trouble
    {
      mode = "n";
      key = "<leader>tt";
      action.__raw = ''function() require("trouble").toggle({ mode = "diagnostics" }) end'';
      options.desc = "Toggle Trouble";
    }

    # Oil
    {
      mode = "n";
      key = "-";
      action = "<cmd>Oil<CR>";
      options.desc = "Open parent directory";
    }
    {
      mode = "n";
      key = "<leader>o";
      action = "<cmd>Oil --float<CR>";
      options.desc = "Open Oil float";
    }

    # Flash
    {
      mode = ["n" "x" "o"];
      key = "s";
      action.__raw = "function() require('flash').jump() end";
      options.desc = "Flash jump";
    }
    {
      mode = ["n" "x" "o"];
      key = "S";
      action.__raw = "function() require('flash').treesitter() end";
      options.desc = "Flash treesitter";
    }
    {
      mode = "o";
      key = "r";
      action.__raw = "function() require('flash').remote() end";
      options.desc = "Flash remote";
    }

    # cheatsheet-nvim
    {
      mode = "n";
      key = "<leader>?";
      action = "<cmd>Cheatsheet<CR>";
      options.desc = "Open cheatsheet";
    }

    # Lazygit
    {
      mode = "n";
      key = "<leader>gg";
      action = "<cmd>LazyGit<CR>";
      options.desc = "Open Lazygit";
    }

    # Conform — manual format
    {
      mode = ["n" "v"];
      key = "<leader>cf";
      action.__raw = ''
        function()
          require("conform").format({ async = true, lsp_format = "fallback" })
        end
      '';
      options.desc = "Format buffer";
    }
  ];
}

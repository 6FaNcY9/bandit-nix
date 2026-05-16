{ pkgs, ... }:
{
  programs.nixvim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;

    # gruvbox material (matches your gruvbox-dark-pale aesthetic)
    colorschemes.gruvbox-material = {
      enable = true;
      settings = {
        background = "hard";
        foreground = "material";
        transparent_background = 0;
      };
    };

    # ─── Core options ─────────────────────────────────────
    globals.mapleader = " ";        # space as leader
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
      updatetime = 250;            # snappier hover/diagnostics
      timeoutlen = 300;            # which-key popup speed
      undofile = true;
      scrolloff = 8;
      splitright = true;
      splitbelow = true;
      clipboard = "unnamedplus";   # system clipboard integration
    };

    # ─── Plugins ──────────────────────────────────────────
    plugins = {
      # Treesitter — better syntax highlighting and structure
      treesitter = {
        enable = true;
        settings = {
          highlight.enable = true;
          indent.enable = true;
        };
      };

      # LSP — language servers for completion + errors + hover
      lsp = {
        enable = true;
        servers = {
          nil_ls.enable = true;       # Nix
          pyright.enable = true;      # Python
          bashls.enable = true;       # Bash
          lua_ls.enable = true;       # Lua
          ts_ls.enable = true;        # TypeScript / JavaScript
          marksman.enable = true;     # Markdown
          rust_analyzer = {           # Rust
            enable = true;
            installCargo = true;
            installRustc = true;
          };
        };
        keymaps = {
          silent = true;
          lspBuf = {
            "K"          = "hover";                  # show function meaning
            "gd"         = "definition";             # jump to definition
            "gD"         = "declaration";
            "gi"         = "implementation";
            "gr"         = "references";
            "<leader>ca" = "code_action";
            "<leader>rn" = "rename";
          };
          diagnostic = {
            "[d"         = "goto_prev";
            "]d"         = "goto_next";
            "<leader>cd" = "open_float";
          };
        };
# Flash — better than leap, includes treesitter + search jumps
flash = {
  enable = true;
  settings = {
    modes = {
      char = {
        enabled = true;
        jump_labels = true;
      };
      search.enabled = true;   # enhance / and ? search
      treesitter = {
        labels = "abcdefghijklmnopqrstuvwxyz";
      };
    };
  };
};

# Oil — edit filesystem as a buffer
oil = {
  enable = true;
  settings = {
    default_file_explorer = false;  # keep neo-tree as default
    delete_to_trash = true;
    skip_confirm_for_simple_edits = true;
    view_options = {
      show_hidden = true;
    };
  };
};

# DAP — debug adapter protocol (breakpoints, step-through)
dap = {
  enable = true;
  signs = {
    dapBreakpoint = {
      text = "●";
      texthl = "DapBreakpoint";
    };
    dapBreakpointCondition = {
      text = "◆";
      texthl = "DapBreakpointCondition";
    };
    dapLogPoint = {
      text = "◆";
      texthl = "DapLogPoint";
    };
    dapStopped = {
      text = "→";
      texthl = "DapStopped";
    };
  };
};

# DAP UI — visual interface with variables, watches, call stack
dap-ui = {
  enable = true;
  settings = {
    layouts = [
      {
        elements = [
          { id = "scopes";      size = 0.25; }
          { id = "breakpoints"; size = 0.25; }
          { id = "stacks";      size = 0.25; }
          { id = "watches";     size = 0.25; }
        ];
                position = "left";
                size = 40;
              }
              {
                elements = [
                  { id = "repl";    size = 0.5; }
                  { id = "console"; size = 0.5; }
                ];
                position = "bottom";
                size = 10;
              }
            ];
          };
        };

        # Virtual text showing variable values inline during debugging
        dap-virtual-text.enable = true;
      };

      # Completion — the dropdown you described
      cmp = {
        enable = true;
        autoEnableSources = true;
        settings = {
          sources = [
            { name = "nvim_lsp"; }
            { name = "luasnip"; }
            { name = "copilot"; }
            { name = "path"; }
            { name = "buffer"; }
          ];
          mapping = {
            "<C-Space>" = "cmp.mapping.complete()";       # trigger menu
            "<C-d>"     = "cmp.mapping.scroll_docs(-4)";  # scroll doc up
            "<C-f>"     = "cmp.mapping.scroll_docs(4)";   # scroll doc down
            "<CR>"      = "cmp.mapping.confirm({ select = true })";
            "<Tab>"     = ''
              cmp.mapping(function(fallback)
                if cmp.visible() then cmp.select_next_item()
                else fallback() end
              end, { "i", "s" })
            '';
            "<S-Tab>"   = ''
              cmp.mapping(function(fallback)
                if cmp.visible() then cmp.select_prev_item()
                else fallback() end
              end, { "i", "s" })
            '';
          };
          window = {
            completion.border = "rounded";
            documentation.border = "rounded";
          };
        };
      };

      # Snippets — code templates
      luasnip.enable = true;
      friendly-snippets.enable = true;

      # GitHub Copilot — AI completion
      copilot-lua = {
        enable = true;
        settings = {
          suggestion.enabled = false;   # disable inline, use via cmp instead
          panel.enabled = false;
        };
      };
      copilot-cmp.enable = true;

      # Which-Key — shows available keybindings as you type
      which-key = {
        enable = true;
        settings = {
          preset = "modern";
          delay = 300;
          spec = [
            { __unkeyed-1 = "<leader>f"; group = "Find"; }
            { __unkeyed-1 = "<leader>c"; group = "Code"; }
            { __unkeyed-1 = "<leader>g"; group = "Git"; }
            { __unkeyed-1 = "<leader>r"; group = "Rename/Refactor"; }
            { __unkeyed-1 = "<leader>t"; group = "Toggle"; }
          ];
        };
      };

      # Telescope — fuzzy finder for files, grep, buffers, etc
      telescope = {
        enable = true;
        keymaps = {
          "<leader>ff" = "find_files";
          "<leader>fg" = "live_grep";
          "<leader>fb" = "buffers";
          "<leader>fh" = "help_tags";
          "<leader>fr" = "oldfiles";
          "<leader>fk" = "keymaps";       # search all keybindings
          "<leader>fd" = "diagnostics";
        };
      };

      # File tree
      neo-tree = {
        enable = true;
        closeIfLastWindow = true;
      };

      # Statusline
      lualine = {
        enable = true;
        settings.options.theme = "gruvbox-material";
      };

      # Git integration in the gutter
      gitsigns = {
        enable = true;
        settings.current_line_blame = true;
      };

      # Better diagnostics list
      trouble.enable = true;

      # Auto-pairs for brackets, quotes
      nvim-autopairs.enable = true;

      # Comment toggling with gc / gcc
      comment.enable = true;

      # Indent guides
      indent-blankline.enable = true;

      # Pretty notifications + cmdline
      noice = {
        enable = true;
        settings.presets = {
          bottom_search = true;
          command_palette = true;
          lsp_doc_border = true;
        };
      };
      notify.enable = true;

      # Web devicons (for neo-tree, lualine, etc)
      web-devicons.enable = true;
    };

    # ─── Custom keymaps ─────────────────────────────────────
    keymaps = [
      { mode = "n"; key = "<leader>e"; action = "<cmd>Neotree toggle<CR>";
        options.desc = "Toggle file tree"; }
      { mode = "n"; key = "<leader>w"; action = "<cmd>w<CR>";
        options.desc = "Save"; }
      { mode = "n"; key = "<leader>q"; action = "<cmd>q<CR>";
        options.desc = "Quit"; }
      { mode = "n"; key = "<leader>tt"; action = "<cmd>TroubleToggle<CR>";
        options.desc = "Toggle Trouble"; }
      { mode = "n"; key = "<Esc>"; action = "<cmd>nohlsearch<CR>";
        options.desc = "Clear search highlight"; }
    ];
  };
}

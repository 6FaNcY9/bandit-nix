_: {
  # ─── Plugins ──────────────────────────────────────────
  programs.nixvim.plugins = {
    # Treesitter — syntax highlighting and structure
    treesitter = {
      enable = true;
      settings = {
        ensure_installed = "all";
        incrementalSelection.enable = true;
        highlight.enable = true;
        indent.enable = true;
      };
    };

    # Markdown Plugin
    render-markdown = {
      enable = true;
      settings = {
        enable = true;
        anti_conceal.enabled = true;
      };
    };

    # Rainbow-colored matching brackets/delimiters by nesting depth
    rainbow-delimiters.enable = true;

    # Highlight other occurrences of the symbol under the cursor
    illuminate.enable = true;

    glow.enable = true;

    # Copilot — inline suggestions surfaced through cmp (below), not its
    # own ghost-text/panel, to avoid two competing suggestion UIs.
    copilot-lua = {
      enable = true;
      settings = {
        suggestion.enabled = false;
        panel.enabled = false;
      };
    };

    # Which-key — shows keybindings as you type
    which-key = {
      enable = true;
      settings = {
        preset = "modern";
        delay = 300;
        spec = [
          {
            __unkeyed-1 = "<leader>f";
            group = "Find";
          }
          {
            __unkeyed-1 = "<leader>c";
            group = "Code";
          }
          {
            __unkeyed-1 = "<leader>g";
            group = "Git";
          }
          {
            __unkeyed-1 = "<leader>cf";
            group = "Format";
          }
          {
            __unkeyed-1 = "<leader>r";
            group = "Rename/Refactor";
          }
          {
            __unkeyed-1 = "<leader>t";
            group = "Toggle";
          }
          {
            __unkeyed-1 = "<leader>d";
            group = "Debug";
          }
        ];
      };
    };

    # Telescope — fuzzy finder
    telescope = {
      enable = true;
      keymaps = {
        "<leader>ff" = "find_files";
        "<leader>fg" = "live_grep";
        "<leader>fb" = "buffers";
        "<leader>fh" = "help_tags";
        "<leader>fr" = "oldfiles";
        "<leader>fk" = "keymaps";
        "<leader>fd" = "diagnostics";
      };
    };

    # File tree
    neo-tree = {
      enable = true;
      settings = {
        close_if_last_window = true;
      };
    };

    # Oil — edit filesystem as a buffer
    oil = {
      enable = true;
      settings = {
        default_file_explorer = false;
        delete_to_trash = true;
        skip_confirm_for_simple_edits = true;
        view_options.show_hidden = true;
      };
    };

    # Flash — fast cursor jumping with treesitter awareness
    flash = {
      enable = true;
      settings = {
        modes = {
          char = {
            enabled = true;
            jump_labels = true;
          };
          search.enabled = true;
          treesitter = {
            labels = "abcdefghijklmnopqrstuvwxyz";
          };
        };
      };
    };

    # Formatting — conform-nvim dispatches to per-filetype formatters
    conform-nvim = {
      enable = true;
      settings = {
        formatters_by_ft = {
          nix = ["alejandra"];
          python = ["ruff_format"];
          bash = ["shfmt"];
          sh = ["shfmt"];
          lua = ["stylua"];
          javascript = [["prettierd" "prettier"]];
          typescript = [["prettierd" "prettier"]];
          json = [["prettierd" "prettier"]];
          yaml = [["prettierd" "prettier"]];
          markdown = [["prettierd" "prettier"]];
        };
        format_on_save = {
          timeout_ms = 500;
          lsp_format = "fallback";
        };
      };
    };

    # Lazygit — full git TUI inside nvim
    lazygit.enable = true;

    # Git signs in gutter
    gitsigns = {
      enable = true;
      settings.current_line_blame = true;
    };

    # Diagnostics list
    trouble.enable = true;

    # Auto-pairs
    nvim-autopairs.enable = true;

    # Comment toggling
    comment.enable = true;

    # Indent guides
    indent-blankline.enable = true;

    # Pretty UI — notifications, cmdline, popups
    noice = {
      enable = true;
      settings.presets = {
        bottom_search = true;
        command_palette = true;
        lsp_doc_border = true;
      };
    };
    notify.enable = true;

    # Icons
    web-devicons.enable = true;
  };
}

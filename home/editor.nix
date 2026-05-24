_: {
  programs.nixvim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;

    colorschemes.gruvbox = {
      enable = true;
      settings = {
        contrast_dark = "hard";
        transparent_bg = false;
      };
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
      clipboard = "unnamedplus";
    };

    # ─── Plugins ──────────────────────────────────────────
    plugins = {
      # Treesitter — syntax highlighting and structure
      treesitter = {
        enable = true;
        settings = {
          highlight.enable = true;
          indent.enable = true;
        };
      };

      # LSP — language servers
      lsp = {
        enable = true;
        servers = {
          nil_ls.enable = true;
          pyright.enable = true;
          bashls.enable = true;
          lua_ls.enable = true;
          ts_ls.enable = true;
          marksman.enable = true;
          rust_analyzer = {
            enable = true;
            installCargo = true;
            installRustc = true;
          };
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

      # Completion — dropdown menu
      cmp = {
        enable = true;
        autoEnableSources = true;
        settings = {
          sources = [
            {name = "nvim_lsp";}
            {name = "luasnip";}
            {name = "copilot";}
            {name = "path";}
            {name = "buffer";}
          ];
          mapping = {
            "<C-Space>" = "cmp.mapping.complete()";
            "<C-d>" = "cmp.mapping.scroll_docs(-4)";
            "<C-f>" = "cmp.mapping.scroll_docs(4)";
            "<CR>" = "cmp.mapping.confirm({ select = true })";
            "<Tab>" = ''
              cmp.mapping(function(fallback)
                if cmp.visible() then cmp.select_next_item()
                else fallback() end
              end, { "i", "s" })
            '';
            "<S-Tab>" = ''
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

      # Snippets
      luasnip.enable = true;
      friendly-snippets.enable = true;

      # GitHub Copilot — integrated into cmp
      copilot-lua = {
        enable = true;
        settings = {
          suggestion.enabled = false;
          panel.enabled = false;
        };
      };
      copilot-cmp.enable = true;

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

      # DAP — debugger
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

      # DAP UI — visual debug interface
      dap-ui = {
        enable = true;
        settings = {
          layouts = [
            {
              elements = [
                {
                  id = "scopes";
                  size = 0.25;
                }
                {
                  id = "breakpoints";
                  size = 0.25;
                }
                {
                  id = "stacks";
                  size = 0.25;
                }
                {
                  id = "watches";
                  size = 0.25;
                }
              ];
              position = "left";
              size = 40;
            }
            {
              elements = [
                {
                  id = "repl";
                  size = 0.5;
                }
                {
                  id = "console";
                  size = 0.5;
                }
              ];
              position = "bottom";
              size = 10;
            }
          ];
        };
      };

      # DAP virtual text — variable values inline while debugging
      dap-virtual-text.enable = true;

      # Statusline
      lualine = {
        enable = true;
        settings.options.theme = "gruvbox";
      };

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

    # ─── Keymaps ──────────────────────────────────────────
    keymaps = [
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
        action = "<cmd>TroubleToggle<CR>";
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

      # DAP
      {
        mode = "n";
        key = "<leader>db";
        action.__raw = "function() require('dap').toggle_breakpoint() end";
        options.desc = "Toggle breakpoint";
      }
      {
        mode = "n";
        key = "<leader>dc";
        action.__raw = "function() require('dap').continue() end";
        options.desc = "Continue / start";
      }
      {
        mode = "n";
        key = "<leader>di";
        action.__raw = "function() require('dap').step_into() end";
        options.desc = "Step into";
      }
      {
        mode = "n";
        key = "<leader>do";
        action.__raw = "function() require('dap').step_over() end";
        options.desc = "Step over";
      }
      {
        mode = "n";
        key = "<leader>dO";
        action.__raw = "function() require('dap').step_out() end";
        options.desc = "Step out";
      }
      {
        mode = "n";
        key = "<leader>dr";
        action.__raw = "function() require('dap').repl.open() end";
        options.desc = "Open REPL";
      }
      {
        mode = "n";
        key = "<leader>du";
        action.__raw = "function() require('dapui').toggle() end";
        options.desc = "Toggle DAP UI";
      }
      {
        mode = "n";
        key = "<leader>dt";
        action.__raw = "function() require('dap').terminate() end";
        options.desc = "Terminate session";
      }
    ];
  };
}

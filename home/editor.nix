{
  pkgs,
  inputs,
  ...
}: {
  programs.nixvim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    nixpkgs.source = inputs.nixpkgs;

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
      providers.xclip.enable = true;
    };

    # ─── Plugins ──────────────────────────────────────────
    plugins = {
      # Treesitter — syntax highlighting and structure
      treesitter = {
        enable = true;
        settings = {
          ensure_installed = [
            "markdown"
            "markdown_inline"
            "lua"
            "vim"
            "bash"
            "python"
            "json"
            "yaml"
            "rust"
            "nix"
          ];
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

      glow.enable = true;

      # LSP — language servers
      lsp = {
        enable = true;
        servers = {
          nixd = {
            enable = true;
            settings = {
              nixpkgs.expr = "import <nixpkgs> {}";
              options = {
                nixos.expr = "(builtins.getFlake \"/home/vino/src/bandit-nix\").nixosConfigurations.bandit.options";
                home_manager.expr = "(builtins.getFlake \"/home/vino/src/bandit-nix\").nixosConfigurations.bandit.options.home-manager.users.type.getSubOptions []";
              };
            };
          };
          pyright.enable = true;
          bashls.enable = true;
          lua_ls.enable = true;
          ts_ls.enable = true;
          marksman.enable = true;
          rust_analyzer = {
            enable = true;
            # Rust toolchain provided per-project via direnv/devenv.
            installCargo = false;
            installRustc = false;
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
        settings.options.theme = "auto";
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
      # Nix rebuild with quickfix population
      {
        mode = "n";
        key = "<leader>nr";
        action.__raw = ''
          function()
            local cmd = "sudo nixos-rebuild test --flake .#bandit 2>&1"
            local output = vim.fn.systemlist(cmd)
            local qflist = {}
            for _, line in ipairs(output) do
              -- match "file.nix:line:col: message" patterns
              local file, lnum, col, msg = line:match("([^:]+):(%d+):(%d+): (.+)")
              if file then
                table.insert(qflist, { filename = file, lnum = tonumber(lnum), col = tonumber(col), text = msg })
              end
            end
            if #qflist > 0 then
              vim.fn.setqflist(qflist)
              vim.cmd("copen")
            else
              vim.notify(table.concat(output, "\n"), vim.log.levels.INFO)
            end
          end
        '';
        options.desc = "Nix rebuild → quickfix";
      }

      # Just evaluate (fast, no build)
      {
        mode = "n";
        key = "<leader>ne";
        action.__raw = ''
          function()
            local out = vim.fn.system("nix eval .#nixosConfigurations.bandit.config.system.build.toplevel 2>&1")
            vim.notify(out, vim.log.levels.WARN)
          end
        '';
        options.desc = "Nix eval check";
      }
    ];
  };
}

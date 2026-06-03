{
  lib,
  pkgs,
  ...
}: {
  programs = {
    # ─── Fish ─────────────────────────────────────────────────
    fish = {
      enable = true;

      plugins = [
        # fzf keybindings: ctrl-r history, ctrl-f dir, ctrl-v vars, ctrl-alt-p procs
        {
          name = "fzf-fish";
          src = pkgs.fishPlugins.fzf-fish.src;
        }
        # Reminds you when a shorter alias/abbr exists
        {
          name = "fish-you-should-use";
          src = pkgs.fishPlugins.fish-you-should-use.src;
        }
        # fzf on top of fish's native tab completion engine
        {
          name = "fifc";
          src = pkgs.fishPlugins.fifc.src;
        }
        # Auto-close (), [], {}, "", ''
        {
          name = "autopair";
          src = pkgs.fishPlugins.autopair.src;
        }
        # Colorized man pages
        {
          name = "colored-man-pages";
          src = pkgs.fishPlugins.colored-man-pages.src;
        }
        # Remove failed / typo commands from history
        {
          name = "sponge";
          src = pkgs.fishPlugins.sponge.src;
        }
        # Desktop notification when long command finishes
        {
          name = "done";
          src = pkgs.fishPlugins.done.src;
        }
        # Text expansions: . → ./, ... → ../..
        {
          name = "puffer";
          src = pkgs.fishPlugins.puffer.src;
        }
      ];

      shellAbbrs = {
        # Nix rebuilds
        nrs = "sudo nixos-rebuild switch --flake .#bandit";
        nrt = "sudo nixos-rebuild test --flake .#bandit";
        nfc = "nix flake check --no-update-lock-file";
        # Git
        gst = "git status";
        gcm = "git commit -m";
        gco = "git checkout";
        gpsh = "git push";
        # Systemd
        jfu = "journalctl -fu";
        jb = "journalctl -b";
        sc = "systemctl";
        scu = "systemctl --user";
        # Safety — abbrs expand only at the prompt, never inside plugins/functions
        rm = "rm -i";
        cp = "cp -i";
        mv = "mv -i";
      };

      shellAliases = {
        # ── Nix workflow ──────────────────────────────────────
        ns = "nh os switch";
        nt = "nh os test";
        nfu = "nix flake update";
        ngc = "nix-collect-garbage -d";
        nd = "nix develop";
        nsp = "nix shell nixpkgs#";
        # ── Navigation ────────────────────────────────────────
        ll = "eza -la --icons --git";
        la = "eza -la --icons --git";
        lt = "eza --tree --icons --level=2";
        lta = "eza --tree --icons --level=3 -a";
        cat = "bat";
        # ── Git ───────────────────────────────────────────────
        g = "git";
        ga = "git add";
        gc = "git commit";
        gca = "git commit --amend";
        gp = "git push";
        gl = "git pull";
        gs = "git status";
        gd = "git diff";
        glog = "git log --oneline --decorate --graph";
        # ── Editor ────────────────────────────────────────────
        v = "nvim";
        vi = "nvim";
        vim = "nvim";
        # ── System ────────────────────────────────────────────
        reload = "exec fish";
        path = "string split : $PATH";
        ports = "ss -tulanp";
        psg = "ps aux | grep";
        cls = "clear";
        # ── Network ───────────────────────────────────────────
        myip = "curl -sf ifconfig.me";
      };

      interactiveShellInit = ''
        # ── Vi mode ───────────────────────────────────────────
        fish_vi_key_bindings
        # Restore fzf bindings clobbered by vi mode
        # ctrl-r=history  ctrl-f=dir  ctrl-v=shell-vars  ctrl-alt-p=processes
        fzf_configure_bindings --history=\cr --directory=\cf --git_log=\cg --git_status=\cs --variables=\cv --processes=\ca\cp

        # ── Retro greeter ─────────────────────────────────────
        function fish_greeting
            set -l nixver (nixos-version 2>/dev/null | string split ' ' --max 2 --field 1)
            set -l kern (uname -r)
            echo ""
            set_color ffcc66
            echo "  λ  bandit · NixOS $nixver"
            set_color 999999
            echo "  kernel $kern  ·  fish $version"
            set_color normal
            echo ""
        end

        # ── Silence you-should-use for git shorthand aliases ──
        set -gx YSU__IGNORED_GLOBAL_ALIASES '^(g|ga|gc|gca|gp|gl|gs|gd|glog)$'

        # ── Cachix — token from sops secret, never global ─────
        function cachix
          if test -r /run/secrets/cachix-secret
            set -lx CACHIX_AUTH_TOKEN (cat /run/secrets/cachix-secret)
            command cachix $argv
          else
            command cachix $argv
          end
        end
      '';
    };

    # ─── Starship — gruvbox dark prompt ───────────────────────
    starship = {
      enable = true;
      enableFishIntegration = true;
      settings = {
        palette = lib.mkForce "tomorrow_night_eighties";

        palettes.tomorrow_night_eighties = {
          color_fg0 = "#f2f0ec";
          color_bg1 = "#393939";
          color_bg3 = "#515151";
          color_blue = "#6699cc";
          color_aqua = "#66cccc";
          color_green = "#99cc99";
          color_orange = "#f99157";
          color_purple = "#cc99cc";
          color_red = "#f2777a";
          color_yellow = "#ffcc66";
        };

        format = "$username$directory$git_branch$git_status$nix_shell$cmd_duration$line_break$character";

        username = {
          style_user = "color_green bold";
          style_root = "color_red bold";
          format = "[$user]($style) ";
          show_always = false;
        };

        directory = {
          style = "color_blue bold";
          format = "[$path]($style)[$read_only]($read_only_style) ";
          truncation_length = 4;
          truncate_to_repo = false;
          read_only = " 󰌾";
        };

        git_branch = {
          style = "color_yellow bold";
          format = "on [$symbol$branch]($style) ";
          symbol = " ";
        };

        git_status = {
          style = "color_red bold";
          conflicted = "⚡";
          ahead = "⇡\${count}";
          behind = "⇣\${count}";
          diverged = "⇕⇡\${ahead_count}⇣\${behind_count}";
          modified = "!";
          untracked = "?";
          staged = "+";
          deleted = "✘";
        };

        nix_shell = {
          format = "via [$symbol$state]($style) ";
          style = "color_aqua bold";
          symbol = "❄ ";
          impure_msg = "impure";
          pure_msg = "pure";
        };

        cmd_duration = {
          min_time = 2000;
          format = "took [$duration]($style) ";
          style = "color_orange bold";
        };

        character = {
          success_symbol = "[❯](color_green bold)";
          error_symbol = "[❯](color_red bold)";
          vimcmd_symbol = "[❮](color_yellow bold)";
        };

        # Language modules — only shown inside relevant project dirs
        rust = {
          style = "color_orange bold";
          format = "via [$symbol($version)]($style) ";
        };
        python = {
          style = "color_blue bold";
          format = "via [$symbol$pyenv_prefix($version)($virtualenv)]($style) ";
        };
        nodejs = {
          style = "color_green bold";
          format = "via [$symbol($version)]($style) ";
        };
        golang = {
          style = "color_aqua bold";
          format = "via [$symbol($version)]($style) ";
        };
      };
    };

    # ─── CLI tools ─────────────────────────────────────────────
    nix-index = {
      enable = true;
      enableFishIntegration = true;
    };

    eza.enable = true;
    bat.enable = true;

    fish.functions.cb = {
      description = "Copy file contents to clipboard (or stdin if no arg)";
      body = ''
        if test (count $argv) -eq 0
          xclip -selection clipboard
        else if test -f $argv[1]
          xclip -selection clipboard < $argv[1]
        else
          echo "cb: '$argv[1]' is not a file" >&2
          return 1
        end
      '';
    };

    zoxide = {
      enable = true;
      enableFishIntegration = true;
    };

    fzf = {
      enable = true;
      enableFishIntegration = true;
      # Colors managed by Stylix (gruvbox-dark-hard)
    };
  };
}

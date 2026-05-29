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
        # ctrl-r history, ctrl-f file, ctrl-v cd — fzf keybindings
        {
          name = "fzf-fish";
          src = pkgs.fishPlugins.fzf-fish.src;
        }
        # Reminds you when a shorter alias/abbr exists
        {
          name = "fish-you-should-use";
          src = pkgs.fishPlugins.fish-you-should-use.src;
        }
      ];

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
        # ── Safety ────────────────────────────────────────────
        rm = "rm -i";
        cp = "cp -i";
        mv = "mv -i";
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
        fzf_configure_bindings --history=\cr --directory=\cf --git_log=\cg --git_status=\cs

        # ── Suppress default greeting ─────────────────────────
        set -g fish_greeting ""

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
        palette = lib.mkForce "gruvbox_dark";

        palettes.gruvbox_dark = {
          color_fg0 = "#fbf1c7";
          color_bg1 = "#3c3836";
          color_bg3 = "#665c54";
          color_blue = "#458588";
          color_aqua = "#689d6a";
          color_green = "#98971a";
          color_orange = "#d65d0e";
          color_purple = "#b16286";
          color_red = "#cc241d";
          color_yellow = "#d79921";
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

{
  lib,
  pkgs,
  ...
}: {
  programs = {
    # ─── ZSH ──────────────────────────────────────────────────
    zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      historySubstringSearch.enable = true;

      history = {
        size = 50000;
        save = 50000;
        ignoreDups = true;
        ignoreSpace = true;
        extended = true; # timestamps
        share = true; # share across terminal sessions
      };

      plugins = [
        {
          # Shows nix-shell / nix develop context in prompt
          name = "zsh-nix-shell";
          file = "nix-shell.plugin.zsh";
          src = pkgs.zsh-nix-shell;
        }
        {
          # Reminds you when a shorter alias exists
          name = "zsh-you-should-use";
          src = pkgs.zsh-you-should-use;
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
        reload = "exec zsh";
        path = "echo $PATH | tr ':' '\n'";
        ports = "ss -tulanp";
        psg = "ps aux | grep";
        cls = "clear";
        # ── Network ───────────────────────────────────────────
        myip = "curl -sf ifconfig.me";
      };

      initExtra = ''
        # ── Vi mode ───────────────────────────────────────────
        bindkey -v
        export KEYTIMEOUT=1  # faster mode switch (10ms)

        # ── History navigation ────────────────────────────────
        bindkey '^[[A' history-substring-search-up
        bindkey '^[[B' history-substring-search-down
        bindkey -M vicmd 'k' history-substring-search-up
        bindkey -M vicmd 'j' history-substring-search-down
        bindkey '^R' history-incremental-search-backward

        # ── ZSH options ───────────────────────────────────────
        setopt AUTO_CD          # cd by just typing the dir name
        setopt GLOB_DOTS        # globs match dotfiles
        setopt NO_BEEP
        setopt HIST_VERIFY      # expand history before executing
        setopt EXTENDED_GLOB
        setopt PUSHD_IGNORE_DUPS

        # ── Completion styling ────────────────────────────────
        zstyle ':completion:*' menu select
        zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
        zstyle ':completion:*:descriptions' format '[%d]'
        zstyle ':completion:*' list-colors "''${(s.:.)LS_COLORS}"

        # ── Cachix — token from sops secret, never global ─────
        cachix() {
          if [[ -r /run/secrets/cachix-secret ]]; then
            CACHIX_AUTH_TOKEN=$(cat /run/secrets/cachix-secret) command cachix "$@"
          else
            command cachix "$@"
          fi
        }
      '';
    };

    # ─── Starship — gruvbox dark prompt ───────────────────────
    starship = {
      enable = true;
      enableZshIntegration = true;
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
    eza.enable = true;
    bat.enable = true;

    zoxide = {
      enable = true;
      enableZshIntegration = true;
    };

    fzf = {
      enable = true;
      enableZshIntegration = true;
      # Stylix manages colors (gruvbox-dark-hard) — no override needed
    };
  };
}

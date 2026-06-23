{
  config,
  pkgs,
  inputs,
  ...
}: let
  sharedAliases = import ../aliases.nix;
in {
  programs = {
    # ─── Zsh ──────────────────────────────────────────────────────
    zsh = {
      enable = true;
      dotDir = "${config.xdg.configHome}/zsh";
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      enableCompletion = true;

      historySubstringSearch = {
        enable = true;
        searchUpKey = ["^P" "^[[A"]; # ctrl-p + up-arrow
        searchDownKey = ["^N" "^[[B"]; # ctrl-n + down-arrow
      };

      history = {
        size = 100000;
        save = 100000;
        path = "${config.xdg.stateHome}/zsh/history";
        ignoreDups = true;
        share = true;
        extended = true;
        ignoreSpace = true;
      };

      plugins = [
        # Auto-close (), [], {}, "", ''
        {
          name = "autopair";
          src = pkgs.zsh-autopair;
          file = "share/zsh/zsh-autopair/autopair.zsh";
        }
        # Remind when a defined alias exists for a typed command
        {
          name = "you-should-use";
          src = pkgs.zsh-you-should-use;
          file = "share/zsh/plugins/you-should-use/you-should-use.plugin.zsh";
        }
        # Keep zsh config inside nix-shell / nix develop
        {
          name = "nix-shell";
          src = pkgs.zsh-nix-shell;
          file = "share/zsh/plugins/zsh-nix-shell/nix-shell.plugin.zsh";
        }
      ];

      # fzf-tab must be loaded after compinit — hook into completionInit
      completionInit = ''
        mkdir -p ${config.xdg.cacheHome}/zsh
        autoload -U compinit && compinit -i -d ${config.xdg.cacheHome}/zsh/zcompdump
        source ${pkgs.zsh-fzf-tab}/share/fzf-tab/fzf-tab.plugin.zsh
        # fzf-tab-source: extra completions (git, systemd, cargo, pip, etc.)
        source ${inputs.fzf-tab-source}/fzf-tab-source.plugin.zsh
      '';

      shellAliases =
        sharedAliases
        // {
          # zsh-only (fish has these as abbrs in shell.nix)
          nrs = "sudo nixos-rebuild switch --flake .#bandit";
          nrt = "sudo nixos-rebuild test --flake .#bandit";
          nfc = "nix flake check --no-update-lock-file";
          gst = "git status";
          gcm = "git commit -m";
          gco = "git checkout";
          gpsh = "git push";
          jfu = "journalctl -fu";
          jb = "journalctl -b";
          sc = "systemctl";
          scu = "systemctl --user";
          rm = "rm -i";
          cp = "cp -i";
          mv = "mv -i";
          # zsh-specific (different syntax from fish)
          reload = "exec zsh";
          paths = "echo $PATH | tr ':' '\n'";
        };

      initContent = ''
        # ── Extra completions (~150 tools) ───────────────────
        fpath+=(${pkgs.zsh-completions}/share/zsh/site-functions)

        # ── Emacs mode ────────────────────────────────────────
        bindkey -e
        bindkey '^[[1;5D' backward-word   # Ctrl+Left
        bindkey '^[[1;5C' forward-word    # Ctrl+Right
        # fzf history widget (ctrl-r) — source only key-bindings, not completion
        # (completion is handled by fzf-tab loaded in completionInit above)
        [[ -f ${pkgs.fzf}/share/fzf/key-bindings.zsh ]] && source ${pkgs.fzf}/share/fzf/key-bindings.zsh

        # ── Zsh options ───────────────────────────────────────
        setopt AUTO_CD
        setopt GLOB_DOTS
        setopt NO_BEEP
        setopt INTERACTIVE_COMMENTS

        # ── fzf-tab tweaks ────────────────────────────────────
        # Disable built-in menu so fzf-tab owns completion display entirely
        zstyle ':completion:*' menu no
        # Named groups — required for fzf-tab-source $group-based preview branches
        # (git-checkout, journalctl, ps, ip, etc. all switch on $group)
        zstyle ':completion:*' group-name ""
        # Coloured entries in completion lists
        zstyle ':completion:*' list-colors ''${(s.:.)LS_COLORS}

        # cd / zoxide: eza directory preview (fzf-tab-source has no cd source)
        zstyle ':fzf-tab:complete:cd:*' fzf-preview \
          'eza -1 --icons --color=always $realpath 2>/dev/null'
        zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview \
          'eza -1 --icons --color=always $realpath 2>/dev/null || ls -la $realpath 2>/dev/null'
        # NOTE: no ':fzf-tab:complete:*:*' here — fzf-tab-source's --complete.zsh
        # registers ':fzf-tab:complete:*' as the catch-all using the smarter
        # `less ''${realpath#-*=}`. A *:* override would silently win over it.

        # lesspipe: lets `less` open archives, images, etc. in fzf previews
        export LESSOPEN="|${pkgs.lesspipe}/bin/lesspipe.sh %s"

        zstyle ':fzf-tab:*' fzf-flags --height=50% --border=sharp --ansi
        zstyle ':fzf-tab:*' switch-group ',' '.'

        # ── Colored man pages via bat ─────────────────────────
        export MANPAGER="sh -c 'col -bx | bat -l man -p'"
        export MANROFFOPT="-c"

        # ── Greeting — top-level shell only, not nested/exec zsh ─
        if [[ $- == *i* && $SHLVL -eq 1 ]]; then
          nixver=$(nixos-version 2>/dev/null | cut -d' ' -f1)
          kern=$(uname -r)
          print ""
          print -P "%F{#ffcc66}  λ  bandit · NixOS $nixver%f"
          print -P "%F{#999999}  kernel $kern  ·  zsh $ZSH_VERSION%f"
          print ""
        fi

        # ── cachix: inject token from sops secret ─────────────
        cachix() {
          if [[ -r /run/secrets/cachix-secret ]]; then
            CACHIX_AUTH_TOKEN=$(< /run/secrets/cachix-secret) command cachix "$@"
          else
            command cachix "$@"
          fi
        }

        # ── nsp: open a nix shell with nixpkgs packages ──────
        nsp() {
          if [[ $# -eq 0 ]]; then
            print "Usage: nsp <package> [package ...]" >&2
            return 1
          fi

          local packages=()
          local package

          for package in "$@"; do
            packages+=("nixpkgs#$package")
          done

          nix shell "''${packages[@]}"
        }

        # ── cb: copy file/stdin to clipboard ──────────────────
        cb() {
          if [[ $# -eq 0 ]]; then
            xclip -selection clipboard
          elif [[ -f "$1" ]]; then
            xclip -selection clipboard < "$1"
          else
            print "cb: '$1' is not a file" >&2
            return 1
          fi
        }
      '';
    };

    # ── Enable zsh integrations for shell tools ──────────────────
    zoxide.enableZshIntegration = true;
    nix-index.enableZshIntegration = true;

    # fzf: key-bindings sourced manually in initExtra to avoid loading
    # fzf's completion.zsh (conflicts with fzf-tab)
    fzf.enableZshIntegration = false;
  };
}

{
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
      ];

      # fzf-tab must be loaded after compinit — hook into completionInit
      completionInit = ''
        autoload -U compinit && compinit -i
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
        # ── Vi mode ───────────────────────────────────────────
        bindkey -v
        export KEYTIMEOUT=1

        # Cursor shape: block in normal, beam in insert
        _zle_cursor_vicmd()  { print -n '\e[2 q' }
        _zle_cursor_viins()  { print -n '\e[5 q' }
        _zle_keymap_select() { [[ $KEYMAP == vicmd ]] && _zle_cursor_vicmd || _zle_cursor_viins }
        zle -N zle-keymap-select _zle_keymap_select
        zle -N zle-line-init     _zle_cursor_viins
        print -n '\e[5 q'

        # Restore useful bindings in vi insert mode
        bindkey '^a' beginning-of-line
        bindkey '^e' end-of-line
        bindkey '^w' backward-kill-word
        bindkey '^k' kill-line
        # fzf history widget (ctrl-r) — source only key-bindings, not completion
        # (completion is handled by fzf-tab loaded in completionInit above)
        [[ -f ${pkgs.fzf}/share/fzf/key-bindings.zsh ]] && source ${pkgs.fzf}/share/fzf/key-bindings.zsh

        # ── Zsh options ───────────────────────────────────────
        setopt AUTO_CD
        setopt GLOB_DOTS
        setopt NO_BEEP
        setopt INTERACTIVE_COMMENTS

        # ── fzf-tab tweaks ────────────────────────────────────
        zstyle ':fzf-tab:complete:cd:*' fzf-preview \
          'eza -1 --icons --color=always $realpath 2>/dev/null'
        zstyle ':fzf-tab:complete:*:*' fzf-preview \
          'bat --color=always --style=numbers $realpath 2>/dev/null || ls -la $realpath 2>/dev/null'
        zstyle ':fzf-tab:*' fzf-flags --height=50% --border=sharp
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

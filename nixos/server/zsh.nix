{
  pkgs,
  zellijMenu,
  ...
}: {
  programs.zsh = {
    autosuggestions.enable = true;
    enableCompletion = true;
    syntaxHighlighting.enable = true;

    interactiveShellInit = ''
      # Keep console/SSH editing sane even when the terminal reports odd keys.
      stty erase '^?' 2>/dev/null || true
      bindkey -e
      bindkey '^?' backward-delete-char
      bindkey '^H' backward-delete-char
      bindkey '^[[3~' delete-char
      bindkey '^[[3;5~' kill-word
      bindkey '^[[H' beginning-of-line
      bindkey '^[[F' end-of-line
      bindkey '^[[1;5D' backward-word
      bindkey '^[[1;5C' forward-word

      [[ -r ${pkgs.fzf}/share/fzf/key-bindings.zsh ]] && source ${pkgs.fzf}/share/fzf/key-bindings.zsh 2> >(${pkgs.gnugrep}/bin/grep -v "can't change option: zle" >&2)
      [[ -r ${pkgs.zsh-fzf-tab}/share/fzf-tab/fzf-tab.plugin.zsh ]] && source ${pkgs.zsh-fzf-tab}/share/fzf-tab/fzf-tab.plugin.zsh
      command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"

      zstyle ':completion:*' menu no
      zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
      zstyle ':fzf-tab:*' fzf-flags --height=50% --border=sharp --ansi
      zstyle ':fzf-tab:*' switch-group ',' '.'

      zj() {
        ZELLIJ_CONFIG_DIR=/etc/xdg/zellij zellij attach "''${1:-main}" --create
      }

      zjh() {
        print "zellij quick help"
        print "  zj [name]     attach/create a zellij session"
        print "  zjm           open the Zellij command menu"
        print ""
        print "How keys work:"
        print "  Press Ctrl-Space, release both keys, then press the next key."
        print "  Example: Ctrl-Space, release, Space opens the command menu."
        print "  Example: Ctrl-Space, release, ? opens shortcut help."
        print "  Ctrl-g is only lock/unlock; it is not the menu leader."
        print ""
        print "Main keys after Ctrl-Space:"
        print "  Space         command menu"
        print "  ?             shortcut help"
        print "  r             tab switcher"
        print "  Esc/Enter     leave mode"
      }

      zjm() {
        if [[ -z "''${ZELLIJ:-}" ]]; then
          print "zjm works inside Zellij. Run 'zj' first."
          return 1
        fi
        zellij run --floating --close-on-exit --width 86% --height 80% --x 7% --y 10% -- ${zellijMenu}/bin/zellij-menu
      }

      if [[ $- == *i* && $SHLVL -eq 1 ]]; then
        print ""
        print "bandit-lab TTY · run 'zj' for Zellij · inside it press Ctrl-Space then Space for menu · run 'zjh' for help"
        print ""
      fi
    '';
  };
}

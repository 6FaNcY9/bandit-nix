{pkgs, ...}: {
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
    '';
  };
}

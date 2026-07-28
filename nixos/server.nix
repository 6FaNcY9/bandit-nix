{
  lib,
  pkgs,
  repoConfig,
  ...
}: let
  # Bandit Retro base16 palette, shared with the workstation theme.
  c = repoConfig.serverPalette;
  zellijMenu = pkgs.writeShellScriptBin "zellij-menu" ''
    set -euo pipefail

    zellij=${lib.getExe pkgs.zellij}
    fzf=${lib.getExe pkgs.fzf}
    sed=${lib.getExe pkgs.gnused}

    result="$(
      printf '%s\n' \
        'New pane (auto)|n' \
        'Split pane down|d' \
        'Split pane right|r' \
        'New tab|t' \
        'Next tab|]' \
        'Previous tab|[' \
        'Focus next pane|Tab' \
        'Toggle fullscreen|f' \
        'Toggle floating panes|w' \
        'Toggle pane frames|z' \
        'Edit scrollback|e' \
        'Shortcut help|?' \
        'Tab switcher|R' \
        'Session manager|s' \
        'Plugin manager|p' \
        'Configuration|c' \
        'Close focused pane|x' \
        'Detach from Zellij|q' \
        'Exit menu|Esc' \
      | "$fzf" \
          --no-sort \
          --border=sharp \
          --prompt='zellij  ' \
          --delimiter='|' \
          --with-nth=1,2 \
          --expect='n,d,r,t,],\[,tab,f,w,z,e,?,R,s,p,c,x,q' \
          --bind='esc:abort'
    )" || exit 0

    key="$(printf '%s\n' "$result" | "$sed" -n '1p')"
    choice="$(printf '%s\n' "$result" | "$sed" -n '$p')"

    case "$key" in
      n) action='New pane (auto)' ;;
      d) action='Split pane down' ;;
      r) action='Split pane right' ;;
      t) action='New tab' ;;
      ']') action='Next tab' ;;
      '[') action='Previous tab' ;;
      tab) action='Focus next pane' ;;
      f) action='Toggle fullscreen' ;;
      w) action='Toggle floating panes' ;;
      z) action='Toggle pane frames' ;;
      e) action='Edit scrollback' ;;
      '?') action='Shortcut help' ;;
      R) action='Tab switcher' ;;
      s) action='Session manager' ;;
      p) action='Plugin manager' ;;
      c) action='Configuration' ;;
      x) action='Close focused pane' ;;
      q) action='Detach from Zellij' ;;
      *) action="''${choice%%|*}" ;;
    esac

    case "$action" in
      'New pane (auto)') "$zellij" action new-pane ;;
      'Split pane down') "$zellij" action new-pane --direction down ;;
      'Split pane right') "$zellij" action new-pane --direction right ;;
      'New tab') "$zellij" action new-tab ;;
      'Next tab') "$zellij" action go-to-next-tab ;;
      'Previous tab') "$zellij" action go-to-previous-tab ;;
      'Focus next pane') "$zellij" action focus-next-pane ;;
      'Toggle fullscreen') "$zellij" action toggle-fullscreen ;;
      'Toggle floating panes') "$zellij" action toggle-floating-panes ;;
      'Toggle pane frames') "$zellij" action toggle-pane-frames ;;
      'Edit scrollback') "$zellij" action edit-scrollback ;;
      'Shortcut help') "$zellij" action launch-or-focus-plugin --floating --move-to-focused-tab file:${zellijForgotWasm} ;;
      'Tab switcher') "$zellij" action launch-or-focus-plugin --floating --move-to-focused-tab file:${roomWasm} ;;
      'Session manager') "$zellij" action launch-or-focus-plugin --floating --move-to-focused-tab zellij:session-manager ;;
      'Plugin manager') "$zellij" action launch-or-focus-plugin --floating --move-to-focused-tab zellij:plugin-manager ;;
      'Configuration') "$zellij" action launch-or-focus-plugin --floating --move-to-focused-tab zellij:configuration ;;
      'Close focused pane') "$zellij" action close-pane ;;
      'Detach from Zellij') "$zellij" action detach ;;
      'Exit menu') exit 0 ;;
    esac
  '';

  zellijForgotWasm = pkgs.fetchurl {
    url = "https://github.com/karimould/zellij-forgot/releases/download/0.4.2/zellij_forgot.wasm";
    hash = "sha256-MRlBRVGdvcEoaFtFb5cDdDePoZ/J2nQvvkoyG6zkSds=";
  };

  roomWasm = pkgs.fetchurl {
    url = "https://github.com/rvcas/room/releases/download/v1.2.1/room.wasm";
    hash = "sha256-kLSDpAt2JGj7dYYhYFh6BfvtzVwTrcs+0jHwG/nActE=";
  };
in {
  imports = [
    ./sops.nix
    ./cli-tools.nix
    ./core.nix
    ./boot.nix
    ./network.nix
    ./firmware.nix
    ./users.nix
    ./server/editor.nix
  ];

  environment = {
    # ── Base server packages (no desktop/VM tools) ──────────────────────────
    systemPackages = with pkgs; [
      btop
      htop
      iotop
      lsof
      ncdu
      dnsutils
      fzf
      zoxide
      zellij
      zellijMenu
      starship
      zsh-autosuggestions
      zsh-fzf-tab
      zsh-syntax-highlighting
      brightnessctl
      libinput
    ];

    etc."xdg/zellij/config.kdl".text = ''
      theme "tomorrow-night-eighties"
      pane_frames true
      default_layout "compact"
      simplified_ui true

      keybinds {
          shared_except "locked" {
              bind "Ctrl Space" { SwitchToMode "Session"; }
          }

          session {
              bind "Ctrl Space" { SwitchToMode "Normal"; }
              bind "Space" {
                  Run "${zellijMenu}/bin/zellij-menu" {
                      floating true
                      close_on_exit true
                      width "86%"
                      height "80%"
                      x "7%"
                      y "10%"
                  }
                  SwitchToMode "Normal"
              }
              bind "?" {
                  LaunchOrFocusPlugin "file:${zellijForgotWasm}" {
                      "LOAD_ZELLIJ_BINDINGS" "false"
                      "open stable workspace" "run zj from the shell"
                      "key style" "press Ctrl-Space, release, then press the next key"
                      "do not use Ctrl-g for commands" "Ctrl-g only locks/unlocks Zellij"
                      "command menu" "Ctrl-Space, then Space"
                      "shortcut help" "Ctrl-Space, then ?"
                      "tab switcher" "Ctrl-Space, then r"
                      "new pane" "Ctrl-Space, Space, then n"
                      "split down" "Ctrl-Space, Space, then d"
                      "split right" "Ctrl-Space, Space, then r"
                      "new tab" "Ctrl-Space, Space, then t"
                      "next tab" "Ctrl-Space, Space, then ]"
                      "previous tab" "Ctrl-Space, Space, then ["
                      "close pane" "Ctrl-Space, Space, then x"
                      "detach" "Ctrl-Space, Space, then q"
                      "leave mode/menu" "Esc or Enter"
                      floating true
                  }
                  SwitchToMode "Normal"
              }
              bind "r" {
                  LaunchOrFocusPlugin "file:${roomWasm}" {
                      floating true
                      ignore_case true
                      quick_jump true
                  }
                  SwitchToMode "Normal"
              }
          }
      }

      plugins {
          compact-bar location="zellij:compact-bar" {
              tooltip "F1"
          }
          zellij-forgot location="file:${zellijForgotWasm}"
          room location="file:${roomWasm}"
      }

      themes {
          tomorrow-night-eighties {
              fg 213 196 161
              bg 45 45 45
              black 30 30 30
              red 242 119 122
              green 153 204 153
              yellow 255 204 102
              blue 102 153 204
              magenta 204 153 204
              cyan 102 204 204
              white 242 240 236
              orange 249 145 87
          }
      }
    '';

    # ── Remote access ──────────────────────────────────────────────────────
    enableAllTerminfo = true;
  };

  programs = {
    zsh = {
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

    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
    nh.enable = true;

    starship = {
      enable = true;
      settings = {
        palette = "stylix";

        palettes.stylix = {
          color_fg0 = c.base05;
          color_bg1 = c.base01;
          color_bg3 = c.base02;
          color_blue = c.base0D;
          color_aqua = c.base0C;
          color_green = c.base0B;
          color_orange = c.base09;
          color_purple = c.base0E;
          color_red = c.base08;
          color_yellow = c.base0A;
        };

        format = "$hostname$username$directory$git_branch$git_status$nix_shell$custom.net$time$cmd_duration$line_break$character";

        hostname = {
          ssh_only = false;
          style = "color_red bold";
          format = "[\\[$hostname\\]]($style) ";
        };

        username = {
          style_user = "color_green bold";
          style_root = "color_red bold";
          format = "[\\[$user\\]]($style) ";
          show_always = false;
        };

        directory = {
          style = "color_blue bold";
          format = "[\\[$path$read_only\\]]($style) ";
          truncation_length = 4;
          truncate_to_repo = false;
          read_only = " ro";
        };

        git_branch = {
          style = "color_yellow bold";
          format = "[\\[$symbol$branch\\]]($style) ";
          symbol = "";
        };

        git_status = {
          style = "color_red bold";
          conflicted = "!";
          ahead = "up\${count}";
          behind = "down\${count}";
          diverged = "up\${ahead_count}/down\${behind_count}";
          modified = "!";
          untracked = "?";
          staged = "+";
          deleted = "x";
          stashed = "stash";
          format = "[\\[$all_status$ahead_behind\\]]($style) ";
        };

        nix_shell = {
          format = "[\\[$symbol$state\\]]($style) ";
          style = "color_aqua bold";
          symbol = "nix:";
        };

        "custom.net" = {
          command = ''
            IFACE=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
            [[ -z "$IFACE" ]] && exit 1
            PREV="/tmp/starship-net-$IFACE"
            RX=$(awk -v i="$IFACE:" '$1==i {print $2}' /proc/net/dev)
            TX=$(awk -v i="$IFACE:" '$1==i {print $10}' /proc/net/dev)
            if [[ -f "$PREV" ]]; then
              read -r prev_rx prev_tx < "$PREV"
              DRX=$(( (RX - prev_rx) / 1024 ))
              DTX=$(( (TX - prev_tx) / 1024 ))
            else
              DRX=0; DTX=0
            fi
            echo "$RX $TX" > "$PREV"
            echo "↑''${DTX}k ↓''${DRX}k"
          '';
          when = "true";
          shell = ["bash" "-c"];
          format = "[\\[$output\\]](color_aqua bold) ";
        };

        time = {
          disabled = false;
          format = "[\\[$time\\]](color_purple bold) ";
          time_format = "%H:%M";
        };

        cmd_duration = {
          min_time = 1000;
          style = "color_orange bold";
          format = "[\\[$duration\\]]($style) ";
        };

        character = {
          success_symbol = "[\\$](color_green bold) ";
          error_symbol = "[\\$](color_red bold) ";
          vimcmd_symbol = "[\\$](color_yellow bold) ";
        };
      };
    };
  };

  fonts.packages = [pkgs.nerd-fonts.jetbrains-mono];

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # ── Memory ────────────────────────────────────────────────────────────────
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 25; # 16 GB zram out of 64 GB RAM
  };

  # ── BTRFS maintenance ─────────────────────────────────────────────────────
  services.btrfs.autoScrub = {
    enable = true;
    # Server keeps the same monthly cadence as the laptop; adjust per-host if disk churn increases.
    interval = "monthly";
    fileSystems = ["/"];
  };

  # ── Nix build capacity ────────────────────────────────────────────────────
  nix.settings = {
    max-jobs = 2;
    cores = 4;
  };
}

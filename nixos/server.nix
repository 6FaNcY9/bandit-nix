{
  inputs,
  lib,
  pkgs,
  ...
}: let
  retroTheme = import ../lib/retro-theme.nix;
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
    nixvim = {
      enable = true;
      defaultEditor = true;
      nixpkgs.source = inputs.nixpkgs;
      viAlias = true;
      vimAlias = true;

      plugins.lualine = {
        enable = true;
        settings.options = {
          component_separators = {
            left = "";
            right = "";
          };
          section_separators = {
            left = "";
            right = "";
          };
          globalstatus = true;
          theme = retroTheme.lualineTheme;
        };
      };
    };

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
        palette = "tomorrow_night_eighties";

        palettes.tomorrow_night_eighties = retroTheme.starshipPalette;

        format = "$hostname$username$directory$git_branch$git_status$nix_shell$cmd_duration$line_break$character";

        hostname = {
          ssh_only = false;
          style = "color_red bold";
          format = "[$hostname]($style) ";
        };

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
          read_only = " ro";
        };

        git_branch = {
          style = "color_yellow bold";
          format = "on [$symbol$branch]($style) ";
          symbol = "git:";
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
        };

        nix_shell = {
          format = "via [$symbol$state]($style) ";
          style = "color_aqua bold";
          symbol = "nix:";
        };

        cmd_duration = {
          min_time = 1000;
          style = "color_orange";
          format = "took [$duration]($style) ";
        };

        character = {
          success_symbol = "[＄](color_green bold) ";
          error_symbol = "[＄](color_red bold) ";
          vimcmd_symbol = "[＄](color_yellow bold) ";
        };
      };
    };
  };

  fonts.packages = [pkgs.nerd-fonts.jetbrains-mono];

  # Blank the local console after 5 minutes without keyboard/mouse input.
  boot.kernelParams = ["consoleblank=300"];

  # ── TTY-only server surface ───────────────────────────────────────────────
  services = {
    kmscon = {
      enable = true;
      useXkbConfig = true;
      config = {
        "font-name" = "JetBrainsMono Nerd Font Mono";
        "font-size" = 18;
        hwaccel = false;
      };
    };
  };

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  systemd.services.server-screen-idle = {
    description = "Turn off the laptop panel backlight after local input idle";
    wantedBy = ["multi-user.target"];
    after = ["systemd-udevd.service"];
    path = with pkgs; [
      brightnessctl
      coreutils
      libinput
    ];
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = "5s";
    };
    script = ''
      set -euo pipefail

      idle_seconds=300
      state_dir=/run/server-screen-idle
      mkdir -p "$state_dir"

      restore_screen() {
        local saved name value dpms
        for saved in "$state_dir"/*.dpms; do
          [[ -e "$saved" ]] || continue
          read -r dpms < "$saved" || continue
          [[ -w "$dpms" ]] && printf 'On\n' > "$dpms" || true
          rm -f "$saved"
        done

        for saved in "$state_dir"/*.brightness; do
          [[ -e "$saved" ]] || continue
          read -r name value < "$saved" || continue
          brightnessctl -q -d "$name" set "$value" || true
          rm -f "$saved"
        done
      }

      dim_screen() {
        local dev name current connector dpms status saved_name
        for dpms in /sys/class/drm/card*-*/dpms; do
          [[ -e "$dpms" && -w "$dpms" ]] || continue
          connector="$(dirname "$dpms")"
          status="$(cat "$connector/status" 2>/dev/null || true)"
          [[ "$status" == "connected" ]] || continue
          saved_name="$(basename "$connector")"
          printf '%s\n' "$dpms" > "$state_dir/$saved_name.dpms"
          printf 'Off\n' > "$dpms" || true
        done

        for dev in /sys/class/backlight/*; do
          [[ -e "$dev" ]] || continue
          name="$(basename "$dev")"
          current="$(brightnessctl -d "$name" get 2>/dev/null || true)"
          [[ -n "$current" && "$current" -gt 0 ]] || continue
          printf '%s %s\n' "$name" "$current" > "$state_dir/$name.brightness"
          brightnessctl -q -d "$name" set 0 || true
        done
      }

      trap restore_screen EXIT

      last_input="$(date +%s)"
      screen_dimmed=0

      while true; do
        if read -r -t 5 _event; then
          last_input="$(date +%s)"
          if [[ "$screen_dimmed" -eq 1 ]]; then
            restore_screen
            screen_dimmed=0
          fi

          while read -r -t 0 _event; do
            last_input="$(date +%s)"
          done
        fi

        now="$(date +%s)"
        if [[ "$screen_dimmed" -eq 0 && $((now - last_input)) -ge "$idle_seconds" ]]; then
          dim_screen
          screen_dimmed=1
        fi
      done < <(libinput debug-events --udev --show-keycodes)
    '';
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
    max-jobs = 16; # i9-14900HX: 24 physical / 32 logical cores; 16 is conservative, raise if builds are slow
    cores = 0;
  };
}

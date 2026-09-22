{
  lib,
  pkgs,
  repoConfig,
  ...
}: let
  # Bandit Retro base16 palette, shared with the workstation theme.
  c = repoConfig.serverPalette;
  # base16 hex → "r g b" for Zellij theme definitions.
  rgb = hex: let
    h = lib.removePrefix "#" hex;
    byte = i: toString (lib.fromHexString (builtins.substring i 2 h));
  in "${byte 0} ${byte 2} ${byte 4}";
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
  _module.args.zellijMenu = zellijMenu;

  environment.etc."xdg/zellij/config.kdl".text = ''
    theme "bandit-retro"
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
        bandit-retro {
            fg ${rgb c.base05}
            bg ${rgb c.base02}
            black ${rgb c.base01}
            red ${rgb c.base08}
            green ${rgb c.base0B}
            yellow ${rgb c.base0A}
            blue ${rgb c.base0D}
            magenta ${rgb c.base0E}
            cyan ${rgb c.base0C}
            white ${rgb c.base06}
            orange ${rgb c.base09}
        }
    }
  '';
}

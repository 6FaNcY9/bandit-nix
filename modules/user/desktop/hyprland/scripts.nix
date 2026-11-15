{
  pkgs,
  bandit,
  ...
}: {
  home = {
    file = {
      "Pictures/Screenshots/.keep".text = "";

      # ─── Region screenshot: select, then draw in satty; Enter copies + saves ───
      # grim + slurp instead of Flameshot: Flameshot 14 must capture through the
      # portal on Hyprland, about 0.8 s before its overlay even appears.
      ".local/bin/hypr-screenshot" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          set -euo pipefail
          dir="${bandit.workstation.homeDirectory}/Pictures/Screenshots"
          mkdir -p "$dir"
          region=$(${pkgs.slurp}/bin/slurp -d) || exit 0 # Esc cancels the selection
          ${pkgs.grim}/bin/grim -g "$region" - |
            ${pkgs.satty}/bin/satty --filename - \
              --output-filename "$dir/%Y-%m-%d_%H-%M-%S.png" \
              --copy-command ${pkgs.wl-clipboard}/bin/wl-copy \
              --actions-on-enter save-to-clipboard --save-after-copy --early-exit
        '';
      };

      # ─── Cockpit (Mod+C): master layout with a log pane, per workspace ───
      ".local/bin/hypr-cockpit" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          # Spike, Hyprland 0.56.2: a workspace_rule with layout re-tiles a live workspace at once, so Cockpit is per workspace.
          set -euo pipefail
          jq=${pkgs.jq}/bin/jq
          dir="''${XDG_RUNTIME_DIR:-/tmp}/hypr-cockpit"
          ws=$(hyprctl activeworkspace -j)
          id=$($jq .id <<<"$ws")
          # Empty workspace or a fullscreen window: nothing to do.
          [ "$($jq '.windows > 0 and (.hasfullscreen | not)' <<<"$ws")" = true ] || exit 0
          set_layout() { hyprctl eval "hl.workspace_rule({ workspace = \"$id\", layout = \"$1\" })" >/dev/null; }
          clients=$(hyprctl clients -j)

          # A state file without the master layout is stale: a config reload drops the rule.
          if [ -e "$dir/$id" ] && [ "$($jq -r .tiledLayout <<<"$ws")" = master ]; then
            set_layout dwindle
            $jq -r --argjson id "$id" '.[] | select(.workspace.id == $id and .class == "cockpit-log") | .address' <<<"$clients" |
              while read -r addr; do
                hyprctl dispatch "hl.dsp.window.close({ window = \"address:$addr\" })" >/dev/null
              done
            rm -f "$dir/$id"
          else
            # Only floating windows: nothing to tile, and a full-size log would become the only tile.
            read -r slots logs < <($jq -r --argjson id "$id" '
              [.[] | select(.workspace.id == $id and (.floating | not))]
              | "\([.[] | select(.class != "cockpit-log") | .grouped[0] // .address] | unique | length) \([.[] | select(.class == "cockpit-log")] | length)"
            ' <<<"$clients")
            [ "$slots" -gt 0 ] || exit 0
            set_layout master
            # The work window (most recently focused tiled non-log window) becomes master, never the log pane.
            # ignoremaster: a focused master stays; "master" would swap it out again.
            work=$($jq -r --argjson id "$id" '
              [.[] | select(.workspace.id == $id and (.floating | not) and (.hidden | not) and .class != "cockpit-log")]
              | sort_by(.focusHistoryID) | .[0].address // empty
            ' <<<"$clients")
            if [ -n "$work" ]; then
              hyprctl dispatch "hl.dsp.focus({ window = \"address:$work\" })" >/dev/null
              hyprctl dispatch 'hl.dsp.layout("swapwithmaster ignoremaster")' >/dev/null
            fi
            # One tiled window or group alone and no log yet: add the log pane (opens right).
            if [ "$slots" -le 1 ] && [ "$logs" -eq 0 ]; then
              setsid -f ${pkgs.kitty}/bin/kitty --class cockpit-log journalctl -f >/dev/null 2>&1
            fi
            mkdir -p "$dir"
            touch "$dir/$id"
          fi
        '';
      };

      # ─── Shortcut cheatsheet launcher (Mod+F1) ────────────
      ".local/bin/hyprland-cheatsheet-show" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          exec kitty --title 'Hyprland Shortcuts' \
            --override remember_window_size=no \
            --override initial_window_width=800 \
            --override initial_window_height=560 \
            bash -c 'cat ~/.local/bin/hyprland-cheatsheet | less -R'
        '';
      };

      # ─── Shortcut cheatsheet content (plain text, piped to less) ───────
      ".local/bin/hyprland-cheatsheet".text = ''
          ╔══════════════════════════════════════════════════════════╗
          ║        Hyprland Shortcuts  (Mod = Super / Win key)       ║
          ╚══════════════════════════════════════════════════════════╝

          LAUNCH
            Mod+Return          kitty (terminal)
            Mod+Shift+W         firefox
            Mod+D               rofi app launcher
            Mod+Shift+V         cliphist clipboard picker
            Mod+Shift+F         PCManFM file manager

          WINDOWS
            Mod+Shift+Q         kill focused window
            Mod+F               fullscreen toggle
        Mod+Ctrl+F          fullscreen without app mode
            Mod+Shift+Space     toggle float/tile
            Mod+Ctrl+Space      pin floating window
            Mod+A               focus current/last window
            Mod+Shift+X         lock screen

          FOCUS  (also works with arrow keys)
            Mod+J               focus left
            Mod+K               focus down
            Mod+L               focus up
            Mod+;               focus right

          MOVE  (also works with arrow keys)
            Mod+Shift+J         move/group left
            Mod+Shift+K         move/group down
            Mod+Shift+L         move/group up
            Mod+Shift+;         move/group right

          LAYOUT (dwindle)
            Mod+E               toggle split orientation
            Mod+V               next window opens below
            Mod+B               next window opens right
            Mod+Ctrl+E          swap split branches
            Mod+C               cockpit: master + log on/off
            Mod+S               toggle tab group
            Mod+Ctrl+S          lock active group
            Mod+P               toggle pseudotile

          GROUPS / STACKS
            Mod+Tab             next tab in group
            Mod+Shift+Tab       previous tab in group
            Mod+Ctrl+Tab        move tab forward in group
            Mod+Ctrl+Shift+Tab  move tab backward in group
            Mod+Ctrl+O          remove window from group

          RESIZE MODE  (Mod+R, then…)
            J/K/L/; or Arrows   resize window
            Return / Escape     exit resize mode

          WORKSPACES
            Mod+1…0             switch to workspace 1–10
            Mod+Shift+1…0       move window to workspace
            Mod+mouse wheel     cycle workspaces
            Mod+G               show/hide scratchpad
            Mod+Shift+G         move window to scratchpad

          MOUSE
            Mod+left drag       move window
            Mod+right drag      resize window

          NOTIFICATIONS (mako)
            Mod+`               restore last dismissed notification
            Mod+Shift+D         toggle do-not-disturb
            Mod+Shift+.         dismiss all notifications

          SCREENSHOTS
            Print / F11 / Mod+Shift+S   region screenshot, draw in satty (Enter = copy + save)

          MEDIA
            XF86AudioRaise/Lower  volume ±5%
            XF86AudioMute         mute toggle
            XF86MonBrightness+/-  screen brightness
            XF86AudioPlay/Next/Prev  media control

          HYPRLAND
            Mod+Shift+C         reload config
            Mod+F1              this help screen
            Mod+F2              keybinding search (rofi, incl. Neovim)
      '';
    };

    packages = [
      pkgs.grim
      pkgs.slurp
      pkgs.wl-clipboard
      pkgs.cliphist
      pkgs.libnotify
      pkgs.playerctl
      pkgs.brightnessctl
      pkgs.networkmanagerapplet
      pkgs.less
    ];
  };
}

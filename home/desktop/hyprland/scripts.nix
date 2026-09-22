{
  pkgs,
  repoConfig,
  ...
}: {
  home = {
    file = {
      "Pictures/Screenshots/.keep".text = "";

      # ─── Region screenshot: capture, save, copy, notify ───
      ".local/bin/hypr-screenshot" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          set -euo pipefail
          dir="${repoConfig.workstation.homeDirectory}/Pictures/Screenshots"
          mkdir -p "$dir"
          file="$dir/$(date +%Y-%m-%d_%H-%M-%S).png"
          ${pkgs.grim}/bin/grim -g "$(${pkgs.slurp}/bin/slurp)" "$file"
          ${pkgs.wl-clipboard}/bin/wl-copy < "$file"
          ${pkgs.libnotify}/bin/notify-send -a hypr-screenshot "Screenshot saved" "$file"
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
            Mod+Ctrl+E          swap split branches
            Mod+S               toggle tab group
            Mod+Shift+S         lock active group
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
            Print / F11         region screenshot (grim + slurp)

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

    packages = with pkgs; [
      grim
      slurp
      wl-clipboard
      cliphist
      libnotify
      playerctl
      brightnessctl
      networkmanagerapplet
      less
    ];
  };
}

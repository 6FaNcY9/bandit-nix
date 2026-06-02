_: {
  xfconf.settings = {
    # ── Terminal ──────────────────────────────────────────────────
    "xfce4-terminal" = {
      "color-use-theme" = false;
      "color-background" = "#2d2d2d";
      "color-foreground" = "#cccccc";
      "color-cursor" = "#cccccc";
      "color-bold-is-bright" = true;
      "scrollbar-style" = "TERMINAL_SCROLLBAR_NONE";
      "misc-slim-tabs" = true;
      # 16-color tomorrow-night-eighties palette
      "color-palette" = "#2d2d2d;#f2777a;#99cc99;#ffcc66;#6699cc;#cc99cc;#66cccc;#d3d0c8;#747369;#f2777a;#99cc99;#ffcc66;#6699cc;#cc99cc;#66cccc;#f2f0ec";
    };

    # ── Panel ─────────────────────────────────────────────────────
    # Layout (12 plugins):
    # [❄] │ [tasklist───expand───] │ [cpu][mem][net] │ [vol][bat][tray] │ [clock]
    "xfce4-panel" = {
      "panels" = [1];

      "panels/panel-1/position" = "p=6;x=0;y=0";
      "panels/panel-1/position-locked" = true;
      "panels/panel-1/length" = 100;
      "panels/panel-1/size" = 26;
      "panels/panel-1/nrows" = 1;
      "panels/panel-1/background-style" = 1;
      "panels/panel-1/background-color" = "#2d2d2d";
      "panels/panel-1/enter-opacity" = 100;
      "panels/panel-1/leave-opacity" = 100;

      # Layout (14 plugins):
      # [❄] │ [tasklist w/ labels ──expand──] │ [cpu][mem][net] │ [vol][bat] │ [pager] │ [clock] │ [tray]
      "panels/panel-1/plugin-ids" = [1 2 3 4 5 6 7 8 9 10 11 12 13 14];

      # ── Plugin type registration ────────────────────────────────
      "plugins/plugin-1" = "whiskermenu";
      "plugins/plugin-2" = "separator";
      "plugins/plugin-3" = "tasklist";
      "plugins/plugin-4" = "separator";
      "plugins/plugin-5" = "genmon";
      "plugins/plugin-6" = "genmon";
      "plugins/plugin-7" = "genmon";
      "plugins/plugin-8" = "separator";
      "plugins/plugin-9" = "pulseaudio";
      "plugins/plugin-10" = "battery";
      "plugins/plugin-11" = "pager";
      "plugins/plugin-12" = "separator";
      "plugins/plugin-13" = "clock";
      "plugins/plugin-14" = "systray";

      # ── Whiskermenu — icon-only ❄ button ───────────────────────
      "plugins/plugin-1/show-button-title" = false;
      "plugins/plugin-1/show-button-icon" = true;
      "plugins/plugin-1/button-icon" = "nix-snowflake";

      # ── Separators ─────────────────────────────────────────────
      "plugins/plugin-2/style" = 1; # handle line
      "plugins/plugin-2/expand" = false;
      "plugins/plugin-4/style" = 0; # transparent
      "plugins/plugin-4/expand" = true; # pushes right group
      "plugins/plugin-8/style" = 1; # handle line

      # ── Tasklist — labeled grouped flat buttons ─────────────────
      "plugins/plugin-3/grouping" = 1;
      "plugins/plugin-3/show-labels" = true;
      "plugins/plugin-3/include-all-workspaces" = false;
      "plugins/plugin-3/flat-buttons" = true;
      "plugins/plugin-3/show-handle" = false;
      "plugins/plugin-3/show-only-minimized" = false;

      # ── Genmon — cpu/mem/net scripts ───────────────────────────
      # Both cases needed: genmon reads lowercase 'command', home-manager sets uppercase
      "plugins/plugin-5/Command" = "/home/vino/.local/bin/panel-cpu";
      "plugins/plugin-5/command" = "/home/vino/.local/bin/panel-cpu";
      "plugins/plugin-5/UpdatePeriod" = 2000;
      "plugins/plugin-5/UseLabel" = false;
      "plugins/plugin-6/Command" = "/home/vino/.local/bin/panel-mem";
      "plugins/plugin-6/command" = "/home/vino/.local/bin/panel-mem";
      "plugins/plugin-6/UpdatePeriod" = 3000;
      "plugins/plugin-6/UseLabel" = false;
      "plugins/plugin-7/Command" = "/home/vino/.local/bin/panel-net";
      "plugins/plugin-7/command" = "/home/vino/.local/bin/panel-net";
      "plugins/plugin-7/UpdatePeriod" = 2000;
      "plugins/plugin-7/UseLabel" = false;

      # ── Battery — icon + percentage only ───────────────────────
      "plugins/plugin-10/show-percentage" = true;
      "plugins/plugin-10/show-time" = false;
      "plugins/plugin-10/show-icon" = true;
      "plugins/plugin-10/show-label" = false;

      # ── Pager — workspace minimap ───────────────────────────────
      "plugins/plugin-11/rows" = 1;
      "plugins/plugin-11/miniature-view" = true;

      # ── Separator before clock — thin line ──────────────────────
      "plugins/plugin-12/style" = 1;
      "plugins/plugin-12/expand" = false;

      # ── Clock — yellow, date + time, bracketed ──────────────────
      "plugins/plugin-13/digital-format" = "[ <span color='#ffcc66'>%a %d  %H:%M</span> ]";
      "plugins/plugin-13/digital-font" = "JetBrainsMono Nerd Font 11";
      "plugins/plugin-13/tooltip-format" = "%A %d %B %Y  –  week %V";
      "plugins/plugin-13/mode" = 2;
    };

    # ── Thunar file manager ───────────────────────────────────────
    "thunar" = {
      "last-view" = "ThunarDetailsView";
      "last-show-hidden" = true;
      "misc-single-click" = false;
      "misc-open-new-windows-in-tab" = true;
      "misc-thumbnail-mode" = "THUNAR_THUMBNAIL_MODE_ALWAYS";
      "misc-file-size-binary" = true;
      "misc-date-style" = "THUNAR_DATE_STYLE_SIMPLE";
      "misc-confirm-move-to-trash" = false;
    };

    # ── Icon theme (Papirus-Dark for GTK apps incl. Thunar) ──────
    "xsettings" = {
      "Net/IconThemeName" = "Papirus-Dark";
    };

    # ── Power manager ─────────────────────────────────────────────
    "xfce4-power-manager" = {
      "/xfce4-power-manager/lock-screen-suspend-hibernate" = true;
      # 0 = nothing — i3 binds XF86PowerOff to the rofi power menu instead
      "/xfce4-power-manager/power-button-action" = 0;
    };

    # ── xfwm4 (disabled as WM, but its compositor can still run) ──
    "xfwm4" = {
      "/general/use_compositing" = false;
    };

    # ── Notification daemon appearance ────────────────────────────
    # Note: xfce4-notifyd is disabled via autostart override below.
    # dunst handles notifications instead.
    "xfce4-notifyd" = {
      "notify-location" = 1; # top-right
      "expire-timeout" = 8000;
      "initial-opacity" = 0.95;
      "do-fadeout" = true;
    };
  };

  # Prevent xfce4-notifyd from starting so dunst can own org.freedesktop.Notifications
  xdg.configFile."autostart/xfce4-notifyd.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Xfce Notification Daemon
    Hidden=true
  '';

  # Whiskermenu menu appearance
  xdg.configFile."xfce4/panel/whiskermenu-1.rc".text = ''
    button-title=bandit
    button-icon=nix-snowflake
    show-button-icon=true
    show-button-title=true
    background-opacity=95
    item-icon-size=16
    category-icon-size=16
    position-search-alternate=true
    recent-items-max=5
    show-recent-always=false
  '';
}

_: {
  xfconf.settings = {
    # ── Terminal ──────────────────────────────────────────────────
    "xfce4-terminal" = {
      "color-use-theme" = false;
      "color-background" = "#272727";
      "color-foreground" = "#ebdbb2";
      "color-cursor" = "#ebdbb2";
      "color-bold-is-bright" = true;
      "scrollbar-style" = "TERMINAL_SCROLLBAR_NONE";
      "misc-slim-tabs" = true;
      # 16-color gruvbox dark palette
      "color-palette" = "#282828;#cc241d;#98971a;#d79921;#458588;#b16286;#689d6a;#a89984;#928374;#fb4934;#b8bb26;#fabd2f;#83a598;#d3869b;#8ec07c;#ebdbb2";
    };

    # ── Panel ─────────────────────────────────────────────────────
    "xfce4-panel" = {
      "panels" = [1];

      "panels/panel-1/position" = "p=6;x=0;y=0";
      "panels/panel-1/position-locked" = true;
      "panels/panel-1/length" = 100;
      "panels/panel-1/size" = 30;
      "panels/panel-1/background-style" = 1;
      "panels/panel-1/background-color" = "#111111";

      "panels/panel-1/plugin-ids" = [1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18];

      # ── Plugin type registration ────────────────────────────────
      "plugins/plugin-1" = "whiskermenu";
      "plugins/plugin-2" = "separator";
      "plugins/plugin-3" = "tasklist";
      "plugins/plugin-4" = "separator";
      "plugins/plugin-5" = "genmon";
      "plugins/plugin-6" = "genmon";
      "plugins/plugin-7" = "genmon";
      "plugins/plugin-8" = "sensors";
      "plugins/plugin-9" = "separator";
      "plugins/plugin-10" = "pager";
      "plugins/plugin-11" = "separator";
      "plugins/plugin-12" = "pulseaudio";
      "plugins/plugin-13" = "battery";
      "plugins/plugin-14" = "netload";
      "plugins/plugin-15" = "power-manager-plugin";
      "plugins/plugin-16" = "screenshooter";
      "plugins/plugin-17" = "systray";
      "plugins/plugin-18" = "clock";

      # ── Whiskermenu — ❄ bandit button ──────────────────────────
      "plugins/plugin-1/show-button-title" = true;
      "plugins/plugin-1/button-title" = "bandit";
      "plugins/plugin-1/show-button-icon" = true;
      "plugins/plugin-1/button-icon" = "nix-snowflake";

      # ── Separators ─────────────────────────────────────────────
      "plugins/plugin-2/style" = 1;
      "plugins/plugin-2/expand" = false;
      "plugins/plugin-4/style" = 0;
      "plugins/plugin-4/expand" = true;
      "plugins/plugin-9/style" = 1;
      "plugins/plugin-11/style" = 1;

      # ── Tasklist — flat icon+label buttons ─────────────────────
      "plugins/plugin-3/grouping" = 0;
      "plugins/plugin-3/show-labels" = true;
      "plugins/plugin-3/include-all-workspaces" = false;
      "plugins/plugin-3/flat-buttons" = true;
      "plugins/plugin-3/show-handle" = false;

      # ── Genmon — net/cpu/mem scripts ───────────────────────────
      "plugins/plugin-5/Command" = "/home/vino/.local/bin/panel-net";
      "plugins/plugin-5/UpdatePeriod" = 2000;
      "plugins/plugin-5/UseLabel" = false;
      "plugins/plugin-6/Command" = "/home/vino/.local/bin/panel-cpu";
      "plugins/plugin-6/UpdatePeriod" = 2000;
      "plugins/plugin-6/UseLabel" = false;
      "plugins/plugin-7/Command" = "/home/vino/.local/bin/panel-mem";
      "plugins/plugin-7/UpdatePeriod" = 3000;
      "plugins/plugin-7/UseLabel" = false;

      # ── Pager ───────────────────────────────────────────────────
      "plugins/plugin-10/rows" = 1;
      "plugins/plugin-10/miniature-view" = true;

      # ── Clock ───────────────────────────────────────────────────
      "plugins/plugin-18/digital-format" = "%a %H:%M";
      "plugins/plugin-18/tooltip-format" = "%A %d %B %Y";
      "plugins/plugin-18/mode" = 2;
    };

    # ── Thunar file manager ───────────────────────────────────────
    "thunar" = {
      "last-view" = "ThunarDetailsView";
      "last-show-hidden" = false;
      "misc-single-click" = false;
      "misc-thumbnail-mode" = "THUNAR_THUMBNAIL_MODE_ALWAYS";
      "misc-file-size-binary" = true;
      "misc-date-style" = "THUNAR_DATE_STYLE_SIMPLE";
    };

    # ── Icon theme (Papirus-Dark for GTK apps incl. Thunar) ──────
    "xsettings" = {
      "Net/IconThemeName" = "Papirus-Dark";
    };

    # ── Notification daemon appearance ────────────────────────────
    "xfce4-notifyd" = {
      "notify-location" = 1; # top-right
      "expire-timeout" = 8000;
      "initial-opacity" = 0.95;
      "do-fadeout" = true;
    };
  };

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

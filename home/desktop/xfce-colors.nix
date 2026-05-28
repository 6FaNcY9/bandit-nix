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
      # Declare panel 1 as the only panel
      "panels" = [1];

      # Panel geometry and appearance
      "panels/panel-1/position" = "p=6;x=0;y=0"; # top, full width
      "panels/panel-1/position-locked" = true;
      "panels/panel-1/length" = 100;
      "panels/panel-1/size" = 30;
      "panels/panel-1/background-style" = 1; # solid color
      "panels/panel-1/background-color" = "#111111";

      # Plugin ordering (IDs 1–12)
      "panels/panel-1/plugin-ids" = [1 2 3 4 5 6 7 8 9 10 11 12];

      # ── Plugin type registration ────────────────────────────────
      "plugins/plugin-1" = "applicationsmenu";
      "plugins/plugin-2" = "separator";
      "plugins/plugin-3" = "tasklist";
      "plugins/plugin-4" = "separator"; # spacer
      "plugins/plugin-5" = "systemload";
      "plugins/plugin-6" = "separator";
      "plugins/plugin-7" = "genmon";
      "plugins/plugin-8" = "separator";
      "plugins/plugin-9" = "pager";
      "plugins/plugin-10" = "separator";
      "plugins/plugin-11" = "systray";
      "plugins/plugin-12" = "clock";

      # ── App menu ───────────────────────────────────────────────
      "plugins/plugin-1/show-button-title" = true;
      "plugins/plugin-1/button-title" = "▸ apps";
      "plugins/plugin-1/show-button-icon" = false;

      # ── Separators ─────────────────────────────────────────────
      # style: 0=transparent, 1=separator line, 2=handle
      "plugins/plugin-2/style" = 1;
      "plugins/plugin-2/expand" = false;
      "plugins/plugin-4/style" = 0; # transparent spacer
      "plugins/plugin-4/expand" = true; # pushes right block to edge
      "plugins/plugin-6/style" = 1;
      "plugins/plugin-8/style" = 1;
      "plugins/plugin-10/style" = 1;

      # ── Tasklist — current workspace only, no grouping ─────────
      "plugins/plugin-3/grouping" = 0;
      "plugins/plugin-3/show-labels" = true;
      "plugins/plugin-3/include-all-workspaces" = false;
      "plugins/plugin-3/flat-buttons" = true;

      # ── Genmon — panel-netmon script, 1s refresh ───────────────
      "plugins/plugin-7/Command" = "/home/vino/.local/bin/panel-netmon";
      "plugins/plugin-7/update-period" = 1000;

      # ── Pager — 1 row of mini workspace squares ─────────────────
      "plugins/plugin-9/rows" = 1;
      "plugins/plugin-9/miniature-view" = true;

      # ── Clock — compact digital format ─────────────────────────
      "plugins/plugin-12/digital-format" = "%a %H:%M";
      "plugins/plugin-12/tooltip-format" = "%A %d %B %Y";
      "plugins/plugin-12/mode" = 2; # 0=analog, 1=binary, 2=digital
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
}

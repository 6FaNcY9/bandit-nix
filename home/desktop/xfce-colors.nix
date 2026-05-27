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
    # Sets background color to match wallpaper (#272727).
    # background-style: 0=none, 1=solid color, 2=image
    "xfce4-panel" = {
      "panels/panel-1/background-style" = 1;
      "panels/panel-1/background-color" = "#272727ff";
      "panels/panel-1/size" = 30;
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

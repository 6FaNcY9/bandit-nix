{pkgs, ...}: {
  services.dunst = {
    enable = true;

    iconTheme = {
      package = pkgs.papirus-icon-theme;
      name = "Papirus-Dark";
      size = "32x32";
    };

    settings = {
      global = {
        # ── Layout ──────────────────────────────────────────────
        width = "(200, 380)";
        height = 200;
        origin = "top-right";
        offset = "12x40";
        scale = 0;
        notification_limit = 5;
        gap_size = 4;

        # ── Appearance ──────────────────────────────────────────
        corner_radius = 0;
        frame_width = 2;
        frame_color = "#6699cc";
        separator_height = 1;
        separator_color = "frame";
        padding = 12;
        horizontal_padding = 14;
        text_icon_padding = 10;

        # ── Progress bar ────────────────────────────────────────
        progress_bar = true;
        progress_bar_height = 8;
        progress_bar_frame_width = 1;
        progress_bar_min_width = 150;
        progress_bar_max_width = 350;
        progress_bar_corner_radius = 0;

        # ── Typography ──────────────────────────────────────────
        font = "JetBrainsMono Nerd Font 10";
        line_height = 2;
        markup = "full";
        format = "<b>%s</b>\\n<span foreground='#999999'>%b</span>";
        alignment = "left";
        vertical_alignment = "center";
        show_age_threshold = 60;
        ellipsize = "middle";
        word_wrap = true;
        stack_duplicates = true;
        hide_duplicate_count = false;
        show_indicators = true;

        # ── Icons ───────────────────────────────────────────────
        enable_recursive_icon_lookup = true;
        icon_position = "left";
        min_icon_size = 0;
        max_icon_size = 32;

        # ── History / timing ────────────────────────────────────
        sort = true;
        idle_threshold = 120;

        # ── Actions ─────────────────────────────────────────────
        dmenu = "${pkgs.rofi}/bin/rofi -dmenu -p dunst";
        browser = "${pkgs.firefox}/bin/firefox";
        always_run_script = true;
        title = "Dunst";
        class = "Dunst";
        follow = "mouse";
        mouse_left_click = "close_current";
        mouse_middle_click = "do_action, close_current";
        mouse_right_click = "close_all";
      };

      urgency_low = {
        background = "#2d2d2d";
        foreground = "#999999";
        frame_color = "#393939";
        highlight = "#999999";
        timeout = 5;
      };

      urgency_normal = {
        background = "#2d2d2d";
        foreground = "#cccccc";
        frame_color = "#6699cc";
        highlight = "#6699cc";
        timeout = 10;
      };

      urgency_critical = {
        background = "#2d2d2d";
        foreground = "#f2777a";
        frame_color = "#f2777a";
        highlight = "#f2777a";
        timeout = 0;
      };
    };
  };
}

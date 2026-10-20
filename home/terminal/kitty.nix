{config, ...}: let
  r = config.bandit.theme.roles;
in {
  programs.kitty = {
    enable = true;

    # Stylix manages base colors and font; tab chrome comes from the palette
    # roles. Everything else here is behavior only.

    shellIntegration = {
      enableZshIntegration = true;
      # lets kitty track cwd, mark prompts, jump between commands
      mode = "enabled";
    };

    settings = {
      # ── Ligatures ────────────────────────────────────────────
      # FiraCode's programming ligatures (=>, !=, >=) stay enabled.
      disable_ligatures = "never";

      # ── Scrollback ─────────────────────────────────────────
      scrollback_lines = 10000;
      scrollback_pager_history_size = 0; # Keep terminal history in memory only.

      # ── Cursor ─────────────────────────────────────────────
      cursor_shape = "block";
      cursor_blink_interval = "0.6";
      cursor_trail = 1;

      # ── URL handling ───────────────────────────────────────
      detect_urls = "yes";
      url_style = "curly";
      open_url_with = "xdg-open";

      # ── Mouse ──────────────────────────────────────────────
      mouse_hide_wait = "3.0";
      copy_on_select = "no"; # Copy explicitly to avoid persisting selected secrets.
      focus_follows_mouse = "yes";

      # ── Performance ────────────────────────────────────────
      repaint_delay = 10; # ms — smooth at 100 fps
      input_delay = 3;
      sync_to_monitor = "yes";

      # ── Bell ───────────────────────────────────────────────
      enable_audio_bell = "no";
      visual_bell_duration = "0.0";

      # ── Window ─────────────────────────────────────────────
      window_padding_width = 6;
      hide_window_decorations = "yes";
      confirm_os_window_close = 0; # no "are you sure?" dialog

      # ── Tab bar ────────────────────────────────────────────
      tab_bar_edge = "top";
      tab_bar_style = "separator";
      tab_separator = " ┃ ";
      tab_title_template = "{index}│{title}";
      tab_bar_min_tabs = "2";
      tab_bar_background = r.bg;
      active_tab_foreground = r.bg;
      active_tab_background = r.accent;
      active_tab_font_style = "bold";
      inactive_tab_foreground = r.dim;
      inactive_tab_background = r.surface;
      inactive_tab_font_style = "normal";
      tab_bar_margin_color = r.bg;

      # ── Misc ───────────────────────────────────────────────
      strip_trailing_spaces = "smart";
      # enable remote control (kitty @ ...) for scripting
      allow_remote_control = "socket-only";
      listen_on = "unix:\${XDG_RUNTIME_DIR}/kitty-{kitty_pid}";
    };

    keybindings = {
      # Font size
      "ctrl+shift+equal" = "change_font_size all +1.0";
      "ctrl+shift+minus" = "change_font_size all -1.0";
      "ctrl+shift+backspace" = "change_font_size all 0";

      # Scrollback
      "ctrl+shift+h" = "show_scrollback";
      "ctrl+shift+g" = "show_last_command_output";

      # Tabs
      "ctrl+shift+t" = "new_tab_with_cwd";
      "ctrl+shift+w" = "close_tab";
      "ctrl+shift+right" = "next_tab";
      "ctrl+shift+left" = "previous_tab";
      "ctrl+shift+l" = "next_tab";
      "ctrl+shift+j" = "previous_tab";

      # Windows
      "ctrl+shift+enter" = "new_window_with_cwd";
      "ctrl+shift+]" = "next_window";
      "ctrl+shift+[" = "previous_window";

      # Hints — open URLs / copy paths without mouse
      "ctrl+shift+e" = "open_url_with_hints";
      "ctrl+shift+p>f" = "kitten hints --type path --program -"; # copy path
      "ctrl+shift+p>l" = "kitten hints --type line --program -"; # copy line

      # Clipboard
      "ctrl+shift+c" = "copy_to_clipboard";
      "ctrl+shift+v" = "paste_from_clipboard";

      # New window/tab in current directory
      "ctrl+shift+n" = "new_os_window_with_cwd";

      # Unicode character picker
      "ctrl+shift+u" = "kitten unicode_input";

      # Config reload
      "ctrl+shift+f5" = "load_config_file";
    };
  };
}

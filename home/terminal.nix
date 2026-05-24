_: {
  programs.kitty = {
    enable = true;

    # Stylix manages colors (gruvbox-dark-hard) and font (JetBrainsMono Nerd Font)
    # so we only configure behavior here

    shellIntegration = {
      enableFishIntegration = true;
      # lets kitty track cwd, mark prompts, jump between commands
      mode = "enabled";
    };

    settings = {
      # ── Scrollback ─────────────────────────────────────────
      scrollback_lines = 10000;
      scrollback_pager_history_size = 4; # MB on disk for very long sessions

      # ── Cursor ─────────────────────────────────────────────
      cursor_shape = "beam";
      cursor_blink_interval = "0.5";
      cursor_trail = 3; # subtle animated trail

      # ── URL handling ───────────────────────────────────────
      detect_urls = "yes";
      url_style = "curly";
      open_url_with = "xdg-open";

      # ── Mouse ──────────────────────────────────────────────
      mouse_hide_wait = "3.0";
      copy_on_select = "clipboard"; # primary + clipboard on select
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
      confirm_os_window_close = 0; # no "are you sure?" dialog

      # ── Tab bar ────────────────────────────────────────────
      tab_bar_style = "powerline";
      tab_powerline_style = "slanted";
      tab_title_template = "{index}: {title}";

      # ── Misc ───────────────────────────────────────────────
      strip_trailing_spaces = "smart";
      # enable remote control (kitty @ ...) for scripting
      allow_remote_control = "socket-only";
      listen_on = "unix:/tmp/kitty-{kitty_pid}";
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

      # Config reload
      "ctrl+shift+f5" = "load_config_file";
    };
  };
}

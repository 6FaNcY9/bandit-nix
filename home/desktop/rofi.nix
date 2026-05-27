{pkgs, ...}: let
  # Gruvbox dark palette
  bg = "#282828";
  bg1 = "#3c3836";
  bg2 = "#504945";
  bg3 = "#665c54";
  fg = "#ebdbb2";
  fg2 = "#d5c4a1";
  fg4 = "#a89984";
  blue = "#458588";
  red = "#cc241d";
in {
  # Write theme to rofi themes dir so it can be referenced by name
  xdg.configFile."rofi/themes/gruvbox-dark.rasi".text = ''
    * {
        background-color: transparent;
        text-color:       ${fg};
    }

    window {
        background-color: ${bg};
        border:           2px;
        border-color:     ${blue};
        border-radius:    0;
        width:            600px;
        padding:          0;
    }

    mainbox {
        spacing:   0;
        padding:   0;
        children:  [ inputbar, message, listview ];
    }

    inputbar {
        background-color: ${bg1};
        border:           0 0 2px 0;
        border-color:     ${blue};
        padding:          8px 12px;
        spacing:          8px;
        children:         [ prompt, entry ];
    }

    prompt {
        background-color: transparent;
        text-color:       ${blue};
        font:             "JetBrainsMono Nerd Font Bold 11";
    }

    entry {
        background-color: transparent;
        text-color:       ${fg};
        placeholder:      "type to search...";
        placeholder-color: ${fg4};
        cursor:           text;
    }

    message {
        background-color: ${bg1};
        border:           0 0 1px 0;
        border-color:     ${bg2};
        padding:          4px 12px;
    }

    textbox {
        text-color: ${fg4};
        font:       "JetBrainsMono Nerd Font 9";
    }

    listview {
        background-color: ${bg};
        border:           0;
        padding:          4px 0;
        spacing:          0;
        lines:            10;
        scrollbar:        false;
        fixed-height:     true;
    }

    element {
        background-color: transparent;
        border:           0;
        border-radius:    0;
        padding:          6px 12px;
        spacing:          8px;
        orientation:      horizontal;
    }

    element.normal.normal {
        background-color: transparent;
        text-color:       ${fg2};
    }

    element.normal.urgent {
        background-color: transparent;
        text-color:       ${red};
    }

    element.normal.active {
        background-color: transparent;
        text-color:       ${blue};
    }

    element.selected.normal {
        background-color: ${bg2};
        text-color:       ${fg};
        border:           0 0 0 3px;
        border-color:     ${blue};
    }

    element.selected.urgent {
        background-color: ${red};
        text-color:       ${fg};
    }

    element.selected.active {
        background-color: ${bg2};
        text-color:       ${blue};
    }

    element.alternate.normal {
        background-color: transparent;
        text-color:       ${fg2};
    }

    element-icon {
        size:             22px;
        background-color: transparent;
    }

    element-text {
        background-color: transparent;
        vertical-align:   0.5;
    }

    scrollbar {
        background-color: ${bg1};
        handle-color:     ${bg3};
        handle-width:     8px;
        border:           0;
    }
  '';

  programs.rofi = {
    enable = true;
    package = pkgs.rofi;
    theme = "gruvbox-dark";

    extraConfig = {
      modi = "drun,run,window";
      show-icons = true;
      drun-display-format = "{name}";
      display-drun = " apps";
      display-run = " run";
      display-window = " windows";
      terminal = "${pkgs.xfce4-terminal}/bin/xfce4-terminal";
      sort = true;
      matching = "fuzzy";
      tokenize = true;
    };
  };
}

{pkgs, ...}: let
  # tomorrow-night-eighties palette
  bg = "#2d2d2d";
  bg1 = "#393939";
  bg2 = "#515151";
  fg = "#cccccc";
  fg2 = "#999999";
  yellow = "#ffcc66";
  blue = "#6699cc";
  red = "#f2777a";
  cyan = "#66cccc";
in {
  # ── Main launcher theme ───────────────────────────────────────
  xdg.configFile."rofi/themes/retro-eighties.rasi".text = ''
    * {
        background-color: transparent;
        text-color:       ${fg};
    }

    window {
        background-color: ${bg};
        border:           2px;
        border-color:     ${yellow};
        border-radius:    0;
        width:            640px;
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
        border-color:     ${yellow};
        padding:          10px 14px;
        spacing:          8px;
        children:         [ prompt, entry ];
    }

    prompt {
        background-color: transparent;
        text-color:       ${cyan};
        font:             "JetBrainsMono Nerd Font Bold 11";
    }

    entry {
        background-color: transparent;
        text-color:       ${fg};
        placeholder:      "type to search…";
        placeholder-color: ${fg2};
        cursor:           text;
    }

    message {
        background-color: ${bg1};
        border:           0 0 1px 0;
        border-color:     ${bg2};
        padding:          4px 14px;
    }

    textbox {
        text-color: ${fg2};
        font:       "JetBrainsMono Nerd Font 9";
    }

    listview {
        background-color: ${bg};
        border:           0;
        padding:          6px 0;
        spacing:          0;
        lines:            12;
        scrollbar:        false;
        fixed-height:     true;
    }

    element {
        background-color: transparent;
        border:           0;
        border-radius:    0;
        padding:          8px 14px;
        spacing:          10px;
        orientation:      horizontal;
    }

    element.normal.normal {
        background-color: transparent;
        text-color:       ${fg};
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
        background-color: ${bg1};
        text-color:       ${yellow};
        border:           0 0 0 4px;
        border-color:     ${yellow};
    }

    element.selected.urgent {
        background-color: ${red};
        text-color:       ${bg};
    }

    element.selected.active {
        background-color: ${bg1};
        text-color:       ${blue};
        border:           0 0 0 4px;
        border-color:     ${blue};
    }

    element.alternate.normal {
        background-color: transparent;
        text-color:       ${fg};
    }

    element-icon {
        size:             22px;
        background-color: transparent;
    }

    element-text {
        background-color: transparent;
        vertical-align:   0.5;
    }
  '';

  # ── Power-menu theme (narrower, centered) ─────────────────────
  xdg.configFile."rofi/themes/retro-power.rasi".text = ''
    * {
        background-color: transparent;
        text-color:       ${fg};
    }

    window {
        background-color: ${bg};
        border:           2px;
        border-color:     ${red};
        border-radius:    0;
        width:            280px;
        padding:          0;
        location:         center;
        anchor:           center;
    }

    mainbox {
        spacing:   0;
        padding:   0;
        children:  [ inputbar, listview ];
    }

    inputbar {
        background-color: ${bg1};
        border:           0 0 2px 0;
        border-color:     ${red};
        padding:          8px 14px;
        children:         [ prompt ];
    }

    prompt {
        background-color: transparent;
        text-color:       ${red};
        font:             "JetBrainsMono Nerd Font Bold 11";
    }

    listview {
        background-color: ${bg};
        padding:          6px 0;
        spacing:          0;
        lines:            5;
        scrollbar:        false;
        fixed-height:     true;
    }

    element {
        padding:          8px 18px;
        spacing:          10px;
        font:             "JetBrainsMono Nerd Font 11";
    }

    element.normal.normal {
        text-color: ${fg};
    }

    element.selected.normal {
        background-color: ${bg1};
        text-color:       ${red};
        border:           0 0 0 4px;
        border-color:     ${red};
    }
  '';

  programs.rofi = {
    enable = true;
    package = pkgs.rofi;
    theme = "retro-eighties";

    extraConfig = {
      modi = "drun,run,window";
      show-icons = true;
      drun-display-format = "{name}";
      display-drun = " apps";
      display-run = " run";
      display-window = " windows";
      terminal = "${pkgs.kitty}/bin/kitty";
      sort = true;
      matching = "fuzzy";
      tokenize = true;
    };
  };
}

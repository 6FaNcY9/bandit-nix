{
  config,
  pkgs,
  ...
}: let
  colors = config.lib.stylix.colors.withHashtag;
  bg = colors.base00;
  bg1 = colors.base01;
  bg2 = colors.base02;
  fg = colors.base05;
  fg2 = colors.base03;
  blue = colors.base0D;
  red = colors.base08;
  green = colors.base0B;
  interfaceFont = config.stylix.fonts.sansSerif.name;
  # One size for every menu: Stylix popups (also notifications, tooltips).
  font = "${interfaceFont} ${toString config.stylix.fonts.sizes.popups}";
  boldFont = "${interfaceFont} Bold ${toString config.stylix.fonts.sizes.popups}";
in {
  # ── Main launcher theme ───────────────────────────────────────
  xdg.configFile."rofi/themes/retro-eighties.rasi".text = ''
    * {
        background-color: transparent;
        text-color:       ${fg};
    }

    window {
        background-color: ${bg};
        border:           3px;
        border-color:     ${blue};
        border-radius:    8px;
        width:            44em;
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
        border-color:     ${bg2};
        padding:          10px 14px;
        spacing:          8px;
        children:         [ prompt, entry ];
    }

    prompt {
        background-color: transparent;
        text-color:       ${blue};
        font:             "${boldFont}";
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
        font:       "${font}";
    }

    listview {
        background-color: ${bg};
        border:           0;
        padding:          6px 6px;
        spacing:          0;
        lines:            10;
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
        text-color:       ${green};
    }

    element.selected.normal {
        background-color: ${blue};
        text-color:       ${bg};
        border-radius:    6px;
    }

    element.selected.urgent {
        background-color: ${red};
        text-color:       ${bg};
    }

    element.selected.active {
        background-color: ${green};
        text-color:       ${bg};
        border-radius:    6px;
    }

    element.alternate.normal {
        background-color: transparent;
        text-color:       ${fg};
    }

    element-icon {
        size:             1.4em;
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
        border:           3px;
        border-color:     ${red};
        border-radius:    8px;
        width:            14em;
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
        font:             "${boldFont}";
    }

    listview {
        background-color: ${bg};
        padding:          6px 6px;
        spacing:          0;
        lines:            5;
        scrollbar:        false;
        fixed-height:     true;
    }

    element {
        padding:          8px 18px;
        spacing:          10px;
        font:             "${font}";
    }

    element.normal.normal {
        text-color: ${fg};
    }

    element.selected.normal {
        background-color: ${red};
        text-color:       ${bg};
        border-radius:    6px;
    }
  '';

  programs.rofi = {
    enable = true;
    # rofi-wayland has been merged into the main rofi package in this nixpkgs.
    package = pkgs.rofi;
    theme = "retro-eighties";

    settings = {
      inherit font;
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

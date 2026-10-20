{
  config,
  pkgs,
  ...
}: let
  r = config.bandit.theme.roles;
  interfaceFont = config.stylix.fonts.sansSerif.name;

  # Shared by both themes: flat window, 1px frame, prompt-only header.
  # `tone` is the frame/prompt colour (accent for the launcher, crit for power).
  window = {
    tone,
    width,
    extra ? "",
  }: ''
    window {
        background-color: ${r.bg};
        border:           1px;
        border-color:     ${tone};
        border-radius:    0;
        width:            ${width};
        padding:          0;${extra}
    }
  '';
  inputbar = {
    tone,
    padding,
    children,
    extra ? "",
  }: ''
    inputbar {
        background-color: ${r.surface};
        border:           0 0 1px 0;
        border-color:     ${tone};
        padding:          ${padding};${extra}
        children:         [ ${children} ];
    }

    prompt {
        background-color: transparent;
        text-color:       ${tone};
        font:             "${interfaceFont} Bold 11";
    }
  '';
  selected = tone: ''
    element.selected.normal {
        background-color: ${tone};
        text-color:       ${r.bg};
    }
  '';
in {
  # ── Main launcher theme ───────────────────────────────────────
  xdg.configFile."rofi/themes/retro-eighties.rasi".text = ''
    * {
        background-color: transparent;
        text-color:       ${r.fg};
    }

    ${window {
      tone = r.accent;
      width = "640px";
    }}
    mainbox {
        spacing:   0;
        padding:   0;
        children:  [ inputbar, message, listview ];
    }

    ${inputbar {
      tone = r.accent;
      padding = "10px 14px";
      children = "prompt, entry";
      extra = "\n        spacing:          8px;";
    }}
    entry {
        background-color: transparent;
        text-color:       ${r.fg};
        placeholder:      "type to search…";
        placeholder-color: ${r.muted};
        cursor:           text;
    }

    message {
        background-color: ${r.surface};
        border:           0 0 1px 0;
        border-color:     ${r.line};
        padding:          4px 14px;
    }

    textbox {
        text-color: ${r.dim};
        font:       "${interfaceFont} 9";
    }

    listview {
        background-color: ${r.bg};
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
        text-color:       ${r.fg};
    }

    element.normal.urgent {
        background-color: transparent;
        text-color:       ${r.crit};
    }

    element.normal.active {
        background-color: transparent;
        text-color:       ${r.info};
    }

    ${selected r.accent}
    element.selected.urgent {
        background-color: ${r.crit};
        text-color:       ${r.bg};
    }

    element.selected.active {
        background-color: ${r.info};
        text-color:       ${r.bg};
    }

    element.alternate.normal {
        background-color: transparent;
        text-color:       ${r.fg};
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
        text-color:       ${r.fg};
    }

    ${window {
      tone = r.crit;
      width = "280px";
      extra = "\n        location:         center;\n        anchor:           center;";
    }}
    mainbox {
        spacing:   0;
        padding:   0;
        children:  [ inputbar, listview ];
    }

    ${inputbar {
      tone = r.crit;
      padding = "8px 14px";
      children = "prompt";
    }}
    listview {
        background-color: ${r.bg};
        padding:          6px 0;
        spacing:          0;
        lines:            5;
        scrollbar:        false;
        fixed-height:     true;
    }

    element {
        padding:          8px 18px;
        spacing:          10px;
        font:             "${interfaceFont} 11";
    }

    element.normal.normal {
        text-color: ${r.fg};
    }

    ${selected r.crit}
  '';

  programs.rofi = {
    enable = true;
    # rofi-wayland has been merged into the main rofi package in this nixpkgs.
    package = pkgs.rofi;
    theme = "retro-eighties";

    settings = {
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

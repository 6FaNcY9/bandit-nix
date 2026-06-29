let
  colors = {
    bg = "#2d2d2d";
    bg1 = "#393939";
    bg3 = "#515151";
    fg = "#f2f0ec";
    muted = "#999999";
    muted2 = "#747369";
    panelFg = "#cccccc";
    blue = "#6699cc";
    aqua = "#66cccc";
    green = "#99cc99";
    orange = "#f99157";
    purple = "#cc99cc";
    red = "#f2777a";
    yellow = "#ffcc66";
  };
in {
  inherit colors;

  starshipPalette = {
    color_fg0 = colors.fg;
    color_bg1 = colors.bg1;
    color_bg3 = colors.bg3;
    color_blue = colors.blue;
    color_aqua = colors.aqua;
    color_green = colors.green;
    color_orange = colors.orange;
    color_purple = colors.purple;
    color_red = colors.red;
    color_yellow = colors.yellow;
  };

  lualineTheme = {
    normal = {
      a = {
        bg = colors.yellow;
        fg = colors.bg;
        gui = "bold";
      };
      b = {
        bg = colors.bg1;
        fg = colors.panelFg;
      };
      c = {
        inherit (colors) bg;
        fg = colors.muted;
      };
    };
    insert = {
      a = {
        bg = colors.blue;
        fg = colors.bg;
        gui = "bold";
      };
      b = {
        bg = colors.bg1;
        fg = colors.panelFg;
      };
      c = {
        inherit (colors) bg;
        fg = colors.muted;
      };
    };
    visual = {
      a = {
        bg = colors.purple;
        fg = colors.bg;
        gui = "bold";
      };
      b = {
        bg = colors.bg1;
        fg = colors.panelFg;
      };
      c = {
        inherit (colors) bg;
        fg = colors.muted;
      };
    };
    replace = {
      a = {
        bg = colors.red;
        fg = colors.bg;
        gui = "bold";
      };
      b = {
        bg = colors.bg1;
        fg = colors.panelFg;
      };
      c = {
        inherit (colors) bg;
        fg = colors.muted;
      };
    };
    command = {
      a = {
        bg = colors.green;
        fg = colors.bg;
        gui = "bold";
      };
      b = {
        bg = colors.bg1;
        fg = colors.panelFg;
      };
      c = {
        inherit (colors) bg;
        fg = colors.muted;
      };
    };
    inactive = {
      a = {
        bg = colors.bg1;
        fg = colors.muted;
        gui = "bold";
      };
      b = {
        inherit (colors) bg;
        fg = colors.muted;
      };
      c = {
        inherit (colors) bg;
        fg = colors.muted2;
      };
    };
  };
}

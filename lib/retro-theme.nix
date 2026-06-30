let
  colors = {
    bg = "#282828";
    bg1 = "#3c3836";
    bg3 = "#504945";
    fg = "#d5c4a1";
    muted = "#928374";
    muted2 = "#665c54";
    panelFg = "#ebdbb2";
    blue = "#458588";
    aqua = "#689d6a";
    green = "#98971a";
    orange = "#d65d0e";
    purple = "#b16286";
    red = "#cc241d";
    yellow = "#d79921";
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

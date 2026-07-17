{
  inputs,
  repoConfig,
  ...
}: let
  c = repoConfig.serverPalette;
in {
  programs.nixvim = {
    enable = true;
    defaultEditor = true;
    nixpkgs.source = inputs.nixpkgs;
    viAlias = true;
    vimAlias = true;

    plugins.lualine = {
      enable = true;
      settings.options = {
        component_separators = {
          left = "";
          right = "";
        };
        section_separators = {
          left = "";
          right = "";
        };
        globalstatus = true;
        theme = {
          normal = {
            a = {
              bg = c.base0A;
              fg = c.base00;
              gui = "bold";
            };
            b = {
              bg = c.base01;
              fg = c.base06;
            };
            c = {
              bg = c.base00;
              fg = c.base03;
            };
          };
          insert = {
            a = {
              bg = c.base0D;
              fg = c.base00;
              gui = "bold";
            };
            b = {
              bg = c.base01;
              fg = c.base06;
            };
            c = {
              bg = c.base00;
              fg = c.base03;
            };
          };
          visual = {
            a = {
              bg = c.base0E;
              fg = c.base00;
              gui = "bold";
            };
            b = {
              bg = c.base01;
              fg = c.base06;
            };
            c = {
              bg = c.base00;
              fg = c.base03;
            };
          };
          replace = {
            a = {
              bg = c.base08;
              fg = c.base00;
              gui = "bold";
            };
            b = {
              bg = c.base01;
              fg = c.base06;
            };
            c = {
              bg = c.base00;
              fg = c.base03;
            };
          };
          command = {
            a = {
              bg = c.base0B;
              fg = c.base00;
              gui = "bold";
            };
            b = {
              bg = c.base01;
              fg = c.base06;
            };
            c = {
              bg = c.base00;
              fg = c.base03;
            };
          };
          inactive = {
            a = {
              bg = c.base01;
              fg = c.base03;
              gui = "bold";
            };
            b = {
              bg = c.base00;
              fg = c.base03;
            };
            c = {
              bg = c.base00;
              fg = c.base02;
            };
          };
        };
      };
    };
  };
}

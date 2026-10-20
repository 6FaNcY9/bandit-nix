{config, ...}: let
  r = config.bandit.theme.roles;
in {
  # Statusline
  programs.nixvim.plugins.lualine = {
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
            bg = r.accent;
            fg = r.bg;
            gui = "bold";
          };
          b = {
            bg = r.surface;
            fg = r.bright;
          };
          c = {
            bg = r.bg;
            fg = r.muted;
          };
        };
        insert = {
          a = {
            bg = r.info;
            fg = r.bg;
            gui = "bold";
          };
          b = {
            bg = r.surface;
            fg = r.bright;
          };
          c = {
            bg = r.bg;
            fg = r.muted;
          };
        };
        visual = {
          a = {
            bg = r.info;
            fg = r.bg;
            gui = "bold";
          };
          b = {
            bg = r.surface;
            fg = r.bright;
          };
          c = {
            bg = r.bg;
            fg = r.muted;
          };
        };
        replace = {
          a = {
            bg = r.crit;
            fg = r.bg;
            gui = "bold";
          };
          b = {
            bg = r.surface;
            fg = r.bright;
          };
          c = {
            bg = r.bg;
            fg = r.muted;
          };
        };
        command = {
          a = {
            bg = r.ok;
            fg = r.bg;
            gui = "bold";
          };
          b = {
            bg = r.surface;
            fg = r.bright;
          };
          c = {
            bg = r.bg;
            fg = r.muted;
          };
        };
        inactive = {
          a = {
            bg = r.surface;
            fg = r.muted;
            gui = "bold";
          };
          b = {
            bg = r.bg;
            fg = r.muted;
          };
          c = {
            bg = r.bg;
            fg = r.raised;
          };
        };
      };
    };
  };
}

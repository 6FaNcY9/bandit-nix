{config, ...}: let
  colors = config.lib.stylix.colors.withHashtag;
in {
  stylix.targets = {
    fish.enable = true;
    gtk.enable = true;
    kitty.enable = true;
    nixvim.enable = true;
    i3.enable = true;
    firefox = {
      enable = true;
      firefoxGnomeTheme.enable = true;
      colorTheme.enable = true;
    };
    rofi.enable = false;
    dunst.enable = false;
    bat.enable = true;
    fzf.enable = true;
    starship.enable = true;
    btop.enable = true;
  };

  # Retro dark aesthetic — square corners, beveled chrome, classic 90s feel
  stylix.targets.gtk.extraCss = ''
    * {
      border-radius: 0;
      transition: none;
    }

    window, dialog, .background { border-radius: 0; }
    window.csd { border-radius: 0; }

    /* Title bars — hard line, no shadow, flat */
    headerbar, headerbar.titlebar, .titlebar {
      border-radius: 0;
      border-bottom: 2px solid ${colors.base02};
      box-shadow: none;
      background-image: none;
    }
    .csd .titlebar { border-radius: 0; }

    /* Beveled buttons — raised normal, sunken when pressed */
    button {
      border-radius: 0;
      box-shadow:
        inset -1px -1px 0 ${colors.base00},
        inset  1px  1px 0 ${colors.base02};
    }
    button:hover {
      background-image: none;
      background-color: ${colors.base01};
    }
    button:active, button:checked {
      box-shadow:
        inset  1px  1px 0 ${colors.base00},
        inset -1px -1px 0 ${colors.base02};
    }

    /* Sunken entries (text inputs inset into the surface) */
    entry, spinbutton, textview {
      border-radius: 0;
      box-shadow:
        inset 1px 1px 0 ${colors.base00},
        inset -1px -1px 0 ${colors.base02};
    }

    /* Popovers / menus — square + flat */
    popover, popover.background, popover > contents { border-radius: 0; }
    .menu, menu, menuitem { border-radius: 0; }
    menubar { border-radius: 0; }
    menuitem:hover {
      background-color: ${colors.base0A};
      color: ${colors.base00};
    }

    tooltip { border-radius: 0; }

    notebook > header tabs tab { border-radius: 0; }
    treeview.view { border-radius: 0; }

    /* Chunky beveled scrollbars */
    scrollbar { border-radius: 0; }
    scrollbar slider {
      border-radius: 0;
      min-width: 14px;
      min-height: 14px;
      background-color: ${colors.base02};
      box-shadow:
        inset -1px -1px 0 ${colors.base00},
        inset  1px  1px 0 ${colors.base03};
    }
    scrollbar.horizontal slider { min-height: 14px; }
    scrollbar.vertical   slider { min-width: 14px; }
  '';

  gtk.gtk3.extraConfig = {
    gtk-enable-animations = false;
    gtk-button-images = true;
    gtk-menu-images = true;
  };
}

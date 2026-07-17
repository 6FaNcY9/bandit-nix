{
  config,
  inputs,
  pkgs,
  lib,
  ...
}: let
  colors = config.lib.stylix.colors.withHashtag;
  retroKvantum = let
    kvconfig = config.lib.stylix.colors {
      template = "${inputs.stylix}/modules/qt/kvconfig.mustache";
      extension = ".kvconfig";
    };
    svg = config.lib.stylix.colors {
      template = "${inputs.stylix}/modules/qt/kvantum.svg.mustache";
      extension = ".svg";
    };
  in
    pkgs.runCommandLocal "bandit-retro-kvantum" {} ''
      directory="$out/share/Kvantum/BanditRetroKvantum"
      mkdir --parents "$directory"
      cp ${kvconfig} "$directory/BanditRetroKvantum.kvconfig"
      ${pkgs.gnused}/bin/sed -i \
        's/^highlight\.color=.*/highlight.color=${colors.base0A}/' \
        "$directory/BanditRetroKvantum.kvconfig"
      cp ${svg} "$directory/BanditRetroKvantum.svg"
    '';
in {
  home.pointerCursor.enable = true;

  # Generate the custom theme in the Nix store so Home Manager can safely
  # manage it as a symlink.
  qt.kvantum = {
    settings.General.theme = lib.mkForce "BanditRetroKvantum";
    themes = [retroKvantum];
  };

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

    /* Amber primary and cyan secondary accents from Bandit Retro. */
    button:focus, entry:focus, textview:focus {
      outline: 2px solid ${colors.base0A};
      outline-offset: -2px;
    }
    button:hover {
      background-color: ${colors.base0C};
      color: ${colors.base00};
    }
    selection, *:selected {
      background-color: ${colors.base0A};
      color: ${colors.base00};
    }
    scrollbar slider:hover, scrollbar slider:active {
      background-color: ${colors.base0A};
    }
    notebook > header tabs tab:checked {
      border-bottom: 2px solid ${colors.base0A};
    }
  '';

  gtk = {
    gtk3.extraConfig = {
      gtk-application-prefer-dark-theme = true;
      gtk-enable-animations = false;
      gtk-button-images = true;
      gtk-menu-images = true;
      gtk-icon-theme-name = "Gruvbox Plus Dark";
    };

    gtk4.extraConfig = {
      gtk-application-prefer-dark-theme = true;
      gtk-icon-theme-name = "Gruvbox Plus Dark";
    };
  };
}

{
  config,
  inputs,
  pkgs,
  lib,
  ...
}: let
  colors = config.lib.stylix.colors.withHashtag;
  gruvboxKvantum = let
    kvconfig = config.lib.stylix.colors {
      template = "${inputs.stylix}/modules/qt/kvconfig.mustache";
      extension = ".kvconfig";
    };
    svg = config.lib.stylix.colors {
      template = "${inputs.stylix}/modules/qt/kvantum.svg.mustache";
      extension = ".svg";
    };
  in
    pkgs.runCommandLocal "bandit-gruvbox-kvantum" {} ''
      directory="$out/share/Kvantum/BanditGruvboxKvantum"
      mkdir --parents "$directory"
      cp ${kvconfig} "$directory/BanditGruvboxKvantum.kvconfig"
      ${pkgs.gnused}/bin/sed -i \
        's/^highlight\.color=.*/highlight.color=${colors.base0A}/' \
        "$directory/BanditGruvboxKvantum.kvconfig"
      cp ${svg} "$directory/BanditGruvboxKvantum.svg"
    '';
in {
  home = {
    # Stylix's HM cursor module (cascaded from nixos/theme.nix's stylix.cursor)
    # plain-sets package/name/size on the NixOS-embedded config but never sets
    # `enable` itself, which is what triggers its own deprecation warning.
    # mkForce enable so the warning goes away everywhere; mkDefault the rest
    # so Stylix's values win when present, falling back to the same values
    # for the standalone homeConfigurations output where Stylix doesn't cascade.
    pointerCursor = {
      enable = lib.mkForce true;
      package = lib.mkDefault pkgs.openzone-cursors;
      name = lib.mkDefault "OpenZone_Black_Slim";
      size = lib.mkDefault 30;
    };
  };

  # Generate the custom theme in the Nix store so Home Manager can safely
  # manage it as a symlink.
  qt.kvantum = {
    settings.General.theme = lib.mkForce "BanditGruvboxKvantum";
    themes = [gruvboxKvantum];
  };

  stylix.targets = {
    fish.enable = true;
    gtk.enable = true;
    kitty.enable = true;
    nixvim.enable = true;
    hyprland.enable = true;
    hyprlock.enable = true;
    firefox = {
      enable = true;
      firefoxGnomeTheme.enable = true;
      colorTheme.enable = true;
    };
    rofi.enable = false;
    mako.enable = false;
    bat.enable = true;
    fzf.enable = true;
    starship.enable = true;
    btop.enable = true;
  };

  # Warm retro aesthetic — mostly-flat chrome with a gentle bevel, softened
  # from the old high-contrast 90s look to match Gruvbox Material's mellower
  # warmth. Headerbars/menus/scrollbars stay hard-edged; buttons/entries/
  # popovers get a small radius and a lighter, blended-tone shadow.
  stylix.targets.gtk.extraCss = ''
    * {
      border-radius: 3px;
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

    /* Softly beveled buttons — raised normal, sunken when pressed */
    button {
      border-radius: 3px;
      box-shadow:
        inset -1px -1px 0 ${colors.base02},
        inset  1px  1px 0 ${colors.base03};
    }
    button:active, button:checked {
      box-shadow:
        inset  1px  1px 0 ${colors.base02},
        inset -1px -1px 0 ${colors.base03};
    }

    /* Gently sunken entries (text inputs inset into the surface) */
    entry, spinbutton, textview {
      border-radius: 3px;
      box-shadow:
        inset 1px 1px 0 ${colors.base02},
        inset -1px -1px 0 ${colors.base03};
    }

    /* Popovers / menus — mostly square, softly flat */
    popover, popover.background, popover > contents { border-radius: 3px; }
    .menu, menu, menuitem { border-radius: 0; }
    menubar { border-radius: 0; }
    menuitem:hover {
      background-color: ${colors.base0A};
      color: ${colors.base00};
    }

    tooltip { border-radius: 3px; }

    notebook > header tabs tab { border-radius: 0; }
    treeview.view { border-radius: 0; }

    /* Chunky, softly beveled scrollbars */
    scrollbar { border-radius: 0; }
    scrollbar slider {
      border-radius: 3px;
      min-width: 14px;
      min-height: 14px;
      background-color: ${colors.base02};
      box-shadow:
        inset -1px -1px 0 ${colors.base01},
        inset  1px  1px 0 ${colors.base03};
    }
    scrollbar.horizontal slider { min-height: 14px; }
    scrollbar.vertical   slider { min-width: 14px; }

    /* Warm amber primary and teal secondary accents from Gruvbox Material. */
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

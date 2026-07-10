{
  config,
  pkgs,
  lib,
  ...
}: let
  colors = config.lib.stylix.colors.withHashtag;
in {
  # Stylix generates ~/.config/Kvantum/Base16Kvantum/Base16Kvantum.kvconfig
  # from the base16 scheme, but its accent color (highlight.color) comes out
  # as base16 mauve (#b16286), not the golden #d79921 used everywhere else
  # (i3 focused border, kitty active tab). Patch just that one line in place
  # after Stylix writes the file, rather than shadowing the whole generated
  # config — this stays correct across future Stylix template changes.
  home = {
    activation.kvantumAccentOverride = lib.hm.dag.entryAfter ["writeBoundary"] ''
      run ${pkgs.gnused}/bin/sed -i \
        's/^highlight\.color=.*/highlight.color=#d79921/' \
        "$HOME/.config/Kvantum/Base16Kvantum/Base16Kvantum.kvconfig"
    '';

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

    /* Golden/teal retro-colorful accents — match i3 focused border (#d79921)
       and teal secondary accent (#458588) used across i3/kitty. */
    button:focus, entry:focus, textview:focus {
      outline: 2px solid #d79921;
      outline-offset: -2px;
    }
    button:hover {
      background-color: #458588;
      color: ${colors.base00};
    }
    selection, *:selected {
      background-color: #d79921;
      color: ${colors.base00};
    }
    scrollbar slider:hover, scrollbar slider:active {
      background-color: #d79921;
    }
    notebook > header tabs tab:checked {
      border-bottom: 2px solid #d79921;
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

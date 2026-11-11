{
  config,
  pkgs,
  lib,
  ...
}: let
  colors = config.lib.stylix.colors.withHashtag;
  gruvboxKvantum = let
    kvconfig = config.lib.stylix.colors {
      # Vendored from stylix's modules/qt/: the template argument must be a
      # real path — a string is written verbatim as file content instead.
      template = ./kvantum/kvconfig.mustache;
      extension = ".kvconfig";
    };
    svg = config.lib.stylix.colors {
      template = ./kvantum/kvantum.svg.mustache;
      extension = ".svg";
    };
  in
    pkgs.runCommandLocal "bandit-gruvbox-kvantum" {} ''
      directory="$out/share/Kvantum/BanditGruvboxKvantum"
      mkdir --parents "$directory"
      cp ${kvconfig} "$directory/BanditGruvboxKvantum.kvconfig"
      ${pkgs.gnused}/bin/sed -i \
        's/^highlight\.color=.*/highlight.color=${colors.base0D}/' \
        "$directory/BanditGruvboxKvantum.kvconfig"
      cp ${svg} "$directory/BanditGruvboxKvantum.svg"
    '';
in {
  home = {
    # Stylix's HM cursor module (cascaded from modules/desktop/theme.nix's stylix.cursor)
    # plain-sets package/name/size on the NixOS-embedded config but never sets
    # `enable` itself, which is what triggers its own deprecation warning.
    # mkForce enable so the warning goes away everywhere; mkDefault the rest
    # so Stylix's values win when present, falling back to the same values
    # for the standalone homeConfigurations output where Stylix doesn't cascade.
    pointerCursor = {
      enable = lib.mkForce true;
      package = lib.mkDefault pkgs.openzone-cursors;
      name = lib.mkDefault "OpenZone_Black_Slim";
      size = lib.mkDefault 20;
    };
  };

  # Generate the custom theme in the Nix store so Home Manager can safely
  # manage it as a symlink.
  qt.kvantum = {
    settings.General.theme = lib.mkForce "BanditGruvboxKvantum";
    themes = [gruvboxKvantum];
  };

  stylix.targets = {
    gtk.enable = true;
    kitty.enable = true;
    nixvim.enable = true;
    # Hyprland's palette is owned by modules/user/desktop/hyprland.nix so its orange
    # borders do not conflict with Stylix's default teal border definitions.
    hyprland.enable = false;
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

  # Modern flat chrome: no bevels or shadows, 8 px radius on controls,
  # one focus colour (blue base0D) for focus, selection and active tabs.
  # Windows stay square; Hyprland rounds their corners.
  stylix.targets.gtk.extraCss = ''
    * { transition: none; }

    window, dialog, .background { border-radius: 0; }
    window.csd, .csd .titlebar { border-radius: 0; }

    headerbar, headerbar.titlebar, .titlebar {
      border-radius: 0;
      border-bottom: 2px solid ${colors.base02};
      box-shadow: none;
      background-image: none;
    }

    button, entry, spinbutton, textview, popover, popover.background,
    popover > contents, tooltip {
      border-radius: 8px;
      box-shadow: none;
      background-image: none;
    }
    button {
      background-color: ${colors.base01};
      border: 1px solid ${colors.base02};
    }
    button:hover { background-color: ${colors.base02}; }
    entry, spinbutton { border: 1px solid ${colors.base02}; }

    .menu, menu, menuitem, menubar { border-radius: 0; }
    menuitem:hover {
      background-color: ${colors.base0D};
      color: ${colors.base00};
    }

    notebook > header tabs tab { border-radius: 0; }
    treeview.view { border-radius: 0; }

    scrollbar { border-radius: 0; }
    scrollbar slider {
      border-radius: 8px;
      min-width: 12px;
      min-height: 12px;
      background-color: ${colors.base02};
    }

    button:focus, entry:focus, textview:focus {
      outline: 2px solid ${colors.base0D};
      outline-offset: -2px;
    }
    selection, *:selected {
      background-color: ${colors.base0D};
      color: ${colors.base00};
    }
    scrollbar slider:hover, scrollbar slider:active {
      background-color: ${colors.base0D};
    }
    notebook > header tabs tab:checked {
      border-bottom: 2px solid ${colors.base0D};
    }
  '';

  gtk = let
    # Follow the Stylix polarity so the light boot specialisation gets a
    # light GTK hint and light icons instead of the dark holdouts.
    isDark = config.stylix.polarity == "dark";
    gruvboxIcons =
      if isDark
      then "Gruvbox Plus Dark"
      else "Gruvbox Plus Light";
  in {
    gtk3.extraConfig = {
      gtk-application-prefer-dark-theme = isDark;
      gtk-enable-animations = false;
      gtk-button-images = true;
      gtk-menu-images = true;
      gtk-icon-theme-name = gruvboxIcons;
    };

    gtk4.extraConfig = {
      gtk-application-prefer-dark-theme = isDark;
      gtk-icon-theme-name = gruvboxIcons;
    };
  };
}

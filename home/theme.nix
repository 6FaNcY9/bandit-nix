_: {
  stylix.targets = {
    fish.enable = true;
    gtk.enable = true;
    xfce.enable = true;
    kitty.enable = true;
    nixvim.enable = true;
    i3.enable = true;
    firefox.enable = true;
    rofi.enable = false;
    dunst.enable = false;
  };

  # Retro dark aesthetic — square corners, visible borders, classic feel
  stylix.targets.gtk.extraCss = ''
    * {
      border-radius: 0;
      transition: none;
    }

    window, dialog, .background { border-radius: 0; }
    window.csd { border-radius: 0; }
    headerbar, headerbar.titlebar, .titlebar { border-radius: 0; box-shadow: none; border-bottom: 1px solid #515151; }
    .csd .titlebar { border-radius: 0; }

    button { border-radius: 0; box-shadow: none; }
    button:active { box-shadow: inset 1px 1px 0 rgba(0,0,0,0.3); }

    entry, spinbutton { border-radius: 0; }

    popover, popover.background, popover > contents { border-radius: 0; }

    .menu, menu, menuitem { border-radius: 0; }
    menubar { border-radius: 0; }

    tooltip { border-radius: 0; }

    notebook > header tabs tab { border-radius: 0; }
    treeview.view { border-radius: 0; }

    scrollbar { border-radius: 0; }
    scrollbar slider { border-radius: 0; min-width: 12px; min-height: 12px; }
    scrollbar.horizontal slider { min-height: 12px; }
    scrollbar.vertical slider { min-width: 12px; }
  '';

  gtk.gtk4.theme = null;

  gtk.gtk3.extraConfig = {
    gtk-enable-animations = false;
    gtk-button-images = true;
    gtk-menu-images = true;
  };
}

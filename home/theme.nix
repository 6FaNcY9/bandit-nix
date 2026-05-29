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

  # Soft 2px border-radius — retro gruvbox aesthetic with slight roundness
  stylix.targets.gtk.extraCss = ''
    * {
      border-radius: 2px !important;
      box-shadow: none !important;
    }
    headerbar,
    headerbar.titlebar { border-radius: 2px !important; }
    .csd .titlebar { border-radius: 2px !important; }
    popover.background,
    popover > contents { border-radius: 4px !important; }
    button,
    button.flat,
    button.suggested-action,
    button.destructive-action { border-radius: 2px !important; }
    entry,
    spinbutton { border-radius: 2px !important; }
    .menu,
    menuitem { border-radius: 0 !important; }
    tooltip { border-radius: 2px !important; }
    notebook > header tabs tab { border-radius: 2px !important; }
    treeview.view { border-radius: 0 !important; }
    window.csd { border-radius: 0 !important; }
  '';

  # Disable GTK animations for a snappier retro feel
  gtk.gtk3.extraConfig = {
    gtk-enable-animations = false;
    gtk-button-images = true;
    gtk-menu-images = true;
  };
}

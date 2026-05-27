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

  # Remove rounded corners everywhere — retro/flat gruvbox aesthetic
  stylix.targets.gtk.extraCss = ''
    * {
      border-radius: 0 !important;
      box-shadow: none !important;
    }
    headerbar,
    headerbar.titlebar { border-radius: 0 !important; }
    .csd .titlebar { border-radius: 0 !important; }
    popover.background,
    popover > contents { border-radius: 0 !important; }
    button,
    button.flat,
    button.suggested-action,
    button.destructive-action { border-radius: 0 !important; }
    entry,
    spinbutton { border-radius: 0 !important; }
    .menu,
    menuitem { border-radius: 0 !important; }
    tooltip { border-radius: 0 !important; }
    notebook > header tabs tab { border-radius: 0 !important; }
    treeview.view { border-radius: 0 !important; }
  '';

  # Disable GTK animations for a snappier retro feel
  gtk.gtk3.extraConfig = {
    gtk-enable-animations = false;
    gtk-button-images = true;
    gtk-menu-images = true;
  };
}

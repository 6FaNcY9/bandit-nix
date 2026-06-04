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
      border-bottom: 2px solid #515151;
      box-shadow: none;
      background-image: none;
    }
    .csd .titlebar { border-radius: 0; }

    /* Beveled buttons — raised normal, sunken when pressed */
    button {
      border-radius: 0;
      box-shadow:
        inset -1px -1px 0 #1a1a1a,
        inset  1px  1px 0 #515151;
    }
    button:hover {
      background-image: none;
      background-color: #393939;
    }
    button:active, button:checked {
      box-shadow:
        inset  1px  1px 0 #1a1a1a,
        inset -1px -1px 0 #515151;
    }

    /* Sunken entries (text inputs inset into the surface) */
    entry, spinbutton, textview {
      border-radius: 0;
      box-shadow:
        inset 1px 1px 0 #1a1a1a,
        inset -1px -1px 0 #515151;
    }

    /* Popovers / menus — square + flat */
    popover, popover.background, popover > contents { border-radius: 0; }
    .menu, menu, menuitem { border-radius: 0; }
    menubar { border-radius: 0; }
    menuitem:hover {
      background-color: #ffcc66;
      color: #2d2d2d;
    }

    tooltip { border-radius: 0; }

    /* XFCE Panel — uniform font size for all widgets */
    .xfce4-panel,
    .xfce4-panel * { font-size: 14pt; }

    /* XFCE Panel — bevel chrome on all plugin buttons */
    .xfce4-panel button,
    .xfce4-panel .panel-button {
      border-radius: 0;
      padding: 0 3px;
      box-shadow:
        inset -1px -1px 0 #1a1a1a,
        inset  1px  1px 0 #515151;
    }
    .xfce4-panel button:active,
    .xfce4-panel button:checked,
    .xfce4-panel .panel-button:active,
    .xfce4-panel .panel-button:checked {
      box-shadow:
        inset  1px  1px 0 #1a1a1a,
        inset -1px -1px 0 #515151;
      background-color: #393939;
    }
    /* Tasklist — active window sunken + accent, inactive raised.
       XFCE uses wnck-tasklist; older themes target .tasklist-button,
       but current widgets are bare <button> children of wnck-tasklist. */
    .xfce4-panel .tasklist-button,
    .xfce4-panel wnck-tasklist button,
    .xfce4-panel .tasklist button {
      border-radius: 0;
      min-width: 80px;
      padding: 0 6px;
      background-image: none;
      background-color: #2d2d2d;
      box-shadow:
        inset -1px -1px 0 #1a1a1a,
        inset  1px  1px 0 #515151;
    }
    .xfce4-panel .tasklist-button:hover,
    .xfce4-panel wnck-tasklist button:hover,
    .xfce4-panel .tasklist button:hover {
      background-color: #393939;
    }
    .xfce4-panel .tasklist-button:checked,
    .xfce4-panel .tasklist-button:active,
    .xfce4-panel wnck-tasklist button:checked,
    .xfce4-panel wnck-tasklist button:active,
    .xfce4-panel .tasklist button:checked,
    .xfce4-panel .tasklist button:active {
      background-image: none;
      background-color: #393939;
      color: #ffcc66;
      box-shadow:
        inset  1px  1px 0 #1a1a1a,
        inset -1px -1px 0 #515151;
    }

    notebook > header tabs tab { border-radius: 0; }
    treeview.view { border-radius: 0; }

    /* Chunky beveled scrollbars */
    scrollbar { border-radius: 0; }
    scrollbar slider {
      border-radius: 0;
      min-width: 14px;
      min-height: 14px;
      background-color: #515151;
      box-shadow:
        inset -1px -1px 0 #1a1a1a,
        inset  1px  1px 0 #999999;
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

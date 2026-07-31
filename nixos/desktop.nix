{pkgs, ...}: {
  services = {
    greetd = {
      enable = true;
      useTextGreeter = true;
      settings.default_session.command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd start-hyprland";
    };

    # For mounting/unmounting drives in file managers.
    udisks2.enable = true;
    gvfs.enable = true;

    # Gnome Keyring - needed for nm-applet to prompt for wifi passwords
    gnome.gnome-keyring.enable = true;

    blueman.enable = true;
  };

  # programs.hyprland enables XWayland, registers the session with greetd,
  # and wires xdg.portal (extraPortals + configPackages) automatically.
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  security.pam.services.greetd.enableGnomeKeyring = true;

  # Bluetooth
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = false;
  };

  environment.systemPackages = with pkgs; [
    brightnessctl
  ];

  # Polkit for privilege escalation in GUI apps (e.g. software updater)
  security.polkit = {
    enable = true;
    extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.libvirt.unix.manage" &&
            subject.isInGroup("libvirtd")) {
          return polkit.Result.YES;
        }
      });
    '';
  };
  # Needed for GTK apps
  programs.dconf.enable = true;
  hardware.acpilight.enable = true;

  # XDG portals for sandboxed apps (flatpak, snap, etc.) — programs.hyprland
  # adds xdg-desktop-portal-hyprland on top of this for screen sharing.
  xdg.portal = {
    enable = true;
    extraPortals = [pkgs.xdg-desktop-portal-gtk];
    config.common.default = "gtk";
  };
}

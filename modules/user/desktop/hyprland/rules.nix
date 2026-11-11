{
  pkgs,
  lib,
  ...
}: let
  lua = lib.generators.mkLuaInline;
  windowRule = spec: {_args = [spec];};

  startupCommands = [
    # Attach the PAM-unlocked keyring to the session bus before any app asks for
    # secrets; otherwise D-Bus spawns a fresh, locked daemon that prompts.
    "${pkgs.gnome-keyring}/bin/gnome-keyring-daemon --start --components=secrets"
    "${pkgs.networkmanagerapplet}/bin/nm-applet"
    "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
    "${pkgs.blueman}/bin/blueman-applet"
    "${pkgs.wl-clipboard}/bin/wl-paste --type text --watch ${pkgs.cliphist}/bin/cliphist store"
    "${pkgs.wl-clipboard}/bin/wl-paste --type image --watch ${pkgs.cliphist}/bin/cliphist store"
    # Resident daemon keeps copied screenshots in the Wayland clipboard after the capture UI closes.
    "${pkgs.flameshot}/bin/flameshot"
  ];
  startupHandler = lib.concatMapStringsSep "\n" (command: "  hl.exec_cmd(${builtins.toJSON command})") startupCommands;

  windowRules = map windowRule [
    {
      # Ignore client requests to start maximized. kitty asks for it, which put
      # every new terminal into the maximized state (full work area, bar still
      # visible) until toggled twice with Mod+F. Same rule as Hyprland's own
      # default configuration.
      name = "ignore-client-maximize";
      match.class = ".*";
      suppress_event = "maximize";
    }
    {
      name = "pavucontrol";
      match.class = "^(pavucontrol|org.pulseaudio.pavucontrol)$";
      float = true;
      size = "900 600";
      center = true;
    }
    {
      name = "blueman-manager";
      match.class = "^(blueman-manager)$";
      float = true;
      size = "720 520";
      center = true;
    }
    {
      name = "picture-in-picture";
      match.title = "^(Picture-in-Picture)$";
      float = true;
      pin = true;
    }
    {
      # Flameshot's capture overlay must cover the screen untouched by tiling.
      name = "flameshot";
      match.class = "^(flameshot)$";
      float = true;
      pin = true;
      move = "0 0";
      no_anim = true;
    }
    {
      name = "hyprland-shortcuts";
      match.title = "^(Hyprland Shortcuts)$";
      float = true;
      size = "800 560";
      center = true;
    }
    # Fixed workspaces; the waybar glyphs in ../waybar.nix follow this layout.
    {
      name = "web";
      match.class = "^(firefox|brave-browser)$";
      workspace = "2";
    }
    {
      name = "docs";
      match.class = "^(org.kde.okular|obsidian|libreoffice.*|soffice.*)$";
      workspace = "3";
    }
    {
      # The main window tiles by default; only its title starts with the version.
      name = "prism";
      match.class = "^(org.prismlauncher.PrismLauncher)$";
      workspace = "4";
    }
    {
      # Mod downloads, instance settings, console and crash log float.
      name = "prism-dialogs";
      match.class = "^(org.prismlauncher.PrismLauncher)$";
      match.title = "negative:^Prism Launcher [0-9].*$";
      float = true;
      center = true;
    }
    {
      # hypridle locks after 600 s; AFK in game must not lock the session.
      name = "minecraft";
      match.class = "^(com.mojang.minecraft.*|Minecraft.*)$";
      workspace = "4";
      fullscreen = true;
      idle_inhibit = "focus";
    }
    {
      # Started in the background; must not steal focus.
      name = "comms";
      match.class = "^(thunderbird|vesktop)$";
      workspace = "6 silent";
    }
    {
      name = "files";
      match.class = "^(pcmanfm)$";
      workspace = "7";
    }
    {
      name = "media";
      match.class = "^(mpv)$";
      workspace = "8";
    }
    {
      name = "scrcpy";
      match.class = "^(.scrcpy-wrapped|scrcpy)$";
      workspace = "9";
      float = true;
      center = true;
    }
    {
      name = "bitwarden";
      match.class = "^(Bitwarden|bitwarden)$";
      float = true;
      size = "1000 700";
      center = true;
    }
  ];
in {
  wayland.windowManager.hyprland.settings = {
    on = {
      _args = [
        "hyprland.start"
        (lua ''
          function()
          ${startupHandler}
          end
        '')
      ];
    };

    window_rule = windowRules;
  };
}

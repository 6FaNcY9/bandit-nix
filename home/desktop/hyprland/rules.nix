{
  pkgs,
  lib,
  ...
}: let
  lua = lib.generators.mkLuaInline;
  windowRule = spec: {_args = [spec];};

  startupCommands = [
    "${pkgs.networkmanagerapplet}/bin/nm-applet"
    "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
    "${pkgs.blueman}/bin/blueman-applet"
    "${pkgs.wl-clipboard}/bin/wl-paste --type text --watch ${pkgs.cliphist}/bin/cliphist store"
    "${pkgs.wl-clipboard}/bin/wl-paste --type image --watch ${pkgs.cliphist}/bin/cliphist store"
  ];
  startupHandler = lib.concatMapStringsSep "\n" (command: "  hl.exec_cmd(${builtins.toJSON command})") startupCommands;

  windowRules = map windowRule [
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
      name = "hyprland-shortcuts";
      match.title = "^(Hyprland Shortcuts)$";
      float = true;
      size = "800 560";
      center = true;
    }
    {
      name = "firefox-workspace";
      match.class = "^(firefox)$";
      workspace = "1";
    }
    {
      name = "pcmanfm-workspace";
      match.class = "^(pcmanfm)$";
      workspace = "3";
    }
    {
      name = "thunderbird-workspace";
      match.class = "^(thunderbird)$";
      workspace = "4";
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

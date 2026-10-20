{
  pkgs,
  repoConfig,
  ...
}: let
  # Region screenshot: capture, save, copy, notify. A cancelled slurp
  # (Escape / right click) is not an error, so it exits 0 quietly.
  hyprScreenshot = pkgs.writeShellApplication {
    name = "hypr-screenshot";
    runtimeInputs = [pkgs.grim pkgs.slurp pkgs.wl-clipboard pkgs.libnotify pkgs.coreutils];
    text = ''
      dir="${repoConfig.workstation.homeDirectory}/media/screenshots"
      mkdir -p -- "$dir"
      if ! region="$(slurp)" || [ -z "$region" ]; then
        exit 0
      fi
      file="$dir/$(date +%Y-%m-%d_%H-%M-%S).png"
      grim -g "$region" "$file"
      wl-copy < "$file"
      notify-send -a hypr-screenshot "Screenshot saved" "$file"
    '';
  };
in {
  # The hand-maintained shortcut cheatsheet was removed: it drifted from
  # bindings.nix. The rofi keybinds menu (Mod+F2, home/desktop/keybinds-menu.nix)
  # reads the live bind descriptions instead.
  home = {
    file = {
      "media/screenshots/.keep".text = "";
      # Kept for muscle memory / external callers; bindings use the store path.
      ".local/bin/hypr-screenshot".source = "${hyprScreenshot}/bin/hypr-screenshot";
    };

    packages = with pkgs; [
      hyprScreenshot
      grim
      slurp
      wl-clipboard
      cliphist
      libnotify
      playerctl
      brightnessctl
      networkmanagerapplet
      less
    ];
  };
}

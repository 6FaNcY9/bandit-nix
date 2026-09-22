{repoConfig, ...}: let
  c = repoConfig.serverPalette;
in {
  programs.starship = {
    enable = true;
    settings = {
      palette = "stylix";

      palettes.stylix = {
        color_fg0 = c.base05;
        color_bg1 = c.base01;
        color_bg3 = c.base02;
        color_blue = c.base0D;
        color_aqua = c.base0C;
        color_green = c.base0B;
        color_orange = c.base09;
        color_purple = c.base0E;
        color_red = c.base08;
        color_yellow = c.base0A;
      };

      format = "$hostname$username$directory$git_branch$git_status$nix_shell\${custom.net}$time$cmd_duration$line_break$character";

      hostname = {
        ssh_only = false;
        style = "color_red bold";
        format = "[\\[$hostname\\]]($style) ";
      };

      username = {
        style_user = "color_green bold";
        style_root = "color_red bold";
        format = "[\\[$user\\]]($style) ";
        show_always = false;
      };

      directory = {
        style = "color_blue bold";
        format = "[\\[$path$read_only\\]]($style) ";
        truncation_length = 4;
        truncate_to_repo = false;
        read_only = " ro";
      };

      git_branch = {
        style = "color_yellow bold";
        format = "[\\[$symbol$branch\\]]($style) ";
        symbol = "";
      };

      git_status = {
        style = "color_red bold";
        conflicted = "!";
        ahead = "up\${count}";
        behind = "down\${count}";
        diverged = "up\${ahead_count}/down\${behind_count}";
        modified = "!";
        untracked = "?";
        staged = "+";
        deleted = "x";
        stashed = "stash";
        format = "[\\[$all_status$ahead_behind\\]]($style) ";
      };

      nix_shell = {
        format = "[\\[$symbol$state\\]]($style) ";
        style = "color_aqua bold";
        symbol = "nix:";
      };

      custom.net = {
        command = ''
          IFACE=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
          [[ -z "$IFACE" ]] && exit 1
          ADDRESS=$(ip -o -4 addr show dev "$IFACE" scope global | awk '{print $4; exit}')
          [[ -n "$ADDRESS" ]] || exit 1
          printf '%s %s\n' "$IFACE" "$ADDRESS"
        '';
        when = "true";
        shell = ["bash" "-c"];
        format = "[\\[$output\\]](color_aqua bold) ";
      };

      time = {
        disabled = false;
        format = "[\\[$time\\]](color_purple bold) ";
        time_format = "%H:%M";
      };

      cmd_duration = {
        min_time = 1000;
        style = "color_orange bold";
        format = "[\\[$duration\\]]($style) ";
      };

      character = {
        success_symbol = "[\\$](color_green bold) ";
        error_symbol = "[\\$](color_red bold) ";
        vimcmd_symbol = "[\\$](color_yellow bold) ";
      };
    };
  };
}

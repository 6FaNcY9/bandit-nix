{lib, ...}: let
  retroTheme = import ../../lib/retro-theme.nix;
in {
  programs.starship = {
    enable = true;
    enableFishIntegration = true;
    enableZshIntegration = true;
    settings = {
      palette = lib.mkForce "tomorrow_night_eighties";

      palettes.tomorrow_night_eighties = retroTheme.starshipPalette;

      format = "$hostname$username$directory$git_branch$git_status$nix_shell$cmd_duration$line_break$character";

      hostname = {
        ssh_only = false;
        style = "color_green bold";
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
        conflicted = "⚡";
        ahead = "⇡\${count}";
        behind = "⇣\${count}";
        diverged = "⇕⇡\${ahead_count}⇣\${behind_count}";
        modified = "!";
        untracked = "?";
        staged = "+";
        deleted = "✘";
        stashed = "stash";
        format = "[\\[$all_status$ahead_behind\\]]($style) ";
      };

      nix_shell = {
        format = "[\\[$symbol$state\\]]($style) ";
        style = "color_aqua bold";
        symbol = "nix:";
        impure_msg = "impure";
        pure_msg = "pure";
      };

      cmd_duration = {
        min_time = 2000;
        format = "[\\[$duration\\]]($style) ";
        style = "color_orange bold";
      };

      character = {
        success_symbol = "[\\$](color_green bold) ";
        error_symbol = "[\\$](color_red bold) ";
        vimcmd_symbol = "[\\$](color_yellow bold) ";
      };

      # Language modules — only shown inside relevant project dirs
      rust = {
        style = "color_orange bold";
        format = "via [$symbol($version)]($style) ";
      };
      python = {
        style = "color_blue bold";
        format = "via [$symbol$pyenv_prefix($version)($virtualenv)]($style) ";
      };
      nodejs = {
        style = "color_green bold";
        format = "via [$symbol($version)]($style) ";
      };
      golang = {
        style = "color_aqua bold";
        format = "via [$symbol($version)]($style) ";
      };
    };
  };
}

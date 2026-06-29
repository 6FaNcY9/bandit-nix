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

      # ╭─[ bandit ]─[ ~/src/bandit-nix ]─[  main ]─[ ~2⇡1 ]────[ 3s ]
      # ╰─$ _
      format = "[╭─](color_bg3)$hostname$directory$git_branch$git_status$nix_shell$rust$python$nodejs$golang$fill$cmd_duration$line_break[╰─](color_bg3)$character";

      fill = {
        symbol = "─";
        style = "color_bg3";
      };

      hostname = {
        ssh_only = false;
        format = "[\\[ $hostname \\]](color_green bold)[─](color_bg3)";
      };

      username = {
        style_user = "color_green bold";
        style_root = "color_red bold";
        format = "[\\[ $user \\]]($style)[─](color_bg3)";
        show_always = false;
      };

      directory = {
        style = "color_blue bold";
        format = "[\\[ $path$read_only \\]]($style)[─](color_bg3)";
        truncation_length = 4;
        truncate_to_repo = false;
        read_only = " ro";
      };

      git_branch = {
        style = "color_yellow bold";
        format = "[\\[ $symbol$branch \\]]($style)[─](color_bg3)";
        symbol = " ";
      };

      git_status = {
        style = "color_red bold";
        conflicted = "⚡";
        ahead = "⇡\${count}";
        behind = "⇣\${count}";
        diverged = "⇕⇡\${ahead_count}⇣\${behind_count}";
        modified = "~";
        untracked = "?";
        staged = "+";
        deleted = "✘";
        format = "[\\[ $all_status$ahead_behind \\]]($style)[─](color_bg3)";
      };

      nix_shell = {
        format = "[\\[ nix:$state \\]](color_aqua bold)[─](color_bg3)";
        impure_msg = "impure";
        pure_msg = "pure";
      };

      cmd_duration = {
        min_time = 2000;
        format = "[\\[ $duration \\]](color_orange bold)";
        style = "color_orange bold";
      };

      character = {
        success_symbol = "[\\$](color_green bold) ";
        error_symbol = "[\\$](color_red bold) ";
        vimcmd_symbol = "[\\$](color_yellow bold) ";
      };

      rust = {
        style = "color_orange bold";
        format = "[\\[ $symbol$version \\]]($style)[─](color_bg3)";
      };
      python = {
        style = "color_blue bold";
        format = "[\\[ $symbol$pyenv_prefix$version($virtualenv) \\]]($style)[─](color_bg3)";
      };
      nodejs = {
        style = "color_green bold";
        format = "[\\[ $symbol$version \\]]($style)[─](color_bg3)";
      };
      golang = {
        style = "color_aqua bold";
        format = "[\\[ $symbol$version \\]]($style)[─](color_bg3)";
      };
    };
  };
}

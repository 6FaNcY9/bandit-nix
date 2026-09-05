{
  config,
  pkgs,
  ...
}: let
  jq = "${pkgs.jq}/bin/jq";
  rofi = "${config.programs.rofi.package}/bin/rofi";
  wlCopy = "${pkgs.wl-clipboard}/bin/wl-copy";
  notifySend = "${pkgs.libnotify}/bin/notify-send";
  timeout = "${pkgs.coreutils}/bin/timeout";
in {
  # Searchable keybinding browser: aggregates live Hyprland binds (hyprctl)
  # and Neovim keymaps (headless nvim dump, cached) into one fuzzy-searchable
  # rofi menu. Selecting an entry copies the key combo. Bound to SUPER+F2
  # in home/desktop/hyprland.nix. Uses the retro-eighties rofi theme, which
  # follows the active Stylix palette.
  home.file.".local/share/keybinds-menu/nvim-dump.lua".text = ''
    local modes = {
      n = "Normal",
      v = "Visual",
      x = "Visual",
      s = "Select",
      i = "Insert",
      c = "Command",
      t = "Terminal",
      o = "Operator",
    }
    local lines = {}
    for mode, category in pairs(modes) do
      for _, map in ipairs(vim.api.nvim_get_keymap(mode)) do
        if map.desc and map.desc ~= "" and not map.lhs:match("^<Plug>") then
          lines[#lines + 1] = table.concat({ "Neovim", category, map.lhs, map.desc }, "\t")
        end
      end
    end
    table.sort(lines)
    vim.fn.writefile(lines, vim.env.OUT)
  '';

  home.file.".local/bin/keybinds-menu" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail

      cache_dir="$HOME/.cache/keybinds-menu"
      mkdir -p "$cache_dir"

      # ── Hyprland: live binds from the running session ────────────
      hyprland_tsv() {
        hyprctl binds -j 2>/dev/null | ${jq} -r '
          def modstr:
            [(if ((.modmask / 64) | floor) % 2 == 1 then "SUPER" else empty end),
             (if ((.modmask / 4) | floor) % 2 == 1 then "CTRL" else empty end),
             (if ((.modmask / 8) | floor) % 2 == 1 then "ALT" else empty end),
             (if .modmask % 2 == 1 then "SHIFT" else empty end)] | join(" + ");

          # Lua-configured binds report dispatcher as "__lua N", so the
          # category is derived from the (Nix-controlled) description text.
          def category:
            if (.submap // "") != "" then "Modes"
            elif (.description | test("workspace|scratchpad"; "i")) then "Workspaces"
            elif (.description | test("^focus"; "i")) then "Focus"
            elif (.description | test("volume|brightness|track|play/pause|mute"; "i")) then "Media"
            elif (.description | test("notification|do-not-disturb"; "i")) then "Notifications"
            elif (.description | test("screenshot"; "i")) then "Capture"
            elif (.description | test("^open |launcher|picker"; "i")) then "Launch"
            elif (.description | test("lock screen|power menu|reload|cheatsheet|keybinding|mouse"; "i")) then "System"
            elif (.description | test("window|group|split|fullscreen|floating|pseudotile|pin|resize"; "i")) then "Window/Layout"
            else "Misc" end;

          .[]
          | select(.key != "")
          | (.dispatcher + (if ((.arg // "") != "") then " " + .arg else "" end)) as $fallback
          | (if ((.description // "") != "") then .description else $fallback end) as $action
          | modstr as $mods
          | (if $mods == "" then .key else $mods + " + " + .key end) as $combo
          | ["Hyprland", category, $combo, $action]
          | @tsv
        ' || true
      }

      # ── Neovim: headless keymap dump, cached per config ─────────
      # The cache is invalidated when the nvim binary or the generated
      # ~/.config/nvim/init.lua changes (i.e. after every rebuild that
      # touches the editor config).
      nvim_tsv() {
        local stamp_file="$cache_dir/nvim.stamp"
        local data_file="$cache_dir/nvim.tsv"
        local nvim_bin
        nvim_bin=$(command -v nvim) || return 0
        local stamp
        stamp="$(readlink -f "$nvim_bin") $(readlink -f "$HOME/.config/nvim/init.lua" 2>/dev/null || echo none)"
        if [[ ! -f "$data_file" || ! -f "$stamp_file" || "$(cat "$stamp_file")" != "$stamp" ]]; then
          local tmp="$cache_dir/nvim.tsv.tmp"
          if OUT="$tmp" ${timeout} 20 "$nvim_bin" --headless \
            -c "luafile $HOME/.local/share/keybinds-menu/nvim-dump.lua" \
            -c "qa!" </dev/null &>/dev/null \
            && [[ -s "$tmp" ]]; then
            mv "$tmp" "$data_file"
            printf '%s' "$stamp" > "$stamp_file"
          fi
        fi
        [[ -f "$data_file" ]] && cat "$data_file" || true
      }

      # ── Merge, sort by app → category → key, show in rofi ───────
      mapfile -t rows < <({ hyprland_tsv; nvim_tsv; } | sort -t $'\t' -k1,1 -k2,2 -k3,3)
      if ((''${#rows[@]} == 0)); then
        ${notifySend} -a keybinds-menu "No keybindings found"
        exit 1
      fi

      display=()
      keys=()
      for row in "''${rows[@]}"; do
        IFS=$'\t' read -r app category combo action <<< "$row"
        display+=("$app · $category · $combo — $action")
        keys+=("$combo")
      done

      idx=$(printf '%s\n' "''${display[@]}" | ${rofi} -dmenu -i -p "keys" -format i -theme retro-eighties -no-show-icons) || exit 0
      [[ -n "$idx" ]] || exit 0

      printf '%s' "''${keys[$idx]}" | ${wlCopy}
      ${notifySend} -a keybinds-menu "Keybinding copied" "''${keys[$idx]}"
    '';
  };
}

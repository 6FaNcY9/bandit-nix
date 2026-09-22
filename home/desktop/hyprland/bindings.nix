{
  config,
  pkgs,
  lib,
  ...
}: let
  mod = "SUPER";

  # Home Manager's Lua renderer requires structured call arguments. Inline
  # values are limited to dispatcher callbacks that must remain Lua code.
  # Every bind carries a description flag: hyprctl binds reports Lua
  # dispatchers only as opaque "__lua N", so the description is what makes
  # binds introspectable (used by ~/.local/bin/keybinds-menu).
  lua = lib.generators.mkLuaInline;
  bind = keyCombo: dispatcher: description: {
    _args = [keyCombo (lua dispatcher) {inherit description;}];
  };
  bindWithOptions = keyCombo: dispatcher: options: description: {
    _args = [keyCombo (lua dispatcher) (options // {inherit description;})];
  };
  execBinding = keyCombo: command: description:
    bind keyCombo "hl.dsp.exec_cmd(${builtins.toJSON command})" description;

  # ─── Helpers ──────────────────────────────────────────
  pactlBin = "${pkgs.pulseaudio}/bin/pactl";
  brightnessctlBin = "${pkgs.brightnessctl}/bin/brightnessctl";
  playerctlBin = "${pkgs.playerctl}/bin/playerctl";

  # ─── Directional focus (vim + arrows) ─────────────────
  directionalFocus = [
    (bind "${mod} + j" ''hl.dsp.focus({ direction = "left" })'' "focus window left")
    (bind "${mod} + k" ''hl.dsp.focus({ direction = "down" })'' "focus window down")
    (bind "${mod} + l" ''hl.dsp.focus({ direction = "up" })'' "focus window up")
    (bind "${mod} + semicolon" ''hl.dsp.focus({ direction = "right" })'' "focus window right")
    (bind "${mod} + Left" ''hl.dsp.focus({ direction = "left" })'' "focus window left")
    (bind "${mod} + Down" ''hl.dsp.focus({ direction = "down" })'' "focus window down")
    (bind "${mod} + Up" ''hl.dsp.focus({ direction = "up" })'' "focus window up")
    (bind "${mod} + Right" ''hl.dsp.focus({ direction = "right" })'' "focus window right")
  ];

  # ─── Directional move (Shift + vim/arrows) ────────────
  directionalMove = [
    (bind "${mod} + SHIFT + j" ''hl.dsp.window.move({ direction = "left", group_aware = true })'' "move window left")
    (bind "${mod} + SHIFT + k" ''hl.dsp.window.move({ direction = "down", group_aware = true })'' "move window down")
    (bind "${mod} + SHIFT + l" ''hl.dsp.window.move({ direction = "up", group_aware = true })'' "move window up")
    (bind "${mod} + SHIFT + semicolon" ''hl.dsp.window.move({ direction = "right", group_aware = true })'' "move window right")
    (bind "${mod} + SHIFT + Left" ''hl.dsp.window.move({ direction = "left", group_aware = true })'' "move window left")
    (bind "${mod} + SHIFT + Down" ''hl.dsp.window.move({ direction = "down", group_aware = true })'' "move window down")
    (bind "${mod} + SHIFT + Up" ''hl.dsp.window.move({ direction = "up", group_aware = true })'' "move window up")
    (bind "${mod} + SHIFT + Right" ''hl.dsp.window.move({ direction = "right", group_aware = true })'' "move window right")
  ];

  # ─── Layout management (dwindle) ──────────────────────
  # i3's parent/child focus and container-level split have no equivalent in
  # Hyprland's flat dwindle model, so those bindings are dropped rather than
  # faked; see the cheatsheet for exactly what's bound.
  layoutBindings = [
    (bind "${mod} + f" "hl.dsp.window.fullscreen()" "toggle fullscreen")
    (bind "${mod} + CTRL + f" ''hl.dsp.window.fullscreen_state({ internal = 2, client = 0, action = "toggle" })'' "fullscreen without app mode")
    (bind "${mod} + e" ''hl.dsp.layout("togglesplit")'' "toggle split orientation")
    (bind "${mod} + CTRL + e" ''hl.dsp.layout("swapsplit")'' "swap split branches")
    (bind "${mod} + s" "hl.dsp.group.toggle()" "toggle tab group")
    (bind "${mod} + Tab" "hl.dsp.group.next()" "next window in group")
    (bind "${mod} + SHIFT + Tab" "hl.dsp.group.prev()" "previous window in group")
    (bind "${mod} + CTRL + Tab" "hl.dsp.group.move_window({ forward = true })" "move window forward in group")
    (bind "${mod} + CTRL + SHIFT + Tab" "hl.dsp.group.move_window({ forward = false })" "move window backward in group")
    (bind "${mod} + CTRL + o" "hl.dsp.window.move({ out_of_group = true })" "remove window from group")
    (bind "${mod} + SHIFT + s" ''hl.dsp.group.lock_active({ action = "toggle" })'' "lock active group")
    (bind "${mod} + p" "hl.dsp.window.pseudo()" "toggle pseudotile")
    (bind "${mod} + SHIFT + SPACE" ''hl.dsp.window.float({ action = "toggle" })'' "toggle floating")
    (bind "${mod} + CTRL + SPACE" ''hl.dsp.window.pin({ action = "toggle" })'' "pin floating window")
    (bind "${mod} + a" "hl.dsp.focus({ last = true })" "focus last window")
    (bind "${mod} + g" ''hl.dsp.workspace.toggle_special("scratchpad")'' "toggle scratchpad workspace")
    (bind "${mod} + SHIFT + g" ''hl.dsp.window.move({ workspace = "special:scratchpad" })'' "move window to scratchpad")
  ];

  mouseBindings = [
    (bindWithOptions "${mod} + mouse:272" "hl.dsp.window.drag()" {mouse = true;} "drag window with mouse")
    (bindWithOptions "${mod} + mouse:273" "hl.dsp.window.resize()" {mouse = true;} "resize window with mouse")
  ];

  workspaceScroll = [
    (bind "${mod} + mouse_down" ''hl.dsp.focus({ workspace = "e+1" })'' "next workspace (scroll)")
    (bind "${mod} + mouse_up" ''hl.dsp.focus({ workspace = "e-1" })'' "previous workspace (scroll)")
  ];

  # ─── System / app launchers ────────────────────────────
  systemBindings = [
    (execBinding "${mod} + Return" "${pkgs.kitty}/bin/kitty" "open terminal (kitty)")
    (execBinding "${mod} + SHIFT + w" "${pkgs.firefox}/bin/firefox" "open Firefox")
    (execBinding "${mod} + SHIFT + e" "${pkgs.thunderbird}/bin/thunderbird" "open Thunderbird")
    (execBinding "${mod} + SHIFT + f" "${pkgs.pcmanfm}/bin/pcmanfm" "open file manager")
    (execBinding "${mod} + d" "${config.programs.rofi.package}/bin/rofi -show drun" "app launcher (rofi)")
    (execBinding "${mod} + SHIFT + v" "${pkgs.cliphist}/bin/cliphist list | ${config.programs.rofi.package}/bin/rofi -dmenu | ${pkgs.cliphist}/bin/cliphist decode | ${pkgs.wl-clipboard}/bin/wl-copy" "clipboard history picker")

    (bind "${mod} + SHIFT + q" "hl.dsp.window.close()" "close window")
    (execBinding "${mod} + SHIFT + c" "hyprctl reload" "reload Hyprland config")
    (bind "${mod} + r" ''hl.dsp.submap("resize")'' "enter resize mode")
    (execBinding "${mod} + SHIFT + x" "${pkgs.hyprlock}/bin/hyprlock" "lock screen")

    (execBinding "XF86PowerOff" "~/.local/bin/powermenu" "power menu")
    (execBinding "${mod} + Escape" "~/.local/bin/powermenu" "power menu")

    (execBinding "${mod} + F1" "~/.local/bin/hyprland-cheatsheet-show" "shortcut cheatsheet")
    (execBinding "${mod} + F2" "~/.local/bin/keybinds-menu" "keybinding search (rofi, incl. Neovim)")

    (execBinding "Print" "~/.local/bin/hypr-screenshot" "region screenshot")
    (execBinding "F11" "~/.local/bin/hypr-screenshot" "region screenshot")

    # Mako notification controls
    (execBinding "${mod} + grave" "${pkgs.mako}/bin/makoctl restore" "restore last notification")
    (execBinding "${mod} + SHIFT + d" "${pkgs.mako}/bin/makoctl mode -t dnd" "toggle do-not-disturb")
    (execBinding "${mod} + SHIFT + period" "${pkgs.mako}/bin/makoctl dismiss --all" "dismiss all notifications")
  ];

  # ─── Media keys ────────────────────────────────────────
  mediaKeys = [
    (execBinding "XF86AudioRaiseVolume" "${pactlBin} set-sink-volume @DEFAULT_SINK@ +5%" "volume up")
    (execBinding "XF86AudioLowerVolume" "${pactlBin} set-sink-volume @DEFAULT_SINK@ -5%" "volume down")
    (execBinding "XF86AudioMute" "${pactlBin} set-sink-mute @DEFAULT_SINK@ toggle" "mute toggle")
    (execBinding "XF86AudioMicMute" "${pactlBin} set-source-mute @DEFAULT_SOURCE@ toggle" "mic mute toggle")
    (execBinding "XF86MonBrightnessUp" "${brightnessctlBin} set +10%" "brightness up")
    (execBinding "XF86MonBrightnessDown" "${brightnessctlBin} set 10%-" "brightness down")
    (execBinding "XF86AudioPlay" "${playerctlBin} play-pause" "play/pause")
    (execBinding "XF86AudioNext" "${playerctlBin} next" "next track")
    (execBinding "XF86AudioPrev" "${playerctlBin} previous" "previous track")
  ];

  # ─── Workspaces (explicit, no helper) ─────────────────
  workspaceSwitch = builtins.genList (i: let
    n = i + 1;
  in
    bind "${mod} + ${toString (lib.mod n 10)}" "hl.dsp.focus({ workspace = ${toString n} })" "switch to workspace ${toString n}")
  10;

  workspaceMove = builtins.genList (i: let
    n = i + 1;
  in
    bind "${mod} + SHIFT + ${toString (lib.mod n 10)}" "hl.dsp.window.move({ workspace = ${toString n} })" "move window to workspace ${toString n}")
  10;

  resizeBindings = [
    (bindWithOptions "j" "hl.dsp.window.resize({ x = -10, y = 0, relative = true })" {repeating = true;} "resize window left")
    (bindWithOptions "k" "hl.dsp.window.resize({ x = 0, y = 10, relative = true })" {repeating = true;} "resize window down")
    (bindWithOptions "l" "hl.dsp.window.resize({ x = 0, y = -10, relative = true })" {repeating = true;} "resize window up")
    (bindWithOptions "semicolon" "hl.dsp.window.resize({ x = 10, y = 0, relative = true })" {repeating = true;} "resize window right")
    (bindWithOptions "Left" "hl.dsp.window.resize({ x = -10, y = 0, relative = true })" {repeating = true;} "resize window left")
    (bindWithOptions "Down" "hl.dsp.window.resize({ x = 0, y = 10, relative = true })" {repeating = true;} "resize window down")
    (bindWithOptions "Up" "hl.dsp.window.resize({ x = 0, y = -10, relative = true })" {repeating = true;} "resize window up")
    (bindWithOptions "Right" "hl.dsp.window.resize({ x = 10, y = 0, relative = true })" {repeating = true;} "resize window right")
    (bind "Return" ''hl.dsp.submap("reset")'' "exit resize mode")
    (bind "Escape" ''hl.dsp.submap("reset")'' "exit resize mode")
    (bind "${mod} + r" ''hl.dsp.submap("reset")'' "exit resize mode")
  ];
in {
  wayland.windowManager.hyprland = {
    settings.bind =
      directionalFocus
      ++ directionalMove
      ++ layoutBindings
      ++ systemBindings
      ++ mediaKeys
      ++ workspaceSwitch
      ++ workspaceMove
      ++ workspaceScroll
      ++ mouseBindings;

    submaps = {
      resize = {
        onDispatch = "reset";
        settings.bind = resizeBindings;
      };
    };
  };
}

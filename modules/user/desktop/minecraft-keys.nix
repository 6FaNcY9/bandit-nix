{
  config,
  lib,
  ...
}: let
  c = config.lib.stylix.colors.withHashtag;
  rofi = "${config.programs.rofi.package}/bin/rofi";

  # Minecraft key help (Mod+M): a searchable rofi overlay, also over the
  # fullscreen game. Short words, one key per row, a coloured category in
  # front, so it reads quickly (the user has ADHD and dyslexia).
  # Source of truth: the 26.2 instance configs (Meteor modules.nbt and
  # macros.nbt, IPN inventoryprofiles.json, options.txt), checked on
  # 2026-11-11. Update these rows when a bind changes.
  cats = {
    kampf = {
      glyph = "󰓥";
      label = "KAMPF";
      color = c.base08;
    };
    werkzeug = {
      glyph = "󰖷";
      label = "WERKZEUG";
      color = c.base0D;
    };
    sehen = {
      glyph = "󰈈";
      label = "SEHEN";
      color = c.base0C;
    };
    inventar = {
      glyph = "󰜦";
      label = "INVENTAR";
      color = c.base0B;
    };
    makro = {
      glyph = "󰞷";
      label = "MAKRO";
      color = c.base0A;
    };
    karte = {
      glyph = "󰍍";
      label = "KARTE";
      color = c.base0E;
    };
    menue = {
      glyph = "󰍜";
      label = "MENÜ";
      color = c.base09;
    };
    spiel = {
      glyph = "󰍳";
      label = "SPIEL";
      color = c.base05;
    };
  };

  rows = [
    ["kampf" "↑" "PvP AN · Kill Aura, Totem, Gapple, Crits"]
    ["kampf" "↓" "PvP AUS"]
    ["kampf" "Alt+C" "Crystal Aura · Kristalle setzen + zünden"]
    ["kampf" "Alt+X" "Surround · Obsidian um die Füße"]
    ["kampf" "Alt+Y" "Self Trap · Obsidian über den Kopf"]
    ["kampf" "Alt+Z" "Auto Trap · Gegner einsperren"]
    ["kampf" "Alt+Tab" "Auto City · Obsidian vom Gegner aufbrechen"]
    ["kampf" "Alt+R" "Speed · schneller laufen"]
    ["kampf" "R dann 5" "Hotbar für Crystal-PvP ordnen"]
    ["werkzeug" "Strg+R" "Elytra Fly"]
    ["werkzeug" "Strg+C" "Chest Swap · Brustplatte ⇄ Elytra"]
    ["werkzeug" "Strg+X" "Freecam"]
    ["werkzeug" "Strg+Y" "Scaffold · Blöcke unter dir"]
    ["werkzeug" "H" "Air Place · Block in die Luft"]
    ["werkzeug" "N" "Safe Walk · nicht von Kanten fallen"]
    ["werkzeug" "," "Flight · fliegen"]
    ["werkzeug" "Maus hinten" "Free Look · halten = umschauen"]
    ["sehen" "J" "ESP · Spieler und Mobs markieren"]
    ["sehen" "K" "Storage ESP · Kisten finden"]
    ["sehen" "I" "X-Ray"]
    ["sehen" "←" "Light Overlay · dunkle Stellen zeigen"]
    ["sehen" "Maus vorne" "Zoom · halten, Mausrad = stärker"]
    ["inventar" "Alt+1" "Profil Survival"]
    ["inventar" "Alt+2" "Profil Bauen"]
    ["inventar" "Alt+3" "Profil Kampf"]
    ["inventar" "Alt+4" "Profil Elytra"]
    ["inventar" "R dann 5" "Profil Crystal-PvP"]
    ["inventar" "R" "im Inventar: sortieren"]
    ["inventar" "R dann C" "IPN-Einstellungen"]
    ["inventar" "Alt+6" "Auto Drop an/aus"]
    ["inventar" "F" "Item in die Offhand"]
    ["inventar" "Q" "Item wegwerfen"]
    ["makro" "Alt+5" "Müll löschen · Cobble, Erde, Kies"]
    ["makro" "Alt+8" "Tag"]
    ["makro" "Alt+9" "Sonne"]
    ["makro" "Alt+0" "Survival-Modus"]
    ["makro" "Alt+-" "Creative-Modus"]
    ["makro" "Alt+Bild↑" "Reisemodus AN · Auto Walk, Auto Log"]
    ["makro" "Alt+Bild↓" "Reisemodus AUS"]
    ["karte" "M" "Weltkarte"]
    ["karte" "B" "neuer Wegpunkt"]
    ["karte" "U" "alle Wegpunkte"]
    ["karte" "Z" "halten = Minimap groß"]
    ["karte" "Enter" "Sofort-Wegpunkt"]
    ["menue" "Rechts-Shift" "Meteor-Menü (nur am K6)"]
    ["menue" "." "Meteor-Befehl"]
    ["menue" "G" "Admin-Befehle"]
    ["menue" "T" "Chat"]
    ["menue" "/" "Befehl"]
    ["menue" "Rücktaste" "Sprachchat-Menü"]
    ["menue" "Pos1" "Mikro stumm"]
    ["menue" "Super+M" "diese Hilfe"]
    ["menue" "Super+H" "alle Tasten vom Laptop suchen"]
    ["spiel" "W A S D" "laufen"]
    ["spiel" "Leertaste" "springen"]
    ["spiel" "Links-Shift" "schleichen"]
    ["spiel" "Links-Strg" "sprinten"]
    ["spiel" "E" "Inventar"]
    ["spiel" "Tab" "Spielerliste"]
    ["spiel" "V" "Perspektive"]
    ["spiel" "L" "Fortschritte"]
    ["spiel" "F1" "HUD aus · K6: Fn2+1"]
    ["spiel" "F3" "Debug-Anzeige · K6: Fn2+3"]
  ];

  # Nix strings are bytes; count the few multibyte glyphs used here as one
  # column so the monospace columns line up.
  width = s: builtins.stringLength (builtins.replaceStrings ["↑" "↓" "←" "Ü" "ü"] ["x" "x" "x" "x" "x"] s);
  pad = n: s: s + lib.concatStrings (lib.replicate (lib.max 1 (n - width s)) " ");
  row = r: let
    cat = cats.${builtins.elemAt r 0};
  in "<span color='${cat.color}'>${cat.glyph} ${pad 9 cat.label}</span><b>${pad 13 (builtins.elemAt r 1)}</b>${builtins.elemAt r 2}";
in {
  home.file.".local/bin/mc-keys" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      # Toggle: a second Mod+M closes the open help.
      pkill -x rofi && exit 0
      cat <<'ROWS' | ${rofi} -dmenu -i -markup-rows -no-custom -no-show-icons \
        -p "󰍳 Tasten" -mesg "Tippen = suchen   ·   Esc = zu" \
        -theme retro-eighties -font "FiraCode Nerd Font Mono SemiBold 15" \
        -theme-str 'window { width: 62%; } listview { lines: 16; } prompt { font: "FiraCode Nerd Font Bold 15"; } textbox { font: "FiraCode Nerd Font 13"; }' >/dev/null
      ${lib.concatMapStringsSep "\n" row rows}
      ROWS
    '';
  };
}

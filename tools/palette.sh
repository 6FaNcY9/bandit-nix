#!/usr/bin/env bash
# rofi command palette: Claude, hack and switch rows plus the other menus in one list; the picked action runs after rofi has returned.
# Env: PAL_DIM / PAL_WARN (pango colours). Stream mode masks target and VPN IP with •••.
# Commands: rofi lage waybar-target waybar-stream makoctl hypr-cockpit keybinds-menu net-menu powermenu hypr-screenshot cliphist wl-copy kitty notify-send jq sed grep ls
set -euo pipefail
PATH=$PATH:$HOME/.local/bin # Hyprland's PATH lacks it; appended so Nix inputs and test stubs win
dim=${PAL_DIM:-#848488} warn=${PAL_WARN:-#fdb827}

esc() { sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' <<<"$1"; }
shown() { if ((stream)); then echo '•••'; else echo "$1"; fi; }
# pick <rofi args>: rows on stdin, prints the picked index; fails on Esc, an empty answer or -1 (typed text that matches no row)
pick() { rofi -dmenu -i -format i -theme retro-eighties -no-show-icons "$@" | grep -xE '[0-9]+'; }

acts=() plain=() marks=()
row() { # row <action> <group> <label> [value or key hint] [label markup]: plain text is what rofi filters on, markup what it shows
  local g v=${4:-}
  printf -v g '%-8s' "$2"
  acts+=("$1") plain+=("$g $3${v:+  $v}")
  marks+=("<span color=\"$dim\">$g</span> ${5:-$3}${v:+  <span color=\"$dim\">$(esc "$v")</span>}")
}
sw() { # sw <action> <name> <on 0|1>
  if (($3)); then row "$1" Schalter "$2: AN" "" "$2: <span color=\"$warn\">AN</span>"; else row "$1" Schalter "$2: AUS"; fi
}

folder() { # newest repo first; worktrees have a .git file and are skipped
  local g dirs=() i
  while IFS= read -r g; do if [[ -d $g ]]; then dirs+=("${g%/.git}"); fi; done < <(ls -dt "$HOME"/src/*/.git 2>/dev/null)
  if ((${#dirs[@]} == 0)); then notify-send Palette "Keine Ordner"; return 0; fi
  i=$(printf '%s\n' "${dirs[@]##*/}" | pick -p ordner) || return 0
  exec kitty --directory "${dirs[i]}" claude
}
clip() { # Esc must not reach wl-copy, which would empty the clipboard
  local c
  c=$(cliphist list | rofi -dmenu) || return 0
  cliphist decode <<<"$c" | wl-copy
}

vpn='' target=''
{ IFS= read -r vpn || true; IFS= read -r target || true; } < <(waybar-target get 2>/dev/null)
stream=0; if waybar-stream status >/dev/null 2>&1; then stream=1; fi
dnd=0; if grep -qx dnd <<<"$(makoctl mode 2>/dev/null || true)"; then dnd=1; fi
n=$(lage bar 2>/dev/null | jq -r '.text | capture("▲ (?<n>[0-9]+)").n' 2>/dev/null || true)
n=${n:-0}

if ((n > 0)); then row "lage bar --focus" KI "Claude wartet: $n" "" "<span color=\"$warn\">Claude wartet: $n</span>"; else row "lage bar --focus" KI "Claude: nichts offen"; fi
row hypr-cockpit KI Cockpit Super+C
row folder KI "Claude in Ordner …"
if [[ -n $target ]]; then row "waybar-target copy target" Hacken "Ziel-IP kopieren" "$(shown "$target")"; fi
if [[ -n $vpn ]]; then row "waybar-target copy vpn" Hacken "VPN-IP kopieren" "$(shown "$vpn")"; fi
sw "waybar-stream toggle" Stream "$stream"
sw "makoctl mode -t dnd" Ruhe "$dnd"
row "rofi -show drun" Menüs Programme Super+D
row keybinds-menu Menüs Tasten Super+H
row net-menu Menüs Netz
row clip Menüs Ablage Super+Shift+V
row hypr-screenshot Menüs Bildschirmfoto Super+Shift+S
row powermenu Menüs "Aus / Sperren" Super+Esc

mesg=
if ((n > 0)); then mesg="Claude wartet: $n · "; fi
mesg+="Stream $(if ((stream)); then echo AN; else echo AUS; fi)"
if [[ -n $target ]]; then mesg+=" · Ziel $(shown "$target")"; fi

i=$(
  for k in "${!acts[@]}"; do printf '%s\0display\x1f%s\n' "${plain[k]}" "${marks[k]}"; done |
    pick -markup-rows -p befehl -theme-str 'listview { lines: 13; }' -mesg "$(esc "$mesg")"
) || exit 0

# the action words are a command line; folder and clip are the functions above
case ${acts[i]} in
  folder) folder ;;
  clip) clip ;;
  *) read -ra cmd <<<"${acts[i]}"; "${cmd[@]}" ;;
esac

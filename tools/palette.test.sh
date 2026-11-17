#!/usr/bin/env bash
# Test for tools/palette.sh with stub commands first on PATH (a stub rofi picks a row by text, never a real menu).
# Run: tools/palette.test.sh
set -euo pipefail
trap 'echo "FAIL at line $LINENO" >&2' ERR
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT

# Stubs, steered per call by env vars: PICK='a|b' (n-th rofi call picks the first row containing the n-th pattern, none = Esc),
# WAIT=N, LAGE=fail, VPN/TARGET (default 10.10.14.7 / 10.10.11.5), STREAM=on, MODES (makoctl mode output).
# Everything but the read-only queries (lage bar, waybar-stream status, waybar-target get, makoctl mode) logs "<name> <args>" to $t/log.
export BAR_TEST_DIR=$t HOME=$t/home LC_ALL=C.UTF-8 # the palette pads the group column by characters, which needs a UTF-8 locale
mkdir -p "$t/stub" "$HOME/src"
stub() { cat >"$t/stub/$1"; chmod +x "$t/stub/$1"; } # stub <name>: stdin is the script
stub rofi <<'EOF'
#!/usr/bin/env bash
d=$BAR_TEST_DIR
n=$(( $(cat "$d/rofi.n" 2>/dev/null || echo 0) + 1 )); echo "$n" >"$d/rofi.n"
cat >"$d/rofi.$n"; echo "$*" >"$d/rofi.$n.args"
IFS='|' read -ra picks <<<"${PICK:-}"; pat=${picks[n-1]:-}
[[ -n $pat ]] || exit 1
[[ $pat == @custom ]] && { echo -1; exit 0; } # typed text that matches no row: rofi -format i prints -1
i=0
while IFS= read -r plain; do
  if [[ ${plain,,} == *"${pat,,}"* ]]; then echo "$i"; exit 0; fi
  i=$((i + 1))
done < <(tr '\0' '\t' <"$d/rofi.$n" | cut -f1)
exit 1
EOF
stub lage <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-}:${2:-} == bar: ]]; then
  [[ ${LAGE:-ok} == ok ]] || exit 1
  echo "{\"text\":\"● 1 ▲ ${WAIT:-2}\"}"; exit 0
fi
echo "lage $*" >>"$BAR_TEST_DIR/log"
EOF
stub waybar-stream <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == status ]]; then [[ ${STREAM:-off} == on ]]; exit; fi
echo "waybar-stream $*" >>"$BAR_TEST_DIR/log"
EOF
stub waybar-target <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == get ]]; then printf '%s\n%s\n' "${VPN-10.10.14.7}" "${TARGET-10.10.11.5}"; exit 0; fi
echo "waybar-target $*" >>"$BAR_TEST_DIR/log"
EOF
stub makoctl <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-}:${2:-} == mode: ]]; then printf '%s\n' "${MODES:-default}"; exit 0; fi
echo "makoctl $*" >>"$BAR_TEST_DIR/log"
EOF
stub cliphist <<'EOF'
#!/usr/bin/env bash
echo "cliphist $*" >>"$BAR_TEST_DIR/log"
[[ ${1:-} == list ]] && echo '1 clip'
exit 0
EOF
for c in kitty keybinds-menu net-menu powermenu hypr-cockpit hypr-screenshot notify-send wl-copy; do
  stub "$c" <<'EOF'
#!/usr/bin/env bash
echo "$(basename "$0")${*:+ $*}" >>"$BAR_TEST_DIR/log" # no trailing space without args
EOF
done
export PATH=$t/stub:$PATH

pal() { rm -f "$t"/rofi.*; : >"$t/log"; bash "$here/palette.sh"; }
rows() { tr '\0' '\t' <"$t/rofi.1" | cut -f1; } # the plain (filter) part of every main row
no() { if "$@"; then echo "FAIL at line ${BASH_LINENO[0]}: unexpected: $*" >&2; exit 1; fi; } # no <cmd...>: must fail

PICK=Stream pal; grep -qx 'waybar-stream toggle' "$t/log"
grep -q -- '-mesg Claude wartet: 2 · Stream AUS · Ziel 10.10.11.5' "$t/rofi.1.args"
[[ $(rows | wc -l) == 13 ]]; rows | head -1 | grep -q 'Claude wartet: 2'
flags() { local f; for f in "${@:2}"; do grep -q -- "$f" "$1" || { echo "FAIL at line ${BASH_LINENO[0]}: no $f in $1" >&2; exit 1; }; done; } # flags <args file> <flag>...
flags "$t/rofi.1.args" -dmenu -i -markup-rows "-format i" "-p befehl" "-theme retro-eighties" -no-show-icons "-theme-str listview { lines: 13; }"
grep -qw -- -no-sort "$t/rofi.1.args"                                                     # table order must win over fuzzy sorting
rows | grep -qF 'Menüs    Netz'; rows | grep -qF 'Hacken   Ziel-IP kopieren'                # group padded to 8 characters, not bytes
grep -q 'color="#fdb827">Claude wartet: 2<' "$t/rofi.1"; grep -q 'color="#848488">KI ' "$t/rofi.1"   # default colours without the Nix wrapper
PICK=Ruhe pal; grep -qx 'makoctl mode -t dnd' "$t/log"
MODES=$'default\ndnd\nstream' PICK=x pal; rows | grep -q 'Ruhe: AN'
grep -q 'Ruhe: <span color="#fdb827">AN</span>' "$t/rofi.1"
PICK=hack pal; grep -qx 'waybar-target copy target' "$t/log"
PICK='VPN-IP' pal; grep -qx 'waybar-target copy vpn' "$t/log"
PICK=Netz pal; grep -qx 'net-menu' "$t/log"
PAL_DIM=DIM PAL_WARN=WARN PICK=x pal; grep -q 'color="WARN">Claude wartet: 2<' "$t/rofi.1"; grep -q 'color="DIM">Hacken' "$t/rofi.1"
STREAM=on PICK=x pal; no grep -q '10\.10\.' "$t/rofi.1" "$t/rofi.1.args"; grep -q '•••' "$t/rofi.1"; grep -q 'Stream AN · Ziel •••' "$t/rofi.1.args"
TARGET='' VPN='' PICK=x pal; if rows | grep -q Hacken; then false; fi; [[ $(rows | wc -l) == 11 ]]
TARGET='a&b<c>' PICK=x pal; grep -q 'a&amp;b&lt;c&gt;' "$t/rofi.1"; grep -q 'Ziel a&amp;b&lt;c&gt;' "$t/rofi.1.args"
TARGET='' PICK=x pal; [[ $(rows | wc -l) == 12 ]]; no grep -q 'Ziel' "$t/rofi.1.args"      # VPN row only
WAIT=0 PICK=x pal; rows | head -1 | grep -q 'Claude: nichts offen'; no grep -q 'Claude wartet' "$t/rofi.1.args"
LAGE=fail PICK=x pal; rows | head -1 | grep -q 'Claude: nichts offen'
pal; [[ ! -s $t/log ]]                                                                    # Esc: nothing runs
PICK=@custom pal; [[ ! -s $t/log ]]                                                           # -1 must not pick the last row
for p in 'wartet:lage bar --focus' 'Cockpit:hypr-cockpit' 'Tasten:keybinds-menu' 'Bildschirmfoto:hypr-screenshot' 'Aus /:powermenu'; do
  PICK=${p%%:*} pal; grep -qx "${p#*:}" "$t/log"
done
PICK='Ablage|clip' pal; grep -qx 'cliphist decode' "$t/log"; grep -q '^wl-copy' "$t/log"
PICK='Ablage' pal; no grep -q 'cliphist decode' "$t/log"                                  # Esc in the picker: clipboard untouched

# folders: git repos with a .git dir, worktrees (.git file) skipped, newest .git first
mkdir -p "$HOME/src/alpha/.git" "$HOME/src/zeta/.git" "$HOME/src/wt"; echo 'gitdir: x' >"$HOME/src/wt/.git"
touch -d '2 days ago' "$HOME/src/alpha/.git"
PICK='in Ordner|zeta' pal; grep -qx "kitty --directory $HOME/src/zeta claude" "$t/log"
[[ $(cat "$t/rofi.2") == $'zeta\nalpha' ]]
PICK='in Ordner|alpha' pal; grep -qx "kitty --directory $HOME/src/alpha claude" "$t/log"
flags "$t/rofi.2.args" -dmenu -i "-format i" "-p ordner" "-theme retro-eighties" -no-show-icons; grep -qw -- -no-sort "$t/rofi.2.args"
PICK='in Ordner' pal; no grep -q kitty "$t/log"                                           # Esc in the 2nd list
PICK='in Ordner|@custom' pal; no grep -q kitty "$t/log"                                   # -1 in the 2nd list: not the last folder
HOME=$t/none PICK='in Ordner' pal; grep -qx 'notify-send Palette Keine Ordner' "$t/log"; [[ ! -e $t/rofi.2 ]]

echo ok

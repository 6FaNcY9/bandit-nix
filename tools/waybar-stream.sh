#!/usr/bin/env bash
# Stream mode: hides IPs and the hostname on the bar and mutes mako while the screen is shared (auto) or toggled by hand (manual).
# State = flag files bar-stream-auto / bar-stream-manual in $XDG_RUNTIME_DIR, on while either exists; this is the only place that touches them.
# `status` exits 0 when on. `text <value>` prints Waybar JSON. Every other subcommand exits 0: mako or Waybar may not be running.
set -euo pipefail

dir=${XDG_RUNTIME_DIR:-}
auto=$dir/bar-stream-auto
manual=$dir/bar-stream-manual

on() { [[ -n $dir ]] && { [[ -e $auto ]] || [[ -e $manual ]]; }; }

case ${1:-}:${2:-} in
  status:*) on ;;
  text:*)
    v=${2:-}
    if on; then v=•••; fi
    v=${v//\\/\\\\}; v=${v//\"/\\\"} # shortcut: escapes only \ and ", fine for IPs and hostnames
    printf '{"text":"%s"}\n' "$v" ;;
  toggle:* | auto:on | auto:off)
    [[ -n $dir ]] || { echo "waybar-stream: XDG_RUNTIME_DIR is not set, nothing changed" >&2; exit 0; }
    case $1:${2:-} in
      toggle:*) if [[ -e $manual ]]; then rm -f "$manual"; else : >"$manual"; fi ;;
      auto:on) : >"$auto" ;;
      auto:off) rm -f "$auto" ;;
    esac
    # mako leaves stream mode only when both flags are gone; signal 8 makes Waybar redraw its modules.
    # `-a` appends without a duplicate check and `-r` removes one entry, so add only when absent (grep without -q: no SIGPIPE under pipefail).
    if on; then makoctl mode | grep -x stream >/dev/null || makoctl mode -a stream || true; else makoctl mode -r stream || true; fi
    pkill -RTMIN+8 -x '\.waybar-wrapped|waybar' || true ;;
  *) echo "usage: waybar-stream status | toggle | auto on|off | text <value>" >&2; exit 2 ;;
esac

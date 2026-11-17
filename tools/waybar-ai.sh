#!/usr/bin/env bash
# Waybar custom module: the Claude weekly limit from the claude-hud usage snapshot, as Waybar JSON.
# Env: BAR_AI_FILE (snapshot path), BAR_NOW (epoch seconds, tests only). Any read/parse failure hides the module.
set -euo pipefail

file=${BAR_AI_FILE:-$HOME/.cache/claude-hud/usage.json}

jq -c --argjson now "${BAR_NOW:-$(date +%s)}" '
  def ts: sub("\\.[0-9]+"; "") | fromdateiso8601; # claude-hud writes JS ISO strings with milliseconds
  def left($r): ([($r | ts) - $now, 0] | max) as $s
    | if $s >= 86400 then "\($s / 86400 | floor)d \($s % 86400 / 3600 | floor)h"
      else "\($s / 3600 | floor)h \($s % 3600 / 60 | floor)m" end;
  def line($label; $o): "\($label) \($o.used_percentage | round) %"
    + (if $o.resets_at then " · reset in \(left($o.resets_at))" else "" end);
  ((.seven_day.used_percentage | numbers | round) // error("no weekly percentage")) as $p
  | ($p / 10 | round | [., 0] | max | [., 10] | min) as $n
  | {
      text: "AI \([range(10) | if . < $n then "▰" else "▱" end] | join("")) \($p)%",
      class: (if ($now - (.updated_at | ts)) > 600 then "stale"
        elif $p >= 95 then "crit" elif $p >= 80 then "warn" else "ok" end),
      tooltip: ([line("Woche"; .seven_day), (.five_hour | select(.used_percentage | numbers) | line("5 h"; .))] | join("\n"))
    }' "$file" 2>/dev/null || echo '{"text":""}'

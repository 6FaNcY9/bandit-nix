# Stage the Minecraft data volume before the container starts (runs as root).
#
# File ownership, one writer per file:
#   Nix   - the panel (VoxelDash) and map (BlueMap) jars, BlueMap's core.conf
#           when it does not exist yet, and the CommandPanels menu YAML files.
#           Replaced on every start.
#   Panel - every other plugin jar and all runtime settings once the one-time
#           seed below has run. The panel (or an operator) installs, updates and
#           removes them; Nix never deletes or overwrites them again.
#
# The seed step is guarded by a stamp file: it installs a pinned plugin only
# when no jar with that plugin's name prefix exists, and applies the validated
# one-time settings patches. Rename the stamp (v2, ...) to seed again.
#
# Inputs (environment): MC_DATA, MC_OWNER (empty = do not chown), STAGE_*.
set -euo pipefail

data=${MC_DATA:-/srv/containers/minecraft/data}
owner=${MC_OWNER-1000:1000}
plugins=$data/plugins
stamp=$data/.nix-seed-v1

own=()
if [ -n "$owner" ]; then
  own=(-o "${owner%%:*}" -g "${owner##*:}")
fi

seed_settings() {
  local serverProperties=$data/server.properties
  if [ ! -f "$serverProperties" ] || [ "$(grep -Ec '^allow-flight=(true|false)$' "$serverProperties")" -ne 1 ]; then
    echo "Refusing to edit unexpected allow-flight property" >&2
    exit 1
  fi
  local viaConfig=$plugins/ViaVersion/config.yml
  if [ ! -f "$viaConfig" ]; then
    echo "Refusing to edit missing ViaVersion config" >&2
    exit 1
  fi
  local packetLimiterBlock
  packetLimiterBlock="$(sed -n '/^packet-limiter:[[:space:]]*$/,/^[^[:space:]#]/p' "$viaConfig")"
  if [ "$(grep -Ec '^[[:space:]]+enabled:[[:space:]]*(true|false)[[:space:]]*$' <<<"$packetLimiterBlock")" -ne 1 ]; then
    echo "Refusing to edit unexpected ViaVersion packet-limiter block" >&2
    exit 1
  fi

  local moderationConfig=$plugins/SModeration/config.yml
  if [ ! -f "$moderationConfig" ] || [ "$(grep -Ec '^force-reason: (true|false)$' "$moderationConfig")" -ne 1 ]; then
    echo "Refusing to edit unexpected SModeration config" >&2
    exit 1
  fi
  local feature
  for feature in punishments smodmenu invsee enderchestsee offlinetp socialspy vanish; do
    if [ "$(grep -Ec "^[[:space:]]+$feature:[[:space:]]+true$" "$moderationConfig")" -ne 1 ]; then
      echo "Refusing to edit missing or disabled SModeration feature: $feature" >&2
      exit 1
    fi
  done
  local customPunishmentsBlock
  customPunishmentsBlock="$(sed -n '/^custom-punishments:[[:space:]]*$/,/^[^[:space:]#]/p' "$moderationConfig")"
  if [ "$(grep -Ec '^[[:space:]]+enabled:[[:space:]]+(true|false)$' <<<"$customPunishmentsBlock")" -ne 1 ]; then
    echo "Refusing to edit unexpected SModeration custom-punishments block" >&2
    exit 1
  fi
  local warnBlock expectedWarnBlock
  warnBlock="$(awk '/^  warn:[[:space:]]*$/ { found=1 } found && $0 !~ /^  / { exit } found { print }' "$moderationConfig")"
  expectedWarnBlock=$'  warn:\n    timed: false\n    name: Warn\n    effects: []\n    commands:\n      - /warn\n      - /smodwarn'
  if [ -n "$warnBlock" ] && [ "$warnBlock" != "$expectedWarnBlock" ]; then
    echo "Refusing to overwrite unexpected SModeration warn definition" >&2
    exit 1
  fi

  sed -E -i 's/^allow-flight=(true|false)$/allow-flight=true/' "$serverProperties"
  if ! grep -q '^allow-flight=true$' "$serverProperties"; then
    echo "allow-flight validation failed" >&2
    exit 1
  fi

  sed -i '/^packet-limiter:[[:space:]]*$/,/^[^[:space:]#]/ s/^\([[:space:]]*enabled:[[:space:]]*\)\(true\|false\)$/\1false/' "$viaConfig"
  packetLimiterBlock="$(sed -n '/^packet-limiter:[[:space:]]*$/,/^[^[:space:]#]/p' "$viaConfig")"
  if ! grep -Eq '^[[:space:]]+enabled:[[:space:]]*false[[:space:]]*$' <<<"$packetLimiterBlock"; then
    echo "ViaVersion packet-limiter validation failed" >&2
    exit 1
  fi

  sed -i -E 's/^force-reason: (true|false)$/force-reason: true/' "$moderationConfig"
  sed -i '/^custom-punishments:[[:space:]]*$/,/^[^[:space:]#]/ s/^  enabled: false$/  enabled: true/' "$moderationConfig"
  if [ -z "$warnBlock" ]; then
    sed -i '/^custom-punishments:[[:space:]]*$/,/^[^[:space:]#]/ s|^  enabled: true$|  enabled: true\n\x20\x20warn:\n\x20\x20\x20\x20timed: false\n\x20\x20\x20\x20name: Warn\n\x20\x20\x20\x20effects: []\n\x20\x20\x20\x20commands:\n\x20\x20\x20\x20\x20\x20- /warn\n\x20\x20\x20\x20\x20\x20- /smodwarn|' "$moderationConfig"
  fi
  if ! grep -q '^force-reason: true$' "$moderationConfig" || ! grep -q '^  enabled: true$' <<<"$(sed -n '/^custom-punishments:[[:space:]]*$/,/^[^[:space:]#]/p' "$moderationConfig")"; then
    echo "SModeration config validation failed" >&2
    exit 1
  fi
  warnBlock="$(awk '/^  warn:[[:space:]]*$/ { found=1 } found && $0 !~ /^  / { exit } found { print }' "$moderationConfig")"
  if [ "$warnBlock" != "$expectedWarnBlock" ]; then
    echo "SModeration warn validation failed" >&2
    exit 1
  fi
}

# Install a seed jar only when no jar with the same name prefix is present
# (e.g. LuckPerms-Bukkit-5.5.71.jar -> prefix LuckPerms-Bukkit).
# True when at least one of the given glob matches exists.
exists() {
  local f
  for f in "$@"; do
    if [ -e "$f" ]; then return 0; fi
  done
  return 1
}

seed_jar() {
  local name prefix
  name=$(basename "$1")
  prefix=$(sed -E 's/-[0-9][^/]*\.jar$//' <<<"$name")
  if exists "$plugins/$prefix"-*.jar "$plugins/$prefix.jar"; then
    echo "seed: $prefix already installed, leaving it to the panel"
  else
    install -m 0644 "$1" "$plugins/$name"
    echo "seed: installed $name"
  fi
}

mkdir -p "$plugins"

# --- Nix-owned: panel and map -------------------------------------------------
rm -f "$plugins"/VoxelDash-*.jar "$plugins"/BlueMap-*.jar "$plugins"/voxeldash-*.jar "$plugins"/bluemap-*.jar
install -m 0644 "$STAGE_VOXELDASH" "$plugins/VoxelDash-$STAGE_VOXELDASH_VERSION.jar"
install -m 0644 "$STAGE_BLUEMAP" "$plugins/BlueMap-$STAGE_BLUEMAP_VERSION.jar"

# BlueMap downloads Mojang's client jar for textures only after its operator
# accepts that download; metrics stay off. Written only when no config exists.
install -d "${own[@]}" -m 0750 "$plugins/BlueMap"
if [ ! -e "$plugins/BlueMap/core.conf" ]; then
  install "${own[@]}" -m 0644 "$STAGE_BLUEMAP_CORE" "$plugins/BlueMap/core.conf"
fi

# CommandPanels menus are repository-owned.
install -d "${own[@]}" -m 0750 "$plugins/CommandPanels" "$plugins/CommandPanels/panels"
for panel in "$STAGE_PANELS"/*.yml; do
  install "${own[@]}" -m 0644 "$panel" "$plugins/CommandPanels/panels/$(basename "$panel")"
done

# --- One-time seed: everything else belongs to the panel ----------------------
if [ -e "$stamp" ]; then
  echo "seed stamp present: plugin versions and settings are panel-owned"
  exit 0
fi

seed_settings
for jar in "$STAGE_SEED"/*.jar; do
  seed_jar "$jar"
done
# PlaceholderAPI's Player expansion lives under the plugin's own directory.
install -d "${own[@]}" -m 0750 "$plugins/PlaceholderAPI" "$plugins/PlaceholderAPI/expansions"
for jar in "$STAGE_EXPANSIONS"/*.jar; do
  if ! exists "$plugins/PlaceholderAPI/expansions/$(sed -E 's/_.*//' <<<"$(basename "$jar")")"_*.jar; then
    install "${own[@]}" -m 0644 "$jar" "$plugins/PlaceholderAPI/expansions/$(basename "$jar")"
  fi
done
touch "$stamp"
echo "seed complete"

{
  config,
  pkgs,
  ...
}: let
  # Paper plugins pinned from Hangar (hangar.papermc.io), latest Release
  # channel. ViaVersion lets newer clients join; ViaBackwards (requires
  # ViaVersion) lets older clients join. Both support Paper 1.8/1.10-26.2.
  viaVersion = pkgs.fetchurl {
    url = "https://hangarcdn.papermc.io/plugins/ViaVersion/ViaVersion/versions/5.11.0/PAPER/ViaVersion-5.11.0.jar";
    hash = "sha256-idt2yOPmdCOPXu4rt6npor7roHYLvRuGSUd46KWlL3A=";
  };
  viaBackwards = pkgs.fetchurl {
    url = "https://hangarcdn.papermc.io/plugins/ViaVersion/ViaBackwards/versions/5.11.0/PAPER/ViaBackwards-5.11.0.jar";
    hash = "sha256-QQhaWdeEyaDRSRf+dIfvXiAanaeCX9BH8I0yj/M+7Nw=";
  };
  # Official Modrinth releases explicitly supporting Minecraft 26.2.
  luckPerms = pkgs.fetchurl {
    url = "https://cdn.modrinth.com/data/Vebnzrzj/versions/b0mk8uS6/LuckPerms-Bukkit-5.5.71.jar";
    hash = "sha512-GIqR8KVD0jv9oyOF/KbbY9YeScikIr1FKiYL2cvGp9f+RQcRmen8qPPOQ8K0HuhP0xW9FUZFdwKP85UafU+rJw==";
  };
  sModeration = pkgs.fetchurl {
    url = "https://cdn.modrinth.com/data/psWnUhHl/versions/oSGjnNOf/SModeration-Paper-2.0.0.jar";
    hash = "sha512-lPfgeAqYZMZU4ACHBd4Hj7PtCCfcpfVUQ8jWHxwkrEWgO0aJve+jAQB0tjIZEJTw6VE1MalxwIGBwD63nAU2KA==";
  };
  commandPanels = pkgs.fetchurl {
    url = "https://github.com/rockyhawk64/CommandPanels/releases/download/4.2.4/CommandPanels-4.2.4.jar";
    hash = "sha256-I5BNRmQALJbL/9w5RCBl4iC09r0CKxXT+CsXgRUgYAE=";
  };
  inventoryRollbackPlus = pkgs.fetchurl {
    url = "https://cdn.modrinth.com/data/XWKWAzd8/versions/2JWRgmoZ/InventoryRollbackPlus-1.8.4.jar";
    hash = "sha512-UUS+wSYGcxIvG9yRwnQ/JsfSDeR0A8FWiY0pnQrhqV9KptWM/Sg6VH5RhiyRmxMb8JzMOA2iFbcOTuVrc5wbEA==";
  };
  axGraves = pkgs.fetchurl {
    url = "https://cdn.modrinth.com/data/Cz6msz34/versions/TVfUUk5c/AxGraves-1.32.0.jar";
    hash = "sha512-ZH1PTpLRu+6DkTgDLVM4DhfyCZTe9GfGZ5U1u44/k/fk2bGhuVDCx1Es1wA9azjxhSATFzEobtLYgMvpZOD1Lw==";
  };
  pluginsDir = "/srv/containers/minecraft/data/plugins";
  commandPanelsDir = "${pluginsDir}/CommandPanels";
  grep = "${pkgs.gnugrep}/bin/grep";
  sed = "${pkgs.gnused}/bin/sed";
  awk = "${pkgs.gawk}/bin/awk";
in {
  # Match the container's minecraft UID/GID so Paper can read player saves.
  systemd.tmpfiles.rules = [
    "d /srv/containers/minecraft/data 0750 1000 1000 -"
  ];

  # Stage pinned plugin JARs into the data volume before the container
  # starts. Stale managed JARs are removed first so version bumps don't
  # leave duplicates behind. Runs as root on the host; the container only
  # sees plain files (a nix-store symlink would not resolve inside it).
  systemd.services.minecraft-plugins = {
    description = "Stage managed Minecraft Paper plugins";
    before = ["docker-minecraft.service"];
    requiredBy = ["docker-minecraft.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      serverProperties=/srv/containers/minecraft/data/server.properties
      if [ ! -f "$serverProperties" ] || [ "$(${grep} -Ec '^allow-flight=(true|false)$' "$serverProperties")" -ne 1 ]; then
        echo "Refusing to edit unexpected allow-flight property" >&2
        exit 1
      fi
      viaConfig=${pluginsDir}/ViaVersion/config.yml
      if [ ! -f "$viaConfig" ]; then
        echo "Refusing to edit missing ViaVersion config" >&2
        exit 1
      fi
      packetLimiterBlock="$(${sed} -n '/^packet-limiter:[[:space:]]*$/,/^[^[:space:]#]/p' "$viaConfig")"
      if [ "$(${grep} -Ec '^[[:space:]]+enabled:[[:space:]]*(true|false)[[:space:]]*$' <<<"$packetLimiterBlock")" -ne 1 ]; then
        echo "Refusing to edit unexpected ViaVersion packet-limiter block" >&2
        exit 1
      fi

      moderationConfig=${pluginsDir}/SModeration/config.yml
      if [ ! -f "$moderationConfig" ] || [ "$(${grep} -Ec '^force-reason: (true|false)$' "$moderationConfig")" -ne 1 ]; then
        echo "Refusing to edit unexpected SModeration config" >&2
        exit 1
      fi
      for feature in punishments smodmenu invsee enderchestsee offlinetp socialspy vanish; do
        if [ "$(${grep} -Ec "^[[:space:]]+$feature:[[:space:]]+true$" "$moderationConfig")" -ne 1 ]; then
          echo "Refusing to edit missing or disabled SModeration feature: $feature" >&2
          exit 1
        fi
      done
      customPunishmentsBlock="$(${sed} -n '/^custom-punishments:[[:space:]]*$/,/^[^[:space:]#]/p' "$moderationConfig")"
      if [ "$(${grep} -Ec '^[[:space:]]+enabled:[[:space:]]+(true|false)$' <<<"$customPunishmentsBlock")" -ne 1 ]; then
        echo "Refusing to edit unexpected SModeration custom-punishments block" >&2
        exit 1
      fi
      warnBlock="$(${awk} '/^  warn:[[:space:]]*$/ { found=1 } found && $0 !~ /^  / { exit } found { print }' "$moderationConfig")"
      expectedWarnBlock=$'  warn:\n    timed: false\n    name: Warn\n    effects: []\n    commands:\n      - /warn\n      - /smodwarn'
      if [ -n "$warnBlock" ] && [ "$warnBlock" != "$expectedWarnBlock" ]; then
        echo "Refusing to overwrite unexpected SModeration warn definition" >&2
        exit 1
      fi

      ${sed} -E -i 's/^allow-flight=(true|false)$/allow-flight=true/' "$serverProperties"
      if ! ${grep} -q '^allow-flight=true$' "$serverProperties"; then
        echo "allow-flight validation failed" >&2
        exit 1
      fi

      ${sed} -i '/^packet-limiter:[[:space:]]*$/,/^[^[:space:]#]/ s/^\([[:space:]]*enabled:[[:space:]]*\)\(true\|false\)$/\1false/' "$viaConfig"
      packetLimiterBlock="$(${sed} -n '/^packet-limiter:[[:space:]]*$/,/^[^[:space:]#]/p' "$viaConfig")"
      if ! ${grep} -Eq '^[[:space:]]+enabled:[[:space:]]*false[[:space:]]*$' <<<"$packetLimiterBlock"; then
        echo "ViaVersion packet-limiter validation failed" >&2
        exit 1
      fi

      ${sed} -i -E 's/^force-reason: (true|false)$/force-reason: true/' "$moderationConfig"
      ${sed} -i '/^custom-punishments:[[:space:]]*$/,/^[^[:space:]#]/ s/^  enabled: false$/  enabled: true/' "$moderationConfig"
      if [ -z "$warnBlock" ]; then
        ${sed} -i '/^custom-punishments:[[:space:]]*$/,/^[^[:space:]#]/ s|^  enabled: true$|  enabled: true\n\x20\x20warn:\n\x20\x20\x20\x20timed: false\n\x20\x20\x20\x20name: Warn\n\x20\x20\x20\x20effects: []\n\x20\x20\x20\x20commands:\n\x20\x20\x20\x20\x20\x20- /warn\n\x20\x20\x20\x20\x20\x20- /smodwarn|' "$moderationConfig"
      fi
      if ! ${grep} -q '^force-reason: true$' "$moderationConfig" || ! ${grep} -q '^  enabled: true$' <<<"$(${sed} -n '/^custom-punishments:[[:space:]]*$/,/^[^[:space:]#]/p' "$moderationConfig")"; then
        echo "SModeration config validation failed" >&2
        exit 1
      fi
      warnBlock="$(${awk} '/^  warn:[[:space:]]*$/ { found=1 } found && $0 !~ /^  / { exit } found { print }' "$moderationConfig")"
      if [ "$warnBlock" != "$expectedWarnBlock" ]; then
        echo "SModeration warn validation failed" >&2
        exit 1
      fi

      mkdir -p ${pluginsDir}
      rm -f ${pluginsDir}/ViaVersion-*.jar ${pluginsDir}/ViaBackwards-*.jar
      rm -f ${pluginsDir}/LuckPerms-Bukkit-*.jar ${pluginsDir}/SModeration-Paper-*.jar ${pluginsDir}/InventoryRollbackPlus-*.jar ${pluginsDir}/AxGraves-*.jar ${pluginsDir}/CommandPanels-*.jar
      install -m 0644 ${luckPerms} ${pluginsDir}/LuckPerms-Bukkit-5.5.71.jar
      install -m 0644 ${sModeration} ${pluginsDir}/SModeration-Paper-2.0.0.jar
      install -m 0644 ${inventoryRollbackPlus} ${pluginsDir}/InventoryRollbackPlus-1.8.4.jar
      install -m 0644 ${axGraves} ${pluginsDir}/AxGraves-1.32.0.jar
      install -m 0644 ${viaVersion} ${pluginsDir}/ViaVersion-5.11.0.jar
      install -m 0644 ${viaBackwards} ${pluginsDir}/ViaBackwards-5.11.0.jar
      install -d -o 1000 -g 1000 -m 0750 ${commandPanelsDir} ${commandPanelsDir}/panels
      install -m 0644 ${commandPanels} ${pluginsDir}/CommandPanels-4.2.4.jar
      install -o 1000 -g 1000 -m 0644 ${./minecraft/commandpanels/admin.yml} ${commandPanelsDir}/panels/admin.yml
      install -o 1000 -g 1000 -m 0644 ${./minecraft/commandpanels/admin-player.yml} ${commandPanelsDir}/panels/admin-player.yml
    '';
  };

  # Minecraft Java server (Paper) for ~12 players. Hard-capped at 4 CPU cores
  # and 12 GiB so it can never starve Traefik/PostgreSQL/Wazuh & co. — the lab
  # (i9-14900HX, 62 GiB) barely notices it. Not proxied through Traefik:
  # Minecraft is a raw TCP protocol, so port 25565 is published directly.
  virtualisation.oci-containers.containers.minecraft = {
    # java25 tag: Minecraft 26.1+ refuses to start on anything older.
    image = "itzg/minecraft-server@sha256:769a826c340586e9d483a0eb6437b8e2c3611aea6a115ff072a2fe372d43e2be"; # java25
    environment = {
      EULA = "TRUE";
      # Paper over vanilla: same gameplay, much better tick performance.
      TYPE = "PAPER";
      VERSION = "26.2";
      TZ = config.time.timeZone;
      # 8 GiB heap (Xms = Xmx) + Aikar GC flags = no GC stutter; container
      # cap below leaves headroom for off-heap/metaspace.
      MEMORY = "8G";
      USE_AIKAR_FLAGS = "true";
      MAX_PLAYERS = "12";
      MOTD = "bandit-lab";
      OPS = "fancy8869";
      # Administer through the local console without exposing RCON.
      CREATE_CONSOLE_IN_PIPE = "true";
      ENABLE_RCON = "false";
    };
    ports = ["25565:25565"];
    volumes = ["/srv/containers/minecraft/data:/data"];
    extraOptions = [
      "--memory=12g"
      "--cpus=4"
    ];
  };

  # Java Edition is TCP-only; UDP 25565 stays closed.
  networking.firewall.allowedTCPPorts = [25565];
}

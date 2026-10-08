{
  config,
  lib,
  pkgs,
  repoConfig,
  ...
}: let
  scripts = import ./scripts.nix {inherit pkgs;};

  # Panel and map, pinned and owned by Nix (see stage.sh for the ownership
  # split). VoxelDash is the browser admin panel (MIT, a Paper plugin that runs
  # inside the server process); BlueMap (MIT) is the live map. Both are
  # reachable only through the loopback ports published below and the tailnet
  # HTTPS proxy.
  voxelDashVersion = "1.2.1";
  voxelDash = pkgs.fetchurl {
    url = "https://github.com/gnmyt/VoxelDash/releases/download/v${voxelDashVersion}/voxeldash-spigot-${voxelDashVersion}.jar";
    hash = "sha256-mwUYRpW1thF6zspu1rE7FvPwRYTjxNtZKYDzGC8hWLc=";
  };
  blueMapVersion = "5.28";
  blueMap = pkgs.fetchurl {
    url = "https://github.com/BlueMap-Minecraft/BlueMap/releases/download/v${blueMapVersion}/bluemap-${blueMapVersion}-paper.jar";
    hash = "sha256-TPtKmWMTLVvgqdsDGiipjp35Le7TfrsHVtOn3Ychq5g=";
  };

  # Plugins seeded once (first activation of the one-time seed) and then owned
  # by the panel: pinned from Hangar / Modrinth / GitHub with exact hashes.
  # ViaVersion lets newer clients join; ViaBackwards (requires ViaVersion)
  # lets older clients join. Modrinth releases explicitly support 26.2.
  seedPlugins = {
    "ViaVersion-5.12.0.jar" = pkgs.fetchurl {
      url = "https://hangarcdn.papermc.io/plugins/ViaVersion/ViaVersion/versions/5.12.0/PAPER/ViaVersion-5.12.0.jar";
      hash = "sha256-xNUS+pdg+kHRerrt3hKqH0yb3pINCpkv4PwBaWLxJr4=";
    };
    "ViaBackwards-5.12.0.jar" = pkgs.fetchurl {
      url = "https://hangarcdn.papermc.io/plugins/ViaVersion/ViaBackwards/versions/5.12.0/PAPER/ViaBackwards-5.12.0.jar";
      hash = "sha256-+QL32n65nov69GH4AoPE4nULfZcn5rUI6ku5Fj9Vsds=";
    };
    "LuckPerms-Bukkit-5.5.71.jar" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/Vebnzrzj/versions/b0mk8uS6/LuckPerms-Bukkit-5.5.71.jar";
      hash = "sha512-GIqR8KVD0jv9oyOF/KbbY9YeScikIr1FKiYL2cvGp9f+RQcRmen8qPPOQ8K0HuhP0xW9FUZFdwKP85UafU+rJw==";
    };
    "SModeration-Paper-2.0.0.jar" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/psWnUhHl/versions/oSGjnNOf/SModeration-Paper-2.0.0.jar";
      hash = "sha512-lPfgeAqYZMZU4ACHBd4Hj7PtCCfcpfVUQ8jWHxwkrEWgO0aJve+jAQB0tjIZEJTw6VE1MalxwIGBwD63nAU2KA==";
    };
    "CommandPanels-4.2.4.jar" = pkgs.fetchurl {
      url = "https://github.com/rockyhawk64/CommandPanels/releases/download/4.2.4/CommandPanels-4.2.4.jar";
      hash = "sha256-I5BNRmQALJbL/9w5RCBl4iC09r0CKxXT+CsXgRUgYAE=";
    };
    "PlaceholderAPI-2.12.3.jar" = pkgs.fetchurl {
      url = "https://hangarcdn.papermc.io/plugins/HelpChat/PlaceholderAPI/versions/2.12.3/PAPER/PlaceholderAPI-2.12.3.jar";
      hash = "sha256-/eAyWfWvaTjzwz7rTYFAAKGtq/HSMEzhSXC+gfYJpDc=";
    };
    "InventoryRollbackPlus-1.8.4.jar" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/XWKWAzd8/versions/2JWRgmoZ/InventoryRollbackPlus-1.8.4.jar";
      hash = "sha512-UUS+wSYGcxIvG9yRwnQ/JsfSDeR0A8FWiY0pnQrhqV9KptWM/Sg6VH5RhiyRmxMb8JzMOA2iFbcOTuVrc5wbEA==";
    };
    "AxGraves-1.32.0.jar" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/Cz6msz34/versions/TVfUUk5c/AxGraves-1.32.0.jar";
      hash = "sha512-ZH1PTpLRu+6DkTgDLVM4DhfyCZTe9GfGZ5U1u44/k/fk2bGhuVDCx1Es1wA9azjxhSATFzEobtLYgMvpZOD1Lw==";
    };
  };
  seedExpansions = {
    "PAPI-Expansion-Player_R5xV754.jar" = pkgs.fetchurl {
      url = "https://dl.placeholderapi.com/PAPI-Expansion-Player_R5xV754.jar";
      hash = "sha256-o1V0u76c6IaIIRVDcf11TmZAKjgox0U7jOMrxTborGw=";
    };
  };

  panelPort = "7867";
  mapPort = "8100";
in {
  systemd = {
    # Match the container's minecraft UID/GID so Paper can read player saves.
    tmpfiles.rules = [
      "d /srv/containers/minecraft/data 0750 1000 1000 -"
      "d /srv/containers/minecraft/backups 0750 root root -"
    ];

    services = {
      # Stage the pinned panel/map and seed the panel-owned plugins before the
      # container starts. Runs as root on the host; the container only sees plain
      # files (a nix-store symlink would not resolve inside it). Ownership rules
      # and the one-time seed are documented in stage.sh.
      minecraft-plugins = {
        description = "Stage Minecraft panel, map and one-time plugin seed";
        before = ["docker-minecraft.service"];
        requiredBy = ["docker-minecraft.service"];
        environment = {
          STAGE_VOXELDASH = voxelDash;
          STAGE_VOXELDASH_VERSION = voxelDashVersion;
          STAGE_BLUEMAP = blueMap;
          STAGE_BLUEMAP_VERSION = blueMapVersion;
          STAGE_BLUEMAP_CORE = ./bluemap-core.conf;
          STAGE_PANELS = ./commandpanels;
          STAGE_SEED = pkgs.linkFarm "minecraft-seed-plugins" seedPlugins;
          STAGE_EXPANSIONS = pkgs.linkFarm "minecraft-seed-expansions" seedExpansions;
        };
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${scripts.stage}/bin/minecraft-stage";
        };
      };

      # The tailnet address must exist before Docker can publish on it. tailscaled
      # being "started" does not guarantee the address is assigned yet, so retry
      # indefinitely instead of giving up after the default start limit.
      # Restart=always: a Stop from the panel (or a clean exit) brings the server
      # back; `systemctl stop docker-minecraft` stays the way to keep it down.
      docker-minecraft = {
        after = ["tailscaled.service"];
        wants = ["tailscaled.service"];
        unitConfig.StartLimitIntervalSec = 0;
        serviceConfig = {
          Restart = lib.mkForce "always";
          RestartSec = "10s";
        };
      };

      # Private HTTPS for the panel (443) and the map (8443): Tailscale Serve,
      # tailnet only (never Funnel). Serve and "HTTPS Certificates" must be enabled
      # once in the Tailscale admin console. Until then `tailscale serve --bg`
      # blocks waiting for that, so each call is time-boxed, and the unit logs a
      # warning and still succeeds: a missing console setting must not hang or
      # fail a deployment. After enabling it, run
      #   sudo systemctl restart minecraft-panel-https
      # (bandit-lab-health warns while the panel has no HTTPS route). Meanwhile
      # the panel is reachable through an SSH tunnel (docs/runbooks/minecraft/PANEL.md).
      minecraft-panel-https = {
        description = "Tailnet-only HTTPS for the Minecraft panel and map";
        after = ["tailscaled.service" "docker-minecraft.service"];
        wants = ["tailscaled.service"];
        wantedBy = ["multi-user.target"];
        path = [config.services.tailscale.package pkgs.coreutils];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          TimeoutStartSec = "90s";
        };
        script = ''
          serve() {
            if ! timeout 30 tailscale serve --bg --https="$1" "http://127.0.0.1:$2"; then
              echo "WARNING: could not publish 127.0.0.1:$2 on tailnet HTTPS port $1; enable Serve and HTTPS Certificates in the Tailscale admin console, then restart this unit" >&2
            fi
          }
          serve 443 ${panelPort}
          serve 8443 ${mapPort}
        '';
        preStop = ''
          timeout 30 tailscale serve --https=443 off || true
          timeout 30 tailscale serve --https=8443 off || true
        '';
      };

      # Consistent daily backup with checksum, listing test and retention. The
      # off-host copy is the restic job (services/backup), which runs the same
      # snapshot at 04:30.
      minecraft-backup = {
        description = "Consistent Minecraft backup (flush, snapshot, verify, prune)";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${scripts.backup}/bin/minecraft-backup";
          TimeoutStartSec = "2h";
          Nice = 10;
          IOSchedulingClass = "idle";
        };
      };
    };

    timers.minecraft-backup = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "03:40";
        Persistent = true;
        RandomizedDelaySec = "10m";
      };
    };
  };

  # Minecraft Java server (Paper) for ~12 players. Hard-capped at 4 CPU cores
  # and 12 GiB so it can never starve Traefik/PostgreSQL & co. — the lab
  # (i9-14900HX, 62 GiB) barely notices it. Not proxied through Traefik:
  # Minecraft is a raw TCP protocol, so port 25565 is published directly.
  # The container has no docker.sock, no privileges and a single mount: the
  # panel runs as a plugin inside it and cannot reach the host.
  virtualisation.oci-containers.containers.minecraft = {
    # java25 tag: Minecraft 26.1+ refuses to start on anything older.
    image = "itzg/minecraft-server@sha256:769a826c340586e9d483a0eb6437b8e2c3611aea6a115ff072a2fe372d43e2be"; # java25
    # itzg rewrites every server.properties key that has an environment
    # variable here on each start, so only keys Nix must own are listed
    # (max-players: capacity is sized against the resource cap; ops: admin
    # identity). Everything else in server.properties belongs to the panel.
    environment = {
      EULA = "TRUE";
      # Paper over vanilla: same gameplay, much better tick performance.
      TYPE = "PAPER";
      VERSION = "26.2";
      # Without a pin itzg downloads the newest Paper build on every start.
      # Bump deliberately, after a backup (docs/runbooks/minecraft/PANEL.md).
      PAPER_BUILD = "130";
      TZ = config.time.timeZone;
      # 8 GiB heap (Xms = Xmx) + Aikar GC flags = no GC stutter; container
      # cap below leaves headroom for off-heap/metaspace.
      MEMORY = "8G";
      USE_AIKAR_FLAGS = "true";
      MAX_PLAYERS = "12";
      OPS = "fancy8869";
      # Administer through the local console without exposing RCON.
      CREATE_CONSOLE_IN_PIPE = "true";
      ENABLE_RCON = "false";
    };
    # Game port bound to the tailnet address (decision D6, 2026-10-06). Docker-
    # published ports bypass the NixOS firewall (Docker's DNAT runs before
    # INPUT), so the bind address is the only access control: players join over
    # Tailscale. Panel and map listen on loopback only; tailscale serve (above)
    # is their sole network path.
    ports = [
      "${repoConfig.lab.tailscaleIp}:25565:25565"
      "127.0.0.1:${panelPort}:7867"
      "127.0.0.1:${mapPort}:8100"
    ];
    volumes = ["/srv/containers/minecraft/data:/data"];
    extraOptions = [
      "--memory=12g"
      "--cpus=4"
      # Room for a full world save on SIGTERM (docker's default is 10 s).
      "--stop-timeout=60"
    ];
  };
}

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

  # Velocity proxy in front of Paper (docs/runbooks/minecraft/PROXY.md). The jar
  # is hash-pinned here and handed to itzg/mc-proxy as TYPE=CUSTOM, so nothing is
  # downloaded at start. BotGate is compiled against that same jar.
  velocityJar = pkgs.fetchurl {
    url = "https://fill-data.papermc.io/v1/objects/b4e3164df5377346854dc6cb9e6a78022b1946ff69e89676313f5f6f1c6f0fb3/velocity-3.5.1-615.jar";
    hash = "sha256-tOMWTfU3c0aFTcbLnmp4AisZRv9p6JZ2MT9fbxxvD7M=";
  };
  botgate = import ./botgate {inherit pkgs;};

  # Dedicated /29 for in-lab Mineflayer bots (containers join `mcbots`, connect
  # to velocity:25565). Docker's pools hand out 172.17-31.x.x/16 and then
  # 192.168.x.x; 10.250.77.0/29 collides with none of them nor with the other
  # lab networks. The gateway takes .1, velocity .2 and up to 4 bots remain.
  mcbotsSubnet = "10.250.77.0/29";

  # Sources allowed to skip Mojang authentication for bot1..bot99. Never the
  # `minecraft` network, the default bridge or the lab's own tailnet address.
  botgateSources = "${repoConfig.lab.workstationTailscaleIp}/32,${mcbotsSubnet}";

  # Applied by itzg to Paper's config at every start (PATCH_DEFINITIONS); the
  # secret is resolved from the environment file, never written to the store.
  # PATCH_DEFINITIONS points at a directory, and itzg reads every file there as
  # one patch definition ({file, ops}); a {patches = [...]} patch set is only
  # accepted as a single file and made Paper fail to start (2026-10-08).
  velocityPatch = pkgs.writeText "velocity-patch.json" (builtins.toJSON {
    file = "/data/config/paper-global.yml";
    ops = [
      {
        "$set" = {
          path = "$.proxies.velocity.enabled";
          value = true;
          value-type = "bool";
        };
      }
      {
        "$set" = {
          path = "$.proxies.velocity.online-mode";
          value = true;
          value-type = "bool";
        };
      }
      {
        "$set" = {
          path = "$.proxies.velocity.secret";
          value = "\${CFG_VELOCITY_SECRET}";
        };
      }
    ];
  });

  velocityToml = pkgs.writeText "velocity.toml" ''
    config-version = "2.8"
    bind = "0.0.0.0:25565"
    # Mojang authentication for everyone; BotGate flips single logins offline.
    online-mode = true
    player-info-forwarding-mode = "modern"
    ping-passthrough = "ALL"

    [servers]
    main = "minecraft:25565"
    try = ["main"]

    [forced-hosts]

    # Players come from Docker/Tailscale, not from a PROXY-protocol balancer.
    [advanced]
    haproxy-protocol = false
  '';
in {
  systemd = {
    # Match the container's minecraft UID/GID so Paper can read player saves.
    tmpfiles.rules = [
      "d /srv/containers/minecraft/data 0750 1000 1000 -"
      "d /srv/containers/velocity 0750 1000 1000 -"
      "d /srv/containers/velocity/plugins 0750 1000 1000 -"
      "d /srv/containers/minecraft/backups 0750 root root -"
    ];

    services = {
      docker-network-minecraft = repoConfig.mkDockerNetwork pkgs "minecraft";
      # Same inspect-then-create pattern as mkDockerNetwork, with a pinned subnet.
      docker-network-mcbots = let
        docker = "${pkgs.docker}/bin/docker";
      in {
        description = "Create mcbots Docker network (${mcbotsSubnet})";
        after = ["docker.service"];
        requires = ["docker.service"];
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeShellScript "ensure-mcbots-network" ''
            set -euo pipefail
            if ! ${docker} network inspect mcbots >/dev/null 2>&1; then
              ${docker} network create --subnet ${mcbotsSubnet} mcbots
            fi
          '';
        };
      };

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
          STAGE_PATCHES = velocityPatch;
          STAGE_SEED = pkgs.linkFarm "minecraft-seed-plugins" seedPlugins;
          STAGE_EXPANSIONS = pkgs.linkFarm "minecraft-seed-expansions" seedExpansions;
        };
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${scripts.stage}/bin/minecraft-stage";
        };
      };

      # The tailnet address must exist before Docker can publish on it (now the
      # proxy's job, see docker-velocity). tailscaled being "started" does not
      # guarantee the address is assigned yet, so retry indefinitely instead of
      # giving up after the default start limit.
      # Restart=always: a Stop from the panel (or a clean exit) brings the server
      # back; `systemctl stop docker-minecraft` stays the way to keep it down.
      docker-minecraft = {
        after = ["docker-network-minecraft.service"];
        requires = ["docker-network-minecraft.service"];
        unitConfig.StartLimitIntervalSec = 0;
        serviceConfig = {
          Restart = lib.mkForce "always";
          RestartSec = "10s";
        };
      };

      # The proxy owns the tailnet game port, so it carries the tailscaled
      # retry pattern above. It starts after Paper (the backend must resolve).
      docker-velocity = {
        after = ["tailscaled.service" "docker-network-minecraft.service" "docker-network-mcbots.service" "docker-minecraft.service"];
        wants = ["tailscaled.service"];
        requires = ["docker-network-minecraft.service" "docker-network-mcbots.service"];
        unitConfig.StartLimitIntervalSec = 0;
        serviceConfig = {
          Restart = lib.mkForce "always";
          RestartSec = "10s";
        };
      };

      # Plugins that resolve Maven libraries at start (Citizens, Jarvis) fail to
      # load when the container briefly gets "Network is unreachable" right
      # after start (seen 3 of ~8 starts on 2026-10-08; host shows no network
      # event, cause not found). One automatic restart recovers it.
      # ponytail: retry-once workaround; replace once the startup egress fault
      # is understood.
      minecraft-plugin-check = {
        description = "Restart Minecraft once if a plugin failed to load at start";
        after = ["docker-minecraft.service"];
        wantedBy = ["docker-minecraft.service"];
        path = [pkgs.systemd pkgs.coreutils pkgs.gnugrep];
        serviceConfig = {
          # simple: never blocks a deploy while it waits for the server.
          Type = "simple";
        };
        script = ''
          since=$(systemctl show -p ActiveEnterTimestamp --value docker-minecraft.service)
          log() { journalctl -u docker-minecraft.service --since "$since" --no-pager -o cat; }
          for _ in $(seq 60); do
            log | grep -q 'Done (' && break
            sleep 5
          done
          log | grep -q 'Could not load plugin' || exit 0
          marker=/run/minecraft-plugin-retry
          if [ -e "$marker" ] && [ $(( $(date +%s) - $(stat -c %Y "$marker") )) -lt 900 ]; then
            echo "A plugin failed to load again; not retrying within 15 minutes" >&2
            exit 0
          fi
          touch "$marker"
          echo "A plugin failed to load; restarting Minecraft once" >&2
          systemctl restart --no-block docker-minecraft.service
        '';
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

  # Velocity forwarding secret, shared by the proxy (VELOCITY_FORWARDING_SECRET)
  # and Paper (patched into paper-global.yml). Declared here so only bandit-lab
  # decrypts it. The key `minecraft-velocity-secret` must exist in
  # secrets/lab.yaml (docs/runbooks/minecraft/PROXY.md) before this is deployed.
  sops = {
    secrets."minecraft-velocity-secret".mode = "0400";
    templates."minecraft-velocity.env" = {
      mode = "0400";
      # Docker reads environment files when a container is created; both
      # containers must be recreated together to rotate the secret.
      restartUnits = ["docker-minecraft.service" "docker-velocity.service"];
      content = ''
        VELOCITY_FORWARDING_SECRET=${config.sops.placeholder."minecraft-velocity-secret"}
        CFG_VELOCITY_SECRET=${config.sops.placeholder."minecraft-velocity-secret"}
      '';
    };
  };

  # Minecraft Java server (Paper) for ~12 players. Hard-capped at 4 CPU cores
  # and 12 GiB so it can never starve Traefik/PostgreSQL & co. — the lab
  # (i9-14900HX, 62 GiB) barely notices it. Not proxied through Traefik:
  # Minecraft is a raw TCP protocol. Paper publishes no game port at all: it is
  # reachable only from the Velocity proxy over the `minecraft` Docker network
  # (modern forwarding, shared secret), which is what lets Paper run with
  # online-mode=false without being joinable by anyone else.
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
      # Authentication happens at the proxy (Mojang, or BotGate for bots); the
      # Velocity forwarding secret is what keeps everyone else out of Paper.
      ONLINE_MODE = "FALSE";
      PATCH_DEFINITIONS = "/data/nix-patches";
      # Administer through the local console without exposing RCON.
      CREATE_CONSOLE_IN_PIPE = "true";
      ENABLE_RCON = "false";
    };
    environmentFiles = [config.sops.templates."minecraft-velocity.env".path];
    # Panel and map listen on loopback only; tailscale serve (above) is their
    # sole network path. The game port is published by the proxy, not here.
    ports = [
      "127.0.0.1:${panelPort}:7867"
      "127.0.0.1:${mapPort}:8100"
    ];
    volumes = ["/srv/containers/minecraft/data:/data"];
    extraOptions = [
      "--network=minecraft"
      "--memory=12g"
      "--cpus=4"
      # Room for a full world save on SIGTERM (docker's default is 10 s).
      "--stop-timeout=60"
    ];
  };

  # Velocity 3.5.1 proxy (itzg/mc-proxy, Java 21, TYPE=CUSTOM with the
  # hash-pinned jar from Nix). Game port bound to the tailnet address (decision
  # D6, 2026-10-06): Docker-published ports bypass the NixOS firewall, so the
  # bind address is the only access control; players join over Tailscale.
  # Runs as uid 1000 (not root) with no privileges and no docker.sock. Mojang
  # authentication stays on for everyone except bot1..bot99 from BotGate's
  # allowlisted sources. velocity.toml is re-synced from Nix on every start;
  # the BotGate jar is mounted directly (the image's /plugins copy only
  # replaces older files, and Nix store files all carry epoch mtimes).
  virtualisation.oci-containers.containers.velocity = {
    image = "itzg/mc-proxy@sha256:4bc904ca87ce92a1d6dc4948aaca3e026b770a7fe2bcfead0b099412239ba210"; # java21
    environment = {
      TYPE = "CUSTOM";
      CUSTOM_FAMILY = "velocity";
      BUNGEE_JAR_FILE = "/opt/velocity.jar";
      SYNC_SKIP_NEWER_IN_DESTINATION = "false";
      MEMORY = "512M";
      TZ = config.time.timeZone;
      BOTGATE_SOURCES = botgateSources;
      # The image health check pings 25577 unless told the port Velocity binds.
      SERVER_PORT = "25565";
    };
    environmentFiles = [config.sops.templates."minecraft-velocity.env".path];
    ports = ["${repoConfig.lab.tailscaleIp}:25565:25565"];
    volumes = [
      "/srv/containers/velocity:/server"
      "${velocityToml}:/config/velocity.toml:ro"
      "${velocityJar}:/opt/velocity.jar:ro"
      "${botgate}:/server/plugins/botgate.jar:ro"
    ];
    extraOptions = [
      "--network=minecraft"
      # Fixed address: the mcbots container pins `velocity` to it (it is also on
      # the minecraft network, where BotGate would refuse the source).
      "--network=name=mcbots,ip=10.250.77.2"
      "--user=1000:1000"
      "--memory=1g"
      "--cpus=1"
    ];
  };
}

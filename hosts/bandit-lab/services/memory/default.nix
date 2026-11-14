{
  config,
  lib,
  pkgs,
  repoConfig,
  ...
}: let
  username = repoConfig.workstation.username;
  # One Basic Memory instance per store, each its own Tailscale Service
  # (services/tailnet-https.nix); the tailnet policy decides who reaches which.
  # vino is the original store and keeps its names, ports and paths.
  stores = [
    {
      id = "vino";
      name = "memory";
      mcpPort = 8765;
      webPort = 8766;
    }
    {
      id = "albert";
      name = "memory-albert";
      mcpPort = 8767;
      webPort = 8768;
    }
    {
      id = "firma";
      name = "memory-firma";
      mcpPort = 8769;
      webPort = 8770;
    }
  ];
  # vino's notes that staff may read in firma: memory-mirror copies them there
  # every 10 minutes and overwrites staff edits (paths relative to the store).
  mirroredNotes = [
    "projects/bandit-craft.md"
    "projects/ingame-bots.md"
    "projects/bot-backlog.md"
    "projects/bot-menus-2b.md"
    "projects/fleet-control.md"
    "projects/highway.md"
    "projects/minecraft-phase-5-5.md"
    "projects/misabot-v2.md"
    "projects/combat-retreat-fix.md"
    "projects/discord-platform.md"
    "projects/prismlauncher-minecraft.md"
  ];
  dir = s: "/srv/containers/${s.name}";
  notesDir = id: "${dir (lib.findFirst (s: s.id == id) null stores)}/data/basic-memory";
  # memory-index (index.sh) runs: each store's lagebild.md lists only the stores named
  # here, its own first. vino also sees firma, minus vino's own notes mirrored there.
  indexRuns = [
    {
      dst = "vino";
      sources = ["vino" "firma"];
      skip = mirroredNotes;
    }
    {
      dst = "firma";
      sources = ["firma"];
      skip = [];
    }
    {
      dst = "albert";
      sources = ["albert"];
      skip = [];
    }
  ];
  indexScript = pkgs.writeShellScript "memory-index-one" (builtins.readFile ./index.sh);
  forStores = f: lib.listToAttrs (map f stores);
  # vino's front only. A plain string: alejandra would strip the leading tabs of a nested '' string.
  bnetRoute = "	# bandit-net device list (services/bnet): read-only, the router token is added here so the
	# browser never holds it. Without /etc/bnet/router.env the route just answers 401.
	handle /bnet/devices {
		rewrite * /devices
		reverse_proxy 127.0.0.1:47810 {
			header_up Authorization \"Bearer {env.BNET_TOKEN}\"
		}
	}
";
in {
  # The mirror would overwrite firma's generated lagebild with vino's.
  assertions = [
    {
      assertion = !(lib.elem "lagebild.md" mirroredNotes);
      message = "services/memory: lagebild.md is generated per store and must not be in mirroredNotes";
    }
  ];

  # Shared LLM memory for every tailnet device: Basic Memory's MCP server over
  # streamable HTTP. The endpoint has NO authentication of its own, so it is
  # only published on loopback and reached as the Tailscale Service svc:memory
  # (services/tailnet-https.nix); the tailnet policy decides who connects.
  systemd.tmpfiles.rules =
    lib.concatMap (s: [
      "d ${dir s} 0750 ${username} users -"
      # Markdown notes (the source of truth, in the restic backup).
      "d ${dir s}/data 0750 ${username} users -"
      # Config, SQLite index and the embedding model cache; all rebuildable.
      "d ${dir s}/home 0750 ${username} users -"
    ])
    stores;

  virtualisation.quadlet.containers = forStores (s:
    lib.nameValuePair s.name {
      containerConfig = {
        # 1.0.0
        image = "ghcr.io/basicmachines-co/basic-memory@sha256:cad49f5433bcd8592fea547907a2b967435b3fa60d0f81ebc4d558e2b5cb55a8";
        user = "1000:100";
        networks = [config.virtualisation.quadlet.networks.proxy.ref];
        publishPorts = ["127.0.0.1:${toString s.mcpPort}:8000"];
        exec = ["basic-memory" "mcp" "--transport" "streamable-http" "--host" "0.0.0.0" "--port" "8000"];
        # Only this store's own dirs: no store can read another.
        volumes = [
          "${dir s}/data:/app/data"
          "${dir s}/home:/home/appuser"
        ];
        environments = {
          HOME = "/home/appuser";
          BASIC_MEMORY_DEFAULT_PROJECT = "main";
        };
      };
    });

  # Devices drop raw session transcripts into inbox/ through the MCP endpoint;
  # this turns them into session notes with the lab's Ollama (no extra port).
  # vino's store only: the others have no inbox.
  systemd.services =
    {
      memory-summarise = {
        description = "Summarise session transcripts in the shared memory inbox";
        after = ["memory.service"];
        path = [pkgs.coreutils pkgs.curl pkgs.jq pkgs.gawk pkgs.gnugrep];
        serviceConfig = {
          Type = "oneshot";
          User = username;
          ExecStart = pkgs.writeShellScript "memory-summarise" (builtins.readFile ./summarise.sh);
        };
      };
      # One-way copy vino -> firma (mirror.sh); the source is read-only to this unit.
      memory-mirror = {
        description = "Mirror listed vino memory notes read-only into the firma store";
        after = ["memory-firma.service"];
        path = [pkgs.coreutils pkgs.gawk pkgs.diffutils];
        environment.MEMORY_NOTES = lib.concatStringsSep " " mirroredNotes;
        serviceConfig = {
          Type = "oneshot";
          User = username;
          ExecStart = pkgs.writeShellScript "memory-mirror" (builtins.readFile ./mirror.sh);
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          PrivateNetwork = true;
          ReadWritePaths = ["/srv/containers/memory-firma/data/basic-memory"];
        };
      };
      # lagebild.md per store (index.sh); reads the sources, writes only into the stores' note dirs.
      memory-index = {
        description = "Write the lagebild overview note into each memory store";
        after = map (s: "${s.name}.service") stores;
        path = [pkgs.coreutils pkgs.gawk pkgs.diffutils];
        serviceConfig = {
          Type = "oneshot";
          User = username;
          # All three runs even when one fails; the unit then fails and alerts.
          ExecStart = pkgs.writeShellScript "memory-index" ''
            status=0
            ${lib.concatMapStrings (r: ''
                MEMORY_INDEX_DST=${notesDir r.dst} \
                MEMORY_INDEX_SOURCES=${lib.escapeShellArg (lib.concatMapStringsSep " " (id: "${id}=${notesDir id}") r.sources)} \
                MEMORY_INDEX_SKIP=${lib.escapeShellArg (lib.concatStringsSep " " r.skip)} \
                ${indexScript} || status=1
              '')
              indexRuns}
            exit "$status"
          '';
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          PrivateNetwork = true;
          ReadWritePaths = map (r: notesDir r.dst) indexRuns;
        };
      };
    }
    # One loopback front per store for its Tailscale Service: the page for people at /,
    # the notes read-only at /notes/, and the agents' MCP endpoint at /mcp.
    // forStores (s:
      lib.nameValuePair "${s.name}-web" {
        description = "Shared memory web page and MCP front";
        wantedBy = ["multi-user.target"];
        after = ["${s.name}.service"];
        serviceConfig =
          {
            User = username;
            StateDirectory = "${s.name}-web";
            Environment = ["XDG_DATA_HOME=/var/lib/${s.name}-web" "XDG_CONFIG_HOME=/var/lib/${s.name}-web"];
            ExecStart = "${pkgs.caddy}/bin/caddy run --adapter caddyfile --config ${pkgs.writeText "${s.name}-web.Caddyfile" ''
              {
              	admin off
              	auto_https off
              }
              http://:${toString s.webPort} {
              	bind 127.0.0.1
              	@mcp path /mcp /mcp/*
              	handle @mcp {
              		reverse_proxy 127.0.0.1:${toString s.mcpPort} {
              			flush_interval -1
              		}
              	}
              ${lib.optionalString (s.id == "vino") bnetRoute}	handle_path /notes/* {
              		root * ${dir s}/data/basic-memory
              		file_server browse
              	}
              	handle {
              		root * ${./ui}
              		file_server
              	}
              }
            ''}";
            Restart = "on-failure";
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
          }
          # BNET_TOKEN=... for the /bnet/devices route; optional (leading -) so the page never depends on bnet.
          // lib.optionalAttrs (s.id == "vino") {EnvironmentFile = "-/etc/bnet/router.env";};
      });
  systemd.timers.memory-summarise = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "2min";
    };
  };
  systemd.timers.memory-index = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "5min";
    };
  };
  systemd.timers.memory-mirror = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "10min";
    };
  };
}

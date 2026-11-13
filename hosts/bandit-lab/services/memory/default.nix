{
  config,
  pkgs,
  repoConfig,
  ...
}: let
  username = repoConfig.workstation.username;
in {
  # Shared LLM memory for every tailnet device: Basic Memory's MCP server over
  # streamable HTTP. The endpoint has NO authentication of its own, so it is
  # only published on loopback and reached as the Tailscale Service svc:memory
  # (services/tailnet-https.nix); the tailnet policy decides who connects.
  systemd.tmpfiles.rules = [
    "d /srv/containers/memory 0750 ${username} users -"
    # Markdown notes (the source of truth, in the restic backup).
    "d /srv/containers/memory/data 0750 ${username} users -"
    # Config, SQLite index and the embedding model cache; all rebuildable.
    "d /srv/containers/memory/home 0750 ${username} users -"
  ];

  virtualisation.quadlet.containers.memory.containerConfig = {
    # 1.0.0
    image = "ghcr.io/basicmachines-co/basic-memory@sha256:cad49f5433bcd8592fea547907a2b967435b3fa60d0f81ebc4d558e2b5cb55a8";
    user = "1000:100";
    networks = [config.virtualisation.quadlet.networks.proxy.ref];
    publishPorts = ["127.0.0.1:8765:8000"];
    exec = ["basic-memory" "mcp" "--transport" "streamable-http" "--host" "0.0.0.0" "--port" "8000"];
    volumes = [
      "/srv/containers/memory/data:/app/data"
      "/srv/containers/memory/home:/home/appuser"
    ];
    environments = {
      HOME = "/home/appuser";
      BASIC_MEMORY_DEFAULT_PROJECT = "main";
    };
  };

  # Devices drop raw session transcripts into inbox/ through the MCP endpoint;
  # this turns them into session notes with the lab's Ollama (no extra port).
  systemd.services.memory-summarise = {
    description = "Summarise session transcripts in the shared memory inbox";
    after = ["memory.service"];
    path = [pkgs.coreutils pkgs.curl pkgs.jq pkgs.gawk pkgs.gnugrep];
    serviceConfig = {
      Type = "oneshot";
      User = username;
      ExecStart = pkgs.writeShellScript "memory-summarise" (builtins.readFile ./summarise.sh);
    };
  };
  systemd.timers.memory-summarise = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "2min";
    };
  };

  # One loopback front for the Tailscale Service: the page for people at /,
  # the notes read-only at /notes/, and the agents' MCP endpoint at /mcp.
  systemd.services.memory-web = {
    description = "Shared memory web page and MCP front";
    wantedBy = ["multi-user.target"];
    after = ["memory.service"];
    serviceConfig = {
      User = username;
      StateDirectory = "memory-web";
      Environment = ["XDG_DATA_HOME=/var/lib/memory-web" "XDG_CONFIG_HOME=/var/lib/memory-web"];
      # BNET_TOKEN=... for the /bnet/devices route; optional (leading -) so the page never depends on bnet.
      EnvironmentFile = "-/etc/bnet/router.env";
      ExecStart = "${pkgs.caddy}/bin/caddy run --adapter caddyfile --config ${pkgs.writeText "memory-web.Caddyfile" ''
        {
        	admin off
        	auto_https off
        }
        http://:8766 {
        	bind 127.0.0.1
        	@mcp path /mcp /mcp/*
        	handle @mcp {
        		reverse_proxy 127.0.0.1:8765 {
        			flush_interval -1
        		}
        	}
        	# bandit-net device list (services/bnet): read-only, the router token is added here so the
        	# browser never holds it. Without /etc/bnet/router.env the route just answers 401.
        	handle /bnet/devices {
        		rewrite * /devices
        		reverse_proxy 127.0.0.1:47810 {
        			header_up Authorization "Bearer {env.BNET_TOKEN}"
        		}
        	}
        	handle_path /notes/* {
        		root * /srv/containers/memory/data/basic-memory
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
    };
  };
}

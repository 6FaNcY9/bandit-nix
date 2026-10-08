# Mineflayer bots (docs/runbooks/minecraft/BOTS.md): containers on the `mcbots`
# network join Velocity as velocity:25565 (BotGate admits bot1..bot99 from that
# subnet) and are driven from a dashboard served on the tailnet only.
# Switch off: `bandit-lab.mcbots.enable = false;` (or drop the import).
{
  config,
  lib,
  pkgs,
  repoConfig,
  ...
}: let
  cfg = config.bandit-lab.mcbots;
  app = pkgs.callPackage ./package.nix {};
  image = pkgs.dockerTools.buildLayeredImage {
    name = "mcbots";
    contents = [app];
    config = {
      User = "1000:1000";
      Cmd = ["${app}/bin/mcbots"];
    };
  };
  dashboardPort = "8095";
  servePort = "8445";
  # Hub for remote workers (laptop bots): WebSocket on /worker only, bearer
  # token required, published on loopback and exposed by Tailscale Serve.
  workerPort = "8096";
  workerServePort = toString repoConfig.lab.mcbotsWorkerServePort;
in {
  options.bandit-lab.mcbots.enable = lib.mkEnableOption "Mineflayer bots and their tailnet dashboard" // {default = true;};

  config = lib.mkIf cfg.enable {
    virtualisation.oci-containers.containers.mcbots = {
      image = "${image.imageName}:${image.imageTag}";
      imageFile = image;
      environment = {
        BOT_NAMES = "bot1,bot2,bot3,bot4";
        MC_HOST = "velocity";
        MC_PORT = "25565";
        DASHBOARD_HOST = "0.0.0.0"; # inside the container; published on loopback only
        DASHBOARD_PORT = dashboardPort;
        WORKER_HOST = "0.0.0.0"; # inside the container; published on loopback only
        WORKER_PORT = workerPort;
        HOST_LABEL = "bandit-lab";
        # tailscale serve identifies the tailnet user; everything else gets 403.
        ALLOWED_TS_LOGINS = "6FaNcY9@github";
        # Global player positions (read-only JSON) from BlueMap in the minecraft
        # container, reachable over the `minecraft` network.
        BLUEMAP_URL = "http://minecraft:8100";
        # Chest next to the bots' respawn point (spawnpoint -36 64 -197); after a
        # death a bot re-equips armour, sword and food from it.
        SUPPLY_CHEST = "-37,65,-200";
        # Standing orders (dashboard switch, off after every restart): what the
        # keeper keeps in the supply chest, item:amount. Optional KEEPER_SITE
        # "x,y,z" makes the bots walk there before they chop or mine.
        KEEPER_QUOTAS = "logs:64,cobblestone:128,coal:32,torch:64";
        # Bots never dig or place inside these x1,z1,x2,z2 boxes: the main base
        # around spawn and MidariBread's base (from BlueMap light data, +16).
        PROTECTED_AREAS = "-80,-144,80,80;112,368,272,592";
        NODE_OPTIONS = "--max-old-space-size=1536";
      };
      ports = [
        "127.0.0.1:${dashboardPort}:${dashboardPort}"
        "127.0.0.1:${workerPort}:${workerPort}"
      ];
      # BOT_PASSWORD_SEED for the VeloAuth /register + /login of each bot,
      # derived one-way from the Velocity secret by mcbots-seed below; the
      # container never sees the secret itself. The same file carries
      # WORKER_TOKEN (sops secret mcbots-worker-token), which must not sit in
      # the world-readable environment attribute.
      environmentFiles = ["/run/mcbots/seed.env"];
      extraOptions = [
        "--network=mcbots"
        # Second network only to read BlueMap at minecraft:8100. Paper there
        # accepts logins only with Velocity's forwarding secret. With two
        # networks the name `velocity` could resolve to its minecraft-network
        # address (BotGate refuses that source), so pin it to Velocity's
        # mcbots-network address (gateway .1, velocity .2 of 10.250.77.0/29).
        "--network=minecraft"
        "--add-host=velocity:10.250.77.2"
        "--memory=2g"
        "--cpus=2"
        "--pids-limit=256"
        "--cap-drop=ALL"
        "--security-opt=no-new-privileges"
      ];
    };

    # Shared secret of the hub: remote workers send it as a bearer token. The
    # same key lives in secrets/bandit.yaml for the laptop (nixos/secrets-workstation.nix).
    sops.secrets."mcbots-worker-token".mode = "0400";

    systemd.services = {
      mcbots-seed = {
        description = "Derive the bots' login password seed and hand over the hub token";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          UMask = "0077";
        };
        path = [pkgs.coreutils];
        script = ''
          install -d -m 0700 /run/mcbots
          seed=$(printf 'mcbots-login:%s' "$(cat ${config.sops.secrets."minecraft-velocity-secret".path})" | sha256sum | cut -c1-64)
          printf 'BOT_PASSWORD_SEED=%s\nWORKER_TOKEN=%s\n' "$seed" "$(tr -d '\n' < ${config.sops.secrets."mcbots-worker-token".path})" > /run/mcbots/seed.env
        '';
      };
      docker-mcbots = {
        after = ["docker-network-mcbots.service" "docker-network-minecraft.service" "docker-velocity.service" "mcbots-seed.service"];
        requires = ["docker-network-mcbots.service" "docker-network-minecraft.service" "mcbots-seed.service"];
        unitConfig.StartLimitIntervalSec = 0;
        serviceConfig = {
          Restart = lib.mkForce "always";
          RestartSec = "10s";
        };
      };

      # Tailnet-only HTTPS for the dashboard (${servePort}) and the worker hub
      # (${workerServePort}), same time-boxed pattern as
      # minecraft-panel-https (Serve must be enabled once in the Tailscale
      # admin console; never Funnel). After enabling: sudo systemctl restart mcbots-https
      mcbots-https = {
        description = "Tailnet-only HTTPS for the Minecraft bot dashboard";
        after = ["tailscaled.service" "docker-mcbots.service"];
        wants = ["tailscaled.service"];
        wantedBy = ["multi-user.target"];
        path = [config.services.tailscale.package pkgs.coreutils];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          TimeoutStartSec = "90s";
        };
        script = ''
          if ! timeout 30 tailscale serve --bg --https=${servePort} http://127.0.0.1:${dashboardPort}; then
            echo "WARNING: could not publish 127.0.0.1:${dashboardPort} on tailnet HTTPS port ${servePort}; enable Serve and HTTPS Certificates in the Tailscale admin console, then restart this unit" >&2
          fi
          if ! timeout 30 tailscale serve --bg --https=${workerServePort} http://127.0.0.1:${workerPort}; then
            echo "WARNING: could not publish the worker hub 127.0.0.1:${workerPort} on tailnet HTTPS port ${workerServePort}" >&2
          fi
        '';
        preStop = ''
          timeout 30 tailscale serve --https=${servePort} off || true
          timeout 30 tailscale serve --https=${workerServePort} off || true
        '';
      };
    };
  };
}

# Mineflayer bots (docs/runbooks/minecraft/BOTS.md): containers on the `mcbots`
# network join Velocity as velocity:25565 (BotGate admits bot1..bot99 from that
# subnet) and are driven from a dashboard served on the tailnet only.
# Switch off: `bandit-lab.mcbots.enable = false;` (or drop the import).
{
  config,
  lib,
  pkgs,
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
        # tailscale serve identifies the tailnet user; everything else gets 403.
        ALLOWED_TS_LOGINS = "6FaNcY9@github";
        # Global player positions (read-only JSON) from BlueMap in the minecraft
        # container, reachable over the `minecraft` network.
        BLUEMAP_URL = "http://minecraft:8100";
        # Chest next to the bots' respawn point (spawnpoint -36 64 -197); after a
        # death a bot re-equips armour, sword and food from it.
        SUPPLY_CHEST = "-37,65,-200";
        # Bots never dig or place inside these x1,z1,x2,z2 boxes: the main base
        # around spawn and MidariBread's base (from BlueMap light data, +16).
        PROTECTED_AREAS = "-80,-144,80,80;112,368,272,592";
        NODE_OPTIONS = "--max-old-space-size=1536";
      };
      ports = ["127.0.0.1:${dashboardPort}:${dashboardPort}"];
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

    systemd.services = {
      docker-mcbots = {
        after = ["docker-network-mcbots.service" "docker-network-minecraft.service" "docker-velocity.service"];
        requires = ["docker-network-mcbots.service" "docker-network-minecraft.service"];
        unitConfig.StartLimitIntervalSec = 0;
        serviceConfig = {
          Restart = lib.mkForce "always";
          RestartSec = "10s";
        };
      };

      # Tailnet-only HTTPS for the dashboard, same time-boxed pattern as
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
        '';
        preStop = ''
          timeout 30 tailscale serve --https=${servePort} off || true
        '';
      };
    };
  };
}

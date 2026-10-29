# mcbots contract: the bot container publishes only on loopback, stays
# unprivileged without docker.sock, joins the dedicated `mcbots` network plus
# `minecraft` (kept until phase 5.6), reaches the host's Velocity, both RCONs and the map on the mcbots
# gateway (phase 5.5), and every bot name matches BotGate's pattern (otherwise Velocity refuses it).
{
  pkgs,
  lib,
  lab,
  repoConfig,
}: let
  c = lab.virtualisation.oci-containers.containers.mcbots;
  extra = lib.concatStringsSep " " c.extraOptions;
  names = lib.splitString "," c.environment.BOT_NAMES;
  units = lab.systemd.services;
  workerServe = toString repoConfig.lab.mcbotsWorkerServePort;
  gw = "10.250.77.1";
  ms = lab.services.minecraft-servers.servers;
in
  assert lib.assertMsg (c.ports != [] && lib.all (lib.hasPrefix "127.0.0.1:") c.ports) "mcbots may publish only on 127.0.0.1: ${toString c.ports}";
  assert lib.assertMsg (!(lib.hasInfix "privileged" extra) && !(lib.hasInfix "cap-add" extra) && !(lib.hasInfix "--network=host" extra) && !(lib.hasInfix "--pid=" extra)) "mcbots must stay unprivileged: ${extra}";
  # Only its own named volume for dashboard settings; never docker.sock or a host path.
  assert lib.assertMsg (c.volumes == ["mcbots-state:/state" "/srv/minecraft/paper/bluemap/web/mcbots:/bluemap-overlay"]) "mcbots mounts only the named volume mcbots-state:/state and BlueMap's mcbots/ web directory for the overlay (no docker.sock, nothing else): ${toString c.volumes}";
  assert lib.assertMsg (lib.elem "d /srv/minecraft/paper/bluemap/web/mcbots 0755 1000 1000 -" lab.systemd.tmpfiles.rules) "the overlay directory must exist, writable for the container uid (1000) and readable for the minecraft user";
  assert lib.assertMsg (lib.hasInfix "--network=mcbots" extra && lib.hasInfix "--network=minecraft" extra && !(lib.hasInfix "--network=bridge" extra) && !(lib.hasInfix "--network=host" extra)) "mcbots joins exactly the mcbots and minecraft networks: ${extra}";
  assert lib.assertMsg (lib.length (lib.filter (lib.hasPrefix "--network") c.extraOptions) == 2) "mcbots may not join further networks: ${extra}";
  assert lib.assertMsg (lib.elem "--add-host=velocity:${gw}" c.extraOptions) "with two networks `velocity` must be pinned to the gateway where the host's Velocity listens, or BotGate sees a minecraft-network source: ${extra}";
  assert lib.assertMsg (c.environment.BLUEMAP_URL == "http://${gw}:8100") "mcbots reads BlueMap through the gateway forwarder: ${c.environment.BLUEMAP_URL}";
  assert lib.assertMsg (let
    cs = lab.virtualisation.oci-containers.containers;
    workers = lib.filter (lib.hasPrefix "mcbots-worker") (lib.attrNames cs);
  in
    workers != [] && lib.all (n: cs.${n}.environment.MC_HOST == gw) workers) "every worker container joins Velocity on the gateway ${gw} (the main one uses the pinned name velocity)";
  # Two consoles, never the same: the dashboard's Server panel must not hit the sandbox, nor the rescue the real server.
  assert lib.assertMsg ((c.environment.RCON_HOST != c.environment.SANDBOX_RCON_HOST || c.environment.RCON_PORT != c.environment.SANDBOX_RCON_PORT) && c.environment.RCON_HOST == gw && c.environment.SANDBOX_RCON_HOST == gw) "RCON and SANDBOX_RCON must differ and both go through the gateway: ${c.environment.RCON_HOST}:${c.environment.RCON_PORT} / ${c.environment.SANDBOX_RCON_HOST}:${c.environment.SANDBOX_RCON_PORT}";
  assert lib.assertMsg (c.environment.RCON_PORT == toString ms.paper.serverProperties."rcon.port" && c.environment.SANDBOX_RCON_PORT == toString ms.sandbox.serverProperties."rcon.port") "RCON_PORT is the real server's rcon.port, SANDBOX_RCON_PORT the sandbox's";
  assert lib.assertMsg (!(lib.hasInfix "/var/lib/minecraft-rcon/password" units.mcbots-seed.script) && lib.hasInfix lab.sops.secrets."minecraft-rcon-password".path units.mcbots-seed.script && lib.hasInfix "/var/lib/minecraft-sandbox-rcon/password" units.mcbots-seed.script) "mcbots-seed hands over the real RCON password from sops and the sandbox's generated one";
  assert lib.assertMsg (lib.elem "docker-network-minecraft.service" units.docker-mcbots.after && lib.elem "docker-network-minecraft.service" units.docker-mcbots.requires) "docker-mcbots needs the minecraft network";
  assert lib.assertMsg (lib.all (n: builtins.match "bot[0-9]{1,2}" n != null) names) "BOT_NAMES must match BotGate's ^bot[0-9]{1,2}$: ${c.environment.BOT_NAMES}";
  assert lib.assertMsg (c.environment.ALLOWED_TS_LOGINS != "") "the dashboard must require a Tailscale login allowlist";
  assert lib.assertMsg (lib.hasInfix "tailscale serve" units.mcbots-https.script && !(lib.hasInfix "funnel" units.mcbots-https.script)) "the dashboard is exposed by Tailscale Serve only, never Funnel";
  # Remote-worker hub: its own loopback port behind Tailscale Serve, token from
  # the sops-fed env file (never the plain environment), distinct from the dashboard.
  assert lib.assertMsg (c.environment.WORKER_PORT != c.environment.DASHBOARD_PORT && lib.elem "127.0.0.1:${c.environment.WORKER_PORT}:${c.environment.WORKER_PORT}" c.ports) "the hub port must be its own loopback-published port: ${toString c.ports}";
  assert lib.assertMsg (!(c.environment ? WORKER_TOKEN) && !(c.environment ? WORKER_TOKEN_FILE)) "the hub token must reach the container only through the env file, not the environment";
  assert lib.assertMsg (lib.elem "/run/mcbots/seed.env" c.environmentFiles && lib.hasInfix "WORKER_TOKEN=" units.mcbots-seed.script && lib.hasInfix lab.sops.secrets."mcbots-worker-token".path units.mcbots-seed.script) "mcbots-seed must hand the mcbots-worker-token secret to the container through /run/mcbots/seed.env";
  assert lib.assertMsg (lab.sops.secrets."mcbots-worker-token".mode == "0400") "the hub token must stay mode 0400";
  assert lib.assertMsg (lib.hasInfix "--https=${workerServe} http://127.0.0.1:${c.environment.WORKER_PORT}" units.mcbots-https.script && workerServe != "8445") "the hub is exposed by Tailscale Serve on its own HTTPS port, loopback upstream";
  assert lib.assertMsg (lib.elem "docker-network-mcbots.service" units.docker-mcbots.after && lib.all (u: lib.elem u units.docker-mcbots.after) ["minecraft-server-velocity.service" "minecraft-server-sandbox.service"]) "docker-mcbots starts after the network, the host's Velocity and the sandbox";
    pkgs.runCommand "lab-mcbots" {} "touch $out"

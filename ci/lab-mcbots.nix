# mcbots contract: the bot container publishes only on loopback, stays
# unprivileged without docker.sock, joins the dedicated `mcbots` network plus
# `minecraft` (read-only BlueMap at minecraft:8100; Paper there needs
# Velocity's secret), and every bot name matches BotGate's pattern (otherwise
# Velocity refuses it).
{
  lib,
  lab,
}: let
  c = lab.virtualisation.oci-containers.containers.mcbots;
  extra = lib.concatStringsSep " " c.extraOptions;
  names = lib.splitString "," c.environment.BOT_NAMES;
  units = lab.systemd.services;
in
  assert lib.assertMsg (c.ports != [] && lib.all (lib.hasPrefix "127.0.0.1:") c.ports) "mcbots may publish only on 127.0.0.1: ${toString c.ports}";
  assert lib.assertMsg (!(lib.hasInfix "privileged" extra) && !(lib.hasInfix "cap-add" extra) && !(lib.hasInfix "--network=host" extra) && !(lib.hasInfix "--pid=" extra)) "mcbots must stay unprivileged: ${extra}";
  assert lib.assertMsg (c.volumes == []) "mcbots needs no mounts (no docker.sock, no host paths): ${toString c.volumes}";
  assert lib.assertMsg (lib.hasInfix "--network=mcbots" extra && lib.hasInfix "--network=minecraft" extra && !(lib.hasInfix "--network=bridge" extra) && !(lib.hasInfix "--network=host" extra)) "mcbots joins exactly the mcbots and minecraft networks: ${extra}";
  assert lib.assertMsg (lib.length (lib.filter (lib.hasPrefix "--network") c.extraOptions) == 2) "mcbots may not join further networks: ${extra}";
  assert lib.assertMsg (lib.hasInfix "--add-host=velocity:10.250.77." extra) "with two networks `velocity` must be pinned to its mcbots-network address, or BotGate sees a minecraft-network source: ${extra}";
  assert lib.assertMsg (c.environment.BLUEMAP_URL == "http://minecraft:8100") "mcbots reads BlueMap over the minecraft network only: ${c.environment.BLUEMAP_URL}";
  assert lib.assertMsg (lib.elem "docker-network-minecraft.service" units.docker-mcbots.after && lib.elem "docker-network-minecraft.service" units.docker-mcbots.requires) "docker-mcbots needs the minecraft network";
  assert lib.assertMsg (lib.all (n: builtins.match "bot[0-9]{1,2}" n != null) names) "BOT_NAMES must match BotGate's ^bot[0-9]{1,2}$: ${c.environment.BOT_NAMES}";
  assert lib.assertMsg (c.environment.ALLOWED_TS_LOGINS != "") "the dashboard must require a Tailscale login allowlist";
  assert lib.assertMsg (lib.hasInfix "tailscale serve" units.mcbots-https.script && !(lib.hasInfix "funnel" units.mcbots-https.script)) "the dashboard is exposed by Tailscale Serve only, never Funnel";
  assert lib.assertMsg (lib.elem "docker-network-mcbots.service" units.docker-mcbots.after && lib.elem "docker-velocity.service" units.docker-mcbots.after) "docker-mcbots starts after the network and Velocity";
    builtins.toFile "lab-mcbots" "ok"

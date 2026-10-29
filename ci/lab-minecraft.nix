# Minecraft contract: what the container may touch, how the panel is exposed,
# and the staging ownership rules (bandit-craft hosts/bandit-lab/services/minecraft/stage.sh)
# exercised on a fixture data directory. Evaluation-time assertions plus one
# sandboxed run of the real staging script; nothing is started or contacted.
{
  pkgs,
  lib,
  repoConfig,
  lab,
  craft, # the bandit-craft input, where the Minecraft module lives
}: let
  c = lab.virtualisation.oci-containers.containers.minecraft;
  v = lab.virtualisation.oci-containers.containers.velocity;
  toml = builtins.readFile "${craft}/hosts/bandit-lab/services/minecraft/default.nix"; # velocity.toml is written there
  tailnet = repoConfig.lab.tailscaleIp;
  scripts = import "${craft}/hosts/bandit-lab/services/minecraft/scripts.nix" {inherit pkgs;};
  units = lab.systemd.services;
  sb = lab.virtualisation.oci-containers.containers.minecraft-sandbox;
  extra = lib.concatStringsSep " " c.extraOptions;
  vExtra = lib.concatStringsSep " " v.extraOptions;
  dummyJar = name: pkgs.writeText name "jar";
  seeds = pkgs.linkFarm "seed-plugins" {
    "LuckPerms-Bukkit-5.5.71.jar" = dummyJar "lp";
    "AxGraves-1.32.0.jar" = dummyJar "ax";
  };
  expansions = pkgs.linkFarm "seed-expansions" {"PAPI-Expansion-Player_R5xV754.jar" = dummyJar "papi";};
  overlay = dummyJar "overlay.js";

  # Rehearsal stack on nix-minecraft (phase 5.3).
  ms = lab.services.minecraft-servers.servers;
  inherit (ms) paper;
  vel = ms.velocity;
  fwAll = [lab.networking.firewall] ++ lib.attrValues lab.networking.firewall.interfaces;
  fwTcp = lib.concatMap (f: f.allowedTCPPorts or []) fwAll;
  fwUdp = lib.concatMap (f: f.allowedUDPPorts or []) fwAll;
  fwTs = lab.networking.firewall.interfaces.tailscale0;
  velToml = builtins.readFile vel.files."velocity.toml";
in
  assert lib.assertMsg (c.volumes == ["/srv/containers/minecraft/data:/data"]) "the Minecraft container may mount only its data directory (no docker.sock, no unrelated paths)";
  assert lib.assertMsg (!(lib.hasInfix "privileged" extra) && !(lib.hasInfix "cap-add" extra) && !(lib.hasInfix "docker.sock" extra)) "the Minecraft container must stay unprivileged: ${extra}";
  # Besides the map, only Simple Voice Chat's UDP port, and on the tailnet address only (2026-10-15).
  assert lib.assertMsg (lib.elem (lib.sort lib.lessThan c.ports) [["127.0.0.1:8100:8100"] (lib.sort lib.lessThan ["127.0.0.1:8100:8100" "${tailnet}:24454:24454/udp"])]) "Paper publishes only the map on loopback and voice chat on the tailnet, never a game port: ${toString c.ports}";
  assert lib.assertMsg (v.ports == ["${tailnet}:25565:25565"]) "the Velocity proxy publishes exactly the game port on the tailnet address: ${toString v.ports}";
  assert lib.assertMsg (c.environment.ONLINE_MODE != "FALSE" || (lab.virtualisation.oci-containers.containers ? velocity && !(lib.any (lib.hasSuffix ":25565") c.ports))) "Paper may run online-mode=false only behind Velocity and without a published game port";
  assert lib.assertMsg (lib.hasInfix "--network=minecraft" extra && lib.hasInfix "--network=minecraft" vExtra) "Paper and Velocity share the dedicated minecraft network";
  assert lib.assertMsg (!(lib.hasInfix "privileged" vExtra) && !(lib.hasInfix "cap-add" vExtra) && !(lib.any (lib.hasInfix "docker.sock") v.volumes)) "the Velocity container must stay unprivileged without docker.sock: ${vExtra}";
  assert lib.assertMsg (!(lib.hasInfix "100.125.161.81/" v.environment.BOTGATE_SOURCES) && !(lib.hasInfix "172." v.environment.BOTGATE_SOURCES) && !(lib.hasInfix "--network=bridge" vExtra)) "BotGate must never allowlist the lab tailnet address, a default Docker range or the bridge: ${v.environment.BOTGATE_SOURCES}";
  assert lib.assertMsg (v.environmentFiles == [(lib.head c.environmentFiles)] && !(lib.hasInfix "VELOCITY_FORWARDING_SECRET" (builtins.toJSON v.environment))) "the forwarding secret reaches both containers only through the sops env file";
  assert lib.assertMsg (c.environment.ENABLE_RCON == "true" && !(c.environment ? RCON_PASSWORD) && !(lib.any (lib.hasInfix "25575") c.ports) && lib.elem "/run/minecraft-rcon/rcon.env" c.environmentFiles) "RCON is on for the internal network only: no published RCON port, password only from the generated env file";
  assert lib.assertMsg (lib.hasInfix "--memory=16g" extra && lib.hasInfix "--cpus=6" extra && c.environment.MEMORY == "12G") "resource caps (16 GiB, 6 CPUs, 12 GiB heap) are part of the contract";
  assert lib.assertMsg (c.environment.PAPER_BUILD != "" && !(c.environment ? MOTD)) "the Paper build is pinned and server.properties keys owned by the panel (MOTD) have no environment variable";
  assert lib.assertMsg (!(units.minecraft-plugins.environment ? STAGE_PANELS) && units.minecraft-panels.partOf == ["docker-minecraft.service"]) "menus are reloaded in place (minecraft-panels), never staged before the start, so a menu change does not restart Minecraft";
  assert lib.assertMsg (units.docker-minecraft.serviceConfig.Restart == "always") "docker-minecraft must restart after a clean stop (panel Stop = restart)";
  # docker-prune deletes networks no container is on (2026-10-28: mcbots gone at boot, Velocity down).
  assert lib.all ({
    u,
    n,
  }:
    lib.assertMsg (lib.hasInfix "ensure-${n}-network" units.${u}.preStart) "${u} must re-create the ${n} network in preStart") [
    {
      u = "docker-minecraft";
      n = "minecraft";
    }
    {
      u = "docker-minecraft-sandbox";
      n = "minecraft";
    }
    {
      u = "docker-velocity";
      n = "minecraft";
    }
    {
      u = "docker-velocity";
      n = "mcbots";
    }
    {
      u = "docker-mcbots";
      n = "minecraft";
    }
    {
      u = "docker-mcbots";
      n = "mcbots";
    }
  ];
  assert lib.assertMsg (lib.hasInfix "tailscale serve" units.minecraft-panel-https.script && !(lib.hasInfix "funnel" units.minecraft-panel-https.script)) "map HTTPS is Tailscale Serve (tailnet only), never Funnel";
  assert lib.assertMsg (!(lib.hasInfix "serve 443" units.minecraft-panel-https.script) && !(lib.any (lib.hasInfix "7867") c.ports)) "the retired VoxelDash panel stays unpublished (no port 7867, no serve on 443)";
  assert lib.assertMsg (sb.ports == [] && lib.head sb.volumes == "/srv/containers/minecraft-sandbox/data:/data" && lib.all (v: lib.hasPrefix "/nix/store/" v && lib.hasSuffix ":ro" v) (lib.tail sb.volumes) && sb.image == c.image && lib.elem "--network=minecraft" sb.extraOptions && !(lib.hasInfix "privileged" (toString sb.extraOptions))) "the sandbox publishes no port, mounts only its own data (plus read-only store jars), uses the real image on the minecraft network";
  assert lib.assertMsg (!(lib.hasInfix "minecraft-sandbox" v.environment.BOTGATE_SOURCES) && lib.hasInfix ''try = ["main"]'' toml && lib.hasInfix ''"sandbox.bots" = ["sandbox"]'' toml) "players land on main; only the bots' virtual host is forced to the sandbox";
  assert lib.assertMsg (let
    cs = lab.virtualisation.oci-containers.containers;
    e = cs.mcbots.environment;
    guests = lib.splitString "," (e.GUEST_BOTS or "");
    # A worker running only GUEST_BOTS (another player's bot) plays on main and also obeys that player.
    guestOnly = n: n != "mcbots" && lib.all (b: lib.elem b guests) (lib.drop 1 cs.${n}.cmd);
    bots = lib.filter (lib.hasPrefix "mcbots") (builtins.attrNames cs);
  in
    lib.all (n:
      if guestOnly n
      then lib.hasPrefix "${e.OWNER_UUIDS}," cs.${n}.environment.OWNER_UUIDS
      else (cs.${n}.environment.MC_VHOST or "") == "sandbox.bots" && cs.${n}.environment.OWNER_UUIDS == e.OWNER_UUIDS)
    bots
    && e.RCON_HOST == "minecraft"
    && (e.OWNER_UUIDS or "") != ""
    && (e.PROTECTED_AREAS or "") != ""
    && lib.elem "PATCH_DEFINITIONS" (builtins.attrNames sb.environment)) "every mcbots container but a guest-only worker plays in the sandbox (MC_VHOST sandbox.bots) until the job board passes there (owner 2026-10-23) and obeys only the owner; a guest worker (GUEST_BOTS) also obeys the owner; protected areas set";
  assert lib.assertMsg (lab.systemd.timers ? minecraft-backup) "the consistent Minecraft backup timer must exist";
  assert lib.assertMsg (paper.serverProperties.server-ip == "127.0.0.1" && paper.serverProperties.server-port == 25567) "the rehearsal Paper listens on loopback 25567 only";
  assert lib.assertMsg (paper.serverProperties."rcon.password" == "@RCON_PASSWORD@") "the RCON password is a placeholder filled from the sops env file, never a value in the store";
  assert lib.assertMsg (!paper.openFirewall && !vel.openFirewall && !lab.services.minecraft-servers.openFirewall) "nix-minecraft must not open any firewall port by itself";
  assert lib.assertMsg (lib.elem 25566 fwTs.allowedTCPPorts && lib.elem 24455 fwTs.allowedUDPPorts && !(lib.elem 25566 lab.networking.firewall.allowedTCPPorts)) "Velocity (25566/tcp) and the rehearsal voice chat (24455/udp) are open on tailscale0 only";
  assert lib.assertMsg (!(lib.elem 25567 (fwTcp ++ fwUdp)) && !(lib.elem 25575 (fwTcp ++ fwUdp))) "Paper's port and RCON are in no firewall list";
  assert lib.assertMsg (lib.hasInfix ''bind = "0.0.0.0:25566"'' velToml && lib.hasInfix ''main = "127.0.0.1:25567"'' velToml) "Velocity binds all addresses (tailnet and bridge, firewall decides) and forwards to loopback Paper";
  # The mcbots bridge reaches the rehearsal through one firewall rule on the gateway; Paper's game port is never in it.
  assert lib.assertMsg (let
    gwRules = lib.filter (lib.hasInfix "10.250.77.1") (lib.splitString "\n" lab.networking.firewall.extraCommands);
  in
    gwRules == ["iptables -A nixos-fw -s 10.250.77.0/29 -d 10.250.77.1 -p tcp -m multiport --dports 25566,25575,8101 -j nixos-fw-accept"]) "exactly one bridge rule, to the gateway, for Velocity, rehearsal RCON and map only";
  assert lib.assertMsg (lib.attrNames lab.systemd.sockets
    != []
    && lib.all (n: let
      s = lab.systemd.sockets.${n};
      p = lib.last (lib.splitString ":" (lib.head s.listenStreams));
    in
      lib.hasPrefix "mc-bridge-" n && s.listenStreams == ["10.250.77.1:${p}"] && s.socketConfig.FreeBind && lib.hasInfix "systemd-socket-proxyd 127.0.0.1:${p}" lab.systemd.services.${n}.serviceConfig.ExecStart) (lib.filter (lib.hasPrefix "mc-bridge-") (lib.attrNames lab.systemd.sockets))) "bridge forwarders listen on the gateway only (FreeBind) and forward to the same loopback port";
  assert lib.assertMsg (let
    src = vel.environment.BOTGATE_SOURCES;
  in
    !(lib.hasInfix tailnet src) && !(lib.hasInfix "172." src) && !(lib.hasInfix "10.250.77.1" src) && !(lib.hasInfix "/29" src)) "the rehearsal BotGate allowlist excludes the lab address, Docker defaults, the bridge gateway and the whole /29: ${vel.environment.BOTGATE_SOURCES}";
  assert lib.assertMsg (!(lib.hasInfix "VELOCITY_FORWARDING_SECRET" (builtins.toJSON [paper.environment vel.environment]))) "the forwarding secret reaches the servers only through the sops env file";
  assert lib.assertMsg (paper.managementSystem.systemd-socket.enable && !paper.managementSystem.tmux.enable) "Paper's console is the systemd socket";
  assert lib.assertMsg (paper.package.version == "${c.environment.VERSION}-build.${c.environment.PAPER_BUILD}") "the rehearsal Paper is the same build as the Docker one: ${paper.package.version}";
    pkgs.runCommand "lab-minecraft" {} ''
      export PATH=${lib.makeBinPath [pkgs.coreutils pkgs.gnugrep pkgs.gnused]}:$PATH
      data=$TMPDIR/data
      mkdir -p $data/plugins/ViaVersion $data/plugins/SModeration
      echo 'allow-flight=false' > $data/server.properties
      printf 'packet-limiter:\n  enabled: true\n  max-per-second: 800\n' > $data/plugins/ViaVersion/config.yml
      printf 'force-reason: false\nfeatures:\n  punishments: true\n  smodmenu: true\n  invsee: true\n  enderchestsee: true\n  offlinetp: true\n  socialspy: true\n  vanish: true\ncustom-punishments:\n  enabled: false\n' > $data/plugins/SModeration/config.yml
      # A plugin the panel already updated: its name prefix must block the seed.
      touch "$data/plugins/LuckPerms-Bukkit-5.5.99_[modrinth_x].jar"

      stage() {
        MC_DATA=$data MC_OWNER= \
          STAGE_BLUEMAP=${dummyJar "bluemap"} STAGE_BLUEMAP_VERSION=2.0 \
          STAGE_IMAGEFRAME=${dummyJar "imageframe"} STAGE_IMAGEFRAME_VERSION=1.0 STAGE_IMAGEFRAME_CONFIG=${dummyJar "ifcfg"} \
          STAGE_BLUEMAP_CORE=${dummyJar "core"} STAGE_OVERLAY=${overlay} STAGE_PATCHES=${dummyJar "patch"} \
          STAGE_SEED=${seeds} STAGE_EXPANSIONS=${expansions} \
          ${scripts.stage}/bin/minecraft-stage
      }

      # The retired VoxelDash jar is cleaned up, its data directory is not touched.
      mkdir -p $data/plugins/VoxelDash && touch $data/plugins/VoxelDash-1.2.1.jar $data/plugins/VoxelDash/voxeldash.db
      stage
      test ! -e $data/plugins/VoxelDash-1.2.1.jar && test -e $data/plugins/VoxelDash/voxeldash.db
      test -e $data/plugins/BlueMap-2.0.jar
      test -e $data/plugins/AxGraves-1.32.0.jar                         # seeded
      test ! -e $data/plugins/LuckPerms-Bukkit-5.5.71.jar               # panel's version wins
      test -e $data/plugins/PlaceholderAPI/expansions/PAPI-Expansion-Player_R5xV754.jar
      grep -q '^allow-flight=true$' $data/server.properties
      grep -q '^force-reason: true$' $data/plugins/SModeration/config.yml
      grep -q '^  warn:$' $data/plugins/SModeration/config.yml
      test -e $data/.nix-seed-v1
      test -e $data/nix-patches/velocity.json

      # After the seed the panel owns everything else: a removed plugin stays
      # removed, a changed setting stays changed, Nix-owned jars are replaced.
      rm $data/plugins/AxGraves-1.32.0.jar
      sed -i 's/^allow-flight=true$/allow-flight=false/' $data/server.properties
      stage
      test ! -e $data/plugins/AxGraves-1.32.0.jar
      grep -q '^allow-flight=false$' $data/server.properties
      test -e $data/plugins/BlueMap-2.0.jar

      # The bot overlay script is staged and registered in BlueMap's webapp.conf, once; an unexpected
      # scripts entry is left alone (stage must still succeed: the map has to start).
      test -e $data/bluemap/web/mcbots/overlay.js
      printf 'enabled: true\nscripts: []\nstyles: []\n' > $data/plugins/BlueMap/webapp.conf
      stage
      stage
      grep -q '^scripts: \["mcbots/overlay.js"\]$' $data/plugins/BlueMap/webapp.conf
      test "$(grep -c overlay $data/plugins/BlueMap/webapp.conf)" -eq 1
      grep -q '^styles: \[\]$' $data/plugins/BlueMap/webapp.conf
      # BlueMap's own generated default spans lines with a comment inside.
      printf 'enabled: true\nscripts: [\n  #"js/my-custom-script.js"\n]\nstyles: [\n]\n' > $data/plugins/BlueMap/webapp.conf
      stage
      stage
      grep -q '^scripts: \["mcbots/overlay.js"\]$' $data/plugins/BlueMap/webapp.conf
      test "$(grep -c overlay $data/plugins/BlueMap/webapp.conf)" -eq 1
      grep -q '^styles: \[$' $data/plugins/BlueMap/webapp.conf
      ! grep -q my-custom-script $data/plugins/BlueMap/webapp.conf
      # An unclosed block is left alone.
      printf 'scripts: [\n  #"x.js"\n' > $data/plugins/BlueMap/webapp.conf
      stage 2>/dev/null
      test "$(wc -l < $data/plugins/BlueMap/webapp.conf)" -eq 2
      printf 'scripts: ["other.js"]\n' > $data/plugins/BlueMap/webapp.conf
      stage 2>/dev/null
      grep -q '^scripts: \["other.js"\]$' $data/plugins/BlueMap/webapp.conf

      # A BlueMap config that exists is never overwritten.
      echo custom > $data/plugins/BlueMap/core.conf
      stage
      grep -q '^custom$' $data/plugins/BlueMap/core.conf

      # minecraft-snapshot on the nix-minecraft backend (phase 5.4), with fake systemctl/journalctl:
      # live = save-off, flush, copy, save-on in that order; inactive = cold copy, no console;
      # an unclear state = no copy (fail closed).
      fake=$TMPDIR/fake && mkdir -p $fake
      printf '#!${pkgs.runtimeShell}\ncat $TMPDIR/state\n[ "$(cat $TMPDIR/state)" = active ]\n' > $fake/systemctl
      printf '#!${pkgs.runtimeShell}\necho "[INFO]: Saved the game"\n' > $fake/journalctl
      chmod +x $fake/*
      snap() {
        : > $TMPDIR/console
        PATH=$fake:${lib.makeBinPath [pkgs.coreutils pkgs.gnugrep pkgs.rsync pkgs.util-linux]} \
          MC_UNIT=minecraft-server-paper MC_CONSOLE=$TMPDIR/console MC_DATA=$data MC_LOCK=$TMPDIR/snap.lock \
          ${pkgs.bash}/bin/bash ${craft}/hosts/bandit-lab/services/minecraft/snapshot.sh "$1"
      }
      echo active > $TMPDIR/state
      snap $TMPDIR/live
      test "$(cat $TMPDIR/console)" = "$(printf 'save-off\nsave-all flush\nsave-on')"
      test -e $TMPDIR/live/server.properties
      echo inactive > $TMPDIR/state
      snap $TMPDIR/cold
      test ! -s $TMPDIR/console && test -e $TMPDIR/cold/server.properties
      echo activating > $TMPDIR/state
      ! snap $TMPDIR/unclear
      test ! -e $TMPDIR/unclear
      touch "$out"
    ''

# Minecraft contract: the live nix-minecraft stack (phase 5.5: ports, firewall, the bridge to the Docker
# mcbots, the cutover), what the stopped Docker containers (kept for rollback until 5.6) may still touch,
# how the panel is exposed, and the staging ownership rules (bandit-craft hosts/bandit-lab/services/minecraft/
# stage.sh) exercised on a fixture data directory. Evaluation-time assertions plus sandboxed runs of the
# real staging, snapshot and cutover scripts; nothing is started or contacted.
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

  # The live stack on nix-minecraft (phase 5.5).
  ms = lab.services.minecraft-servers.servers;
  inherit (ms) paper;
  sbx = ms.sandbox;
  vel = ms.velocity;
  fwAll = [lab.networking.firewall] ++ lib.attrValues lab.networking.firewall.interfaces;
  fwTcp = lib.concatMap (f: f.allowedTCPPorts or []) fwAll;
  fwUdp = lib.concatMap (f: f.allowedUDPPorts or []) fwAll;
  fwTs = lab.networking.firewall.interfaces.tailscale0;
  velToml = builtins.readFile vel.files."velocity.toml";
  velPort = lib.head (builtins.match ".*bind = \"0\\.0\\.0\\.0:([0-9]+)\".*" velToml);
  gw = "10.250.77.1";
  sharedEnv = toString lab.services.minecraft-servers.environmentFile;
  bridgeSockets = lib.filterAttrs (n: _: lib.hasPrefix "mc-bridge-" n) lab.systemd.sockets;
  sockPort = s: lib.last (lib.splitString ":" (lib.head s.listenStreams));
  bridgeTarget = port: let
    names = lib.filter (n: sockPort bridgeSockets.${n} == toString port) (lib.attrNames bridgeSockets);
  in
    if names == []
    then "none"
    else lib.last (lib.splitString " " lab.systemd.services.${lib.head names}.serviceConfig.ExecStart);
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
  assert lib.assertMsg (!(units.minecraft-plugins.environment ? STAGE_PANELS) && units.minecraft-panels.partOf == ["minecraft-server-paper.service"]) "menus are reloaded in place (minecraft-panels, over RCON), never staged before the start, so a menu change does not restart Minecraft";
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
  assert lib.assertMsg (lib.hasInfix "http://127.0.0.1:$2" units.minecraft-panel-https.script && lib.hasInfix "serve 8443 8100" units.minecraft-panel-https.script && lib.elem "minecraft-server-paper.service" units.minecraft-panel-https.after) "the map is served from BlueMap on 127.0.0.1:8100, after the nix Paper";
  assert lib.assertMsg (!(lib.hasInfix "serve 443" units.minecraft-panel-https.script) && !(lib.any (lib.hasInfix "7867") c.ports)) "the retired VoxelDash panel stays unpublished (no port 7867, no serve on 443)";
  assert lib.assertMsg (sb.ports == [] && lib.head sb.volumes == "/srv/containers/minecraft-sandbox/data:/data" && lib.all (v: lib.hasPrefix "/nix/store/" v && lib.hasSuffix ":ro" v) (lib.tail sb.volumes) && sb.image == c.image && lib.elem "--network=minecraft" sb.extraOptions && !(lib.hasInfix "privileged" (toString sb.extraOptions))) "the sandbox publishes no port, mounts only its own data (plus read-only store jars), uses the real image on the minecraft network";
  assert lib.assertMsg (!(lib.hasInfix "minecraft-sandbox" v.environment.BOTGATE_SOURCES) && lib.hasInfix ''try = ["main"]'' toml && lib.hasInfix ''"sandbox.bots" = ["sandbox"]'' toml) "players land on main; only the bots' virtual host is forced to the sandbox";
  assert lib.assertMsg (let
    cs = lab.virtualisation.oci-containers.containers;
    e = cs.mcbots.environment;
  in
    lib.all (n: (cs.${n}.environment.MC_VHOST or "") == "sandbox.bots") (lib.filter (lib.hasPrefix "mcbots") (builtins.attrNames cs)) && e.RCON_HOST == gw && (e.OWNER_UUIDS or "") != "" && (e.PROTECTED_AREAS or "") != "" && lib.elem "PATCH_DEFINITIONS" (builtins.attrNames sb.environment)) "every mcbots container plays in the sandbox (MC_VHOST sandbox.bots) until the job board passes there (owner 2026-10-23); protected areas set, only the owner's in-game orders count";
  # Phase 5.5: the Docker stack stays defined (rollback) but nothing starts it.
  assert lib.assertMsg (lib.all (n: !lab.virtualisation.oci-containers.containers.${n}.autoStart && lab.systemd.services.${"docker-" + n}.wantedBy == []) ["minecraft" "velocity" "minecraft-sandbox"]) "the Docker minecraft, velocity and minecraft-sandbox containers stay defined but must not autostart (removal is phase 5.6)";
  assert lib.assertMsg (lab.systemd.timers ? minecraft-backup && lab.systemd.services.minecraft-backup.environment.MC_UNIT == "minecraft-server-paper" && lab.systemd.services.minecraft-backup.environment.MC_DATA == "/srv/minecraft/paper") "the daily backup must snapshot the nix-minecraft server, not the stopped Docker container";
  # Listening addresses: only Velocity listens beyond loopback; no backend sits on its port.
  assert lib.assertMsg (paper.serverProperties.server-ip == "127.0.0.1" && sbx.serverProperties.server-ip == "127.0.0.1") "both Paper servers listen on loopback only";
  assert lib.assertMsg (lib.hasInfix ''bind = "0.0.0.0:25565"'' velToml && velPort == "25565") "Velocity binds all addresses on 25565 (tailnet and bridge, the firewall decides)";
  assert lib.assertMsg (lib.length (lib.unique (map toString [paper.serverProperties.server-port sbx.serverProperties.server-port paper.serverProperties."rcon.port" sbx.serverProperties."rcon.port"])) == 4 && !(lib.elem velPort (map toString [paper.serverProperties.server-port sbx.serverProperties.server-port paper.serverProperties."rcon.port" sbx.serverProperties."rcon.port"]))) "game and RCON ports of both servers are distinct and none is Velocity's";
  assert lib.assertMsg (lib.hasInfix ''main = "127.0.0.1:${toString paper.serverProperties.server-port}"'' velToml && lib.hasInfix ''sandbox = "127.0.0.1:${toString sbx.serverProperties.server-port}"'' velToml && lib.hasInfix ''try = ["main"]'' velToml && lib.hasInfix ''"sandbox.bots" = ["sandbox"]'' velToml) "players land on main; only the bots' virtual host is forced to the sandbox; both backends are loopback";
  assert lib.assertMsg (paper.serverProperties."rcon.password" == "@RCON_PASSWORD@" && sbx.serverProperties."rcon.password" == "@RCON_PASSWORD@") "the RCON passwords are placeholders filled from environment files, never values in the store";
  assert lib.assertMsg (!sbx.serverProperties.online-mode && !sbx.serverProperties.enforce-secure-profile && sbx.serverProperties.difficulty == "normal" && sbx.serverProperties.view-distance == 8 && sbx.serverProperties.spawn-protection == 0) "the sandbox keeps the Docker sandbox's settings";
  assert lib.assertMsg (lib.attrNames sbx.symlinks == ["plugins/ViaBackwards-5.12.0.jar" "plugins/ViaVersion-5.12.0.jar"] && sbx.operators.fancy8869.level == 4) "the sandbox runs only the ViaVersion pair and has the owner as operator";
  assert lib.assertMsg (!paper.openFirewall && !sbx.openFirewall && !vel.openFirewall && !lab.services.minecraft-servers.openFirewall) "nix-minecraft must not open any firewall port by itself";
  assert lib.assertMsg (lib.elem 25565 fwTs.allowedTCPPorts && lib.elem 24454 fwTs.allowedUDPPorts && !(lib.elem 25565 (lib.concatMap (f: f.allowedTCPPorts or []) (lib.filter (f: f != fwTs) fwAll))) && !(lib.elem 24454 (lib.concatMap (f: f.allowedUDPPorts or []) (lib.filter (f: f != fwTs) fwAll)))) "Velocity (25565/tcp) and voice chat (24454/udp) are open on tailscale0 only";
  assert lib.assertMsg (lib.all (p: !(lib.elem p (fwTcp ++ fwUdp))) [25567 25568 25575 25576 8100]) "Paper's ports, both RCONs and the map are in no firewall list";
  # The mcbots bridge reaches the stack through one firewall rule on the gateway; no Paper game port is in it.
  assert lib.assertMsg (let
    gwRules = lib.filter (lib.hasInfix gw) (lib.splitString "\n" lab.networking.firewall.extraCommands);
    m = builtins.match "iptables -A nixos-fw -s 10\\.250\\.77\\.0/29 -d 10\\.250\\.77\\.1 -p tcp -m multiport --dports ([0-9,]+) -j nixos-fw-accept" (lib.head (gwRules ++ [""]));
  in
    lib.length gwRules == 1 && m != null && lib.sort lib.lessThan (lib.splitString "," (lib.head m)) == lib.sort lib.lessThan ["25565" "25575" "25576" "8100"]) "exactly one bridge rule, to the gateway, for Velocity, both RCONs and the map only";
  assert lib.assertMsg (lib.sort lib.lessThan (map sockPort (lib.attrValues bridgeSockets)) == lib.sort lib.lessThan ["25575" "25576" "8100"]) "the bridge forwards exactly the two RCONs and the map (Velocity listens on the gateway itself)";
  assert lib.assertMsg (lib.all (n: let
    s = bridgeSockets.${n};
    p = sockPort s;
  in
    s.listenStreams == ["${gw}:${p}"] && s.socketConfig.FreeBind && lib.hasInfix "systemd-socket-proxyd 127.0.0.1:${p}" lab.systemd.services.${n}.serviceConfig.ExecStart) (lib.attrNames bridgeSockets)) "bridge forwarders listen on the gateway only (FreeBind) and forward to the same loopback port";
  # Misrouting guard: RCON of the real server must never reach the sandbox (or the other way round), the map is the real one's.
  assert lib.assertMsg (bridgeTarget 25575 == "127.0.0.1:${toString paper.serverProperties."rcon.port"}" && bridgeTarget 25576 == "127.0.0.1:${toString sbx.serverProperties."rcon.port"}" && paper.serverProperties."rcon.port" == 25575 && sbx.serverProperties."rcon.port" == 25576) "the 25575 forwarder targets the real server's RCON and the 25576 forwarder the sandbox's";
  assert lib.assertMsg (let
    src = vel.environment.BOTGATE_SOURCES;
  in
    !(lib.hasInfix tailnet src) && !(lib.hasInfix "172." src) && !(lib.hasInfix gw src) && !(lib.hasInfix "/29" src)) "the BotGate allowlist excludes the lab address, Docker defaults, the bridge gateway and the whole /29: ${vel.environment.BOTGATE_SOURCES}";
  # Resources as the Docker containers had them.
  assert lib.assertMsg (lib.hasInfix "-Xms12G -Xmx12G" paper.jvmOpts && units.minecraft-server-paper.serviceConfig.MemoryMax == "16G" && units.minecraft-server-paper.serviceConfig.CPUQuota == "600%") "the real Paper has the Docker caps: 12 GiB heap, 16 GiB, 6 CPUs";
  assert lib.assertMsg (lib.hasInfix "-Xms4G -Xmx4G" sbx.jvmOpts && units.minecraft-server-sandbox.serviceConfig.MemoryMax == "6G" && units.minecraft-server-sandbox.serviceConfig.CPUQuota == "300%") "the sandbox has the Docker sandbox's caps: 4 GiB heap, 6 GiB, 3 CPUs";
  # Cutover: the Docker units are stopped by systemd before the copy, the copy precedes every nix server, and
  # the rehearsal copy (whose stamp the cutover deletes) is gone so it cannot overwrite the live world.
  assert lib.assertMsg (let
    u = units.minecraft-cutover;
    docker = ["docker-velocity.service" "docker-minecraft.service" "docker-minecraft-sandbox.service"];
    servers = ["minecraft-server-paper.service" "minecraft-server-sandbox.service" "minecraft-server-velocity.service"];
  in
    lib.all (d: lib.elem d u.conflicts && lib.elem d u.after) docker && lib.all (x: lib.elem x u.before && lib.elem x u.requiredBy) servers && u.serviceConfig.Type == "oneshot" && !(units ? minecraft-rehearsal-copy)) "the cutover conflicts with and runs after the Docker units, before and required by all three nix servers; no rehearsal copy remains";
  assert lib.assertMsg (lib.hasInfix "/bin/minecraft-cutover" units.minecraft-cutover.serviceConfig.ExecStart) "the cutover runs minecraft-cutover";
  # Sandbox RCON password: the sandbox's own file is read after the shared one, so it overrides RCON_PASSWORD.
  assert lib.assertMsg (units.minecraft-server-sandbox.serviceConfig.EnvironmentFile == [sharedEnv "/run/minecraft-sandbox-rcon/rcon.env"] && units.minecraft-server-paper.serviceConfig.EnvironmentFile == sharedEnv && lib.elem "minecraft-server-sandbox.service" units.minecraft-sandbox-rcon-seed.requiredBy) "the sandbox reads its own RCON password after the shared environment file";
  assert lib.assertMsg (!(lib.hasInfix "VELOCITY_FORWARDING_SECRET" (builtins.toJSON [paper.environment vel.environment]))) "the forwarding secret reaches the servers only through the sops env file";
  assert lib.assertMsg (paper.managementSystem.systemd-socket.enable && !paper.managementSystem.tmux.enable) "Paper's console is the systemd socket";
  assert lib.assertMsg (paper.package.version == "${c.environment.VERSION}-build.${c.environment.PAPER_BUILD}" && sbx.package == paper.package) "both Paper servers are the build the Docker one was: ${paper.package.version}";
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

      # minecraft-cutover (phase 5.5), fake systemctl/docker: a live Docker unit or container = refuse and copy
      # nothing; cold = copy over the rehearsal copy (stale files go, jars and locks go, ports fixed), stamp both
      # sides; stamped = nothing, even when the sources are live again.
      units=$TMPDIR/units && mkdir -p $units
      printf '#!${pkgs.runtimeShell}\ns=inactive; [ -e "$TMPDIR/units/$2" ] && s=$(cat "$TMPDIR/units/$2")\necho "$s"\n[ "$s" = active ]\n' > $fake/systemctl
      printf '#!${pkgs.runtimeShell}\nif [ -e "$TMPDIR/docker-error" ]; then cat "$TMPDIR/docker-error" >&2; exit 1; fi\ncat "$TMPDIR/docker-running"\n' > $fake/docker
      chmod +x $fake/*
      src=$TMPDIR/old/data
      dst=$TMPDIR/new/paper
      mkdir -p $src/world $src/plugins/BlueMap $src/plugins/voicechat $src/logs $src/backups $src/bluemap/web/mcbots $dst/plugins
      echo level > $src/world/level.dat
      touch $src/world/session.lock $src/plugins/LuckPerms.jar $src/logs/latest.log $src/backups/b.zip $src/.rcon-cli.history
      echo overlay > $src/bluemap/web/mcbots/overlay.js
      printf 'port=24454\n' > $src/plugins/voicechat/voicechat-server.properties
      printf 'port: 8100\nip: "0.0.0.0"\n' > $src/plugins/BlueMap/webserver.conf
      touch $dst/.rehearsal-copied $dst/stale-rehearsal-file
      cutover() {
        PATH=$fake:${lib.makeBinPath [pkgs.coreutils pkgs.findutils pkgs.gnugrep pkgs.gnused pkgs.rsync]} \
          MC_SRC=$src MC_DEST=$dst MC_OLD_STAMP=$TMPDIR/old/CUTOVER-5.5-DONE MC_OWNER= \
          ${pkgs.bash}/bin/bash ${craft}/hosts/bandit-lab/services/minecraft/cutover.sh
      }
      echo false > $TMPDIR/docker-running
      echo active > $units/docker-minecraft.service
      ! cutover 2>/dev/null
      echo inactive > $units/docker-minecraft.service
      echo true > $TMPDIR/docker-running
      ! cutover 2>/dev/null
      echo false > $TMPDIR/docker-running
      echo 'Cannot connect to the Docker daemon' > $TMPDIR/docker-error
      ! cutover 2>/dev/null
      echo 'Error response from daemon: No such object: minecraft' > $TMPDIR/docker-error
      echo active > $units/minecraft-server-paper.service
      ! cutover 2>/dev/null
      test ! -e $dst/.cutover-done && test ! -e $dst/world && test -e $dst/stale-rehearsal-file
      echo inactive > $units/minecraft-server-paper.service
      cutover
      test -e $dst/.cutover-done && test -e $TMPDIR/old/CUTOVER-5.5-DONE
      test "$(cat $dst/world/level.dat)" = level && test ! -e $dst/world/session.lock
      test ! -e $dst/stale-rehearsal-file && test ! -e $dst/.rehearsal-copied && test ! -e $dst/plugins/LuckPerms.jar && test ! -e $dst/.rcon-cli.history
      test ! -e $dst/logs && test ! -e $dst/backups && test -e $dst/bluemap/web/mcbots/overlay.js
      grep -qx 'port=24454' $dst/plugins/voicechat/voicechat-server.properties
      test "$(cat $dst/plugins/BlueMap/webserver.conf)" = "$(printf 'port: 8100\nip: "127.0.0.1"')"
      touch $src/world/new-after-cutover
      echo active > $units/docker-minecraft.service
      cutover
      test ! -e $dst/world/new-after-cutover
      touch "$out"
    ''

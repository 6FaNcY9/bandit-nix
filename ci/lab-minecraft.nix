# Minecraft contract: what the container may touch, how the panel is exposed,
# and the staging ownership rules (hosts/bandit-lab/services/minecraft/stage.sh)
# exercised on a fixture data directory. Evaluation-time assertions plus one
# sandboxed run of the real staging script; nothing is started or contacted.
{
  pkgs,
  lib,
  repoConfig,
  lab,
}: let
  c = lab.virtualisation.oci-containers.containers.minecraft;
  tailnet = repoConfig.lab.tailscaleIp;
  scripts = import ../hosts/bandit-lab/services/minecraft/scripts.nix {inherit pkgs;};
  units = lab.systemd.services;
  extra = lib.concatStringsSep " " c.extraOptions;
  dummyJar = name: pkgs.writeText name "jar";
  seeds = pkgs.linkFarm "seed-plugins" {
    "LuckPerms-Bukkit-5.5.71.jar" = dummyJar "lp";
    "AxGraves-1.32.0.jar" = dummyJar "ax";
  };
  expansions = pkgs.linkFarm "seed-expansions" {"PAPI-Expansion-Player_R5xV754.jar" = dummyJar "papi";};
  panels = pkgs.linkFarm "panels" {"admin.yml" = pkgs.writeText "admin.yml" "title: admin\n";};
in
  assert lib.assertMsg (c.volumes == ["/srv/containers/minecraft/data:/data"]) "the Minecraft container may mount only its data directory (no docker.sock, no unrelated paths)";
  assert lib.assertMsg (!(lib.hasInfix "privileged" extra) && !(lib.hasInfix "cap-add" extra) && !(lib.hasInfix "docker.sock" extra)) "the Minecraft container must stay unprivileged: ${extra}";
  assert lib.assertMsg (lib.sort lib.lessThan c.ports == lib.sort lib.lessThan ["${tailnet}:25565:25565" "127.0.0.1:7867:7867" "127.0.0.1:8100:8100"]) "Minecraft publishes the game port on the tailnet and the panel/map on loopback only: ${toString c.ports}";
  assert lib.assertMsg (c.environment.ENABLE_RCON == "false" && !(c.environment ? RCON_PASSWORD)) "RCON stays disabled";
  assert lib.assertMsg (lib.hasInfix "--memory=12g" extra && lib.hasInfix "--cpus=4" extra && c.environment.MEMORY == "8G") "resource caps (12 GiB, 4 CPUs, 8 GiB heap) are part of the contract";
  assert lib.assertMsg (c.environment.PAPER_BUILD != "" && !(c.environment ? MOTD)) "the Paper build is pinned and server.properties keys owned by the panel (MOTD) have no environment variable";
  assert lib.assertMsg (units.docker-minecraft.serviceConfig.Restart == "always") "docker-minecraft must restart after a clean stop (panel Stop = restart)";
  assert lib.assertMsg (lib.hasInfix "tailscale serve" units.minecraft-panel-https.script && !(lib.hasInfix "funnel" units.minecraft-panel-https.script)) "panel HTTPS is Tailscale Serve (tailnet only), never Funnel";
  assert lib.assertMsg (lab.systemd.timers ? minecraft-backup) "the consistent Minecraft backup timer must exist";
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
          STAGE_VOXELDASH=${dummyJar "voxeldash"} STAGE_VOXELDASH_VERSION=1.0 \
          STAGE_BLUEMAP=${dummyJar "bluemap"} STAGE_BLUEMAP_VERSION=2.0 \
          STAGE_BLUEMAP_CORE=${dummyJar "core"} STAGE_PANELS=${panels} \
          STAGE_SEED=${seeds} STAGE_EXPANSIONS=${expansions} \
          ${scripts.stage}/bin/minecraft-stage
      }

      stage
      test -e $data/plugins/VoxelDash-1.0.jar && test -e $data/plugins/BlueMap-2.0.jar
      test -e $data/plugins/AxGraves-1.32.0.jar                         # seeded
      test ! -e $data/plugins/LuckPerms-Bukkit-5.5.71.jar               # panel's version wins
      test -e $data/plugins/PlaceholderAPI/expansions/PAPI-Expansion-Player_R5xV754.jar
      grep -q '^allow-flight=true$' $data/server.properties
      grep -q '^force-reason: true$' $data/plugins/SModeration/config.yml
      grep -q '^  warn:$' $data/plugins/SModeration/config.yml
      test -e $data/.nix-seed-v1

      # After the seed the panel owns everything else: a removed plugin stays
      # removed, a changed setting stays changed, Nix-owned jars are replaced.
      rm $data/plugins/AxGraves-1.32.0.jar
      sed -i 's/^allow-flight=true$/allow-flight=false/' $data/server.properties
      touch $data/plugins/VoxelDash-0.9.jar
      stage
      test ! -e $data/plugins/AxGraves-1.32.0.jar
      grep -q '^allow-flight=false$' $data/server.properties
      test ! -e $data/plugins/VoxelDash-0.9.jar && test -e $data/plugins/VoxelDash-1.0.jar

      # A BlueMap config that exists is never overwritten.
      echo custom > $data/plugins/BlueMap/core.conf
      stage
      grep -q '^custom$' $data/plugins/BlueMap/core.conf
      touch "$out"
    ''

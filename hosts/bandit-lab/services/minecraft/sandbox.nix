# Sandbox Paper server for the bots: a copy of the real world on the same internal `minecraft` network,
# no published port; only the ViaVersion pair as plugins. Behind Velocity like the real server (modern
# forwarding, same secret): the bots join with the virtual host sandbox.bots (Velocity's forced host),
# players with /server sandbox. Whatever the bots try there never touches the real base.
# Reset: `systemctl stop docker-minecraft-sandbox`, remove
# /srv/containers/minecraft-sandbox/data/world, start it (re-copies the real world).
{
  config,
  lib,
  pkgs,
  ...
}: let
  real = config.virtualisation.oci-containers.containers.minecraft;
  docker = "${pkgs.docker}/bin/docker";
  data = "/srv/containers/minecraft-sandbox/data";
  # The bots speak 26.1 (mineflayer); ViaBackwards (on ViaVersion) lets them join 26.2, as on the real
  # server (same pinned jars as its seedPlugins). Mounted read-only into /plugins, which itzg copies.
  via = {
    "ViaVersion.jar" = pkgs.fetchurl {
      url = "https://hangarcdn.papermc.io/plugins/ViaVersion/ViaVersion/versions/5.12.0/PAPER/ViaVersion-5.12.0.jar";
      hash = "sha256-xNUS+pdg+kHRerrt3hKqH0yb3pINCpkv4PwBaWLxJr4=";
    };
    "ViaBackwards.jar" = pkgs.fetchurl {
      url = "https://hangarcdn.papermc.io/plugins/ViaVersion/ViaBackwards/versions/5.12.0/PAPER/ViaBackwards-5.12.0.jar";
      hash = "sha256-+QL32n65nov69GH4AoPE4nULfZcn5rUI6ku5Fj9Vsds=";
    };
  };
in {
  systemd = {
    tmpfiles.rules = ["d ${data} 0750 1000 1000 -"];

    services = {
      # Own RCON password (root-only), same pattern as minecraft-rcon-seed.
      minecraft-sandbox-rcon-seed = {
        description = "Generate the sandbox Minecraft RCON password and its environment file";
        before = ["docker-minecraft-sandbox.service"];
        requiredBy = ["docker-minecraft-sandbox.service"];
        path = [pkgs.coreutils];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          UMask = "0077";
        };
        script = ''
          install -d -m 0700 /var/lib/minecraft-sandbox-rcon /run/minecraft-sandbox-rcon
          [ -s /var/lib/minecraft-sandbox-rcon/password ] || head -c 32 /dev/urandom | sha256sum | cut -c1-64 > /var/lib/minecraft-sandbox-rcon/password
          printf 'RCON_PASSWORD=%s\n' "$(cat /var/lib/minecraft-sandbox-rcon/password)" > /run/minecraft-sandbox-rcon/rcon.env
        '';
      };

      # First start only: copy the real world. The real server is flushed and
      # frozen (save-off) during the copy; save-on runs on every exit path.
      # The real world is only ever read.
      minecraft-sandbox-seed = {
        description = "Copy the real Minecraft world into the sandbox (once)";
        before = ["docker-minecraft-sandbox.service"];
        requiredBy = ["docker-minecraft-sandbox.service"];
        path = [pkgs.coreutils pkgs.gnugrep];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          TimeoutStartSec = "30min";
        };
        script = ''
          # Bots reconnect often: no connection throttle. Paper fills in the rest of bukkit.yml.
          if ! grep -qs 'connection-throttle: -1$' ${data}/bukkit.yml; then
            printf 'settings:\n  connection-throttle: -1\n' > ${data}/bukkit.yml
            chown 1000:1000 ${data}/bukkit.yml
          fi
          dst=${data}/world
          [ -e "$dst" ] && exit 0
          src=/srv/containers/minecraft/data/world
          [ -d "$src" ] || exit 0 # no real world yet: the sandbox generates its own
          console() { ${docker} exec --user 1000 minecraft mc-send-to-console "$1"; }
          running=$(${docker} inspect -f '{{.State.Running}}' minecraft 2>/dev/null || true)
          if [ "$running" = true ]; then
            trap 'console save-on || true' EXIT
            console save-off
            console "save-all flush"
            sleep 10
          fi
          rm -rf "$dst.partial"
          cp -a "$src" "$dst.partial"
          rm -f "$dst.partial/session.lock"
          mv "$dst.partial" "$dst" # visible only once complete
        '';
      };

      docker-minecraft-sandbox = {
        after = ["docker-network-minecraft.service"];
        requires = ["docker-network-minecraft.service"];
        unitConfig.StartLimitIntervalSec = 0;
        serviceConfig = {
          Restart = lib.mkForce "always";
          RestartSec = "10s";
        };
      };
    };
  };

  virtualisation.oci-containers.containers.minecraft-sandbox = {
    inherit (real) image; # same pinned image as the real server
    environment = {
      EULA = "TRUE";
      TYPE = "PAPER";
      VERSION = "26.2";
      PAPER_BUILD = "130";
      TZ = config.time.timeZone;
      MEMORY = "4G";
      USE_AIKAR_FLAGS = "true";
      # Authentication happens at the proxy; the forwarding secret keeps everyone else out.
      ONLINE_MODE = "FALSE";
      SPAWN_PROTECTION = "0";
      DIFFICULTY = "normal";
      MODE = "survival";
      VIEW_DISTANCE = "8";
      ENABLE_RCON = "true";
      PATCH_DEFINITIONS = "/nix-patches";
      # The owner watches the bots in spectator mode (/gamemode spectator); Velocity's modern forwarding
      # makes this the real, Mojang-checked account.
      OPS = "fancy8869";
    };
    environmentFiles = [
      config.sops.templates."minecraft-velocity.env".path # CFG_VELOCITY_SECRET for the patch below
      "/run/minecraft-sandbox-rcon/rcon.env"
    ];
    volumes =
      ["${data}:/data" "${import ./velocity-patch.nix {inherit pkgs;}}:/nix-patches/velocity.json:ro"]
      ++ lib.mapAttrsToList (name: jar: "${jar}:/plugins/${name}:ro") via;
    extraOptions = [
      "--network=minecraft"
      "--memory=6g"
      "--cpus=3"
      "--stop-timeout=60"
    ];
  };
}

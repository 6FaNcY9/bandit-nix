{
  config,
  pkgs,
  ...
}: let
  # Paper plugins pinned from Hangar (hangar.papermc.io), latest Release
  # channel. ViaVersion lets newer clients join; ViaBackwards (requires
  # ViaVersion) lets older clients join. Both support Paper 1.8/1.10-26.2.
  viaVersion = pkgs.fetchurl {
    url = "https://hangarcdn.papermc.io/plugins/ViaVersion/ViaVersion/versions/5.11.0/PAPER/ViaVersion-5.11.0.jar";
    hash = "sha256-idt2yOPmdCOPXu4rt6npor7roHYLvRuGSUd46KWlL3A=";
  };
  viaBackwards = pkgs.fetchurl {
    url = "https://hangarcdn.papermc.io/plugins/ViaVersion/ViaBackwards/versions/5.11.0/PAPER/ViaBackwards-5.11.0.jar";
    hash = "sha256-QQhaWdeEyaDRSRf+dIfvXiAanaeCX9BH8I0yj/M+7Nw=";
  };
  pluginsDir = "/srv/containers/minecraft/data/plugins";
in {
  # Pre-create the data dir like every other stateful service instead of
  # letting Docker auto-create it root-owned on first start.
  systemd.tmpfiles.rules = [
    "d /srv/containers/minecraft/data 0750 root root -"
  ];

  # Stage pinned plugin JARs into the data volume before the container
  # starts. Stale managed JARs are removed first so version bumps don't
  # leave duplicates behind. Runs as root on the host; the container only
  # sees plain files (a nix-store symlink would not resolve inside it).
  systemd.services.minecraft-plugins = {
    description = "Stage managed Minecraft Paper plugins";
    before = ["docker-minecraft.service"];
    requiredBy = ["docker-minecraft.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mkdir -p ${pluginsDir}
      rm -f ${pluginsDir}/ViaVersion-*.jar ${pluginsDir}/ViaBackwards-*.jar
      install -m 0644 ${viaVersion} ${pluginsDir}/ViaVersion-5.11.0.jar
      install -m 0644 ${viaBackwards} ${pluginsDir}/ViaBackwards-5.11.0.jar
    '';
  };

  # Minecraft Java server (Paper) for ~12 players. Hard-capped at 4 CPU cores
  # and 12 GiB so it can never starve Traefik/PostgreSQL/Wazuh & co. — the lab
  # (i9-14900HX, 62 GiB) barely notices it. Not proxied through Traefik:
  # Minecraft is a raw TCP protocol, so port 25565 is published directly.
  virtualisation.oci-containers.containers.minecraft = {
    # java25 tag: Minecraft 26.1+ refuses to start on anything older.
    image = "itzg/minecraft-server@sha256:769a826c340586e9d483a0eb6437b8e2c3611aea6a115ff072a2fe372d43e2be"; # java25
    environment = {
      EULA = "TRUE";
      # Paper over vanilla: same gameplay, much better tick performance.
      TYPE = "PAPER";
      TZ = config.time.timeZone;
      # 8 GiB heap (Xms = Xmx) + Aikar GC flags = no GC stutter; container
      # cap below leaves headroom for off-heap/metaspace.
      MEMORY = "8G";
      USE_AIKAR_FLAGS = "true";
      MAX_PLAYERS = "12";
      MOTD = "bandit-lab";
      OPS = "fancy8869";
      # Administer through the local console without exposing RCON.
      CREATE_CONSOLE_IN_PIPE = "true";
      ENABLE_RCON = "false";
    };
    ports = ["25565:25565"];
    volumes = ["/srv/containers/minecraft/data:/data"];
    extraOptions = [
      "--memory=12g"
      "--cpus=4"
    ];
  };

  # Java Edition is TCP-only; UDP 25565 stays closed.
  networking.firewall.allowedTCPPorts = [25565];
}

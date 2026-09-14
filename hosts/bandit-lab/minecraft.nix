{config, ...}: {
  # Pre-create the data dir like every other stateful service instead of
  # letting Docker auto-create it root-owned on first start.
  systemd.tmpfiles.rules = [
    "d /srv/containers/minecraft/data 0750 root root -"
  ];

  # Minecraft Java server (Paper) for ~4 players. Hard-capped at 4 CPU cores
  # and 12 GiB so it can never starve Traefik/PostgreSQL/Wazuh & co. — the lab
  # (i9-14900HX, 62 GiB) barely notices it. Not proxied through Traefik:
  # Minecraft is a raw TCP protocol, so port 25565 is published directly.
  virtualisation.oci-containers.containers.minecraft = {
    image = "itzg/minecraft-server@sha256:50bdc4b0746c48456d8e737a017786a94c02295b14a8f0f4cb02592a0388cc09"; # java21
    environment = {
      EULA = "TRUE";
      # Paper over vanilla: same gameplay, much better tick performance.
      TYPE = "PAPER";
      TZ = config.time.timeZone;
      # 8 GiB heap (Xms = Xmx) + Aikar GC flags = no GC stutter; container
      # cap below leaves headroom for off-heap/metaspace.
      MEMORY = "8G";
      USE_AIKAR_FLAGS = "true";
      MAX_PLAYERS = "4";
      MOTD = "bandit-lab";
      # RCON adds an unauthenticated-by-default admin socket; not needed.
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

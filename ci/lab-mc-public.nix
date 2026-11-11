# bandit-lab public Minecraft container, phase 1 (bandit-craft docs/specs/2026-11-10-public-anarchy-world.md):
# the box (pinned user namespace, caps, veth rules, own tailnet node) and what runs inside it (one Velocity,
# one Paper: exact plugin list, no operators, no RCON, premium accounts only, own forwarding secret, game
# port on the container's tailscale0 only). Evaluation-time assertions only; velocity.toml and ops.json are
# read from the store, as lab-minecraft reads the private velocity.toml. Nothing is started or contacted.
{
  pkgs,
  lib,
  lab,
  craft, # the bandit-craft input, where the plugin pins live
}: let
  c = lab.containers.mc-public;
  inner = c.config;
  svc = lab.systemd.services."container@mc-public".serviceConfig;
  prepare = lab.systemd.services.mc-public-prepare;
  fw = lab.networking.firewall;
  fwLines = [
    "iptables -w -I nixos-fw 1 -i ve-mc-public -j nixos-fw-refuse"
    "iptables -w -I DOCKER-USER 1 -i ve-mc-public -d 192.168.0.0/24 -j DROP"
    "iptables -w -I DOCKER-USER 1 -i ve-mc-public -d 10.250.77.0/29 -j DROP"
    "iptables -w -I DOCKER-USER 1 -i ve-mc-public ! -o enp44s0 -j DROP"
    "iptables -w -I DOCKER-USER 1 -o ve-mc-public -m conntrack --ctstate NEW -j DROP"
  ];
  stopLines = [
    "iptables -w -D nixos-fw -i ve-mc-public -j nixos-fw-refuse || true"
    "iptables -w -D DOCKER-USER -i ve-mc-public -d 192.168.0.0/24 -j DROP || true"
    "iptables -w -D DOCKER-USER -i ve-mc-public -d 10.250.77.0/29 -j DROP || true"
    "iptables -w -D DOCKER-USER -i ve-mc-public ! -o enp44s0 -j DROP || true"
    "iptables -w -D DOCKER-USER -o ve-mc-public -m conntrack --ctstate NEW -j DROP || true"
  ];
  # networking.nat writes two lines of its own for an internal interface (the mark for masquerading and the
  # forward accept towards the uplink only); every other mention must be one of fwLines.
  natLines = ["-i 've-mc-public' -j MARK --set-mark 1" "-i 've-mc-public' -o enp44s0 -j ACCEPT"];
  vethLines = lib.filter (l: lib.hasInfix "ve-mc-public" l && !(lib.elem (lib.trim l) natLines)) (lib.splitString "\n" fw.extraCommands);

  # Inside the container.
  innerFw = inner.networking.firewall;
  innerUnits = inner.systemd.services;
  mc = inner.services.minecraft-servers;
  inherit (mc.servers) paper velocity;
  props = paper.serverProperties;
  velToml = builtins.readFile velocity.files."velocity.toml";
  secretEnv = "/run/minecraft-public-secret/forwarding.env";
  servers = ["minecraft-server-paper.service" "minecraft-server-velocity.service"];
  plugins = import "${craft}/hosts/bandit-lab/services/minecraft/plugins.nix" {inherit pkgs;};

  # The private stack on the host, which must not notice any of this.
  private = lab.services.minecraft-servers;
in
  # The box.
  assert lib.assertMsg (c.privateUsers == 589824 && c.privateUsers != lab.containers.jerry.privateUsers && lib.elem "--private-users-ownership=chown" c.extraFlags) "mc-public must use its own pinned user namespace base 589824 with chown ownership";
  assert lib.assertMsg (!inner.nix.enable) "the host nix daemon must not be usable from the container";
  assert lib.assertMsg (c.privateNetwork && c.enableTun && c.additionalCapabilities == []) "mc-public needs a private network and /dev/net/tun, and no further capability";
  assert lib.assertMsg (c.hostAddress == "10.251.1.1" && c.localAddress == "10.251.1.2") "mc-public veth addresses must be 10.251.1.1/10.251.1.2";
  assert lib.assertMsg (lib.attrNames c.bindMounts == [(toString mc.dataDir)] && c.bindMounts.${toString mc.dataDir}.hostPath == "/srv/mc-public/data") "mc-public mounts only its own world directory (no host secret, no path of the private world), at the servers' data directory";
  assert lib.assertMsg (svc.CPUQuota == "300%" && svc.MemoryMax == "10G" && svc.MemorySwapMax == "0" && svc.TasksMax == 2048 && svc.IOWeight == 50) "container@mc-public must carry the design's caps: 3 CPUs, 10G, no swap, a task limit and a low IO weight";
  assert lib.assertMsg (lib.hasInfix "-Xms6G -Xmx6G" paper.jvmOpts && lib.hasInfix "-Xmx512M" velocity.jvmOpts) "heaps (6G Paper, 512M Velocity) must fit the 10G cap";
  # The veth: refused by the host, forwarded to the uplink only, nothing forwarded in.
  assert lib.assertMsg (lib.elem "ve-mc-public" lab.networking.nat.internalInterfaces && lab.networking.nat.externalInterface == "enp44s0") "NAT must serve ve-mc-public through the uplink";
  assert lib.assertMsg (lib.all (l: lib.hasInfix l fw.extraCommands) fwLines) "firewall must refuse ve-mc-public on the host, drop its forwards to the LAN, the mcbots bridge and everything but the uplink, and forward nothing new into it";
  assert lib.assertMsg (lib.all (l: lib.elem l fwLines) vethLines) "no other firewall rule may mention ve-mc-public (an accept would open the host to the box): ${toString vethLines}";
  assert lib.assertMsg (lib.all (l: lib.hasInfix l fw.extraStopCommands) stopLines) "firewall stop commands must mirror every mc-public rule";
  assert lib.assertMsg (!(fw.interfaces ? "ve-mc-public")) "the host opens no port for ve-mc-public";
  assert lib.assertMsg (inner.networking.nameservers == ["9.9.9.9" "1.1.1.1"]) "mc-public must use fixed nameservers, not the host resolv.conf";
  # Own tailnet node; the game port on its tailscale0 only.
  assert lib.assertMsg (inner.services.tailscale.enable && lib.elem "--advertise-tags=tag:mc-public" inner.services.tailscale.extraUpFlags && lib.elem "--ssh=false" inner.services.tailscale.extraUpFlags && !inner.services.openssh.enable) "mc-public is its own tailnet node tagged tag:mc-public, without Tailscale SSH or sshd";
  assert lib.assertMsg (inner.systemd.services.tailscaled-autoconnect.serviceConfig.TimeoutStartSec == "30s") "container autoconnect must time out so the container reports READY without a tailnet login";
  assert lib.assertMsg (lib.hasInfix lab.sops.secrets."mc-public-tailscale-authkey".path prepare.script && lib.elem "container@mc-public.service" prepare.requiredBy && lib.elem "container@mc-public.service" prepare.before) "the tailnet auth key is placed from sops before the container starts";
  assert lib.assertMsg (innerFw.enable && innerFw.trustedInterfaces == ["lo"] && innerFw.allowedTCPPorts == [] && innerFw.allowedUDPPorts == [] && innerFw.allowedTCPPortRanges == [] && innerFw.allowedUDPPortRanges == []) "the container's firewall is on, trusts only lo and opens nothing globally";
  assert lib.assertMsg (lib.attrNames innerFw.interfaces == ["tailscale0"] && innerFw.interfaces.tailscale0.allowedTCPPorts == [25565] && innerFw.interfaces.tailscale0.allowedUDPPorts == []) "the game port (25565/tcp) is open on the container's tailscale0 only, and nothing else is";
  assert lib.assertMsg (!paper.openFirewall && !velocity.openFirewall && !mc.openFirewall) "nix-minecraft must not open any firewall port by itself";
  # One Velocity, one Paper.
  assert lib.assertMsg (lib.attrNames mc.servers == ["paper" "velocity"] && paper.enable && velocity.enable) "the container runs exactly one Paper and one Velocity";
  assert lib.assertMsg (lib.hasInfix "online-mode = true" velToml && !(lib.hasInfix "online-mode = false" velToml) && lib.hasInfix ''player-info-forwarding-mode = "modern"'' velToml) "the public Velocity is premium-only (online-mode = true) with modern forwarding";
  assert lib.assertMsg (velocity.symlinks == {} && velocity.environment == {}) "the public Velocity loads no plugin (no VeloAuth, no BotGate): nothing may flip a login offline";
  assert lib.assertMsg (lib.hasInfix ''bind = "0.0.0.0:25565"'' velToml && lib.hasInfix ''main = "127.0.0.1:${toString props.server-port}"'' velToml && lib.hasInfix ''try = ["main"]'' velToml && lib.hasInfix "haproxy-protocol = true" velToml) "Velocity listens on 25565, sends everyone to the loopback Paper and takes connections from the relay only (PROXY v2, phase 2)";
  assert lib.assertMsg (props.server-ip == "127.0.0.1" && props.server-port != 25565 && !props.online-mode) "Paper listens on loopback only, behind Velocity";
  assert lib.assertMsg (!props.enable-rcon && !props.enable-query && !(props ? "rcon.port") && !(props ? "rcon.password")) "the public Paper has no RCON and no query port";
  assert lib.assertMsg (paper.operators == {} && builtins.readFile paper.files."ops.json" == "[]\n") "the public Paper has no operators, and an empty ops.json is put back on every start";
  assert lib.assertMsg (lib.attrNames paper.symlinks == lib.sort lib.lessThan (map (p: "plugins/${p.file}") [plugins.chunky plugins.smoderation])) "the public Paper loads exactly Chunky and SModeration: ${toString (lib.attrNames paper.symlinks)}";
  assert lib.assertMsg (props.white-list && props.enforce-whitelist) "phase 1: the whitelist is on and enforced";
  assert lib.assertMsg (props.enforce-secure-profile && props.allow-flight && props.max-players == 20 && props.view-distance == 6 && props.simulation-distance == 4 && props.max-world-size == 5000) "the design's server.properties: secure profiles, flight allowed, 20 slots, view 6, simulation 4, border radius 5,000";
  assert lib.assertMsg (paper.managementSystem.systemd-socket.enable && !paper.managementSystem.tmux.enable) "Paper's console is the systemd socket (root in the container), the only way to whitelist, mute or ban";
  # Own forwarding secret, generated inside; never the private environment file, never a sops value.
  assert lib.assertMsg (toString mc.environmentFile == secretEnv && secretEnv != toString private.environmentFile && !(lib.hasInfix "minecraft-servers.env" secretEnv)) "the public pair reads its own environment file, never the private minecraft-servers.env";
  assert lib.assertMsg (lib.all (u: innerUnits.${lib.removeSuffix ".service" u}.serviceConfig.EnvironmentFile == secretEnv) servers) "both public servers read only the generated environment file";
  assert lib.assertMsg (lib.hasInfix secretEnv innerUnits.minecraft-public-secret.script && lib.all (u: lib.elem u innerUnits.minecraft-public-secret.requiredBy && lib.elem u innerUnits.minecraft-public-secret.before) servers) "the forwarding secret is generated inside the container before either server starts";
  assert lib.assertMsg (!(inner ? sops) && !(lib.hasInfix "VELOCITY_FORWARDING_SECRET" (builtins.toJSON [paper.environment velocity.environment])) && lib.hasInfix "strenv(VELOCITY_FORWARDING_SECRET)" paper.extraStartPre) "no sops secret enters the container and the forwarding secret reaches the servers only through the environment file";
  # The private world is untouched by the public plugin pin.
  assert lib.assertMsg (!(lib.any (lib.hasInfix plugins.chunky.file) (lib.attrNames private.servers.paper.symlinks))) "Chunky is pinned for the public world only and must stay off the private Paper";
    pkgs.writeText "lab-mc-public" "ok\n"

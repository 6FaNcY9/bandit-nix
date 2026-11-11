# The public Minecraft world's box, phase 1 (whitelisted testers over the tailnet): an nspawn container
# with its own pinned user namespace on a private veth, built like jerry-box. Inside run one Velocity and
# one Paper from the bandit-craft input (its hosts/bandit-lab/services/minecraft-public). Nothing of the
# private stack is shared: the only bind mount is its own world directory, the only sops secret its
# tailnet auth key, and the game port is open on the container's own tailscale0 (tag:mc-public) only.
# The host refuses everything that arrives from the veth; forwarding is allowed to the uplink only, never
# to the LAN, the mcbots bridge, Docker's or Podman's networks or another container.
# Design: bandit-craft docs/specs/2026-11-10-public-anarchy-world.md. Runbook: bandit-craft
# docs/runbooks/minecraft/PUBLIC.md. Contract: ci/lab-mc-public.nix.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  veth = "ve-mc-public";
  uplink = "enp44s0";
  # The 65536 ids after jerry's (524288-589823).
  uidBase = 589824;
  owner = toString uidBase;
  authkey = "/var/lib/nixos-containers/mc-public/var/lib/tailscale/authkey";
  # The world of record lives outside the container's rootfs, so removing the container never removes it.
  worldDir = "/srv/mc-public/data";
  # Each rule goes to the top of its chain. nixos-fw: nothing from the veth reaches a host address, whatever
  # another module accepts further down (the mcbots bridge rule admits the private RCON forwarders on
  # 10.250.77.1). The forward drops live in Docker's DOCKER-USER chain because Docker reorders FORWARD, as
  # for jerry-box. Unlike jerry-box there is no accept for the host's tailscaled: this box talks to its
  # tailnet peers through the uplink and never to the host. The last rule is the other direction: nothing
  # is forwarded into the box unless the box opened the connection, so the game port does not depend on
  # the container's own firewall alone (replies to its NATed traffic are not NEW and pass).
  rules = [
    "-I nixos-fw 1 -i ${veth} -j nixos-fw-refuse"
    "-I DOCKER-USER 1 -i ${veth} -d 192.168.0.0/24 -j DROP" # the LAN
    "-I DOCKER-USER 1 -i ${veth} -d 10.250.77.0/29 -j DROP" # the mcbots bridge (bandit-craft minecraft/default.nix mcbotsSubnet)
    "-I DOCKER-USER 1 -i ${veth} ! -o ${uplink} -j DROP" # everything else that is not the uplink
    "-I DOCKER-USER 1 -o ${veth} -m conntrack --ctstate NEW -j DROP"
  ];
  delete = r: "iptables -w ${builtins.replaceStrings ["-I nixos-fw 1" "-I DOCKER-USER 1"] ["-D nixos-fw" "-D DOCKER-USER"] r} || true";
in {
  sops.secrets."mc-public-tailscale-authkey" = {};

  containers.mc-public = {
    autoStart = true;
    privateUsers = uidBase;
    # chown (not auto/map), as for jerry-box: numeric privateUsers implies ownership=off, and an idmapped root would hide the authkey.
    extraFlags = ["--private-users-ownership=chown"];
    privateNetwork = true;
    enableTun = true;
    hostAddress = "10.251.1.1";
    localAddress = "10.251.1.2";
    # services.minecraft-servers.dataDir inside (bandit-craft minecraft-public); the check keeps the two in step.
    bindMounts."/srv/minecraft" = {
      hostPath = worldDir;
      isReadOnly = false;
    };
    # UNVERIFIED: nix-minecraft's units (PrivateUsers and the rest of their hardening) and the NixOS firewall have
    # not been run inside a user-namespaced container here; the runbook's checks 1, 3 and 5 are the proof.
    config = {
      imports = [
        inputs.nix-minecraft.nixosModules.minecraft-servers
        inputs.bandit-craft.nixosModules.mc-public
      ];
      # The container evaluates its own package set: the overlay has to be given again (modules/server/minecraft.nix).
      nixpkgs.overlays = [inputs.nix-minecraft.overlay];
      networking = {
        useHostResolvConf = false;
        nameservers = ["9.9.9.9" "1.1.1.1"];
        # Velocity binds every address; only the tailnet interface admits the game port. Paper is loopback.
        firewall = {
          enable = true;
          interfaces.tailscale0.allowedTCPPorts = [25565];
        };
      };
      # No systemd-resolved, and a static /etc/resolv.conf written by hand. With resolved, the container's
      # resolv.conf was the stub (127.0.0.53) and the resolver found no working upstream (tailscale had taken
      # DNS over, the tailnet sets no servers), so api.playit.gg did not resolve. Disabling resolved alone
      # left the stale stub file in place (it is mutable, not a NixOS symlink); forcing the file is what makes
      # glibc query 9.9.9.9 directly. UDP:53 to it works from here (measured). No tailnet-name resolution.
      services.resolved.enable = lib.mkForce false;
      networking.resolvconf.enable = lib.mkForce false;
      environment.etc."resolv.conf" = lib.mkForce {
        text = ''
          nameserver 9.9.9.9
          nameserver 1.1.1.1
        '';
        mode = "0444";
      };
      services.tailscale = {
        enable = true;
        authKeyFile = "/var/lib/tailscale/authkey";
        # --accept-dns=false: the tailnet has no DNS servers set, so MagicDNS would take over the
        # container's systemd-resolved and leave public names unresolvable (api.playit.gg for the tunnel).
        # This box reaches its peers by address, never by tailnet name, so it loses nothing.
        extraUpFlags = ["--ssh=false" "--advertise-tags=tag:mc-public" "--accept-dns=false"];
      };
      # As for jerry-box: fail fast and retry, or a missing tailnet login holds the boot until the host kills the container.
      systemd.services.tailscaled-autoconnect.serviceConfig = {
        TimeoutStartSec = "30s";
        Restart = "on-failure";
        RestartSec = "30s";
      };
      nix.enable = false; # the host nix daemon is not exposed to the guest
      system.stateVersion = "25.11";
    };
  };

  networking = {
    nat = {
      enable = true;
      internalInterfaces = [veth];
      externalInterface = uplink;
    };
    firewall.extraCommands = lib.concatStringsSep "\n" (["iptables -w -N DOCKER-USER 2>/dev/null || true"] ++ map (r: "iptables -w ${r}") rules);
    firewall.extraStopCommands = lib.concatMapStringsSep "\n" delete rules;
  };

  systemd.services = {
    # The design's caps, on the whole container: 6G heap for Paper, 512M for Velocity, the rest is JVM
    # overhead and tailscaled. They keep a lag machine away from the private world and Vaultwarden.
    "container@mc-public".serviceConfig = {
      CPUQuota = "300%";
      MemoryMax = "10G";
      MemorySwapMax = "0";
      TasksMax = 2048;
      IOWeight = 50; # default 100
    };
    # Before the container: the world directory (created once, owned by the container's root; an existing
    # one, for example a quota subvolume from the runbook, is left alone) and the tailnet auth key, which
    # enters the rootfs owned by the mapped root.
    mc-public-prepare = {
      description = "Create the public Minecraft world directory and place the container's tailnet auth key";
      requiredBy = ["container@mc-public.service"];
      before = ["container@mc-public.service"];
      path = [pkgs.coreutils];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        [ -d ${worldDir} ] || install -d -m 0755 -o ${owner} -g ${owner} ${worldDir}
        install -D -m 0400 -o ${owner} -g ${owner} ${config.sops.secrets."mc-public-tailscale-authkey".path} ${authkey}
      '';
    };
  };
}

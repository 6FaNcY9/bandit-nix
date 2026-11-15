# Guest boxes for friends (jerry, martin): one nspawn container each, with its own pinned user namespace,
# on a private veth, NATed out but refused by the host and walled off from the LAN, the bots', Docker's
# and each other's networks. Both run in guests.slice, a shared pool below the host's own services.
# Spec: docs/superpowers/specs/2026-11-01-jerry-guest-box-design.md. Runbook: docs/runbooks/guest-box.md.
# The inside of each container (packages, tools, state in /data) belongs to its guest.
{
  config,
  lib,
  ...
}: let
  guests = import ./guests.nix;
  # Host side: v4 refuses everything from ve-<name> after its hostAccept; v6 refuses everything at the top
  # (the guests have no IPv6, and an accepted router advertisement would rewrite the host's routes).
  # Forward side, in the mangle table that neither Docker nor tailscaled touches, so it holds while Docker
  # is down and whatever order the filter FORWARD chain ends up in: ve-<name> may only leave via enp44s0,
  # and never to a private, link-local or CGNAT range (so never to the LAN or the other guest either).
  private = ["10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16" "169.254.0.0/16" "100.64.0.0/10"];
  rules = name: g:
    map (r: "iptables -w ${r}") g.hostAccept
    ++ [
      "iptables -w -A nixos-fw -i ve-${name} -j nixos-fw-refuse"
      "ip6tables -w -I nixos-fw 1 -i ve-${name} -j nixos-fw-refuse"
    ]
    ++ map (d: "iptables -w -t mangle -A FORWARD -i ve-${name} -d ${d} -j DROP") private
    ++ ["iptables -w -t mangle -A FORWARD -i ve-${name} ! -o enp44s0 -j DROP"];
  allRules = lib.concatLists (lib.mapAttrsToList rules guests);
  delete = r: "${builtins.replaceStrings ["-A " "-I nixos-fw 1"] ["-D " "-D nixos-fw"] r} || true";
  authkey = name: "/var/lib/nixos-containers/${name}/var/lib/tailscale/authkey";
  owner = g: toString g.uid;

  container = name: g: {
    autoStart = true;
    privateUsers = g.uid;
    # chown (not auto/map): numeric privateUsers implies ownership=off, so the rootfs dirs would stay host-uid-0; an idmapped root would hide the authkey owned by the mapped root.
    extraFlags = ["--private-users-ownership=chown"];
    privateNetwork = true;
    enableTun = true;
    hostAddress = "${g.net}.1";
    localAddress = "${g.net}.2";
    bindMounts."/data" = {
      hostPath = "/srv/${name}/box";
      isReadOnly = false;
    };
    config = {pkgs, ...}: {
      networking.useHostResolvConf = false;
      networking.nameservers = ["9.9.9.9" "1.1.1.1"];
      services.openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = false;
          PermitRootLogin = "prohibit-password";
        };
      };
      users.users.root.openssh.authorizedKeys.keys = lib.optional (g.key != "") g.key;
      services.tailscale = {
        enable = true;
        authKeyFile = "/var/lib/tailscale/authkey";
        extraUpFlags = ["--ssh=false" "--advertise-tags=tag:${name}-box"];
      };
      # autoconnect loops until the node is Running and holds the boot; the host kills the
      # container after 60 s without READY (seen 2026-11-01). Fail fast and keep retrying instead.
      systemd.services.tailscaled-autoconnect.serviceConfig = {
        TimeoutStartSec = "30s";
        Restart = "on-failure";
        RestartSec = "30s";
      };
      environment.systemPackages = with pkgs; [git curl python3 uv htop];
      # No nix inside. The host's start script still binds /nix/store and the nix daemon socket in read-only;
      # the daemon refuses the guest's mapped uids (host nix.settings.allowed-users = ["vino"], ci/lab-guests.nix).
      nix.enable = false;
      system.stateVersion = "25.11";
    };
  };

  services = name: g: {
    "container@${name}".serviceConfig = {
      Slice = lib.mkForce "guests.slice"; # out of machine.slice (the container module default) into the shared pool
      CPUQuota = "100%";
      MemoryMax = g.memory;
      MemorySwapMax = "0";
      TasksMax = 512;
    };
    # The tailnet auth key enters the container rootfs owned by its mapped root.
    "${name}-authkey" = {
      description = "Place ${lib.toSentenceCase name}'s tailnet auth key in the container rootfs";
      requiredBy = ["container@${name}.service"];
      before = ["container@${name}.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "/run/current-system/sw/bin/install -D -m 0400 -o ${owner g} -g ${owner g} ${config.sops.secrets."${name}-tailscale-authkey".path} ${authkey name}";
      };
    };
  };
in {
  imports = [./watch.nix];

  sops.secrets = lib.mapAttrs' (name: _: lib.nameValuePair "${name}-tailscale-authkey" {}) guests;

  containers = lib.mapAttrs container guests;

  networking = {
    nat = {
      enable = true;
      internalInterfaces = map (name: "ve-${name}") (lib.attrNames guests);
      externalInterface = "enp44s0";
    };
    firewall.extraCommands = lib.concatStringsSep "\n" allRules;
    firewall.extraStopCommands = lib.concatMapStringsSep "\n" delete allRules;
  };

  # The shared pool: under load the guests compete with each other, and the low weights let the host's
  # own slices (system, user, machine) win. Each guest keeps its own caps inside it.
  systemd.slices.guests.sliceConfig = {
    CPUQuota = "200%";
    MemoryMax = "6G";
    CPUWeight = 20;
    IOWeight = 20;
  };

  systemd.services = lib.mkMerge (lib.mapAttrsToList services guests);
}

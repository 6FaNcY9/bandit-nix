# Guest boxes for friends (jerry, martin): one nspawn container each, with its own pinned user namespace,
# on a private veth, NATed out but refused by the host and walled off from the LAN, the bots', Docker's
# and each other's networks. Both run in guests.slice, a shared pool below the host's own services.
# Spec: docs/superpowers/specs/2026-11-01-jerry-guest-box-design.md. Runbook: docs/runbooks/guest-box.md.
# The inside of each container (packages, tools, state in /data) belongs to its guest.
{
  config,
  lib,
  pkgs,
  ...
}: let
  guests = import ./guests.nix;
  debian = g: (g.os or "nixos") == "debian";
  unit = name: g:
    if debian g
    then "systemd-nspawn@${name}"
    else "container@${name}";
  marker = name: "/var/lib/machines/${name}/etc/guest-seeded";
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
  authkey = name: g: "/var/lib/${
    if debian g
    then "machines"
    else "nixos-containers"
  }/${name}/var/lib/tailscale/authkey";
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

  # Debian guests: the .nspawn file of the stock systemd-nspawn@<name> template (--settings=override, so these win).
  nspawn = name: g: {
    execConfig = {
      PrivateUsers = "${owner g}:65536";
      ResolvConf = "off"; # the guest's own resolv.conf (seeded) stays
      # No NotifyReady: nspawn reports READY at init start, so a slow boot cannot get the box killed (2026-11-01).
    };
    filesConfig = {
      # chown, as for the NixOS boxes: the rootfs belongs to the mapped ids, so the authkey stays readable inside.
      PrivateUsersOwnership = "chown";
      Bind = ["/srv/${name}/box:/data" "/dev/net/tun"];
    };
    networkConfig.VirtualEthernet = true;
  };

  # What guest-debian-init copies into the rootfs; the inside is the guest's after that.
  seed = name: g:
    lib.mapAttrs' (f: text: lib.nameValuePair "guest-seed/${name}/${f}" {inherit text;}) {
      "sshd_config.d/10-guest.conf" = ''
        PasswordAuthentication no
        KbdInteractiveAuthentication no
        PermitRootLogin prohibit-password
      '';
      authorized_keys = "${g.key}\n";
      "10-host0.network" = ''
        [Match]
        Name=host0

        [Network]
        Address=${g.net}.2/32

        [Route]
        Gateway=${g.net}.1
        GatewayOnLink=yes
      '';
      "resolv.conf" = ''
        nameserver 9.9.9.9
        nameserver 1.1.1.1
      '';
      # Fail fast and keep retrying instead of holding the boot until the node is Running (seen 2026-11-01).
      "tailscale-up.service" = ''
        [Unit]
        Description=Join the tailnet as tag:${name}-box
        Wants=network-online.target tailscaled.service
        After=network-online.target tailscaled.service

        [Service]
        Type=oneshot
        RemainAfterExit=yes
        ExecStart=/usr/bin/tailscale up --auth-key=file:/var/lib/tailscale/authkey --ssh=false --advertise-tags=tag:${name}-box
        TimeoutStartSec=30s
        Restart=on-failure
        RestartSec=30s

        [Install]
        WantedBy=multi-user.target
      '';
    };

  services = name: g:
    lib.mkMerge [
      {
        "${unit name g}".serviceConfig = {
          Slice = lib.mkForce "guests.slice"; # out of machine.slice (the container module and nspawn template default) into the shared pool
          CPUQuota = "100%";
          MemoryMax = g.memory;
          MemorySwapMax = "0";
          TasksMax = 512;
        };
        # The tailnet auth key enters the container rootfs owned by its mapped root.
        "${name}-authkey" = {
          description = "Place ${lib.toSentenceCase name}'s tailnet auth key in the container rootfs";
          requiredBy = ["${unit name g}.service"];
          before = ["${unit name g}.service"];
          unitConfig = lib.optionalAttrs (debian g) {ConditionPathExists = marker name;};
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "/run/current-system/sw/bin/install -D -m 0400 -o ${owner g} -g ${owner g} ${config.sops.secrets."${name}-tailscale-authkey".path} ${authkey name g}";
          };
        };
      }
      (lib.mkIf (debian g) {
        "systemd-nspawn@${name}" = {
          overrideStrategy = "asDropin";
          wantedBy = ["multi-user.target"]; # machines.target is not used on the lab
          restartIfChanged = false; # as container@: a deploy must not restart a guest's live box
          unitConfig.ConditionPathExists = marker name; # waits for guest-debian-init
          serviceConfig = {
            # The empty entry resets the template's list (fuse, loop, device-mapper): only tun and ptys stay.
            DeviceAllow = ["" "/dev/net/tun rwm" "char-pts rw"];
            DevicePolicy = "closed";
            # The host does not run networkd: address the host end like the nixos-container start script does.
            ExecStartPost = [
              "${pkgs.iproute2}/bin/ip link set ve-${name} up"
              "${pkgs.iproute2}/bin/ip addr replace ${g.net}.1 dev ve-${name}"
              "${pkgs.iproute2}/bin/ip route replace ${g.net}.2 dev ve-${name}"
            ];
          };
        };
      })
    ];
in {
  imports = [./watch.nix];

  sops.secrets = lib.mapAttrs' (name: _: lib.nameValuePair "${name}-tailscale-authkey" {}) guests;

  containers = lib.mapAttrs container (lib.filterAttrs (_: g: !debian g) guests);
  environment.etc = lib.mkMerge (lib.mapAttrsToList seed (lib.filterAttrs (_: debian) guests));
  environment.systemPackages = lib.optional (lib.any debian (lib.attrValues guests)) (pkgs.callPackage ./debian-init.nix {inherit guests;});

  networking = {
    nat = {
      enable = true;
      internalInterfaces = map (name: "ve-${name}") (lib.attrNames guests);
      externalInterface = "enp44s0";
    };
    firewall.extraCommands = lib.concatStringsSep "\n" allRules;
    firewall.extraStopCommands = lib.concatMapStringsSep "\n" delete allRules;
  };

  systemd = {
    nspawn = lib.mapAttrs nspawn (lib.filterAttrs (_: debian) guests);

    # The shared pool: under load the guests compete with each other, and the low weights let the host's
    # own slices (system, user, machine) win. Each guest keeps its own caps inside it.
    slices.guests.sliceConfig = {
      CPUQuota = "200%";
      MemoryMax = "6G";
      CPUWeight = 20;
      IOWeight = 20;
    };

    services = lib.mkMerge (lib.mapAttrsToList services guests);
  };
}

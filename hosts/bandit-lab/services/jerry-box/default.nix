# Jerry's guest box: an nspawn container with its own pinned user namespace, on a private
# veth, NATed out but refused by the host and walled off from the LAN, the bots' and
# Docker's networks. Spec: docs/superpowers/specs/2026-11-01-jerry-guest-box-design.md.
# The inside of the container (packages, tools, state in /data) is Jerry's.
{
  config,
  lib,
  ...
}: let
  jerryKey = ""; # TODO owner: paste Jerry's SSH public key
  authkey = "/var/lib/nixos-containers/jerry/var/lib/tailscale/authkey";
  # Forward drops live in DOCKER-USER: Docker evaluates it first and leaves it to administrators.
  rules = [
    "-A nixos-fw -i ve-jerry -j nixos-fw-refuse"
    "-I DOCKER-USER 1 -i ve-jerry -d 192.168.0.0/24 -j DROP"
    "-I DOCKER-USER 1 -i ve-jerry -d 10.250.77.0/29 -j DROP"
    "-I DOCKER-USER 1 -i ve-jerry -d 172.16.0.0/12 -j DROP"
  ];
  delete = r: "iptables -w ${builtins.replaceStrings ["-A " "-I DOCKER-USER 1"] ["-D " "-D DOCKER-USER"] r} || true";
in {
  imports = [./watch.nix];

  sops.secrets."jerry-tailscale-authkey" = {};

  containers.jerry = {
    autoStart = true;
    privateUsers = 524288;
    privateNetwork = true;
    enableTun = true;
    hostAddress = "10.251.0.1";
    localAddress = "10.251.0.2";
    bindMounts."/data" = {
      hostPath = "/srv/jerry/box";
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
      users.users.root.openssh.authorizedKeys.keys = lib.optional (jerryKey != "") jerryKey;
      services.tailscale = {
        enable = true;
        authKeyFile = "/var/lib/tailscale/authkey";
        extraUpFlags = ["--ssh=false" "--advertise-tags=tag:jerry-box"];
      };
      environment.systemPackages = with pkgs; [git curl python3 uv htop];
      nix.settings.experimental-features = ["nix-command" "flakes"];
      system.stateVersion = "25.11";
    };
  };

  networking = {
    nat = {
      enable = true;
      internalInterfaces = ["ve-jerry"];
      externalInterface = "enp44s0";
    };
    firewall.extraCommands = lib.concatStringsSep "\n" (["iptables -w -N DOCKER-USER 2>/dev/null || true"] ++ map (r: "iptables -w ${r}") rules);
    firewall.extraStopCommands = lib.concatMapStringsSep "\n" delete rules;
  };

  systemd.services = {
    "container@jerry".serviceConfig = {
      CPUQuota = "100%";
      MemoryMax = "2G";
      MemorySwapMax = "0";
      TasksMax = 512;
    };
    # The tailnet auth key enters the container rootfs owned by its mapped root.
    jerry-authkey = {
      description = "Place Jerry's tailnet auth key in the container rootfs";
      requiredBy = ["container@jerry.service"];
      before = ["container@jerry.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "/run/current-system/sw/bin/install -D -m 0400 -o 524288 -g 524288 ${config.sops.secrets."jerry-tailscale-authkey".path} ${authkey}";
      };
    };
  };
}

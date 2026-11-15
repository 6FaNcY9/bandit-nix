# bandit-lab guest containers (jerry, martin): pinned user namespaces, limits, the shared guests.slice,
# NAT and firewall isolation. Evaluation-time assertions only.
{
  pkgs,
  lib,
  lab,
}: let
  # Expected values written out here on purpose, so a change in guests.nix must be repeated in the check.
  expect = {
    jerry = {
      uid = 524288;
      net = "10.251.0";
      memory = "2G";
      hostAccept = ["iptables -w -A nixos-fw -i ve-jerry -p udp --dport 41641 -j nixos-fw-accept"];
    };
    martin = {
      uid = 655360;
      net = "10.251.2";
      memory = "4G";
      hostAccept = [];
    };
  };
  fw = lab.networking.firewall.extraCommands;
  stop = lab.networking.firewall.extraStopCommands;
  slice = lab.systemd.slices.guests.sliceConfig;
  bases = [lab.containers.jerry.privateUsers lab.containers.martin.privateUsers lab.containers.mc-public.privateUsers];

  check = name: e: let
    c = lab.containers.${name};
    cc = c.config;
    svc = lab.systemd.services."container@${name}".serviceConfig;
    v = "ve-${name}";
    fwLines =
      e.hostAccept
      ++ [
        "iptables -w -A nixos-fw -i ${v} -j nixos-fw-refuse"
        "iptables -w -I DOCKER-USER 1 -i ${v} -d 192.168.0.0/24 -j DROP"
        "iptables -w -I DOCKER-USER 1 -i ${v} ! -o enp44s0 -j DROP" # also drops guest-to-guest forwards
      ];
    stopLines = map (l: builtins.replaceStrings ["-A " "-I DOCKER-USER 1"] ["-D " "-D DOCKER-USER"] l + " || true") fwLines;
    keys = cc.users.users.root.openssh.authorizedKeys.keys;
    uidMax = toString (e.uid + 65535);
  in
    assert lib.assertMsg (c.privateUsers == e.uid) "${name} must use the pinned user namespace base ${toString e.uid}";
    assert lib.assertMsg (lib.elem "--private-users-ownership=chown" c.extraFlags) "${name} needs chown ownership: numeric privateUsers implies ownership=off";
    assert lib.assertMsg (cc.nix.enable == false) "the host nix daemon must not be usable from ${name}";
    assert lib.assertMsg (c.privateNetwork && c.enableTun) "${name} needs a private network and /dev/net/tun";
    assert lib.assertMsg (c.hostAddress == "${e.net}.1" && c.localAddress == "${e.net}.2") "${name} veth addresses must be ${e.net}.1/${e.net}.2";
    assert lib.assertMsg (lib.attrNames c.bindMounts == ["/data"] && c.bindMounts."/data".hostPath == "/srv/${name}/box") "${name} must bind only /data from /srv/${name}/box";
    assert lib.assertMsg (cc.services.openssh.settings.PasswordAuthentication == false && cc.services.openssh.settings.PermitRootLogin == "prohibit-password") "${name} ssh must be key-only";
    assert lib.assertMsg (lib.length keys <= 1 && lib.all (k: k != "") keys) "${name} root may carry at most its one guest key";
    assert lib.assertMsg (cc.services.tailscale.extraUpFlags == ["--ssh=false" "--advertise-tags=tag:${name}-box"]) "${name} must join the tailnet as tag:${name}-box without tailscale ssh";
    assert lib.assertMsg (cc.systemd.services.tailscaled-autoconnect.serviceConfig.TimeoutStartSec == "30s") "${name} autoconnect must time out so the container reports READY without a tailnet login";
    assert lib.assertMsg (lib.elem "container@${name}.service" lab.systemd.services."${name}-ssh-watch".bindsTo) "${name}-ssh-watch must be bound to the container";
    assert lib.assertMsg (lab.systemd.timers."${name}-report".timerConfig.OnCalendar == "hourly") "${name}-report must run hourly";
    assert lib.assertMsg (svc.Slice == "guests.slice") "container@${name} must run in guests.slice";
    assert lib.assertMsg (svc.CPUQuota == "100%" && svc.MemoryMax == e.memory && svc.MemorySwapMax == "0" && svc.TasksMax == 512) "container@${name} must carry CPU, memory (${e.memory}), swap and task limits";
    assert lib.assertMsg (lib.all (l: lib.hasInfix l fw) fwLines) "firewall must refuse ${v} on the host and drop its LAN/bots/docker/other-guest forwards";
    assert lib.assertMsg (e.hostAccept != [] || !(lib.hasInfix "-i ${v} -p" fw || lib.hasInfix "-i ${v} -j nixos-fw-accept" fw)) "${name} must not be accepted by any host port";
    assert lib.assertMsg (lib.all (l: lib.hasInfix l stop) stopLines) "firewall stop commands must mirror every ${name} rule";
    assert lib.assertMsg (cc.networking.nameservers == ["9.9.9.9" "1.1.1.1"]) "${name} must use fixed nameservers, not the host resolv.conf";
    assert lib.assertMsg (lib.elem "-a always,exit -F arch=b64 -S execve -F uid>=${toString e.uid} -F uid<=${uidMax} -k ${name}" lab.security.audit.rules) "audit rule for ${name}'s uid range missing"; true;
in
  assert lib.assertMsg (lib.all lib.id (lib.mapAttrsToList check expect)) "guest checks";
  assert lib.assertMsg (lib.length (lib.unique (map (b: b / 65536) bases)) == lib.length bases && lib.all (b: lib.mod b 65536 == 0) bases) "guest user namespaces must be distinct 65536-aligned blocks";
  assert lib.assertMsg (slice.CPUQuota == "200%" && slice.MemoryMax == "6G" && slice.CPUWeight == 20 && slice.IOWeight == 20) "guests.slice must pool 2 CPUs / 6G at low CPU and IO weight";
  assert lib.assertMsg (lib.sort lib.lessThan lab.networking.nat.internalInterfaces == ["ve-jerry" "ve-martin" "ve-mc-public"]) "NAT must serve ve-jerry, ve-martin and ve-mc-public (ci/lab-mc-public.nix) only";
    pkgs.writeText "lab-guests" "ok\n"

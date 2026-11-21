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
      os = "debian";
      net = "10.251.0";
      memory = "2G";
      hostAccept = ["iptables -w -A nixos-fw -i ve-jerry -p udp --dport 41641 -j nixos-fw-accept"];
    };
    martin = {
      uid = 655360;
      os = "nixos";
      net = "10.251.2";
      memory = "4G";
      hostAccept = [];
      hostname = "freunde";
      users = ["martin"];
    };
  };
  fw = lab.networking.firewall.extraCommands;
  stop = lab.networking.firewall.extraStopCommands;
  slice = lab.systemd.slices.guests.sliceConfig;
  # jerry is a Debian nspawn machine: its base is the first field of the .nspawn PrivateUsers=base:range.
  jerryBase = lib.toInt (lib.head (lib.splitString ":" lab.systemd.nspawn.jerry.execConfig.PrivateUsers));
  bases = [jerryBase lab.containers.martin.privateUsers lab.containers.mc-public.privateUsers];

  # Asserts on the NixOS container (containers.<name>).
  checkNixos = name: e: let
    c = lab.containers.${name};
    cc = c.config;
    keys = cc.users.users.root.openssh.authorizedKeys.keys;
  in
    assert lib.assertMsg (c.privateUsers == e.uid) "${name} must use the pinned user namespace base ${toString e.uid}";
    assert lib.assertMsg (lib.elem "--private-users-ownership=chown" c.extraFlags) "${name} needs chown ownership: numeric privateUsers implies ownership=off";
    assert lib.assertMsg (cc.nix.enable == false) "the host nix daemon must not be usable from ${name}";
    assert lib.assertMsg (c.privateNetwork && c.enableTun) "${name} needs a private network and /dev/net/tun";
    assert lib.assertMsg (c.hostAddress == "${e.net}.1" && c.localAddress == "${e.net}.2") "${name} veth addresses must be ${e.net}.1/${e.net}.2";
    assert lib.assertMsg (lib.attrNames c.bindMounts == ["/data"] && c.bindMounts."/data".hostPath == "/srv/${name}/box") "${name} must bind only /data from /srv/${name}/box";
    assert lib.assertMsg (cc.services.openssh.settings.PasswordAuthentication == false && cc.services.openssh.settings.PermitRootLogin == "prohibit-password") "${name} ssh must be key-only";
    assert lib.assertMsg (lib.length keys <= 1 && lib.all (k: k != "") keys) "${name} root may carry at most its one guest key";
    assert lib.assertMsg (e ? users -> keys == []) "shared box ${name}: no root key";
    assert lib.assertMsg (lib.all (u: let x = cc.users.users.${u}; in x.isNormalUser && x.extraGroups == [] && lib.length x.openssh.authorizedKeys.keys == 1) (e.users or [])) "${name} friends must be normal users without groups, one key each";
    assert lib.assertMsg (lib.sort lib.lessThan (lib.attrNames (lib.filterAttrs (_: x: x.isNormalUser) cc.users.users)) == lib.sort lib.lessThan (e.users or [])) "${name} must have exactly the listed friend accounts";
    assert lib.assertMsg (cc.services.tailscale.extraSetFlags == lib.optional (e ? hostname) "--hostname=${e.hostname or ""}") "${name} tailnet name must be ${e.hostname or "the default"}";
    assert lib.assertMsg (cc.services.tailscale.extraUpFlags == ["--ssh=false" "--advertise-tags=tag:${name}-box"]) "${name} must join the tailnet as tag:${name}-box without tailscale ssh";
    assert lib.assertMsg (cc.systemd.services.tailscaled-autoconnect.serviceConfig.TimeoutStartSec == "30s") "${name} autoconnect must time out so the container reports READY without a tailnet login";
    assert lib.assertMsg (cc.networking.nameservers == ["9.9.9.9" "1.1.1.1"]) "${name} must use fixed nameservers, not the host resolv.conf"; true;

  # Asserts on the Debian rootfs run by the stock systemd-nspawn@<name>: .nspawn file, unit drop-in, seed files.
  checkDebian = name: e: let
    n = lab.systemd.nspawn.${name};
    d = lab.systemd.services."systemd-nspawn@${name}";
    marker = "/var/lib/machines/${name}/etc/guest-seeded";
    unit = "systemd-nspawn@${name}.service";
    ak = lab.systemd.services."${name}-authkey";
    sw = lab.systemd.services."${name}-ssh-watch";
    seed = f: lab.environment.etc."guest-seed/${name}/${f}".text;
    has = f: l: lib.hasInfix l (seed f);
    post = lib.concatStringsSep "\n" (lib.toList d.serviceConfig.ExecStartPost);
  in
    assert lib.assertMsg (!(lab.containers ? ${name})) "${name} is a Debian guest and must not also be a NixOS container";
    assert lib.assertMsg (n.execConfig.PrivateUsers == "${toString e.uid}:65536" && n.filesConfig.PrivateUsersOwnership == "chown") "${name} must use the pinned user namespace base ${toString e.uid} with chown ownership";
    assert lib.assertMsg (n.execConfig.ResolvConf == "off" && !(n.execConfig ? NotifyReady)) "${name} keeps its own resolv.conf and reports READY at init start";
    assert lib.assertMsg (n.networkConfig.VirtualEthernet == true) "${name} needs a private veth";
    assert lib.assertMsg (lib.sort lib.lessThan n.filesConfig.Bind == ["/dev/net/tun" "/srv/${name}/box:/data"]) "${name} must bind only /data from /srv/${name}/box (and /dev/net/tun)";
    assert lib.assertMsg (d.overrideStrategy == "asDropin" && lib.elem "multi-user.target" d.wantedBy) "${unit} must be a drop-in on the stock template, started at boot";
    assert lib.assertMsg (d.restartIfChanged == false) "${unit} must not be restarted by a deploy (the box is live)";
    assert lib.assertMsg (d.unitConfig.ConditionPathExists == marker) "${unit} must wait for the seed marker ${marker}";
    assert lib.assertMsg (d.serviceConfig.DeviceAllow == ["" "/dev/net/tun rwm" "char-pts rw"] && d.serviceConfig.DevicePolicy == "closed") "${unit} may only reach /dev/net/tun and ptys";
    assert lib.assertMsg (lib.hasInfix "addr replace ${e.net}.1 dev ve-${name}" post && lib.hasInfix "route replace ${e.net}.2 dev ve-${name}" post) "${unit} must address the host side of ve-${name} as ${e.net}.1 with a route to ${e.net}.2";
    assert lib.assertMsg (ak.unitConfig.ConditionPathExists == marker && lib.elem unit ak.requiredBy && lib.elem unit ak.before) "${name}-authkey must run before ${unit}, once the rootfs is seeded";
    assert lib.assertMsg (lib.hasSuffix " /var/lib/machines/${name}/var/lib/tailscale/authkey" ak.serviceConfig.ExecStart) "${name}-authkey must write into the Debian rootfs";
    assert lib.assertMsg (sw.unitConfig.ConditionPathExists == marker) "${name}-ssh-watch must skip cleanly before the seed marker (else a start bound to the skipped ${unit} fails the switch)";
    assert lib.assertMsg (lib.elem unit sw.wantedBy && lib.elem "multi-user.target" sw.wantedBy) "${name}-ssh-watch must start with ${unit} and at boot";
    assert lib.assertMsg (has "sshd_config.d/10-guest.conf" "PasswordAuthentication no" && has "sshd_config.d/10-guest.conf" "PermitRootLogin prohibit-password") "${name} ssh must be key-only";
    assert lib.assertMsg (seed "authorized_keys" == (import ../hosts/bandit-lab/services/guest-box/guests.nix).${name}.key + "\n") "${name} root must carry exactly its guest key";
    assert lib.assertMsg (has "resolv.conf" "nameserver 9.9.9.9" && has "resolv.conf" "nameserver 1.1.1.1") "${name} must use fixed nameservers, not the host resolv.conf";
    assert lib.assertMsg (lib.all (has "10-host0.network") ["Address=${e.net}.2/32" "Gateway=${e.net}.1" "GatewayOnLink=yes"]) "${name} host0 must be ${e.net}.2/32 with the on-link gateway ${e.net}.1";
    assert lib.assertMsg (lib.all (has "tailscale-up.service") ["--auth-key=file:/var/lib/tailscale/authkey" "--ssh=false" "--advertise-tags=tag:${name}-box" "TimeoutStartSec=30s" "Restart=on-failure"]) "${name} must join the tailnet as tag:${name}-box without tailscale ssh, failing fast and retrying"; true;

  check = name: e: let
    unit =
      (
        if e.os == "debian"
        then "systemd-nspawn"
        else "container"
      )
      + "@${name}";
    svc = lab.systemd.services.${unit}.serviceConfig;
    v = "ve-${name}";
    refuse = "iptables -w -A nixos-fw -i ${v} -j nixos-fw-refuse";
    fwLines =
      e.hostAccept
      ++ [
        refuse
        "ip6tables -w -I nixos-fw 1 -i ${v} -j nixos-fw-refuse"
      ]
      ++ map (d: "iptables -w -t mangle -A FORWARD -i ${v} -d ${d} -j DROP") ["10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16" "169.254.0.0/16" "100.64.0.0/10"]
      ++ ["iptables -w -t mangle -A FORWARD -i ${v} ! -o enp44s0 -j DROP"]; # also drops guest-to-guest forwards
    stopLines = map (l: builtins.replaceStrings ["-A " "-I nixos-fw 1"] ["-D " "-D nixos-fw"] l + " || true") fwLines;
    fwList = lib.splitString "\n" fw;
    at = l: lib.lists.findFirstIndex (x: x == l) null fwList;
    uidMax = toString (e.uid + 65535);
  in
    assert lib.assertMsg (
      if e.os == "debian"
      then checkDebian name e
      else checkNixos name e
    ) "${name} ${e.os} checks";
    assert lib.assertMsg (lib.elem "${unit}.service" lab.systemd.services."${name}-ssh-watch".bindsTo) "${name}-ssh-watch must be bound to ${unit}";
    assert lib.assertMsg (lab.systemd.timers."${name}-report".timerConfig.OnCalendar == "hourly") "${name}-report must run hourly";
    assert lib.assertMsg (svc.Slice == "guests.slice") "${unit} must run in guests.slice";
    assert lib.assertMsg (svc.CPUQuota == "100%" && svc.MemoryMax == e.memory && svc.MemorySwapMax == "0" && svc.TasksMax == 512) "${unit} must carry CPU, memory (${e.memory}), swap and task limits";
    assert lib.assertMsg (lib.all (l: lib.elem l fwList) fwLines) "firewall must refuse ${v} on the host (v4 and v6) and drop its forwards to private ranges and anything but the uplink";
    assert lib.assertMsg (lib.all (l: at l < at refuse) e.hostAccept) "${name}'s host accept must stay in front of its refuse";
    assert lib.assertMsg (!(lib.hasInfix "DOCKER-USER -i ${v}" fw)) "${name}'s forward isolation must live in mangle FORWARD, not DOCKER-USER";
    assert lib.assertMsg (e.hostAccept != [] || !(lib.hasInfix "-i ${v} -p" fw || lib.hasInfix "-i ${v} -j nixos-fw-accept" fw)) "${name} must not be accepted by any host port";
    assert lib.assertMsg (lib.all (l: lib.hasInfix l stop) stopLines) "firewall stop commands must mirror every ${name} rule";
    assert lib.assertMsg (lib.elem "-a always,exit -F arch=b64 -S execve -S execveat -F uid>=${toString e.uid} -F uid<=${uidMax} -k ${name}" lab.security.audit.rules) "audit rule for ${name}'s uid range missing"; true;
in
  assert lib.assertMsg (lib.all lib.id (lib.mapAttrsToList check expect)) "guest checks";
  assert lib.assertMsg (lib.length (lib.unique (map (b: b / 65536) bases)) == lib.length bases && lib.all (b: lib.mod b 65536 == 0) bases) "guest user namespaces must be distinct 65536-aligned blocks";
  # The -A nixos-fw refuse sits below the generic accepts, so there must be none: ports open on tailscale0 only.
  assert lib.assertMsg (lab.networking.firewall.allowedTCPPorts == [] && lab.networking.firewall.allowedUDPPorts == [] && lab.networking.firewall.allowedTCPPortRanges == [] && lab.networking.firewall.allowedUDPPortRanges == []) "the lab must open no port on all interfaces";
  # The container start script binds the host's nix daemon socket into every box; only vino may use it.
  assert lib.assertMsg (lab.nix.settings.allowed-users == ["vino"]) "the nix daemon must refuse the guests' mapped uids";
  assert lib.assertMsg (slice.CPUQuota == "200%" && slice.MemoryMax == "6G" && slice.CPUWeight == 20 && slice.IOWeight == 20) "guests.slice must pool 2 CPUs / 6G at low CPU and IO weight";
  assert lib.assertMsg (lib.sort lib.lessThan lab.networking.nat.internalInterfaces == ["ve-jerry" "ve-martin" "ve-mc-public"]) "NAT must serve ve-jerry, ve-martin and ve-mc-public (ci/lab-mc-public.nix) only";
    pkgs.writeText "lab-guests" "ok\n"

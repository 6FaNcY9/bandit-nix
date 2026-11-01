# bandit-lab jerry guest container: pinned user namespace, limits, NAT and firewall
# isolation. Evaluation-time assertions only.
{
  pkgs,
  lib,
  lab,
}: let
  c = lab.containers.jerry;
  svc = lab.systemd.services."container@jerry".serviceConfig;
  fw = lab.networking.firewall.extraCommands;
  fwLines = [
    "iptables -w -A nixos-fw -i ve-jerry -j nixos-fw-refuse"
    "iptables -w -I DOCKER-USER 1 -i ve-jerry -d 192.168.0.0/24 -j DROP"
    "iptables -w -I DOCKER-USER 1 -i ve-jerry -d 10.250.77.0/29 -j DROP"
    "iptables -w -I DOCKER-USER 1 -i ve-jerry -d 172.16.0.0/12 -j DROP"
  ];
  stopLines = [
    "iptables -w -D nixos-fw -i ve-jerry -j nixos-fw-refuse || true"
    "iptables -w -D DOCKER-USER -i ve-jerry -d 192.168.0.0/24 -j DROP || true"
    "iptables -w -D DOCKER-USER -i ve-jerry -d 10.250.77.0/29 -j DROP || true"
    "iptables -w -D DOCKER-USER -i ve-jerry -d 172.16.0.0/12 -j DROP || true"
  ];
in
  assert lib.assertMsg (c.privateUsers == 524288) "jerry must use the pinned user namespace base 524288";
  assert lib.assertMsg (c.privateNetwork && c.enableTun) "jerry needs a private network and /dev/net/tun";
  assert lib.assertMsg (c.hostAddress == "10.251.0.1" && c.localAddress == "10.251.0.2") "jerry veth addresses must be 10.251.0.1/10.251.0.2";
  assert lib.assertMsg (c.bindMounts."/data".hostPath == "/srv/jerry/box") "jerry /data must bind /srv/jerry/box";
  assert lib.assertMsg (svc.CPUQuota == "100%" && svc.MemoryMax == "2G" && svc.MemorySwapMax == "0" && svc.TasksMax == 512) "container@jerry must carry CPU, memory, swap and task limits";
  assert lib.assertMsg (lab.networking.nat.internalInterfaces == ["ve-jerry"]) "NAT must serve ve-jerry only";
  assert lib.assertMsg (lib.all (l: lib.hasInfix l fw) fwLines) "firewall must refuse ve-jerry on the host and drop its LAN/bots/docker forwards";
  assert lib.assertMsg (lib.all (l: lib.hasInfix l lab.networking.firewall.extraStopCommands) stopLines) "firewall stop commands must mirror every jerry rule";
  assert lib.assertMsg (c.config.networking.nameservers == ["9.9.9.9" "1.1.1.1"]) "jerry must use fixed nameservers, not the host resolv.conf";
  assert lib.assertMsg (lib.any (r: lib.hasInfix "-F uid>=524288 -F uid<=589823 -k jerry" r) lab.security.audit.rules) "audit rule for jerry's uid range missing";
    pkgs.writeText "lab-jerry" "ok\n"

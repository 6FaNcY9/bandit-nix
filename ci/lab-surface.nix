# bandit-lab attack-surface contract (decisions D4-D6, docs/SECURITY-PLAN.md):
# the host firewall opens ports on tailscale0 only, container-published ports are
# bound to loopback or the tailnet address, and the public tunnel never carries
# SSH. Docker's DNAT runs before the INPUT chain, so firewall settings do not
# restrict published container ports; the bind address is the control.
{
  pkgs,
  lib,
  repoConfig,
  lab,
}: let
  fw = lab.networking.firewall;
  tailnetIp = repoConfig.lab.tailscaleIp;
  noPorts = x: (x.allowedTCPPorts or []) == [] && (x.allowedUDPPorts or []) == [] && (x.allowedTCPPortRanges or []) == [] && (x.allowedUDPPortRanges or []) == [];
  otherInterfaces = lib.attrNames (lib.filterAttrs (n: _: n != "tailscale0") fw.interfaces);

  publishedPorts =
    lib.concatLists (lib.mapAttrsToList (name: c: map (p: {inherit name p;}) (c.ports or [])) lab.virtualisation.oci-containers.containers)
    # Podman (quadlet) publishes through its own DNAT rules, so the same bind-address rule applies.
    ++ lib.concatLists (lib.mapAttrsToList (name: c: map (p: {inherit name p;}) c.containerConfig.publishPorts) lab.virtualisation.quadlet.containers)
    # In a pod the pod publishes the ports, not its containers.
    ++ lib.concatLists (lib.mapAttrsToList (name: c: map (p: {inherit name p;}) c.podConfig.publishPorts) lab.virtualisation.quadlet.pods);
  badPublished = lib.filter (x: !(lib.hasPrefix "127.0.0.1:" x.p || lib.hasPrefix "${tailnetIp}:" x.p)) publishedPorts;

  tunnelTargets = lib.concatMap (t: map (v: toString (v.service or v)) (lib.attrValues t.ingress)) (lib.attrValues lab.services.cloudflared.tunnels);
  sambaAllow = lab.services.samba.settings.global."hosts allow";
in
  # rawConfig replaces the generated unit text, so neither the port rule above nor the
  # hardening defaults (modules/server/containers.nix) could see what it publishes.
  assert lib.assertMsg (lib.all (c: c.rawConfig == null) (lib.attrValues lab.virtualisation.quadlet.containers ++ lib.attrValues lab.virtualisation.quadlet.pods)) "quadlet containers and pods must not use rawConfig";
  assert lib.assertMsg (lab.virtualisation.quadlet.containers.aiia-redis.containerConfig.noNewPrivileges && lab.virtualisation.quadlet.containers.aiia-ghost.containerConfig.noNewPrivileges) "aiia-redis and aiia-ghost must retain no-new-privileges";
  # ntfy listens on all addresses only so the bots container can reach it via its Docker gateway
  # (owner-approved 2026-10-10); then the firewall may admit 2586 from the mcbots subnet and nothing else.
  assert lib.assertMsg (
    lab.services.ntfy-sh.settings.auth-default-access
    == "deny-all"
    && (lab.services.ntfy-sh.settings.listen-http
      == "127.0.0.1:2586"
      || (lab.services.ntfy-sh.settings.listen-http
        == "0.0.0.0:2586"
        && lib.hasInfix "iptables -A nixos-fw -s 10.250.77.0/29 -p tcp --dport 2586 -j nixos-fw-accept" fw.extraCommands
        && lib.length (lib.splitString "--dport 2586" fw.extraCommands) == 2))
  ) "ntfy must listen on loopback, or on all addresses with the firewall admitting port 2586 only from the mcbots subnet, and keep deny-all access";
  assert lib.assertMsg (lab.services.ntfy-sh.settings.auth-access == ["mcbots:mcbots:wo" "phone:mcbots:ro"]) "ntfy must grant only topic-scoped publisher and reader access";
  assert lib.assertMsg (!lab.services.openssh.openFirewall) "sshd must not open the firewall globally; port 22 is allowed on tailscale0 only";
  assert lib.assertMsg (lib.all (p: lib.elem p fw.interfaces.tailscale0.allowedTCPPorts) [22 139 445]) "tailscale0 must allow SSH (22) and SMB (139, 445)";
  # Minecraft (phase 5.5): Velocity's game port and voice chat, on tailscale0 only; Paper and RCON stay off every list.
  assert lib.assertMsg (lib.elem 25565 fw.interfaces.tailscale0.allowedTCPPorts && lib.elem 24454 fw.interfaces.tailscale0.allowedUDPPorts) "tailscale0 must allow Velocity (25565/tcp) and voice chat (24454/udp)";
  assert lib.assertMsg (noPorts fw) "the global firewall lists must be empty: open ports per interface, on tailscale0 only";
  assert lib.assertMsg (lib.all (i: noPorts fw.interfaces.${i}) otherInterfaces) "no interface other than tailscale0 may open ports (found: ${toString otherInterfaces})";
  assert lib.assertMsg (badPublished == []) "Container-published ports must bind 127.0.0.1 or ${tailnetIp}, never all interfaces: ${toString (map (x: "${x.name} ${x.p}") badPublished)}";
  assert lib.assertMsg (!(lib.any (lib.hasPrefix "ssh://") tunnelTargets)) "the public Cloudflare tunnel must not publish SSH (Tailscale is the admin path)";
  assert lib.assertMsg (fw.enable && !lab.networking.nftables.enable && fw.trustedInterfaces == ["lo"]) "the iptables firewall must be on, with no trusted interface besides lo (a trusted tailscale0 would open every port)";
  assert lib.assertMsg (sambaAllow == "127.0.0.1 ::1 100.64.0.0/10 fd7a:115c:a1e0::/48" && lab.services.samba.settings.global."hosts deny" == "ALL") "Samba 'hosts allow' must be exactly loopback plus the tailnet and 'hosts deny' must be ALL";
  assert lib.assertMsg (lab.services.resolved.settings.Resolve.LLMNR == "false" && lab.services.resolved.settings.Resolve.MulticastDNS == "false") "LLMNR and mDNS must stay off on the server";
    pkgs.runCommand "lab-surface" {nativeBuildInputs = [pkgs.gnugrep pkgs.yq-go pkgs.python3 pkgs.bash pkgs.gnused lab.services.ntfy-sh.package];} ''
      python3 ${./ntfy-test.py} ${pkgs.writeText "ntfy-seed.sh" lab.systemd.services.ntfy-seed.script} ${lab.environment.etc."ntfy/server.yml".source}
      touch "$out"
    ''

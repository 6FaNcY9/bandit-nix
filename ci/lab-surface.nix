# bandit-lab attack-surface contract (decisions D4-D6, docs/SECURITY-PLAN.md):
# the host firewall opens ports on tailscale0 only, Docker-published ports are
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

  publishedPorts = lib.concatLists (lib.mapAttrsToList (name: c: map (p: {inherit name p;}) (c.ports or [])) lab.virtualisation.oci-containers.containers);
  badPublished = lib.filter (x: !(lib.hasPrefix "127.0.0.1:" x.p || lib.hasPrefix "${tailnetIp}:" x.p)) publishedPorts;

  tunnelTargets = lib.concatMap (t: map (v: toString (v.service or v)) (lib.attrValues t.ingress)) (lib.attrValues lab.services.cloudflared.tunnels);
  sambaAllow = lab.services.samba.settings.global."hosts allow";
in
  assert lib.assertMsg (lib.elem "--security-opt=no-new-privileges" lab.virtualisation.oci-containers.containers.aiia-redis.extraOptions) "aiia-redis must retain no-new-privileges";
  assert lib.assertMsg (lib.elem "--security-opt=no-new-privileges" lab.virtualisation.oci-containers.containers.aiia-ghost.extraOptions) "aiia-ghost must retain no-new-privileges";
  assert lib.assertMsg (!lab.services.openssh.openFirewall) "sshd must not open the firewall globally; port 22 is allowed on tailscale0 only";
  assert lib.assertMsg (lib.all (p: lib.elem p fw.interfaces.tailscale0.allowedTCPPorts) [22 139 445]) "tailscale0 must allow SSH (22) and SMB (139, 445)";
  assert lib.assertMsg (noPorts fw) "the global firewall lists must be empty: open ports per interface, on tailscale0 only";
  assert lib.assertMsg (lib.all (i: noPorts fw.interfaces.${i}) otherInterfaces) "no interface other than tailscale0 may open ports (found: ${toString otherInterfaces})";
  assert lib.assertMsg (badPublished == []) "Docker-published ports must bind 127.0.0.1 or ${tailnetIp}, never all interfaces: ${toString (map (x: "${x.name} ${x.p}") badPublished)}";
  assert lib.assertMsg (!(lib.any (lib.hasPrefix "ssh://") tunnelTargets)) "the public Cloudflare tunnel must not publish SSH (Tailscale is the admin path)";
  assert lib.assertMsg (fw.enable && !lab.networking.nftables.enable && fw.trustedInterfaces == ["lo"]) "the iptables firewall must be on, with no trusted interface besides lo (a trusted tailscale0 would open every port)";
  assert lib.assertMsg (sambaAllow == "127.0.0.1 ::1 100.64.0.0/10 fd7a:115c:a1e0::/48" && lab.services.samba.settings.global."hosts deny" == "ALL") "Samba 'hosts allow' must be exactly loopback plus the tailnet and 'hosts deny' must be ALL";
  assert lib.assertMsg (lab.services.resolved.settings.Resolve.LLMNR == "false" && lab.services.resolved.settings.Resolve.MulticastDNS == "false") "LLMNR and mDNS must stay off on the server";
    pkgs.runCommand "lab-surface" {nativeBuildInputs = [pkgs.gnugrep pkgs.yq-go];} ''
      yq -e '.services.grafana.security_opt | any_c(. == "no-new-privileges:true")' ${../hosts/bandit-lab/services/monitoring/compose.yml} >/dev/null
      yq -e '.services."blackbox-exporter".security_opt | any_c(. == "no-new-privileges:true")' ${../hosts/bandit-lab/services/monitoring/compose.yml} >/dev/null
      yq -e '.services."node-exporter".security_opt | any_c(. == "no-new-privileges:true")' ${../hosts/bandit-lab/services/monitoring/compose.yml} >/dev/null
      # Compose projects must not publish a bare host:container port either.
      for f in ${../hosts/bandit-lab/services/mrija-archive/compose.yml} ${../hosts/bandit-lab/services/monitoring/compose.yml}; do
        if grep -nE '^[[:space:]]*-[[:space:]]*"?(0\.0\.0\.0:|\[::\]:)?[0-9]{1,5}:[0-9]{1,5}' "$f"; then
          echo "$f publishes a port without a 127.0.0.1 or tailnet bind address" >&2
          exit 1
        fi
      done
      touch "$out"
    ''

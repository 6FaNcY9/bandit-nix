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
  assert lib.assertMsg (lib.elem "--security-opt=no-new-privileges" lab.virtualisation.oci-containers.containers.aiia-mysql.extraOptions) "aiia-mysql must retain no-new-privileges";
  # The lab deploys GPG-signed commits only; a substituter that CI fills without that gate would bypass it (nixos/cachix.nix).
  assert lib.assertMsg (!(lib.any (lib.hasInfix "cachix.org") (lab.nix.settings.substituters ++ (lab.nix.settings.extra-substituters or [])))) "bandit-lab must not trust a Cachix substituter: CI pushes there without the signed-commit gate";
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
  assert lib.assertMsg (noPorts fw) "the global firewall lists must be empty: open ports per interface, on tailscale0 only";
  assert lib.assertMsg (lib.all (i: noPorts fw.interfaces.${i}) otherInterfaces) "no interface other than tailscale0 may open ports (found: ${toString otherInterfaces})";
  assert lib.assertMsg (badPublished == []) "Docker-published ports must bind 127.0.0.1 or ${tailnetIp}, never all interfaces: ${toString (map (x: "${x.name} ${x.p}") badPublished)}";
  assert lib.assertMsg (!(lib.any (lib.hasPrefix "ssh://") tunnelTargets)) "the public Cloudflare tunnel must not publish SSH (Tailscale is the admin path)";
  assert lib.assertMsg (fw.enable && !lab.networking.nftables.enable && fw.trustedInterfaces == ["lo"]) "the iptables firewall must be on, with no trusted interface besides lo (a trusted tailscale0 would open every port)";
  assert lib.assertMsg (sambaAllow == "127.0.0.1 ::1 100.64.0.0/10 fd7a:115c:a1e0::/48" && lab.services.samba.settings.global."hosts deny" == "ALL") "Samba 'hosts allow' must be exactly loopback plus the tailnet and 'hosts deny' must be ALL";
  assert lib.assertMsg (lab.services.resolved.settings.Resolve.LLMNR == "false" && lab.services.resolved.settings.Resolve.MulticastDNS == "false") "LLMNR and mDNS must stay off on the server";
    pkgs.runCommand "lab-surface" {nativeBuildInputs = [pkgs.gnugrep pkgs.yq-go pkgs.python3 pkgs.bash pkgs.gnused lab.services.ntfy-sh.package];} ''
      # Every monitoring container keeps no-new-privileges.
      yq -e '.services | to_entries | all_c(.value.security_opt // [] | any_c(. == "no-new-privileges:true"))' ${../hosts/bandit-lab/services/monitoring/compose.yml} >/dev/null \
        || { echo "every service in monitoring/compose.yml must set no-new-privileges:true" >&2; exit 1; }
      # Peer backup units must stay exported, or the "Backup job failed" alert cannot fire for them.
      grep -q 'restic-backups-peer|restic-peer-prune' ${../hosts/bandit-lab/services/monitoring/compose.yml} \
        || { echo "node-exporter unit-include must cover restic-backups-peer and restic-peer-prune" >&2; exit 1; }
      # Compose projects must not publish a bare host:container port either.
      for f in ${../hosts/bandit-lab/services/mrija-archive/compose.yml} ${../hosts/bandit-lab/services/monitoring/compose.yml}; do
        if grep -nE '^[[:space:]]*-[[:space:]]*"?(0\.0\.0\.0:|\[::\]:)?[0-9]{1,5}:[0-9]{1,5}' "$f"; then
          echo "$f publishes a port without a 127.0.0.1 or tailnet bind address" >&2
          exit 1
        fi
      done
      python3 ${./ntfy-test.py} ${pkgs.writeText "ntfy-seed.sh" lab.systemd.services.ntfy-seed.script} ${lab.environment.etc."ntfy/server.yml".source}
      touch "$out"
    ''

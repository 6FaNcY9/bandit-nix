# Private bot notifications: Tailscale Serve exposes it to the tailnet (8447); the bots
# container reaches it over its Docker network, the only other source the firewall admits.
{
  config,
  lib,
  pkgs,
  repoConfig,
  ...
}: let
  url = "https://${repoConfig.lab.tailnetFqdn}:8447";
  credentials = "/var/lib/mcbots/ntfy";
  # The mcbots Docker network (minecraft/default.nix mcbotsSubnet) and its host-side gateway.
  botsSubnet = "10.250.77.0/29";
  botsGateway = "10.250.77.1";
  port = 2586;
in {
  services.ntfy-sh = {
    enable = true;
    environmentFile = "${credentials}/server.env";
    settings = {
      base-url = url;
      # All addresses, because the bridge gateway exists only once Docker made the
      # network; the firewall below admits the bots' subnet and nothing else (owner OK 2026-10-10).
      listen-http = "0.0.0.0:${toString port}";
      auth-file = "/var/lib/ntfy-sh/user.db";
      auth-default-access = "deny-all";
      auth-access = ["mcbots:mcbots:wo" "phone:mcbots:ro"];
      # iOS uses the upstream only for wake-up requests, never message bodies.
      upstream-base-url = "https://ntfy.sh";
    };
  };

  systemd.services.ntfy-seed = {
    description = "Generate private ntfy credentials once on this host";
    before = ["ntfy-sh.service" "mcbots-seed.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      StateDirectory = "mcbots";
      StateDirectoryMode = "0700";
      UMask = "0077";
    };
    path = [pkgs.coreutils config.services.ntfy-sh.package pkgs.gnused];
    script = ''
      if [ ! -d ${credentials} ]; then
        stage=$(mktemp -d /var/lib/mcbots/ntfy.XXXXXX)
        trap 'rm -rf "$stage"' EXIT
        writer=$(head -c 32 /dev/urandom | sha256sum | cut -c1-64)
        reader=$(head -c 32 /dev/urandom | sha256sum | cut -c1-64)
        writer_hash=$(printf '%s\n%s\n' "$writer" "$writer" | ntfy user hash 2>/dev/null | tr '\r' '\n' | sed -n '/^\$2[aby]\$/p')
        reader_hash=$(printf '%s\n%s\n' "$reader" "$reader" | ntfy user hash 2>/dev/null | tr '\r' '\n' | sed -n '/^\$2[aby]\$/p')
        test -n "$writer_hash" && test -n "$reader_hash"
        token=$(ntfy token generate)
        printf 'NTFY_AUTH_USERS=mcbots:%s:user,phone:%s:user\nNTFY_AUTH_TOKENS=mcbots:%s\n' "$writer_hash" "$reader_hash" "$token" > "$stage/server.env"
        printf 'NTFY_TOKEN=%s\n' "$token" > "$stage/publisher.env"
        printf 'Username: phone\nPassword: %s\n' "$reader" > "$stage/read-credentials"
        mv "$stage" ${credentials}
        trap - EXIT
      fi
      test -s ${credentials}/server.env
      test -s ${credentials}/publisher.env
      test -s ${credentials}/read-credentials
    '';
  };
  systemd.services.ntfy-sh = {
    requires = ["ntfy-seed.service"];
    after = ["ntfy-seed.service"];
    serviceConfig.StateDirectoryMode = "0700";
  };

  networking.firewall.extraCommands = "iptables -A nixos-fw -s ${botsSubnet} -p tcp --dport ${toString port} -j nixos-fw-accept";
  networking.firewall.extraStopCommands = "iptables -D nixos-fw -s ${botsSubnet} -p tcp --dport ${toString port} -j nixos-fw-accept || true";

  # The Docker hub publishes to the gateway: host loopback is not its loopback, and the
  # tailnet address is firewalled off from the bridge (nothing reached the phone before).
  # Worker containers receive neither the ntfy token nor this environment file.
  virtualisation.oci-containers.containers.mcbots = lib.mkIf config.bandit-lab.mcbots.enable {
    environment = {
      NTFY_URL = "http://${botsGateway}:${toString port}";
      NTFY_TOPIC = "mcbots";
    };
    environmentFiles = ["${credentials}/publisher.env"];
  };
  systemd.services.mcbots-seed = lib.mkIf config.bandit-lab.mcbots.enable {
    requires = ["ntfy-seed.service"];
    after = ["ntfy-seed.service"];
  };

  systemd.services.ntfy-https = {
    description = "Tailnet-only HTTPS for bot phone notifications";
    after = ["tailscaled.service" "ntfy-sh.service"];
    wants = ["tailscaled.service" "ntfy-sh.service"];
    wantedBy = ["multi-user.target"];
    path = [config.services.tailscale.package pkgs.coreutils];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "45s";
    };
    script = ''
      if ! timeout 30 tailscale serve --bg --https=8447 http://127.0.0.1:2586; then
        echo "WARNING: could not publish ntfy on tailnet HTTPS port 8447; enable Serve and HTTPS Certificates, then restart ntfy-https" >&2
      fi
    '';
    preStop = ''
      timeout 30 tailscale serve --https=8447 off || true
    '';
  };
}

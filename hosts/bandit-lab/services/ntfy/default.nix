# Private bot notifications; only Tailscale Serve exposes the loopback listener.
{
  config,
  lib,
  pkgs,
  repoConfig,
  ...
}: let
  url = "https://${repoConfig.lab.tailnetFqdn}:8447";
  credentials = "/var/lib/mcbots/ntfy";
in {
  services.ntfy-sh = {
    enable = true;
    environmentFile = "${credentials}/server.env";
    settings = {
      base-url = url;
      listen-http = "127.0.0.1:2586";
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

  # The Docker hub publishes via Serve, because host loopback is not its loopback.
  # Worker containers receive neither the ntfy token nor this environment file.
  virtualisation.oci-containers.containers.mcbots = lib.mkIf config.bandit-lab.mcbots.enable {
    environment = {
      NTFY_URL = url;
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

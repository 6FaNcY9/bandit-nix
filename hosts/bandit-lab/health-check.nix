{
  config,
  pkgs,
  ...
}: let
  criticalUnits = [
    "cloudflared-tunnel-bandit-lab.service"
    # docker-aiia-ghost deliberately stays out until the image transfer onto
    # the host is confirmed — the private GHCR image is docker-loaded by hand,
    # so the unit fails (and would roll back deploys) until then.
    "docker-aiia-mysql.service"
    "docker-network-aiia.service"
    "docker-network-portainer-control.service"
    "docker-network-proxy.service"
    "docker-portainer-agent.service"
    "docker-portainer.service"
    "docker-vaultwarden.service"
    "docker.service"
    # Access path and brute-force protection: a config that silently kills
    # SSH or fail2ban must roll back, not deploy.
    "fail2ban.service"
    # No getty@tty1 here: a headless server does not depend on a virtual
    # console, and a spurious getty failure would roll back a good deploy.
    "postgresql.service"
    "samba-smbd.service"
    "sshd.service"
    "tailscaled.service"
    "traefik.service"
    "traefik-docker-proxy.service"
  ];
  healthCheck = pkgs.writeShellApplication {
    name = "bandit-lab-health";
    runtimeInputs = [pkgs.coreutils pkgs.systemd pkgs.curl pkgs.docker config.services.postgresql.package];
    text = ''
      set -euo pipefail

      critical_units=(${builtins.concatStringsSep " " criticalUnits})
      for unit in "''${critical_units[@]}"; do
        if ! systemctl is-active --quiet "$unit"; then
          echo "Critical unit is not active: $unit" >&2
          exit 1
        fi
      done

      # Units can be active before their applications accept requests.
      # Retry locally; external DNS/Cloudflare availability is not a deploy gate.
      ready() {
        local attempt
        for ((attempt = 1; attempt <= 12; attempt++)); do
          if "$@"; then return 0; fi
          sleep 5
        done
        echo "Readiness check failed: $*" >&2
        return 1
      }
      # Traefik withholds routing while a container's Docker healthcheck is
      # "starting", and vaultwarden's first check lands a full interval after
      # boot. An HTTP probe alone burns all retries on instant 404s and rolls
      # back healthy deploys — wait for the engine health state first.
      container_healthy() {
        local attempt status
        for ((attempt = 1; attempt <= 24; attempt++)); do
          status="$(docker inspect --format '{{.State.Health.Status}}' "$1")"
          case "$status" in
            healthy) return 0 ;;
            unhealthy)
              echo "Container $1 reports unhealthy" >&2
              return 1
              ;;
          esac
          sleep 5
        done
        echo "Container $1 did not become healthy in time" >&2
        return 1
      }
      container_healthy vaultwarden
      ready pg_isready -q -h /run/postgresql -t 3
      ready curl --fail --silent --show-error --output /dev/null --connect-timeout 2 --max-time 5 \
        -H 'Host: portainer.bandit-lab.mrija.org' http://127.0.0.1/api/status
      ready curl --fail --silent --show-error --output /dev/null --connect-timeout 2 --max-time 5 \
        -H 'Host: vault.bandit-lab.mrija.org' http://127.0.0.1/alive

      failed_units="$(systemctl --failed --no-legend --plain)"
      if [[ -n "$failed_units" ]]; then
        printf 'Warning: non-critical failed system units remain:\n%s\n' "$failed_units" >&2
      fi

      echo "bandit-lab health check passed"
    '';
  };
in {
  environment.systemPackages = [healthCheck];
}

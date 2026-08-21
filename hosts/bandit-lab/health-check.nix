{pkgs, ...}: let
  criticalUnits = [
    "cloudflared-tunnel-bandit-lab.service"
    "docker-network-portainer-control.service"
    "docker-network-proxy.service"
    "docker-portainer-agent.service"
    "docker-portainer.service"
    "docker-vaultwarden.service"
    "docker.service"
    # No getty@tty1 here: a headless server does not depend on a virtual
    # console, and a spurious getty failure would roll back a good deploy.
    "postgresql.service"
    "tailscaled.service"
    "traefik.service"
  ];
  healthCheck = pkgs.writeShellApplication {
    name = "bandit-lab-health";
    runtimeInputs = [pkgs.coreutils pkgs.systemd];
    text = ''
      set -euo pipefail

      critical_units=(${builtins.concatStringsSep " " criticalUnits})
      for unit in "''${critical_units[@]}"; do
        if ! systemctl is-active --quiet "$unit"; then
          echo "Critical unit is not active: $unit" >&2
          exit 1
        fi
      done

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

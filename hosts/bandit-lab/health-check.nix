{pkgs, ...}: let
  criticalUnits = [
    "cloudflared-tunnel-bandit-lab.service"
    "docker-network-proxy.service"
    "docker-portainer.service"
    "docker-vaultwarden.service"
    "docker.service"
    "ollama.service"
    "postgresql.service"
    "tailscaled.service"
    "traefik.service"
  ];
  healthCheck = pkgs.writeShellApplication {
    name = "bandit-lab-health";
    runtimeInputs = [pkgs.coreutils pkgs.systemd];
    text = ''
      set -euo pipefail

      failed_units="$(systemctl --failed --no-legend --plain)"
      if [[ -n "$failed_units" ]]; then
        printf 'Failed system units:\n%s\n' "$failed_units" >&2
        exit 1
      fi

      critical_units=(${builtins.concatStringsSep " " criticalUnits})
      for unit in "''${critical_units[@]}"; do
        if ! systemctl is-active --quiet "$unit"; then
          echo "Critical unit is not active: $unit" >&2
          exit 1
        fi
      done

      echo "bandit-lab health check passed"
    '';
  };
in {
  environment.systemPackages = [healthCheck];
}

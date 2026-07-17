{
  pkgs,
  repoConfig,
  ...
}: let
  username = repoConfig.workstation.username;
  healthCheck = pkgs.writeShellApplication {
    name = "bandit-health";
    runtimeInputs = [pkgs.coreutils pkgs.systemd];
    text = ''
      set -euo pipefail

      failed_units="$(systemctl --failed --no-legend --plain)"
      if [[ -n "$failed_units" ]]; then
        printf 'Failed system units:\n%s\n' "$failed_units" >&2
        exit 1
      fi

      systemctl is-active --quiet home-manager-${username}.service
      echo "bandit health check passed"
    '';
  };
in {
  environment.systemPackages = [healthCheck];
}

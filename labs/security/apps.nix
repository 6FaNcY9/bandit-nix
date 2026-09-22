{
  pkgs,
  atomicFiles,
  ...
}: let
  atomicConsole = pkgs.writeShellApplication {
    name = "atomic-console";
    runtimeInputs = [pkgs.coreutils pkgs.powershell];
    text = ''
      if [ ! -d /var/lib/security-lab/atomics ]; then
        mkdir -p /var/lib/security-lab
        cp -r ${atomicFiles}/tests/atomics /var/lib/security-lab/atomics
        chmod -R u+w /var/lib/security-lab/atomics
      fi
      export PSModulePath="${atomicFiles}/modules:''${PSModulePath:-}"
      # PowerShell, not the shell, expands these variables.
      # shellcheck disable=SC2016
      exec pwsh -NoLogo -NoProfile -NoExit -Command '
        $ErrorActionPreference = "Stop"
        Import-Module Invoke-AtomicRedTeam
        $PSDefaultParameterValues["Invoke-AtomicTest:PathToAtomicsFolder"] = "/var/lib/security-lab/atomics"
        Write-Host "Atomic console ready. Tests run only when explicitly invoked."
      '
    '';
  };
  labCompose = pkgs.writeShellApplication {
    name = "lab-compose";
    runtimeInputs = [pkgs.coreutils pkgs.docker-compose];
    text = ''
      case "''${1:-}" in
        bloodhound|crapi) stack="$1"; shift ;;
        *) echo "Usage: lab-compose {bloodhound|crapi} <compose arguments>" >&2; exit 2 ;;
      esac
      mkdir -p "/var/lib/security-lab/$stack"
      export LISTEN_IP=0.0.0.0 BLOODHOUND_HOST=0.0.0.0 TLS_ENABLED=false
      exec docker-compose --project-name "lab-$stack" \
        --project-directory "/var/lib/security-lab/$stack" \
        -f "/etc/security-lab/$stack.yml" "$@"
    '';
  };
in {
  _module.args = {inherit atomicConsole labCompose;};
}

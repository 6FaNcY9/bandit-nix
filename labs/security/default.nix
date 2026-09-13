{
  lib,
  pkgs,
  modulesPath,
  ...
}: let
  atomics = pkgs.fetchurl {
    url = "https://codeload.github.com/redcanaryco/atomic-red-team/tar.gz/388942adbd9641f4dfdcf079d7efe9a75ec0ac43";
    hash = "sha256-oFWKlFCTFoz0o8SgplVqZb/Mbi1YA+a2JJLOa0/Ooco=";
  };
  invoke = pkgs.fetchurl {
    url = "https://codeload.github.com/redcanaryco/invoke-atomicredteam/tar.gz/8af478bb9e4637df568ac1e596553b025b16cd1b";
    hash = "sha256-wYB9v4bWu4+ja7M5bKaHDsLX6AgRda1KSHx7QDLA06c=";
  };
  yaml = pkgs.fetchurl {
    url = "https://www.powershellgallery.com/api/v2/package/powershell-yaml/0.4.12";
    hash = "sha256-1GArx6Sgk3ZlIEItU8qLCazeFiKG+uEeLubI7f6geBA=";
  };
  atomicFiles = pkgs.runCommand "atomic-red-team-files" {nativeBuildInputs = [pkgs.unzip];} ''
    mkdir -p "$out/tests" "$out/modules/Invoke-AtomicRedTeam" "$out/modules/powershell-yaml"
    tar xf ${atomics} --strip-components=1 -C "$out/tests"
    tar xf ${invoke} --strip-components=1 -C "$out/modules/Invoke-AtomicRedTeam"
    unzip -q ${yaml} -d "$out/modules/powershell-yaml"
  '';
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
  imports = [(modulesPath + "/virtualisation/qemu-vm.nix")];
  networking.hostName = "security-lab";
  system.stateVersion = "25.11";
  system.build.atomicCheck =
    pkgs.runCommand "atomic-runner-check" {
      nativeBuildInputs = [pkgs.powershell pkgs.inetutils];
    } ''
      export HOME="$TMPDIR" PSModulePath="${atomicFiles}/modules"
      pwsh -NoLogo -NoProfile -Command '
        $ErrorActionPreference = "Stop"
        Import-Module Invoke-AtomicRedTeam
        $technique = Get-AtomicTechnique -Path "${atomicFiles}/tests/atomics/T1059.004/T1059.004.yaml"
        if ($technique.atomic_tests.Count -lt 1) { throw "No atomic tests parsed" }
      '
      touch "$out"
    '';
  services.getty.autologinUser = "root";
  virtualisation = {
    memorySize = 12288;
    cores = 4;
    diskSize = 40960;
    graphics = false;
    useNixStoreImage = true;
    sharedDirectories = lib.mkForce {};
    restrictNetwork = true;
    forwardPorts = map (port: {
      from = "host";
      host = {
        inherit port;
        address = "127.0.0.1";
      };
      guest.port = port;
    }) [8080 8888 8025];
    docker.enable = true;
  };
  networking.firewall.allowedTCPPorts = [8080 8888 8025];
  environment.etc = {
    "security-lab/bloodhound.yml".source = ./bloodhound.yml;
    "security-lab/crapi.yml".source = ./crapi.yml;
  };
  environment.systemPackages = [labCompose atomicConsole pkgs.git pkgs.curl];
}

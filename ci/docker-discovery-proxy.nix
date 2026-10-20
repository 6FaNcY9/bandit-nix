{
  pkgs,
  lib,
  lab,
}:
pkgs.runCommand "docker-discovery-proxy-regressions" {
  nativeBuildInputs = [pkgs.python3];
} ''
  python3 ${./test-docker-discovery-proxy.py} ${lib.escapeShellArg lab.systemd.services.traefik-docker-proxy.serviceConfig.ExecStart}
  touch "$out"
''

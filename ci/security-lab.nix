# Security-lab VM contract: no host directories shared into either VM variant,
# and both Compose stacks validate and publish the ports the VM forwards.
{
  pkgs,
  lib,
  securityLab,
  securityLabOnline,
}: let
  noSharedDirs = name: cfg:
    lib.assertMsg (cfg.config.virtualisation.sharedDirectories == {})
    "${name} must not share host directories with the VM";
in
  assert noSharedDirs "security-lab" securityLab;
  assert noSharedDirs "security-lab-online" securityLabOnline;
    pkgs.runCommand "security-lab-compose-check" {
      nativeBuildInputs = [pkgs.docker-compose pkgs.gnugrep];
    } ''
      docker-compose -f ${../labs/security/stacks/bloodhound.yml} config --quiet
      docker-compose -f ${../labs/security/stacks/crapi.yml} config --quiet
      # Port contract with labs/security/default.nix labPorts
      # (8080 bloodhound, 8888 crapi gateway, 8025 mail UI): the VM
      # forwards exactly these host ports, so they must stay published.
      docker-compose -f ${../labs/security/stacks/bloodhound.yml} config | grep -q 'published: "8080"'
      docker-compose -f ${../labs/security/stacks/crapi.yml} config | grep -q 'published: "8888"'
      docker-compose -f ${../labs/security/stacks/crapi.yml} config | grep -q 'published: "8025"'
      touch "$out"
    ''

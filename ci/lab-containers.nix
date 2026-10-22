# Container runtime contract for bandit-lab (phase 3, spec step 3): Podman runs
# next to Docker without taking over Docker's socket or backend, and every
# quadlet container is hardened unless it relaxes a flag explicitly. Pure eval.
{
  pkgs,
  lib,
  lab,
  probe,
}: let
  unit = name: probe.environment.etc."containers/systemd/${name}.container".text;
  has = name: line: lib.hasInfix "\n${line}\n" "\n${unit name}\n";
  podman = lab.virtualisation.podman;
in
  assert lib.assertMsg (lab.virtualisation.docker.enable && lab.virtualisation.oci-containers.backend == "docker")
  "Docker stays the oci-containers backend until phase 4 has moved every service";
  assert lib.assertMsg (podman.enable && !podman.dockerCompat && !podman.dockerSocket.enable)
  "Podman must run without taking over the docker CLI or /run/docker.sock";
  assert lib.assertMsg (lab.virtualisation.containers.containersConf.settings.network.firewall_driver == "iptables")
  "netavark must use iptables like the lab firewall and Docker";
  assert lib.assertMsg (has "hardened" "NoNewPrivileges=true" && has "hardened" "DropCapability=all" && has "hardened" "ReadOnly=true")
  "quadlet containers must default to no-new-privileges, cap-drop all and a read-only root:\n${unit "hardened"}";
  assert lib.assertMsg (has "relaxed" "ReadOnly=false" && has "relaxed" "NoNewPrivileges=true")
  "relaxing one flag must keep the other defaults:\n${unit "relaxed"}";
    pkgs.runCommand "lab-containers" {} "touch $out"

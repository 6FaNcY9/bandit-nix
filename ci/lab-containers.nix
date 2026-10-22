# Container runtime contract for bandit-lab (phase 3, spec step 3): Podman runs
# next to Docker without taking over Docker's socket or backend, and every
# quadlet container is hardened unless it relaxes a flag explicitly. Pure eval.
{
  pkgs,
  lib,
  repoConfig,
  lab,
  probe,
  extend,
}: let
  unit = name: probe.environment.etc."containers/systemd/${name}.container".text;
  has = name: line: lib.hasInfix "\n${line}\n" "\n${unit name}\n";
  podman = lab.virtualisation.podman;
  # lab-surface must reject a quadlet port published on all interfaces, as it does for Docker,
  # whether a container or a pod publishes it, and any unit text it cannot inspect (rawConfig).
  surfaceRejects = m:
    !(builtins.tryEval (builtins.seq
        (import ./lab-surface.nix {
          inherit pkgs lib repoConfig;
          lab = extend m;
        })
    .drvPath
        true))
  .success;
  image = "docker.io/library/busybox:latest";
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
  assert lib.assertMsg (surfaceRejects {
    virtualisation.quadlet.containers.wide.containerConfig = {
      inherit image;
      publishPorts = ["8080:80"];
    };
  }) "lab-surface must fail for a quadlet container with publishPorts = [\"8080:80\"]";
  assert lib.assertMsg (surfaceRejects {virtualisation.quadlet.pods.wide.podConfig.publishPorts = ["8080:80"];})
  "lab-surface must fail for a quadlet pod with publishPorts = [\"8080:80\"]";
  assert lib.assertMsg (surfaceRejects {virtualisation.quadlet.containers.raw.rawConfig = "[Container]\nImage=${image}\nPublishPort=8080:80\n";})
  "lab-surface must fail for a quadlet container with rawConfig";
    pkgs.runCommand "lab-containers" {} "touch $out"

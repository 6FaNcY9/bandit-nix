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
  # Rootful Podman maps uids 1:1, so a container runs as the uid that owns its data, never as root.
  rootContainers = lib.attrNames (lib.filterAttrs (_: c: c.containerConfig.user == null || c.containerConfig.userns != null) lab.virtualisation.quadlet.containers);
in
  assert lib.assertMsg (lab.virtualisation.docker.enable && lab.virtualisation.oci-containers.backend == "docker")
  "Docker stays the oci-containers backend until phases 5 and 6 have moved Minecraft and mcbots";
  assert lib.assertMsg (lab.virtualisation.quadlet.networks ? proxy)
  "the lab must define the quadlet network proxy that migrated services join";
  # Phase 4 service contracts: the monitoring stack is a pod publishing Grafana and blackbox on loopback,
  # Traefik reaches it through the file provider, and the compose lifecycle unit is gone.
  assert lib.assertMsg (lab.virtualisation.quadlet.pods.monitoring.podConfig.publishPorts == ["127.0.0.1:3000:3000" "127.0.0.1:9115:9115"])
  "the monitoring pod must publish grafana (3000) and blackbox (9115) on loopback only";
  # Config files are mounted from the store, so a changed prometheus.yml or dashboard changes the unit and restarts the container.
  assert lib.assertMsg (lib.all (v: lib.hasPrefix "/nix/store/" v) (lib.filter (v: lib.hasInfix ":ro" v && !(lib.hasPrefix "/run/" v)) (lab.virtualisation.quadlet.containers.prometheus.containerConfig.volumes ++ lab.virtualisation.quadlet.containers.grafana.containerConfig.volumes ++ lab.virtualisation.quadlet.containers.blackbox-exporter.containerConfig.volumes)))
  "monitoring read-only config mounts must point into the store, not at stable symlinks";
  assert lib.assertMsg (!(lab.systemd.services ? compose-monitoring))
  "the compose-monitoring lifecycle unit must be gone once the pod exists";
  assert lib.assertMsg (lab.services.traefik.dynamicConfigOptions.http.services.grafana.loadBalancer.servers == [{url = "http://127.0.0.1:3000";}])
  "traefik must route grafana to its loopback port through the file provider";
  assert lib.assertMsg (lab.virtualisation.quadlet.containers.mrija-archive.containerConfig.publishPorts == ["127.0.0.1:8081:8080"])
  "mrija-archive must publish its API on loopback only (the sync unit and Traefik use it)";
  assert lib.assertMsg (!(lab.systemd.services ? compose-mrija-archive))
  "the compose-mrija-archive lifecycle unit must be gone once the container exists";
  assert lib.assertMsg (let a = lab.systemd.services.mrija-archive-sync.serviceConfig.IPAddressAllow; in lib.elem "10.89.0.0/24" a && !(lib.elem "172.18.0.0/16" a))
  "mrija-archive-sync must allow the podman proxy subnet (IPAddressAllow sees the DNATed destination), not the old Docker one";
  assert lib.assertMsg (lab.virtualisation.quadlet.pods.aiia.podConfig.publishPorts == ["127.0.0.1:2368:2368"])
  "the aiia pod must publish Ghost on loopback only";
  assert lib.assertMsg (lab.virtualisation.quadlet.containers.aiia-ghost.containerConfig.pull == "never")
  "the aiia-ghost image is loaded by hand and must never be pulled";
  assert lib.assertMsg (lab.virtualisation.quadlet.containers.vaultwarden.containerConfig.publishPorts == ["127.0.0.1:8222:8080"] && lab.virtualisation.quadlet.containers.vaultwarden.containerConfig.notify == "healthy")
  "vaultwarden must publish on loopback only and report ready through its health check";
  assert lib.assertMsg (lib.all (c: (c.containerConfig.notify or null) != "healthy" || (c.containerConfig.healthCmd or null) != null) (lib.attrValues lab.virtualisation.quadlet.containers))
  "a container with notify = healthy needs an explicit healthCmd: podman ignores the image HEALTHCHECK of OCI images and the unit fails to start";
  assert lib.assertMsg (!(lab.virtualisation.quadlet.pods.aiia.podConfig ? networks) || lab.virtualisation.quadlet.pods.aiia.podConfig.networks == [])
  "the aiia pod must not join the proxy network: mysql and redis would be reachable from other containers";
  assert lib.assertMsg (let g = lab.virtualisation.quadlet.containers.aiia-ghost; in g.containerConfig.tmpfses == ["/home/ghost/content/public"] && g.serviceConfig.RestartSec == 5)
  "aiia-ghost writes generated assets to content/public (tmpfs) and restarts after 5s";
  assert lib.assertMsg (let b = lab.systemd.services.restic-backups-peer; in lib.elem "aiia-mysql.service" b.after && lib.elem "vaultwarden.service" b.after && lib.hasInfix "podman exec aiia-mysql" lab.services.restic.backups.peer.backupPrepareCommand)
  "restic-backups-peer must order after the quadlet units and dump aiia-mysql with podman exec";
  assert lib.assertMsg (let s = lab.systemd.services.mrija-archive-sync; in !(lib.elem "mrija-archive.service" s.requires) && lib.elem "mrija-archive.service" s.wants)
  "mrija-archive-sync must only want the container: requires would stop the sync whenever the container restarts";
  assert lib.assertMsg (rootContainers == [])
  "every lab quadlet container must set containerConfig.user and no userns (found: ${toString rootContainers})";
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

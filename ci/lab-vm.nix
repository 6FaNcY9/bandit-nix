# Lab VM test (spec section 6): the real bandit-lab module list boots in a QEMU
# nixosTest. QEMU, not nspawn: Podman inside an nspawn test container would need
# nested user namespaces, and nspawn tests need the uid-range system feature,
# which the laptop's daemon lacks. Secrets are absent (no age key in the VM), so
# units that need one fail and nothing here asserts on them; Docker containers
# cannot pull images offline and are not asserted either.
{
  pkgs,
  modules,
  specialArgs,
}: let
  canaryImage = pkgs.dockerTools.buildImage {
    name = "canary";
    tag = "test";
    copyToRoot = [pkgs.busybox (pkgs.writeTextDir "srv/index.html" "canary\n")];
    config.Cmd = ["httpd" "-f" "-p" "8080" "-h" "/srv"];
  };
in
  pkgs.testers.runNixOSTest {
    name = "lab-vm";
    node = {
      inherit specialArgs;
      # modules/system/core.nix sets nixpkgs.config (unfree predicate).
      pkgsReadOnly = false;
    };
    nodes.lab = {
      imports = modules;
      # The test VM forces videoDrivers to modesetting and has no GPU, so the toolkit's driver assertion cannot hold.
      hardware.nvidia-container-toolkit.enable = pkgs.lib.mkForce false;
      virtualisation = {
        memorySize = 4096;
        cores = 2;
        # Test-only container: no hardening flags set, so it carries the defaults from modules/server/containers.nix.
        quadlet.containers.canary.containerConfig = {
          image = "docker-archive:${canaryImage}";
          publishPorts = ["127.0.0.1:8080:8080"];
        };
      };
    };
    testScript = ''
      import json

      lab.wait_for_unit("multi-user.target")
      lab.wait_for_unit("sshd.service")
      lab.wait_for_unit("docker.service")
      lab.wait_for_unit("podman.socket")
      lab.wait_for_unit("canary.service")
      lab.wait_until_succeeds("curl -fsS http://127.0.0.1:8080/ | grep canary")

      host = json.loads(lab.succeed("podman inspect canary"))[0]["HostConfig"]
      assert "no-new-privileges" in host["SecurityOpt"], host["SecurityOpt"]
      assert host["ReadonlyRootfs"] is True, host["ReadonlyRootfs"]
      assert host["CapDrop"] and not host["CapAdd"], (host["CapDrop"], host["CapAdd"])

      # Docker-API compatibility of the Podman socket: precondition for Traefik's
      # docker provider and the Beszel agent in phase 4.
      lab.succeed("curl -fsS --unix-socket /run/podman/podman.sock http://d/v1.41/containers/json | grep canary")

      # Published on loopback only: the VM's own LAN address must not answer.
      lan = lab.succeed("ip -4 -o addr show eth1 | awk '{print $4}' | cut -d/ -f1").strip()
      assert lan, "eth1 has no IPv4 address"  # an empty address would make the curl below fail vacuously
      lab.fail(f"curl -fsS --max-time 3 http://{lan}:8080/")
    '';
  }

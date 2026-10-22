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
  # The VM has no network: the lab's own service images come in as fixed-output
  # fetches and replace the registry references for the test only. Keep the
  # digests equal to the service modules (bump both together).
  pulled = name: tag: digest: hash:
    pkgs.dockerTools.pullImage {
      imageName = name;
      imageDigest = digest;
      inherit hash;
      finalImageName = name;
      finalImageTag = tag;
    };
  images = {
    prometheus = pulled "prom/prometheus" "v3.13.2" "sha256:508729e0e2d18e11fd742a5a5ca70e557b940a93948c3c95fd0123a6fd538b69" "sha256-/dxFY1+okZ7sP1/ZR0P/z4o9GWI8Z7w0qM1IqR+qjVQ=";
    grafana = pulled "grafana/grafana-oss" "13.0.2" "sha256:5dad0df181cb644a14e13617b913b261a54f7d4fd4510721dba420929f35bea2" "sha256-v37NASJVQdMc14u5xRzRpaapA4s2lQCNpk+m7P+omXY=";
    blackbox-exporter = pulled "prom/blackbox-exporter" "v0.28.0" "sha256:e753ff9f3fc458d02cca5eddab5a77e1c175eee484a8925ac7d524f04366c2fc" "sha256-CrLkLkQ2w9goBAtaClW4aQ2IXWwPgkrdhE6fOfh4abg=";
    node-exporter = pulled "prom/node-exporter" "v1.12.1" "sha256:1b4e4438faca4dd7e001dd445d161a4a2091b0fededa84093b3a8dfeae1f1be0" "sha256-NvmqPfm027ksBCJMZCphTHF1empR65uLf99DNndEWOI=";
  };
in
  pkgs.testers.runNixOSTest {
    name = "lab-vm";
    node = {
      inherit specialArgs;
      # modules/system/core.nix sets nixpkgs.config (unfree predicate).
      pkgsReadOnly = false;
    };
    # Second host on the test network: proves a Podman container forwards out
    # while docker.service owns FORWARD DROP.
    nodes.peer = {
      networking.firewall.allowedTCPPorts = [80];
      systemd.services.peer-httpd = {
        wantedBy = ["multi-user.target"];
        serviceConfig.ExecStart = "${pkgs.busybox}/bin/httpd -f -p 80 -h ${pkgs.writeTextDir "index.html" "peer\n"}";
      };
    };
    nodes.lab = {config, ...}: {
      imports = modules;
      # The test VM forces videoDrivers to modesetting and has no GPU, so the toolkit's driver assertion cannot hold.
      hardware.nvidia-container-toolkit.enable = pkgs.lib.mkForce false;
      virtualisation = {
        memorySize = 4096;
        cores = 2;
        # Podman's image store lives on the VM disk; the default 1 GiB cannot hold the service images.
        diskSize = 8192;
        # Test-only containers: no hardening flags set, so they carry the defaults from modules/server/containers.nix.
        quadlet.containers =
          pkgs.lib.mapAttrs (_: image: {containerConfig.image = pkgs.lib.mkForce "docker-archive:${image}";}) images
          // {
            canary.containerConfig = {
              image = "docker-archive:${canaryImage}";
              publishPorts = ["127.0.0.1:8080:8080"];
              user = "65534:65534";
              networks = [config.virtualisation.quadlet.networks.proxy.ref];
            };
            canary2.containerConfig = {
              image = "docker-archive:${canaryImage}";
              user = "65534:65534";
              networks = [config.virtualisation.quadlet.networks.proxy.ref];
            };
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

      # Container -> container by name over the podman proxy network (aardvark DNS + bridge forward),
      # and container -> another host while docker.service owns FORWARD DROP (netavark's NETAVARK_FORWARD chain).
      lab.wait_for_unit("proxy-network.service")
      lab.wait_for_unit("canary2.service")
      lab.succeed("podman exec canary2 wget -qO- http://canary:8080/ | grep canary")
      # The lab's Docker sets the FORWARD policy to DROP; the VM's boot order may leave it ACCEPT and
      # the jump order of Docker's and netavark's chains varies per boot. Force the worst case so the
      # proof below does not depend on either.
      lab.succeed("iptables -P FORWARD DROP")
      peer.wait_for_unit("peer-httpd.service")
      peer_ip = peer.wait_until_succeeds("ip -4 -o addr | grep -o '192\\.168\\.1\\.[0-9]*' | head -1").strip()
      lab.succeed(f"podman exec canary2 wget -qO- http://{peer_ip}/ | grep peer")
      # No published port of the real lab configuration answers on the LAN address.
      for p in lab.succeed("podman ps --format '{{.Ports}}'").split():
          port = p.split("->")[0].rsplit(":", 1)[-1]
          lab.fail(f"curl -fsS --max-time 3 http://{lan}:{port}/")

      # Real service: the monitoring pod needs no secret except Grafana (not asserted).
      lab.wait_for_unit("monitoring-pod.service")
      lab.wait_for_unit("prometheus.service")
      lab.wait_for_unit("node-exporter.service")
      lab.wait_until_succeeds("curl -fsS http://127.0.0.1:9115/metrics | grep -q blackbox")
      lab.wait_until_succeeds("podman exec prometheus wget -qO- http://localhost:9090/-/ready")
      lab.succeed("podman exec prometheus wget -qO- http://localhost:9100/metrics | grep node_scrape_collector_success >/dev/null")
    '';
  }

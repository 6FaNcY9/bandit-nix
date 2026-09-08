{
  pkgs,
  sops-nix,
}: let
  # These disposable keys and plaintext values are public test fixtures only.
  fixtures =
    pkgs.runCommand "lab-reliability-sops-fixtures" {
      nativeBuildInputs = [pkgs.age pkgs.sops];
    } ''
      mkdir -p "$out"
      age-keygen -o "$out/key.txt"
      recipient=$(age-keygen -y "$out/key.txt")
      for value in initial rotated; do
        printf 'token: %s\n' "$value" > "$value.yaml"
        sops --encrypt --age "$recipient" --input-type yaml --output-type yaml \
          "$value.yaml" > "$out/$value.yaml"
      done
    '';
  fixtureServer = pkgs.writeText "lab-reliability-http.py" ''
    import http.server
    import sys

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(int(sys.argv[2]))
            if sys.argv[2] == "302":
                self.send_header("Location", "http://127.0.0.1:8080/")
            self.end_headers()
            self.wfile.write(b"fixture\n")

    http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
  '';
in
  pkgs.testers.runNixOSTest {
    name = "lab-reliability";
    # Shared CI runners can use QEMU's software fallback when KVM is unavailable.
    requiredFeatures.kvm = false;
    nodes.machine = {
      config,
      lib,
      ...
    }: {
      imports = [sops-nix.nixosModules.sops];
      environment.etc."lab-test-age-key".source = "${fixtures}/key.txt";
      services.prometheus.exporters.blackbox = {
        enable = true;
        configFile = ../hosts/bandit-lab/blackbox.yml;
      };
      systemd.services = {
        origin-fixture = {
          wantedBy = ["multi-user.target"];
          serviceConfig.ExecStart = "${pkgs.python3}/bin/python ${fixtureServer} 8080 200";
        };
        edge-fixture = {
          wantedBy = ["multi-user.target"];
          serviceConfig.ExecStart = "${pkgs.python3}/bin/python ${fixtureServer} 8081 302";
        };
        secret-consumer = {
          wantedBy = ["multi-user.target"];
          serviceConfig = {
            EnvironmentFile = config.sops.templates."consumer.env".path;
            StateDirectory = "secret-consumer";
          };
          script = ''
            printf '%s\n' "$TOKEN" >> /var/lib/secret-consumer/starts
            exec ${pkgs.coreutils}/bin/sleep infinity
          '';
        };
      };
      sops = {
        defaultSopsFile = "${fixtures}/initial.yaml";
        age.keyFile = "/etc/lab-test-age-key";
        age.sshKeyPaths = [];
        gnupg.sshKeyPaths = [];
        secrets.token = {};
        templates."consumer.env" = {
          content = "TOKEN=${config.sops.placeholder.token}\n";
          restartUnits = ["secret-consumer.service"];
        };
      };
      specialisation.rotated.configuration.sops.defaultSopsFile = lib.mkForce "${fixtures}/rotated.yaml";
    };
    testScript = ''
      import shlex

      start_all()
      machine.wait_for_unit("prometheus-blackbox-exporter.service")
      machine.wait_for_unit("secret-consumer.service")
      machine.wait_for_open_port(8080)
      machine.wait_for_open_port(8081)
      machine.wait_for_open_port(9115)

      def probe(module, port):
          url = f"http://127.0.0.1:9115/probe?module={module}&target=http://127.0.0.1:{port}/"
          metrics = machine.succeed("curl --fail --silent " + shlex.quote(url))
          return next(line for line in metrics.splitlines() if line.startswith("probe_success "))

      with subtest("origin probes reject login redirects"):
          assert probe("http_origin", 8080) == "probe_success 1"
          assert probe("http_origin", 8081) == "probe_success 0"
          assert probe("http_wan", 8081) == "probe_success 1"

      with subtest("edge reachability cannot hide stopped origin"):
          machine.succeed("systemctl stop origin-fixture.service")
          assert probe("http_origin", 8080) == "probe_success 0"
          assert probe("http_wan", 8081) == "probe_success 1"

      with subtest("rendered secret rotation restarts the running consumer"):
          machine.wait_until_succeeds("test -f /var/lib/secret-consumer/starts")
          assert machine.succeed("cat /var/lib/secret-consumer/starts").splitlines() == ["initial"]
          initial_invocation = machine.succeed("systemctl show secret-consumer -p InvocationID --value").strip()
          rotated = "/run/current-system/specialisation/rotated/bin/switch-to-configuration test"
          machine.succeed(rotated)
          machine.wait_for_unit("secret-consumer.service")
          machine.wait_until_succeeds("test $(wc -l < /var/lib/secret-consumer/starts) -eq 2")
          assert machine.succeed("cat /var/lib/secret-consumer/starts").splitlines() == ["initial", "rotated"]
          assert machine.succeed("cat /run/secrets/rendered/consumer.env") == "TOKEN=rotated\n"
          assert machine.succeed("systemctl show secret-consumer -p InvocationID --value").strip() != initial_invocation

      with subtest("unchanged secret does not restart the consumer"):
          invocation = machine.succeed("systemctl show secret-consumer -p InvocationID --value").strip()
          machine.succeed("/run/current-system/bin/switch-to-configuration test")
          assert machine.succeed("systemctl show secret-consumer -p InvocationID --value").strip() == invocation
          assert machine.succeed("cat /var/lib/secret-consumer/starts").splitlines() == ["initial", "rotated"]
    '';
  }

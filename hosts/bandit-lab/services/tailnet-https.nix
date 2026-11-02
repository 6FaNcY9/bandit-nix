{
  config,
  pkgs,
  repoConfig,
  ...
}: let
  fqdn = repoConfig.lab.tailnetFqdn;
  # Tailnet-only HTTPS for the admin web UIs that have no public hostname
  # (same mechanism as ntfy 8447, mcbots 8445/8446 and the Minecraft map 8443):
  # https://<fqdn>:<port>. Tailscale terminates TLS and the tailnet ACL decides
  # who may connect; nothing is opened in the host firewall. Services with a
  # Cloudflare hostname (grafana, vault, aiia, mail-archive) keep using it;
  # grafana is also here because its Access gate is in the way on the phone.
  serves = {
    "8448" = "http://127.0.0.1:3000"; # grafana
    "8449" = "http://127.0.0.1:8090"; # beszel
    "8450" = "https+insecure://127.0.0.1:9090"; # cockpit (self-signed cert on loopback)
  };
  serve = port: target: ''
    if ! timeout 30 tailscale serve --bg --https=${port} ${target}; then
      echo "WARNING: could not publish ${target} on tailnet HTTPS port ${port}; enable Serve and HTTPS Certificates in the Tailscale admin console, then restart lab-https" >&2
    fi
  '';
in {
  # Cockpit checks the Origin header of its websocket: allow the serve URL.
  services.cockpit.allowed-origins = ["https://${fqdn}:8450"];

  systemd.services.lab-https = {
    description = "Tailnet-only HTTPS for the lab admin UIs (grafana, beszel, cockpit)";
    after = ["tailscaled.service"];
    wants = ["tailscaled.service"];
    wantedBy = ["multi-user.target"];
    path = [config.services.tailscale.package pkgs.coreutils];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "120s";
    };
    script = pkgs.lib.concatStrings (pkgs.lib.mapAttrsToList serve serves);
    preStop = pkgs.lib.concatMapStrings (port: "timeout 30 tailscale serve --https=${port} off || true\n") (builtins.attrNames serves);
  };
}

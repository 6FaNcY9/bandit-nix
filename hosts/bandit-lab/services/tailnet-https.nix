{
  config,
  pkgs,
  repoConfig,
  ...
}: let
  # Service names live under the tailnet suffix, not under the host name.
  tailnet = pkgs.lib.removePrefix "bandit-lab." repoConfig.lab.tailnetFqdn;
  # Lab web UIs as named Tailscale Services: https://<name>.<tailnet>.ts.net.
  # Services show up in the admin console, the name needs no port, and the
  # tag-based host (bandit-lab carries tag:lab, services use tag:lab-svc) is
  # decided by the tailnet policy. Nothing is opened in the host firewall.
  # The services must be defined in the admin console first (see
  # docs/runbooks/tailnet-services.md). bandit-craft's per-port serves (map
  # 8443, mcbots 8445/8446) and ntfy 8447 are separate and untouched: this unit
  # only ever calls `serve --service` / `serve clear svc:<name>`.
  services = {
    grafana = "http://127.0.0.1:3000";
    beszel = "http://127.0.0.1:8090";
    cockpit = "https+insecure://127.0.0.1:9090"; # self-signed cert on loopback
    comfyui = "http://127.0.0.1:8188"; # services/comfyui, Jerry may reach this one (policy grant svc:comfyui)
  };
  serve = name: target: ''
    if ! timeout 30 tailscale serve --service=svc:${name} --https=443 ${target}; then
      echo "WARNING: could not advertise svc:${name} (${target}); define the service with tag:lab-svc in the Tailscale admin console and check that bandit-lab carries tag:lab, then restart lab-services" >&2
    fi
  '';
in {
  # Cockpit checks the Origin header of its websocket: allow the service URL.
  services.cockpit.allowed-origins = ["https://cockpit.${tailnet}"];

  systemd.services.lab-services = {
    description = "Tailscale Services for the lab admin UIs (grafana, beszel, cockpit)";
    after = ["tailscaled.service"];
    wants = ["tailscaled.service"];
    wantedBy = ["multi-user.target"];
    path = [config.services.tailscale.package pkgs.coreutils];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "120s";
    };
    script = pkgs.lib.concatStrings (pkgs.lib.mapAttrsToList serve services);
    preStop = pkgs.lib.concatMapStrings (name: "timeout 30 tailscale serve clear svc:${name} || true\n") (builtins.attrNames services);
  };
}

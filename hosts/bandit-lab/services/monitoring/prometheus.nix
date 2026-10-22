{pkgs, ...}: let
  # Prometheus scrape configuration, linked to a stable path for the
  # host-managed monitoring stack (docs/runbooks/monitoring.md).
  prometheusYml = pkgs.writeText "prometheus.yml" ''
    global:
      scrape_interval: 15s

    scrape_configs:
      - job_name: prometheus
        static_configs:
          - targets: ["localhost:9090"]

      - job_name: node
        static_configs:
          - targets: ["localhost:9100"]

      # Public endpoint reachability. Cloudflare Access can return a login
      # redirect without contacting the tunnel or origin application.
      - job_name: blackbox-wan
        metrics_path: /probe
        params:
          module: [http_wan]
        static_configs:
          - targets:
              - https://vault.atmosphaere.at
              - https://grafana.atmosphaere.at
              - https://mail-archive.bandit-lab.mrija.org
        relabel_configs:
          - source_labels: [__address__]
            target_label: __param_target
          - source_labels: [__param_target]
            target_label: instance
          - target_label: __address__
            replacement: localhost:9115

      # Direct container endpoints bypass Traefik, the tunnel, and Access.
      # Everything in this pod is on localhost; services on the proxy network
      # are added by name once they run on Podman (vaultwarden: phase 4 task 5).
      - job_name: blackbox-origin
        metrics_path: /probe
        params:
          module: [http_origin]
        static_configs:
          - targets:
              - http://localhost:3000/api/health
        relabel_configs:
          - source_labels: [__address__]
            target_label: __param_target
          - source_labels: [__param_target]
            target_label: instance
          - target_label: __address__
            replacement: localhost:9115

      - job_name: blackbox-exporter
        static_configs:
          - targets: ["localhost:9115"]
  '';

  # Shared with the regression test so it exercises the deployed modules.
  blackboxYml = ../blackbox/blackbox.yml;
in {
  _module.args.monitoringPrometheus = {inherit prometheusYml blackboxYml;};
}

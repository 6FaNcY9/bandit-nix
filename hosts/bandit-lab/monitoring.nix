{pkgs, ...}: let
  # Prometheus scrape configuration, linked to a stable path for the
  # Portainer-managed monitoring stack (docs/runbooks/monitoring.md).
  prometheusYml = pkgs.writeText "prometheus.yml" ''
    global:
      scrape_interval: 15s

    scrape_configs:
      - job_name: prometheus
        static_configs:
          - targets: ["localhost:9090"]

      - job_name: node
        static_configs:
          - targets: ["node-exporter:9100"]

      - job_name: cadvisor
        static_configs:
          - targets: ["cadvisor:8080"]
  '';

  # Pre-wires the in-stack Prometheus as Grafana's default datasource.
  grafanaProvisioning = pkgs.writeTextDir "datasources/prometheus.yaml" ''
    apiVersion: 1
    datasources:
      - name: Prometheus
        type: prometheus
        access: proxy
        url: http://prometheus:9090
        isDefault: true
  '';
in {
  # Consumed by the Portainer "monitoring" stack via bind mount
  # (GF_SECURITY_ADMIN_PASSWORD__FILE). Owner 472 = grafana container user.
  sops.secrets."grafana-admin-password" = {
    owner = "472";
    # sops-nix derives `group` from users.users.${owner} by default; pin it
    # explicitly so a numeric (container-only) uid does not fail evaluation.
    group = "472";
    mode = "0400";
  };

  systemd.tmpfiles.rules = [
    "d /srv/containers/monitoring 0755 root root -"
    "d /srv/containers/monitoring/grafana 0750 472 472 -"
    "d /srv/containers/monitoring/prometheus 0750 65534 65534 -"
    # Stable paths for Portainer bind mounts; targets update on rebuild.
    "L+ /srv/containers/monitoring/prometheus.yml - - - - ${prometheusYml}"
    "L+ /srv/containers/monitoring/grafana-provisioning - - - - ${grafanaProvisioning}"
  ];
}

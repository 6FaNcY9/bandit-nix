{
  monitoringPrometheus,
  monitoringDashboards,
  monitoringProvisioning,
  ...
}: {
  imports = [
    ./prometheus.nix
    ./dashboards.nix
    ./alerting.nix
  ];

  # Host-side grafana system user so sops-install-secrets can resolve the
  # secret owner by name (a bare numeric uid fails activation: "failed to
  # lookup user '472'"). uid/gid match the grafana container user so the
  # bind-mounted files stay readable inside the container.
  users.users.grafana = {
    isSystemUser = true;
    uid = 472;
    group = "grafana";
  };
  users.groups.grafana.gid = 472;

  # Consumed by the Portainer "monitoring" stack via bind mount
  # (GF_SECURITY_ADMIN_PASSWORD__FILE).
  sops.secrets."grafana-admin-password" = {
    owner = "grafana";
    group = "grafana";
    mode = "0400";
  };

  systemd.tmpfiles.rules = let
    inherit
      (monitoringPrometheus)
      prometheusYml
      blackboxYml
      ;
    inherit (monitoringDashboards) grafanaDashboards;
    inherit (monitoringProvisioning) grafanaProvisioning;
  in [
    "d /srv/containers/monitoring 0755 root root -"
    "d /srv/containers/monitoring/grafana 0750 472 472 -"
    "d /srv/containers/monitoring/prometheus 0750 65534 65534 -"
    # Stable paths for Portainer bind mounts; targets update on rebuild.
    "L+ /srv/containers/monitoring/prometheus.yml - - - - ${prometheusYml}"
    "L+ /srv/containers/monitoring/blackbox.yml - - - - ${blackboxYml}"
    "L+ /srv/containers/monitoring/grafana-provisioning - - - - ${grafanaProvisioning}"
    "L+ /srv/containers/monitoring/grafana-dashboards - - - - ${grafanaDashboards}"
  ];
}

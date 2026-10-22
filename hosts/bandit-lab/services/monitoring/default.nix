# Monitoring stack as a Podman pod (phase 4): the four containers share one
# network namespace, so Prometheus scrapes its exporters on localhost and only
# Grafana and blackbox are published, on loopback, for Traefik and the host.
# Config files are mounted straight from the store: a changed file changes the
# unit text, so the container restarts on activation (a stable symlink would not).
{
  config,
  monitoringPrometheus,
  monitoringDashboards,
  monitoringProvisioning,
  ...
}: let
  inherit (config.virtualisation.quadlet) networks pods;
  inherit (monitoringPrometheus) prometheusYml blackboxYml;
  inherit (monitoringDashboards) grafanaDashboards;
  inherit (monitoringProvisioning) grafanaProvisioning;
  data = "/srv/containers/monitoring";
  secret = config.sops.secrets."grafana-admin-password".path;
in {
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

  # Consumed by the "monitoring" Compose stack via bind mount
  # (GF_SECURITY_ADMIN_PASSWORD__FILE).
  sops.secrets."grafana-admin-password" = {
    owner = "grafana";
    group = "grafana";
    mode = "0400";
    restartUnits = ["grafana.service"];
  };

  systemd.tmpfiles.rules = [
    "d /srv/containers/monitoring 0755 root root -"
    "d /srv/containers/monitoring/grafana 0750 472 472 -"
    "d /srv/containers/monitoring/prometheus 0750 65534 65534 -"
  ];

  virtualisation.quadlet = {
    pods.monitoring.podConfig = {
      networks = [networks.proxy.ref];
      publishPorts = ["127.0.0.1:3000:3000" "127.0.0.1:9115:9115"];
    };
    containers = {
      prometheus.containerConfig = {
        image = "docker.io/prom/prometheus:v3.13.2@sha256:508729e0e2d18e11fd742a5a5ca70e557b940a93948c3c95fd0123a6fd538b69";
        pod = pods.monitoring.ref;
        user = "65534:65534";
        exec = ["--config.file=/etc/prometheus/prometheus.yml" "--storage.tsdb.retention.time=30d"];
        volumes = [
          "${prometheusYml}:/etc/prometheus/prometheus.yml:ro"
          "${data}/prometheus:/prometheus"
        ];
      };
      grafana = {
        containerConfig = {
          image = "docker.io/grafana/grafana-oss:13.0.2@sha256:5dad0df181cb644a14e13617b913b261a54f7d4fd4510721dba420929f35bea2";
          pod = pods.monitoring.ref;
          user = "472:472";
          environments = {
            GF_SECURITY_ADMIN_PASSWORD__FILE = secret;
            GF_USERS_ALLOW_SIGN_UP = "false";
          };
          volumes = [
            "${data}/grafana:/var/lib/grafana"
            "${grafanaProvisioning}:/etc/grafana/provisioning:ro"
            "${grafanaDashboards}:/var/lib/grafana-dashboards:ro"
            "${secret}:${secret}:ro"
          ];
        };
        unitConfig = {
          After = ["prometheus.service"];
          Wants = ["prometheus.service"];
        };
      };
      blackbox-exporter.containerConfig = {
        image = "docker.io/prom/blackbox-exporter:v0.28.0@sha256:e753ff9f3fc458d02cca5eddab5a77e1c175eee484a8925ac7d524f04366c2fc";
        pod = pods.monitoring.ref;
        user = "65534:65534";
        exec = ["--config.file=/etc/blackbox_exporter/config.yml"];
        volumes = ["${blackboxYml}:/etc/blackbox_exporter/config.yml:ro"];
      };
      node-exporter.containerConfig = {
        image = "docker.io/prom/node-exporter:v1.12.1@sha256:1b4e4438faca4dd7e001dd445d161a4a2091b0fededa84093b3a8dfeae1f1be0";
        pod = pods.monitoring.ref;
        user = "65534:65534";
        # Host pid namespace and rootfs for host metrics; the D-Bus socket for
        # the systemd collector (node-exporter hard-codes /var/run/dbus).
        podmanArgs = ["--pid=host"];
        exec = [
          "--path.rootfs=/host"
          "--collector.systemd"
          "--collector.systemd.unit-include=(sshd|docker|containerd|podman|traefik|cloudflared.*|postgresql|smbd|nmbd|ollama|tailscaled|lab-update-.*|restic-backups-lab|restic-check|.*-pod|.*-network|prometheus|grafana|blackbox-exporter|node-exporter|mrija-archive|vaultwarden)\\.(service|timer)"
        ];
        volumes = [
          "/:/host:ro,rslave"
          "/run/dbus:/var/run/dbus:ro"
        ];
      };
    };
  };
}

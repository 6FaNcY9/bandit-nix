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

      # End-to-end WAN probes: DNS → Cloudflare Tunnel → Traefik → app.
      # Access-gated apps answer 302/303 to the login redirect, which still
      # proves the whole path works (see the blackbox module below).
      - job_name: blackbox-wan
        metrics_path: /probe
        params:
          module: [http_wan]
        static_configs:
          - targets:
              - https://vault.bandit-lab.mrija.org
              - https://grafana.bandit-lab.mrija.org
              - https://mail.bandit-lab.mrija.org
              - https://portainer.bandit-lab.mrija.org
        relabel_configs:
          - source_labels: [__address__]
            target_label: __param_target
          - source_labels: [__param_target]
            target_label: instance
          - target_label: __address__
            replacement: blackbox-exporter:9115

      - job_name: blackbox-exporter
        static_configs:
          - targets: ["blackbox-exporter:9115"]
  '';

  blackboxYml = pkgs.writeText "blackbox.yml" ''
    modules:
      http_wan:
        prober: http
        timeout: 10s
        http:
          # 200 = app served directly; 302/303 = Cloudflare Access or app
          # login redirect. All three mean the WAN path is healthy.
          valid_status_codes: [200, 302, 303]
          follow_redirects: false
          preferred_ip_protocol: ip4
  '';

  # grafana.com id 1860 rev 45 (Node Exporter Full). Pinned by hash; bump the
  # revision deliberately. Uses a datasource template variable, so it picks
  # up the provisioned Prometheus datasource without patching.
  dashboardNodeExporter = pkgs.fetchurl {
    name = "grafana-dashboard-node-exporter-full.json";
    url = "https://grafana.com/api/dashboards/1860/revisions/45/download";
    hash = "sha256-GExrdAnzBtp1Ul13cvcZRbEM6iOtFrXXjEaY6g6lGYY=";
  };

  # grafana.com id 14282 rev 1 (Cadvisor exporter). The upstream JSON carries
  # an import input (''${DS_PROMETHEUS}) that file provisioning cannot fill;
  # pin it to the provisioned datasource uid and drop import-only metadata.
  dashboardCadvisor = pkgs.runCommand "grafana-dashboard-cadvisor.json" {} ''
    ${pkgs.jq}/bin/jq '
      del(.__inputs, .__requires, .__elements)
      | walk(if . == "''${DS_PROMETHEUS}" then "prometheus" else . end)
    ' ${
      pkgs.fetchurl {
        name = "grafana-dashboard-cadvisor-raw.json";
        url = "https://grafana.com/api/dashboards/14282/revisions/1/download";
        hash = "sha256-dqhaC4r4rXHCJpASt5y3EZXW00g5fhkQM+MgNcgX1c0=";
      }
    } > $out
  '';

  # Small purpose-built dashboard for the blackbox WAN probes (community
  # blackbox dashboards assume datasource UIDs we do not control).
  dashboardWanProbes = pkgs.writeText "grafana-dashboard-wan-probes.json" (builtins.toJSON {
    title = "WAN Probes";
    uid = "wan-probes";
    schemaVersion = 39;
    version = 1;
    editable = false;
    timezone = "browser";
    refresh = "30s";
    time = {
      from = "now-6h";
      to = "now";
    };
    panels = [
      {
        id = 1;
        type = "stat";
        title = "Reachability";
        datasource = {
          type = "prometheus";
          uid = "prometheus";
        };
        gridPos = {
          h = 8;
          w = 24;
          x = 0;
          y = 0;
        };
        targets = [
          {
            refId = "A";
            expr = ''probe_success{job="blackbox-wan"}'';
            legendFormat = "{{instance}}";
          }
        ];
        fieldConfig = {
          defaults = {
            mappings = [
              {
                type = "value";
                options = {
                  "0" = {
                    text = "DOWN";
                    color = "red";
                  };
                  "1" = {
                    text = "UP";
                    color = "green";
                  };
                };
              }
            ];
            thresholds = {
              mode = "absolute";
              steps = [
                {
                  color = "red";
                  value = null;
                }
                {
                  color = "green";
                  value = 1;
                }
              ];
            };
          };
          overrides = [];
        };
        options = {
          colorMode = "background";
          graphMode = "none";
          justifyMode = "auto";
          orientation = "auto";
          reduceOptions = {
            calcs = ["lastNotNull"];
            fields = "";
            values = false;
          };
          textMode = "value";
        };
      }
      {
        id = 2;
        type = "timeseries";
        title = "Probe duration";
        datasource = {
          type = "prometheus";
          uid = "prometheus";
        };
        gridPos = {
          h = 8;
          w = 12;
          x = 0;
          y = 8;
        };
        targets = [
          {
            refId = "A";
            expr = ''probe_duration_seconds{job="blackbox-wan"}'';
            legendFormat = "{{instance}}";
          }
        ];
        fieldConfig = {
          defaults = {unit = "s";};
          overrides = [];
        };
        options = {
          legend = {
            displayMode = "list";
            placement = "bottom";
            showLegend = true;
          };
          tooltip = {
            mode = "multi";
            sort = "none";
          };
        };
      }
      {
        id = 3;
        type = "timeseries";
        title = "TLS certificate expiry";
        datasource = {
          type = "prometheus";
          uid = "prometheus";
        };
        gridPos = {
          h = 8;
          w = 12;
          x = 12;
          y = 8;
        };
        targets = [
          {
            refId = "A";
            expr = ''(probe_ssl_earliest_cert_expiry{job="blackbox-wan"} - time()) / 86400'';
            legendFormat = "{{instance}}";
          }
        ];
        fieldConfig = {
          defaults = {unit = "d";};
          overrides = [];
        };
        options = {
          legend = {
            displayMode = "list";
            placement = "bottom";
            showLegend = true;
          };
          tooltip = {
            mode = "multi";
            sort = "none";
          };
        };
      }
    ];
  });

  # Datasource + dashboard provider + alert rules, file-provisioned so the
  # stack is reproducible from a fresh volume. NOTE: the result must contain
  # real files (cp -L), not symlinkJoin/linkFarm links — Docker bind-mounts
  # the directory, and symlinks pointing into /nix/store would dangle inside
  # the container.
  grafanaProvisioning = let
    datasources = pkgs.writeTextDir "datasources/prometheus.yaml" ''
      apiVersion: 1
      datasources:
        - name: Prometheus
          uid: prometheus
          type: prometheus
          access: proxy
          url: http://prometheus:9090
          isDefault: true
    '';
    dashboards = pkgs.writeTextDir "dashboards/bandit-lab.yaml" ''
      apiVersion: 1
      providers:
        - name: bandit-lab
          type: file
          disableDeletion: true
          editable: false
          updateIntervalSeconds: 60
          options:
            path: /var/lib/grafana-dashboards
            foldersFromFilesStructure: false
    '';
    alerting = pkgs.writeTextDir "alerting/bandit-lab.yaml" ''
      apiVersion: 1
      groups:
        - orgId: 1
          name: bandit-lab
          folder: Bandit Lab
          interval: 1m
          rules:
            - uid: bandit-lab-scrape-down
              title: Scrape target down
              condition: C
              for: 5m
              labels:
                severity: critical
              annotations:
                summary: "Prometheus cannot scrape {{ $labels.job }} ({{ $labels.instance }})"
              data:
                - refId: A
                  relativeTimeRange: {from: 300, to: 0}
                  datasourceUid: prometheus
                  model:
                    editorMode: code
                    expr: up
                    instant: true
                    range: false
                    refId: A
                    intervalMs: 1000
                    maxDataPoints: 43200
                - refId: C
                  relativeTimeRange: {from: 300, to: 0}
                  datasourceUid: __expr__
                  model:
                    type: classic_conditions
                    refId: C
                    expression: A
                    intervalMs: 1000
                    maxDataPoints: 43200
                    datasource: {type: __expr__, uid: __expr__}
                    conditions:
                      - type: query
                        operator: {type: and}
                        query: {params: [C]}
                        reducer: {type: last, params: []}
                        evaluator: {type: lt, params: [1]}
            - uid: bandit-lab-wan-probe-down
              title: WAN probe failing
              condition: C
              for: 3m
              labels:
                severity: critical
              annotations:
                summary: "WAN path to {{ $labels.instance }} is failing"
              data:
                - refId: A
                  relativeTimeRange: {from: 300, to: 0}
                  datasourceUid: prometheus
                  model:
                    editorMode: code
                    expr: probe_success{job="blackbox-wan"}
                    instant: true
                    range: false
                    refId: A
                    intervalMs: 1000
                    maxDataPoints: 43200
                - refId: C
                  relativeTimeRange: {from: 300, to: 0}
                  datasourceUid: __expr__
                  model:
                    type: classic_conditions
                    refId: C
                    expression: A
                    intervalMs: 1000
                    maxDataPoints: 43200
                    datasource: {type: __expr__, uid: __expr__}
                    conditions:
                      - type: query
                        operator: {type: and}
                        query: {params: [C]}
                        reducer: {type: last, params: []}
                        evaluator: {type: lt, params: [1]}
            - uid: bandit-lab-disk-low
              title: Root filesystem almost full
              condition: C
              for: 15m
              labels:
                severity: warning
              annotations:
                summary: "Root filesystem below 15% free on {{ $labels.instance }}"
              data:
                - refId: A
                  relativeTimeRange: {from: 900, to: 0}
                  datasourceUid: prometheus
                  model:
                    editorMode: code
                    expr: node_filesystem_avail_bytes{mountpoint="/", fstype!="tmpfs"} / node_filesystem_size_bytes{mountpoint="/"} * 100
                    instant: true
                    range: false
                    refId: A
                    intervalMs: 1000
                    maxDataPoints: 43200
                - refId: C
                  relativeTimeRange: {from: 900, to: 0}
                  datasourceUid: __expr__
                  model:
                    type: classic_conditions
                    refId: C
                    expression: A
                    intervalMs: 1000
                    maxDataPoints: 43200
                    datasource: {type: __expr__, uid: __expr__}
                    conditions:
                      - type: query
                        operator: {type: and}
                        query: {params: [C]}
                        reducer: {type: last, params: []}
                        evaluator: {type: lt, params: [15]}
            - uid: bandit-lab-memory-low
              title: Memory almost exhausted
              condition: C
              for: 10m
              labels:
                severity: warning
              annotations:
                summary: "Available memory below 10% on {{ $labels.instance }}"
              data:
                - refId: A
                  relativeTimeRange: {from: 600, to: 0}
                  datasourceUid: prometheus
                  model:
                    editorMode: code
                    expr: node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100
                    instant: true
                    range: false
                    refId: A
                    intervalMs: 1000
                    maxDataPoints: 43200
                - refId: C
                  relativeTimeRange: {from: 600, to: 0}
                  datasourceUid: __expr__
                  model:
                    type: classic_conditions
                    refId: C
                    expression: A
                    intervalMs: 1000
                    maxDataPoints: 43200
                    datasource: {type: __expr__, uid: __expr__}
                    conditions:
                      - type: query
                        operator: {type: and}
                        query: {params: [C]}
                        reducer: {type: last, params: []}
                        evaluator: {type: lt, params: [10]}
    '';
  in
    pkgs.runCommand "grafana-provisioning" {} ''
      mkdir -p $out
      cp -rL ${datasources}/datasources $out/datasources
      cp -rL ${dashboards}/dashboards $out/dashboards
      cp -rL ${alerting}/alerting $out/alerting
    '';

  grafanaDashboards = pkgs.runCommand "grafana-dashboards" {} ''
    mkdir -p $out
    cp -L ${dashboardNodeExporter} $out/node-exporter-full.json
    cp -L ${dashboardCadvisor} $out/cadvisor-exporter.json
    cp -L ${dashboardWanProbes} $out/wan-probes.json
  '';
in {
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

  systemd.tmpfiles.rules = [
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

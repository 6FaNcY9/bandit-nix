{pkgs, ...}: let
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
                    type: threshold
                    refId: C
                    expression: A
                    intervalMs: 1000
                    maxDataPoints: 43200
                    datasource: {type: __expr__, uid: __expr__}
                    conditions:
                      - evaluator: {type: lt, params: [1]}
            - uid: bandit-lab-wan-probe-down
              title: Public endpoint probe failing
              condition: C
              for: 3m
              labels:
                severity: critical
              annotations:
                summary: "Public endpoint HTTP probe for {{ $labels.instance }} is failing"
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
                    type: threshold
                    refId: C
                    expression: A
                    intervalMs: 1000
                    maxDataPoints: 43200
                    datasource: {type: __expr__, uid: __expr__}
                    conditions:
                      - evaluator: {type: lt, params: [1]}
            - uid: bandit-lab-origin-probe-down
              title: Direct origin probe failing
              condition: C
              for: 3m
              labels:
                severity: critical
              annotations:
                summary: "Direct origin HTTP probe for {{ $labels.instance }} is failing"
              data:
                - refId: A
                  relativeTimeRange: {from: 300, to: 0}
                  datasourceUid: prometheus
                  model:
                    editorMode: code
                    expr: probe_success{job="blackbox-origin"}
                    instant: true
                    range: false
                    refId: A
                    intervalMs: 1000
                    maxDataPoints: 43200
                - refId: C
                  relativeTimeRange: {from: 300, to: 0}
                  datasourceUid: __expr__
                  model:
                    type: threshold
                    refId: C
                    expression: A
                    intervalMs: 1000
                    maxDataPoints: 43200
                    datasource: {type: __expr__, uid: __expr__}
                    conditions:
                      - evaluator: {type: lt, params: [1]}
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
                    type: threshold
                    refId: C
                    expression: A
                    intervalMs: 1000
                    maxDataPoints: 43200
                    datasource: {type: __expr__, uid: __expr__}
                    conditions:
                      - evaluator: {type: lt, params: [15]}
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
                    type: threshold
                    refId: C
                    expression: A
                    intervalMs: 1000
                    maxDataPoints: 43200
                    datasource: {type: __expr__, uid: __expr__}
                    conditions:
                      - evaluator: {type: lt, params: [10]}
    '';
  in
    pkgs.runCommand "grafana-provisioning" {} ''
      mkdir -p $out
      cp -rL ${datasources}/datasources $out/datasources
      cp -rL ${dashboards}/dashboards $out/dashboards
      cp -rL ${alerting}/alerting $out/alerting
    '';
in {
  _module.args.monitoringProvisioning = {inherit grafanaProvisioning;};
}

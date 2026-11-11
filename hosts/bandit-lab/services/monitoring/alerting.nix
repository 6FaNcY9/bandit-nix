{pkgs, ...}: let
  # One instant query plus a threshold. noData is "Alerting" for series that must
  # exist (a missing unit metric must not sit green), "OK" where absence is healthy.
  rule = {
    uid,
    title,
    for,
    severity,
    summary,
    expr,
    op,
    threshold,
    noData,
    window ? 300,
  }:
    "            "
    + pkgs.lib.removeSuffix "\n            " (builtins.replaceStrings ["\n"] ["\n            "] ''
      - uid: ${uid}
        title: ${title}
        condition: C
        for: ${for}
        noDataState: ${noData}
        labels:
          severity: ${severity}
        annotations:
          summary: "${summary}"
        data:
          - refId: A
            relativeTimeRange: {from: ${toString window}, to: 0}
            datasourceUid: prometheus
            model:
              editorMode: code
              expr: ${expr}
              instant: true
              range: false
              refId: A
              intervalMs: 1000
              maxDataPoints: 43200
          - refId: C
            relativeTimeRange: {from: ${toString window}, to: 0}
            datasourceUid: __expr__
            model:
              type: threshold
              refId: C
              expression: A
              intervalMs: 1000
              maxDataPoints: 43200
              datasource: {type: __expr__, uid: __expr__}
              conditions:
                - evaluator: {type: ${op}, params: [${toString threshold}]}
    '');
  backupUnits = "restic-backups-peer.service|restic-backups-mc-public.service|minecraft-backup.service|postgresqlBackup.service";
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
          url: http://localhost:9090
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
      ${rule {
        uid = "bandit-lab-disk-fill-7d";
        title = "Root filesystem full within 7 days";
        for = "30m";
        severity = "warning";
        summary = "Root filesystem on {{ $labels.instance }} is projected to fill within 7 days";
        expr = ''predict_linear(node_filesystem_avail_bytes{mountpoint="/", fstype!="tmpfs"}[6h], 7*86400)'';
        op = "lt";
        threshold = 0;
        noData = "OK";
        window = 21600;
      }}
      ${rule {
        uid = "bandit-lab-backup-failed";
        title = "Backup job failed";
        for = "5m";
        severity = "critical";
        summary = "{{ $labels.name }} is in the failed state";
        expr = ''node_systemd_unit_state{name=~"${backupUnits}", state="failed"}'';
        op = "gt";
        threshold = 0;
        noData = "Alerting";
      }}
      ${rule {
        uid = "bandit-lab-backup-stale";
        title = "No backup run for 36 hours";
        for = "10m";
        severity = "critical";
        summary = "The {{ $labels.name }} has not fired for more than 36 hours";
        # A timer that has not fired since boot reports 0: count from boot then, so a reboot does not page.
        expr = ''time() - (node_systemd_timer_last_trigger_seconds{name=~"restic-backups-peer.timer|restic-backups-mc-public.timer|minecraft-backup.timer|postgresqlBackup.timer"} > 0 or on(name) (node_systemd_timer_last_trigger_seconds{name=~"restic-backups-peer.timer|restic-backups-mc-public.timer|minecraft-backup.timer|postgresqlBackup.timer"} * 0 + on() group_left() max(node_boot_time_seconds)))'';
        op = "gt";
        threshold = 129600;
        noData = "Alerting";
        window = 600;
      }}
      ${rule {
        uid = "bandit-lab-minecraft-down";
        title = "Minecraft or bot hub not active";
        for = "5m";
        severity = "critical";
        summary = "{{ $labels.name }} has not been active for 5 minutes";
        expr = ''node_systemd_unit_state{name=~"minecraft-server-paper.service|docker-mcbots.service", state="active"}'';
        op = "lt";
        threshold = 1;
        noData = "Alerting";
      }}
      ${rule {
        uid = "bandit-lab-minecraft-port-down";
        title = "Minecraft port probe failing";
        for = "3m";
        severity = "critical";
        summary = "TCP probe of Velocity ({{ $labels.instance }}) is failing";
        expr = ''probe_success{job="blackbox-minecraft"}'';
        op = "lt";
        threshold = 1;
        noData = "Alerting";
      }}
      ${rule {
        uid = "bandit-lab-gpu-metrics-absent";
        title = "GPU metrics missing";
        for = "10m";
        severity = "warning";
        summary = "No nvidia_smi series for 10 minutes: GPU exporter or nvidia-smi is broken";
        expr = ''absent_over_time(nvidia_smi_temperature_gpu[10m])'';
        op = "gt";
        threshold = 0;
        noData = "OK";
        window = 600;
      }}
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

{
  config,
  lib,
  pkgs,
  ...
}: let
  # While the backup module is off the series do not exist, so "no data" must
  # not alert; once it is on, missing data (units not exported, node-exporter
  # not recreated) must alert instead of staying green forever.
  backupNoData =
    if config.bandit-lab.backups.enable
    then "Alerting"
    else "OK";
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
    # One Grafana unified-alerting rule: query A (instant PromQL) feeding
    # threshold expression C. `window` is the relativeTimeRange in seconds.
    # JSON is valid YAML, so the file is rendered with builtins.toJSON.
    mkRule = {
      uid,
      title,
      expr,
      for,
      window,
      op,
      threshold,
      severity,
      summary,
      noDataState ? null,
    }:
      {
        inherit uid title for;
        condition = "C";
        labels = {inherit severity;};
        annotations = {inherit summary;};
        data = [
          {
            refId = "A";
            relativeTimeRange = {
              from = window;
              to = 0;
            };
            datasourceUid = "prometheus";
            model = {
              editorMode = "code";
              inherit expr;
              instant = true;
              range = false;
              refId = "A";
              intervalMs = 1000;
              maxDataPoints = 43200;
            };
          }
          {
            refId = "C";
            relativeTimeRange = {
              from = window;
              to = 0;
            };
            datasourceUid = "__expr__";
            model = {
              type = "threshold";
              refId = "C";
              expression = "A";
              intervalMs = 1000;
              maxDataPoints = 43200;
              datasource = {
                type = "__expr__";
                uid = "__expr__";
              };
              conditions = [
                {
                  evaluator = {
                    type = op;
                    params = [threshold];
                  };
                }
              ];
            };
          }
        ];
      }
      // lib.optionalAttrs (noDataState != null) {inherit noDataState;};
    rules = [
      (mkRule {
        uid = "bandit-lab-scrape-down";
        title = "Scrape target down";
        expr = "up";
        for = "5m";
        window = 300;
        op = "lt";
        threshold = 1;
        severity = "critical";
        summary = "Prometheus cannot scrape {{ $labels.job }} ({{ $labels.instance }})";
      })
      (mkRule {
        uid = "bandit-lab-wan-probe-down";
        title = "Public endpoint probe failing";
        expr = ''probe_success{job="blackbox-wan"}'';
        for = "3m";
        window = 300;
        op = "lt";
        threshold = 1;
        severity = "critical";
        summary = "Public endpoint HTTP probe for {{ $labels.instance }} is failing";
      })
      (mkRule {
        uid = "bandit-lab-origin-probe-down";
        title = "Direct origin probe failing";
        expr = ''probe_success{job="blackbox-origin"}'';
        for = "3m";
        window = 300;
        op = "lt";
        threshold = 1;
        severity = "critical";
        summary = "Direct origin HTTP probe for {{ $labels.instance }} is failing";
      })
      (mkRule {
        uid = "bandit-lab-disk-low";
        title = "Root filesystem almost full";
        expr = ''node_filesystem_avail_bytes{mountpoint="/", fstype!="tmpfs"} / node_filesystem_size_bytes{mountpoint="/"} * 100'';
        for = "15m";
        window = 900;
        op = "lt";
        threshold = 15;
        severity = "warning";
        summary = "Root filesystem below 15% free on {{ $labels.instance }}";
      })
      (mkRule {
        uid = "bandit-lab-memory-low";
        title = "Memory almost exhausted";
        expr = "node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100";
        for = "10m";
        window = 600;
        op = "lt";
        threshold = 10;
        severity = "warning";
        summary = "Available memory below 10% on {{ $labels.instance }}";
      })
      (mkRule {
        uid = "bandit-lab-backup-failed";
        title = "Backup job failed";
        expr = ''node_systemd_unit_state{name=~"restic-backups-lab.service|restic-check.service|restic-backups-peer.service|restic-peer-prune.service", state="failed"}'';
        for = "5m";
        window = 300;
        op = "gt";
        threshold = 0;
        severity = "critical";
        summary = "{{ $labels.name }} is in the failed state (off-host backup or integrity check)";
        noDataState = backupNoData;
      })
      (mkRule {
        uid = "bandit-lab-backup-stale";
        title = "No backup run for 36 hours";
        expr = ''time() - node_systemd_timer_last_trigger_seconds{name="restic-backups-lab.timer"}'';
        for = "10m";
        window = 600;
        op = "gt";
        threshold = 129600;
        severity = "critical";
        summary = "The off-host backup timer has not fired for more than 36 hours";
        noDataState = backupNoData;
      })
    ];
    alerting = pkgs.writeTextDir "alerting/bandit-lab.yaml" (builtins.toJSON {
      apiVersion = 1;
      groups = [
        {
          orgId = 1;
          name = "bandit-lab";
          folder = "Bandit Lab";
          interval = "1m";
          inherit rules;
        }
      ];
    });
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

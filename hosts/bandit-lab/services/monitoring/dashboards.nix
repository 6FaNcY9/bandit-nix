{pkgs, ...}: let
  # grafana.com id 1860 rev 45 (Node Exporter Full). Pinned by hash; bump the
  # revision deliberately. Uses a datasource template variable, so it picks
  # up the provisioned Prometheus datasource without patching.
  dashboardNodeExporter = pkgs.fetchurl {
    name = "grafana-dashboard-node-exporter-full.json";
    url = "https://grafana.com/api/dashboards/1860/revisions/45/download";
    hash = "sha256-GExrdAnzBtp1Ul13cvcZRbEM6iOtFrXXjEaY6g6lGYY=";
  };

  # Small purpose-built dashboard for the blackbox WAN probes (community
  # blackbox dashboards assume datasource UIDs we do not control).
  dashboardWanProbes = pkgs.writeText "grafana-dashboard-wan-probes.json" (builtins.toJSON {
    title = "Public Endpoint Probes";
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
        title = "Public endpoint reachability";
        description = "Accepts HTTP 200, 302, or 303. A Cloudflare Access redirect does not prove tunnel or origin health.";
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

  # Keep origin failures visible independently of public Access redirects.
  dashboardOriginProbes = pkgs.writeText "grafana-dashboard-origin-probes.json" (builtins.toJSON {
    title = "Direct Origin Probes";
    uid = "origin-probes";
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
        title = "Direct origin health";
        description = "Requires HTTP 200 without redirects from the container health endpoint. Does not exercise Traefik, Cloudflare Tunnel, or Access.";
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
            expr = ''probe_success{job="blackbox-origin"}'';
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
    ];
  });

  # Landing page: one screen answering "is the lab healthy?". Thresholds
  # mirror the alert rules in alerting.nix so colours and pages agree.
  prometheusDs = {
    type = "prometheus";
    uid = "prometheus";
  };
  statPanel = {
    id,
    x,
    title,
    expr,
    unit ? "none",
    steps,
    legend ? "",
  }: {
    inherit id title;
    type = "stat";
    datasource = prometheusDs;
    gridPos = {
      h = 4;
      w = 4;
      inherit x;
      y = 0;
    };
    targets = [
      {
        refId = "A";
        inherit expr;
        instant = true;
        legendFormat = legend;
      }
    ];
    fieldConfig = {
      defaults = {
        inherit unit;
        decimals = 0;
        thresholds = {
          mode = "absolute";
          inherit steps;
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
  };
  graphPanel = {
    id,
    x,
    y,
    w,
    title,
    targets,
    unit,
    max ? null,
  }: {
    inherit id title;
    type = "timeseries";
    datasource = prometheusDs;
    gridPos = {
      h = 8;
      inherit w x y;
    };
    targets =
      map ({
        expr,
        legend,
      }: {
        refId = legend;
        inherit expr;
        legendFormat = legend;
      })
      targets;
    fieldConfig = {
      defaults =
        {
          inherit unit;
          min = 0;
          custom.fillOpacity = 10;
        }
        // (
          if max == null
          then {}
          else {inherit max;}
        );
      overrides = [];
    };
    options = {
      legend = {
        displayMode = "list";
        placement = "bottom";
      };
      tooltip.mode = "multi";
    };
  };
  countSteps = [
    {
      color = "green";
      value = null;
    }
    {
      color = "red";
      value = 1;
    }
  ];
  dashboardLabOverview = pkgs.writeText "grafana-dashboard-lab-overview.json" (builtins.toJSON {
    title = "Lab Overview";
    uid = "lab-overview";
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
      (statPanel {
        id = 1;
        x = 0;
        title = "Failed units";
        expr = ''count(node_systemd_unit_state{state="failed"} == 1) or vector(0)'';
        steps = countSteps;
      })
      (statPanel {
        id = 2;
        x = 4;
        title = "Scrape targets down";
        expr = "count(up == 0) or vector(0)";
        steps = countSteps;
      })
      (statPanel {
        id = 3;
        x = 8;
        title = "Endpoints down";
        expr = ''count(probe_success == 0) or vector(0)'';
        steps = countSteps;
      })
      (statPanel {
        id = 4;
        x = 12;
        title = "Root disk free";
        expr = ''node_filesystem_avail_bytes{mountpoint="/", fstype!="tmpfs"} / node_filesystem_size_bytes{mountpoint="/"} * 100'';
        unit = "percent";
        steps = [
          {
            color = "red";
            value = null;
          }
          {
            color = "orange";
            value = 15;
          }
          {
            color = "green";
            value = 25;
          }
        ];
      })
      (statPanel {
        id = 5;
        x = 16;
        title = "Memory available";
        expr = "node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100";
        unit = "percent";
        steps = [
          {
            color = "red";
            value = null;
          }
          {
            color = "orange";
            value = 10;
          }
          {
            color = "green";
            value = 20;
          }
        ];
      })
      (statPanel {
        id = 6;
        x = 20;
        title = "Since last lab backup";
        expr = ''time() - node_systemd_timer_last_trigger_seconds{name="restic-backups-lab.timer"}'';
        unit = "s";
        steps = [
          {
            color = "green";
            value = null;
          }
          {
            color = "orange";
            value = 86400;
          }
          {
            color = "red";
            value = 129600;
          }
        ];
      })
      (graphPanel {
        id = 7;
        x = 0;
        y = 4;
        w = 12;
        title = "CPU busy";
        unit = "percent";
        max = 100;
        targets = [
          {
            expr = ''100 * (1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])))'';
            legend = "busy";
          }
        ];
      })
      (graphPanel {
        id = 8;
        x = 12;
        y = 4;
        w = 12;
        title = "Memory";
        unit = "bytes";
        targets = [
          {
            expr = "node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes";
            legend = "used";
          }
          {
            expr = "node_memory_MemTotal_bytes";
            legend = "total";
          }
        ];
      })
      (graphPanel {
        id = 9;
        x = 0;
        y = 12;
        w = 8;
        title = "Load average";
        unit = "short";
        targets = [
          {
            expr = "node_load1";
            legend = "1m";
          }
          {
            expr = "node_load5";
            legend = "5m";
          }
          {
            expr = "node_load15";
            legend = "15m";
          }
        ];
      })
      (graphPanel {
        id = 10;
        x = 8;
        y = 12;
        w = 8;
        title = "Root disk free";
        unit = "bytes";
        targets = [
          {
            expr = ''node_filesystem_avail_bytes{mountpoint="/", fstype!="tmpfs"}'';
            legend = "free";
          }
        ];
      })
      (graphPanel {
        id = 11;
        x = 16;
        y = 12;
        w = 8;
        title = "Network (physical interfaces)";
        unit = "Bps";
        targets = [
          {
            expr = ''sum(rate(node_network_receive_bytes_total{device=~"en.*|eth.*"}[5m]))'';
            legend = "rx";
          }
          {
            expr = ''sum(rate(node_network_transmit_bytes_total{device=~"en.*|eth.*"}[5m]))'';
            legend = "tx";
          }
        ];
      })
      {
        id = 12;
        type = "stat";
        title = "systemd units";
        description = "Units from the node-exporter include list. Service units behind timers are inactive between runs.";
        datasource = prometheusDs;
        gridPos = {
          h = 10;
          w = 24;
          x = 0;
          y = 20;
        };
        targets = [
          {
            refId = "A";
            # 0 inactive/other, 1 active, 2 failed; summed per unit name.
            expr = ''sum by (name) (node_systemd_unit_state{state="active"} + ignoring(state) 2 * node_systemd_unit_state{state="failed"})'';
            instant = true;
            legendFormat = "{{name}}";
          }
        ];
        fieldConfig = {
          defaults = {
            mappings = [
              {
                type = "value";
                options = {
                  "0" = {
                    text = "inactive";
                    color = "text";
                  };
                  "1" = {
                    text = "active";
                    color = "green";
                  };
                  "2" = {
                    text = "FAILED";
                    color = "red";
                  };
                };
              }
            ];
            thresholds = {
              mode = "absolute";
              steps = [
                {
                  color = "text";
                  value = null;
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
          textMode = "value_and_name";
        };
      }
    ];
  });

  grafanaDashboards = pkgs.runCommand "grafana-dashboards" {} ''
    mkdir -p $out
    cp -L ${dashboardLabOverview} $out/lab-overview.json
    cp -L ${dashboardNodeExporter} $out/node-exporter-full.json
    cp -L ${dashboardWanProbes} $out/wan-probes.json
    cp -L ${dashboardOriginProbes} $out/origin-probes.json
  '';
in {
  _module.args.monitoringDashboards = {inherit grafanaDashboards;};
}

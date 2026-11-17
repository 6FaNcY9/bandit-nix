{
  pkgs,
  repoConfig,
  ...
}: let
  # Tailnet suffix for the service links, e.g. ntopng.tail7facc9.ts.net.
  tailnet = pkgs.lib.removePrefix "bandit-lab." repoConfig.lab.tailnetFqdn;
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

  # Landing page: one screen answering "is the lab healthy?", then detail
  # sections per resource. Tile thresholds mirror the alert rules in
  # alerting.nix so colours and pages agree.
  lib = pkgs.lib;
  prometheusDs = {
    type = "prometheus";
    uid = "prometheus";
  };
  refIds = lib.stringToCharacters "ABCDEFGHIJ";
  statPanel = {
    id,
    x,
    title,
    expr,
    unit ? "none",
    steps,
  }: {
    inherit id title;
    type = "stat";
    datasource = prometheusDs;
    gridPos = {
      h = 4;
      w = 3;
      inherit x;
      y = 0;
    };
    targets = [
      {
        refId = "A";
        inherit expr;
        instant = true;
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
  rowPanel = id: y: title: {
    inherit id title;
    type = "row";
    collapsed = false;
    gridPos = {
      h = 1;
      w = 24;
      x = 0;
      inherit y;
    };
    panels = [];
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
    stack ? false,
    hideLegend ? false,
    overrides ? [],
  }: {
    inherit id title;
    type = "timeseries";
    datasource = prometheusDs;
    gridPos = {
      h = 8;
      inherit w x y;
    };
    targets =
      lib.imap0 (i: {
        expr,
        legend,
      }: {
        refId = lib.elemAt refIds i;
        inherit expr;
        legendFormat = legend;
      })
      targets;
    fieldConfig = {
      defaults =
        {
          inherit unit;
          min = 0;
          custom = {
            fillOpacity = 10;
            stacking.mode =
              if stack
              then "normal"
              else "none";
          };
        }
        // lib.optionalAttrs (max != null) {inherit max;};
      inherit overrides;
    };
    options = {
      legend = {
        displayMode = "list";
        placement = "bottom";
        showLegend = !hideLegend;
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
  # Green above `ok`, orange above `warn`, red below (percent-free style).
  lowIsBad = warn: ok: [
    {
      color = "red";
      value = null;
    }
    {
      color = "orange";
      value = warn;
    }
    {
      color = "green";
      value = ok;
    }
  ];
  highIsBad = warn: bad: [
    {
      color = "green";
      value = null;
    }
    {
      color = "orange";
      value = warn;
    }
    {
      color = "red";
      value = bad;
    }
  ];
  unitOverride = name: unit: {
    matcher = {
      id = "byName";
      options = name;
    };
    properties = [
      {
        id = "unit";
        value = unit;
      }
    ];
  };
  dashboardLabOverview = pkgs.writeText "grafana-dashboard-lab-overview.json" (builtins.toJSON {
    title = "Lab Overview";
    uid = "lab-overview";
    schemaVersion = 39;
    version = 2;
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
        x = 3;
        title = "Scrape targets down";
        expr = "count(up == 0) or vector(0)";
        steps = countSteps;
      })
      (statPanel {
        id = 3;
        x = 6;
        title = "Endpoints down";
        expr = "count(probe_success == 0) or vector(0)";
        steps = countSteps;
      })
      (statPanel {
        id = 4;
        x = 9;
        title = "Root disk free";
        expr = ''node_filesystem_avail_bytes{mountpoint="/", fstype!="tmpfs"} / node_filesystem_size_bytes{mountpoint="/"} * 100'';
        unit = "percent";
        steps = lowIsBad 15 25;
      })
      (statPanel {
        id = 5;
        x = 12;
        title = "Memory available";
        expr = "node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100";
        unit = "percent";
        steps = lowIsBad 10 20;
      })
      (statPanel {
        id = 6;
        x = 15;
        title = "GPU busy";
        expr = "nvidia_smi_utilization_gpu_ratio * 100";
        unit = "percent";
        steps = highIsBad 80 95;
      })
      (statPanel {
        id = 7;
        x = 18;
        title = "CPU package temp";
        expr = ''max(node_hwmon_temp_celsius{chip=~".*coretemp.*"})'';
        unit = "celsius";
        steps = highIsBad 80 90;
      })
      (statPanel {
        id = 8;
        x = 21;
        title = "Since last peer backup";
        expr = ''time() - node_systemd_timer_last_trigger_seconds{name="restic-backups-peer.timer"}'';
        unit = "s";
        steps = highIsBad 86400 129600;
      })
      (graphPanel {
        id = 9;
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
        id = 10;
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
        id = 11;
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
        id = 12;
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
        id = 13;
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
        id = 14;
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

      (rowPanel 20 30 "CPU")
      (graphPanel {
        id = 21;
        x = 0;
        y = 31;
        w = 8;
        title = "CPU by mode";
        unit = "percent";
        max = 100;
        stack = true;
        targets = [
          {
            expr = ''100 * sum by (mode) (rate(node_cpu_seconds_total{mode!="idle"}[5m])) / scalar(count(node_cpu_seconds_total{mode="idle"}))'';
            legend = "{{mode}}";
          }
        ];
      })
      (graphPanel {
        id = 22;
        x = 8;
        y = 31;
        w = 8;
        title = "Per-core busy";
        unit = "percent";
        max = 100;
        hideLegend = true;
        targets = [
          {
            expr = ''100 * (1 - rate(node_cpu_seconds_total{mode="idle"}[5m]))'';
            legend = "cpu{{cpu}}";
          }
        ];
      })
      (graphPanel {
        id = 23;
        x = 16;
        y = 31;
        w = 8;
        title = "Temperatures";
        unit = "celsius";
        targets = [
          {
            expr = ''max by (chip) (node_hwmon_temp_celsius{chip=~".*coretemp.*|.*nvme.*"})'';
            legend = "{{chip}}";
          }
          {
            expr = "nvidia_smi_temperature_gpu";
            legend = "gpu";
          }
        ];
      })

      (rowPanel 30 39 "Memory")
      (graphPanel {
        id = 31;
        x = 0;
        y = 40;
        w = 8;
        title = "Memory breakdown";
        unit = "bytes";
        stack = true;
        targets = [
          {
            expr = "node_memory_MemTotal_bytes - node_memory_MemFree_bytes - node_memory_Buffers_bytes - node_memory_Cached_bytes";
            legend = "apps";
          }
          {
            expr = "node_memory_Cached_bytes";
            legend = "cache";
          }
          {
            expr = "node_memory_Buffers_bytes";
            legend = "buffers";
          }
          {
            expr = "node_memory_MemFree_bytes";
            legend = "free";
          }
        ];
      })
      (graphPanel {
        id = 32;
        x = 8;
        y = 40;
        w = 8;
        title = "Swap (zram)";
        unit = "bytes";
        targets = [
          {
            expr = "node_memory_SwapTotal_bytes - node_memory_SwapFree_bytes";
            legend = "used";
          }
          {
            expr = "node_memory_SwapTotal_bytes";
            legend = "total";
          }
        ];
      })
      (graphPanel {
        id = 33;
        x = 16;
        y = 40;
        w = 8;
        title = "Pressure stall (PSI, some)";
        unit = "percent";
        max = 100;
        targets = [
          {
            expr = "rate(node_pressure_cpu_waiting_seconds_total[5m]) * 100";
            legend = "cpu";
          }
          {
            expr = "rate(node_pressure_memory_waiting_seconds_total[5m]) * 100";
            legend = "memory";
          }
          {
            expr = "rate(node_pressure_io_waiting_seconds_total[5m]) * 100";
            legend = "io";
          }
        ];
      })

      (rowPanel 40 48 "Disk")
      (graphPanel {
        id = 41;
        x = 0;
        y = 49;
        w = 8;
        title = "NVMe throughput";
        unit = "Bps";
        targets = [
          {
            expr = ''rate(node_disk_read_bytes_total{device="nvme0n1"}[5m])'';
            legend = "read";
          }
          {
            expr = ''rate(node_disk_written_bytes_total{device="nvme0n1"}[5m])'';
            legend = "write";
          }
        ];
      })
      (graphPanel {
        id = 42;
        x = 8;
        y = 49;
        w = 8;
        title = "NVMe IOPS";
        unit = "iops";
        targets = [
          {
            expr = ''rate(node_disk_reads_completed_total{device="nvme0n1"}[5m])'';
            legend = "reads";
          }
          {
            expr = ''rate(node_disk_writes_completed_total{device="nvme0n1"}[5m])'';
            legend = "writes";
          }
        ];
      })
      (graphPanel {
        id = 43;
        x = 16;
        y = 49;
        w = 8;
        title = "NVMe busy";
        unit = "percent";
        max = 100;
        targets = [
          {
            expr = ''rate(node_disk_io_time_seconds_total{device="nvme0n1"}[5m]) * 100'';
            legend = "busy";
          }
        ];
      })
      (graphPanel {
        id = 44;
        x = 0;
        y = 57;
        w = 8;
        title = "I/O latency";
        unit = "s";
        targets = [
          {
            expr = ''rate(node_disk_read_time_seconds_total{device="nvme0n1"}[5m]) / rate(node_disk_reads_completed_total{device="nvme0n1"}[5m])'';
            legend = "read";
          }
          {
            expr = ''rate(node_disk_write_time_seconds_total{device="nvme0n1"}[5m]) / rate(node_disk_writes_completed_total{device="nvme0n1"}[5m])'';
            legend = "write";
          }
        ];
      })
      (graphPanel {
        id = 45;
        x = 8;
        y = 57;
        w = 8;
        title = "Filesystem used";
        unit = "percent";
        max = 100;
        targets = [
          {
            expr = ''100 - node_filesystem_avail_bytes{fstype!~"tmpfs|ramfs"} / node_filesystem_size_bytes * 100'';
            legend = "{{mountpoint}}";
          }
        ];
      })
      (graphPanel {
        id = 46;
        x = 16;
        y = 57;
        w = 8;
        title = "Processes";
        unit = "short";
        targets = [
          {
            expr = "node_procs_running";
            legend = "running";
          }
          {
            expr = "node_procs_blocked";
            legend = "blocked on I/O";
          }
        ];
      })

      (rowPanel 50 65 "Network")
      (graphPanel {
        id = 51;
        x = 0;
        y = 66;
        w = 12;
        title = "Throughput per interface";
        unit = "Bps";
        targets = [
          {
            expr = ''rate(node_network_receive_bytes_total{device!~"lo|veth.*|br-.*"}[5m])'';
            legend = "{{device}} rx";
          }
          {
            expr = ''rate(node_network_transmit_bytes_total{device!~"lo|veth.*|br-.*"}[5m])'';
            legend = "{{device}} tx";
          }
        ];
      })
      (graphPanel {
        id = 52;
        x = 12;
        y = 66;
        w = 12;
        title = "Errors and drops (all interfaces)";
        unit = "pps";
        targets = [
          {
            expr = "sum(rate(node_network_receive_errs_total[5m]))";
            legend = "rx errors";
          }
          {
            expr = "sum(rate(node_network_receive_drop_total[5m]))";
            legend = "rx drops";
          }
          {
            expr = "sum(rate(node_network_transmit_errs_total[5m]))";
            legend = "tx errors";
          }
          {
            expr = "sum(rate(node_network_transmit_drop_total[5m]))";
            legend = "tx drops";
          }
        ];
      })
      (graphPanel {
        id = 53;
        x = 0;
        y = 74;
        w = 12;
        title = "Sockets";
        unit = "short";
        targets = [
          {
            expr = "node_sockstat_TCP_inuse";
            legend = "tcp in use";
          }
          {
            expr = "node_sockstat_TCP_tw";
            legend = "tcp time-wait";
          }
          {
            expr = "node_sockstat_UDP_inuse";
            legend = "udp in use";
          }
        ];
      })
      (graphPanel {
        id = 54;
        x = 12;
        y = 74;
        w = 12;
        title = "Conntrack";
        unit = "short";
        targets = [
          {
            expr = "node_nf_conntrack_entries";
            legend = "entries";
          }
          {
            expr = "node_nf_conntrack_entries_limit";
            legend = "limit";
          }
        ];
      })

      (rowPanel 60 82 "GPU")
      (graphPanel {
        id = 61;
        x = 0;
        y = 83;
        w = 8;
        title = "GPU utilization";
        unit = "percent";
        max = 100;
        targets = [
          {
            expr = "nvidia_smi_utilization_gpu_ratio * 100";
            legend = "compute";
          }
          {
            expr = "nvidia_smi_utilization_memory_ratio * 100";
            legend = "memory bandwidth";
          }
        ];
      })
      (graphPanel {
        id = 62;
        x = 8;
        y = 83;
        w = 8;
        title = "GPU memory";
        unit = "bytes";
        targets = [
          {
            expr = "nvidia_smi_memory_used_bytes";
            legend = "used";
          }
          {
            expr = "nvidia_smi_memory_total_bytes";
            legend = "total";
          }
        ];
      })
      (graphPanel {
        id = 63;
        x = 16;
        y = 83;
        w = 8;
        title = "GPU temperature and power";
        unit = "celsius";
        overrides = [(unitOverride "power" "watt")];
        targets = [
          {
            expr = "nvidia_smi_temperature_gpu";
            legend = "temperature";
          }
          {
            expr = "nvidia_smi_power_draw_watts";
            legend = "power";
          }
        ];
      })
    ];
  });

  # aiia.at usage (aiia-create-stats, counts only) and the hourly live check
  # (job aiia-live). German titles: the owner reads this one.
  plainSteps = [
    {
      color = "blue";
      value = null;
    }
  ];
  liveOk = ''min(last_over_time(probe_success{job="aiia-live"}[2h])) * min(aiia_healthz_ok)'';
  dashboardAiia = pkgs.writeText "grafana-dashboard-aiia.json" (builtins.toJSON {
    title = "aiia";
    uid = "aiia";
    schemaVersion = 39;
    version = 1;
    editable = false;
    timezone = "browser";
    refresh = "5m";
    time = {
      from = "now-7d";
      to = "now";
    };
    panels = [
      (statPanel {
        id = 1;
        x = 0;
        title = "Konten";
        expr = "aiia_accounts";
        steps = plainSteps;
      })
      (statPanel {
        id = 2;
        x = 3;
        title = "Designs";
        expr = "aiia_designs";
        steps = plainSteps;
      })
      (statPanel {
        id = 3;
        x = 6;
        title = "Designs mit Konto";
        expr = "aiia_designs_account";
        steps = plainSteps;
      })
      (statPanel {
        id = 4;
        x = 9;
        title = "Offene Meldungen";
        expr = "aiia_reports_open";
        steps = countSteps;
      })
      (statPanel {
        id = 5;
        x = 12;
        title = "Offene Bestellungen";
        expr = ''sum(aiia_orders{state=~"waiting|in_production"})'';
        steps = plainSteps;
      })
      (statPanel {
        id = 6;
        x = 15;
        title = "Bilder im 24-h-Kontingent";
        expr = "aiia_site_generations";
        steps = plainSteps;
      })
      (lib.recursiveUpdate (statPanel {
          id = 7;
          x = 18;
          title = "Live-Check";
          expr = liveOk;
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
        }) {
          description = "aiia.at/create, /info, /api/session, www-Weiterleitung und CDN stündlich, healthz alle 5 Minuten.";
          fieldConfig.defaults.mappings = [
            {
              type = "value";
              options = {
                "0" = {
                  text = "FEHLER";
                  color = "red";
                };
                "1" = {
                  text = "OK";
                  color = "green";
                };
              };
            }
          ];
        })
      (statPanel {
        id = 8;
        x = 21;
        title = "Zahlen zuletzt erfasst vor";
        expr = "time() - aiia_stats_last_success_timestamp_seconds";
        unit = "s";
        steps = highIsBad 600 1800;
      })
      (graphPanel {
        id = 9;
        x = 0;
        y = 4;
        w = 12;
        title = "Konten und Designs";
        unit = "none";
        targets = [
          {
            expr = "aiia_accounts";
            legend = "Konten";
          }
          {
            expr = "aiia_designs";
            legend = "Designs";
          }
          {
            expr = "aiia_designs_account";
            legend = "Designs mit Konto";
          }
        ];
      })
      # shortcut: delta of the stored-designs gauge, so expired designs (30 days
      # after an anonymous one was made) lower it; export a created counter if that matters.
      (lib.recursiveUpdate (graphPanel {
          id = 10;
          x = 12;
          y = 4;
          w = 12;
          title = "Neue Designs pro Tag";
          unit = "none";
          hideLegend = true;
          targets = [
            {
              expr = "clamp_min(delta(aiia_designs[1d]), 0)";
              legend = "neu";
            }
          ];
        }) {
          interval = "1d";
          description = "Zuwachs der gespeicherten Designs pro Tag. Ablaufende Designs (anonym nach 30 Tagen) drücken den Wert.";
          fieldConfig.defaults.custom.drawStyle = "bars";
          fieldConfig.defaults.decimals = 0;
        })
      (graphPanel {
        id = 11;
        x = 0;
        y = 12;
        w = 24;
        title = "Live-Checks (1 = OK)";
        unit = "none";
        max = 1;
        targets = [
          {
            expr = ''last_over_time(probe_success{job="aiia-live"}[2h])'';
            legend = "{{instance}}";
          }
          {
            expr = "aiia_healthz_ok";
            legend = "healthz (lokal)";
          }
        ];
      })
    ];
  });

  # "Netzwerk": what Blocky blocks per device, traffic per device, and freshness
  # of the phone/laptop senders. Blocked/queries come from the Postgres query log
  # (datasource blocky-log), traffic from Prometheus. German titles: the owner
  # reads this one. Panels 6-8 stay empty until the phone sender (pong_*) and the
  # laptop node exporter (job=laptop) land in later tasks.
  blockyDs = {
    type = "grafana-postgresql-datasource";
    uid = "blocky-log";
  };
  sqlTable = {
    id,
    x,
    y,
    w,
    h,
    title,
    sql,
    description ? null,
  }:
    {
      inherit id title;
      type = "table";
      datasource = blockyDs;
      gridPos = {
        inherit h w x y;
      };
      targets = [
        {
          refId = "A";
          format = "table";
          rawQuery = true;
          rawSql = sql;
        }
      ];
      fieldConfig = {
        defaults = {};
        overrides = [];
      };
      options = {
        showHeader = true;
        cellHeight = "sm";
      };
    }
    // lib.optionalAttrs (description != null) {inherit description;};
  # Postgres time series: the query returns time, a metric column and a value.
  sqlTimeseries = {
    id,
    x,
    y,
    w,
    h,
    title,
    sql,
    stack ? false,
  }: {
    inherit id title;
    type = "timeseries";
    datasource = blockyDs;
    gridPos = {
      inherit h w x y;
    };
    targets = [
      {
        refId = "A";
        format = "time_series";
        rawQuery = true;
        rawSql = sql;
      }
    ];
    fieldConfig = {
      defaults = {
        min = 0;
        custom = {
          fillOpacity = 10;
          stacking.mode =
            if stack
            then "normal"
            else "none";
        };
      };
      overrides = [];
    };
    options = {
      legend = {
        displayMode = "list";
        placement = "bottom";
        showLegend = true;
      };
      tooltip.mode = "multi";
    };
  };
  dashboardNetzwerk = pkgs.writeText "grafana-dashboard-netzwerk.json" (builtins.toJSON {
    title = "Netzwerk";
    uid = "netzwerk";
    schemaVersion = 39;
    version = 1;
    editable = false;
    timezone = "browser";
    refresh = "1m";
    time = {
      from = "now-24h";
      to = "now";
    };
    templating.list = [
      {
        name = "domain";
        type = "textbox";
        label = "Domain-Suche";
        query = "";
        current = {
          text = "";
          value = "";
        };
      }
      {
        name = "geraet";
        type = "query";
        label = "Gerät";
        multi = true;
        includeAll = true;
        datasource = blockyDs;
        query = "select distinct client_name from log_entries where client_name <> '' order by 1";
        # 2 = refresh on time-range change.
        refresh = 2;
      }
    ];
    panels = [
      {
        id = 1;
        type = "stat";
        title = "Anfragen (24 h) und Anteil geblockt";
        datasource = blockyDs;
        gridPos = {
          h = 4;
          w = 24;
          x = 0;
          y = 0;
        };
        targets = [
          {
            refId = "A";
            format = "table";
            rawQuery = true;
            rawSql = ''
              select
                count(*) as "Anfragen 24 h",
                round(100.0 * count(*) filter (where response_type = 'BLOCKED') / greatest(count(*), 1), 1) as "% geblockt"
              from log_entries
              where request_ts > now() - interval '24 hours'
            '';
          }
        ];
        fieldConfig = {
          defaults = {
            thresholds = {
              mode = "absolute";
              steps = plainSteps;
            };
          };
          overrides = [(unitOverride "% geblockt" "percent")];
        };
        options = {
          colorMode = "value";
          graphMode = "none";
          justifyMode = "auto";
          orientation = "horizontal";
          reduceOptions = {
            calcs = ["lastNotNull"];
            fields = "";
            values = false;
          };
          textMode = "value_and_name";
        };
      }
      (sqlTable {
        id = 2;
        x = 0;
        y = 4;
        w = 12;
        h = 8;
        title = "Top geblockte Domains (24 h)";
        sql = ''
          select question_name as "Domain", count(*) as "Anfragen", count(distinct client_name) as "Geräte"
          from log_entries
          where response_type = 'BLOCKED' and request_ts > now() - interval '24 hours'
          group by question_name
          order by count(*) desc
          limit 20
        '';
      })
      (sqlTimeseries {
        id = 3;
        x = 12;
        y = 4;
        w = 12;
        h = 8;
        title = "Anfragen pro Gerät und Stunde";
        stack = true;
        sql = ''
          select date_trunc('hour', request_ts) as time, client_name as metric, count(*) as value
          from log_entries
          where request_ts > now() - interval '24 hours'
          group by 1, 2
          order by 1
        '';
      })
      (sqlTable {
        id = 4;
        x = 0;
        y = 12;
        w = 24;
        h = 10;
        title = "Letzte 200 Anfragen";
        description = "Mit den Variablen oben nach Domain und Gerät filtern.";
        sql = ''
          select request_ts as "Zeit", client_name as "Gerät", question_name as "Domain", response_type as "Typ", reason as "Grund"
          from log_entries
          where question_name ILIKE '%' || '$domain' || '%' and client_name in ($geraet)
          order by request_ts desc
          limit 200
        '';
      })
      (sqlTable {
        id = 5;
        x = 0;
        y = 22;
        w = 12;
        h = 8;
        title = "Schadseiten-Treffer (7 Tage)";
        sql = ''
          select client_name as "Gerät", question_name as "Domain", count(*) as "Treffer"
          from log_entries
          where reason ILIKE '%malware%' and request_ts > now() - interval '7 days'
          group by client_name, question_name
          order by count(*) desc
        '';
      })
      (graphPanel {
        id = 6;
        x = 12;
        y = 22;
        w = 12;
        title = "Handy-Verkehr pro App (Top 10)";
        unit = "bytes";
        targets = [
          {
            expr = "topk(10, increase(pong_app_rx_bytes[1h]) + increase(pong_app_tx_bytes[1h]))";
            legend = "{{app}}";
          }
        ];
      })
      {
        id = 7;
        type = "stat";
        title = "Melder zuletzt vor";
        description = "Rot über 15 Minuten: der Melder von Handy oder Laptop schweigt.";
        datasource = prometheusDs;
        gridPos = {
          h = 4;
          w = 24;
          x = 0;
          y = 30;
        };
        targets = [
          {
            refId = "A";
            expr = "time() - pong_netstats_last_push_timestamp_seconds";
            instant = true;
            legendFormat = "Handy";
          }
          {
            refId = "B";
            expr = ''time() - max(timestamp(up{job="laptop"} == 1))'';
            instant = true;
            legendFormat = "Laptop";
          }
        ];
        fieldConfig = {
          defaults = {
            unit = "s";
            decimals = 0;
            thresholds = {
              mode = "absolute";
              steps = highIsBad 900 900;
            };
          };
          overrides = [];
        };
        options = {
          colorMode = "background";
          graphMode = "none";
          justifyMode = "auto";
          orientation = "horizontal";
          reduceOptions = {
            calcs = ["lastNotNull"];
            fields = "";
            values = false;
          };
          textMode = "value_and_name";
        };
      }
      (graphPanel {
        id = 8;
        x = 0;
        y = 34;
        w = 12;
        title = "Laptop-Verkehr";
        unit = "Bps";
        targets = [
          {
            expr = ''rate(node_network_receive_bytes_total{job="laptop", device!~"lo|tailscale0"}[5m])'';
            legend = "{{device}} rx";
          }
          {
            expr = ''rate(node_network_transmit_bytes_total{job="laptop", device!~"lo|tailscale0"}[5m])'';
            legend = "{{device}} tx";
          }
        ];
      })
      {
        id = 9;
        type = "text";
        title = "Mehr Ansichten";
        gridPos = {
          h = 8;
          w = 12;
          x = 12;
          y = 34;
        };
        options = {
          mode = "markdown";
          content = ''
            - [ntopng](https://ntopng.${tailnet}) — Live-Verkehr am Lab
            - [Beszel](https://beszel.${tailnet}) — Netz-Bytes pro PC (albert, slayer)

            CrowdSec-Bans schützen nur das Lab, nicht das ganze Netz: fürs Netz nur Domain-Sperren über DNS.
          '';
        };
      }
    ];
  });

  grafanaDashboards = pkgs.runCommand "grafana-dashboards" {} ''
    mkdir -p $out
    cp -L ${dashboardAiia} $out/aiia.json
    cp -L ${dashboardNetzwerk} $out/netzwerk.json
    cp -L ${dashboardLabOverview} $out/lab-overview.json
    cp -L ${dashboardNodeExporter} $out/node-exporter-full.json
    cp -L ${dashboardWanProbes} $out/wan-probes.json
    cp -L ${dashboardOriginProbes} $out/origin-probes.json
  '';
in {
  _module.args.monitoringDashboards = {inherit grafanaDashboards;};
}

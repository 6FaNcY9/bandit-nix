{pkgs, ...}: let
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

  grafanaDashboards = pkgs.runCommand "grafana-dashboards" {} ''
    mkdir -p $out
    cp -L ${dashboardNodeExporter} $out/node-exporter-full.json
    cp -L ${dashboardCadvisor} $out/cadvisor-exporter.json
    cp -L ${dashboardWanProbes} $out/wan-probes.json
    cp -L ${dashboardOriginProbes} $out/origin-probes.json
  '';
in {
  _module.args.monitoringDashboards = {inherit grafanaDashboards;};
}

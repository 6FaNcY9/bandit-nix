{
  config,
  pkgs,
  repoConfig,
  ...
}: let
  username = repoConfig.workstation.username;
  version = "4.14.7";
  # Manager agent ports listen on the tailnet only; API/indexer/dashboard on loopback.
  tailscaleIp = repoConfig.lab.tailscaleIp;
  stateDir = "/srv/containers/wazuh";
  confDir = "${stateDir}/config";
  certDir = "${confDir}/wazuh_indexer_ssl_certs";

  indexerKey = config.sops.secrets."wazuh-tls-indexer-key".path;
  adminKey = config.sops.secrets."wazuh-tls-admin-key".path;
  managerKey = config.sops.secrets."wazuh-tls-manager-key".path;
  dashboardKey = config.sops.secrets."wazuh-tls-dashboard-key".path;
  internalUsers = config.sops.secrets."wazuh-internal-users-yml".path;
in {
  # Passwords live only as sops placeholders; TLS private keys and the
  # security-plugin user DB (password hashes) are sops secrets. The CA keys
  # are rendered back into the certs dir so the upstream cert-regeneration
  # compose file keeps working. Node/admin keys are mounted from /run/secrets.
  sops = {
    secrets = {
      "wazuh-admin-password" = {mode = "0400";};
      "wazuh-api-password" = {mode = "0400";};
      "wazuh-dashboard-password" = {mode = "0400";};
      "wazuh-tls-manager-key" = {mode = "0400";};
      # Indexer/dashboard containers read as uid 1000 — vino is uid 1000 on
      # this host, so owner=vino keeps the mounted key readable inside.
      "wazuh-tls-indexer-key" = {
        owner = username;
        group = "users";
        mode = "0400";
      };
      "wazuh-tls-admin-key" = {
        owner = username;
        group = "users";
        mode = "0400";
      };
      "wazuh-tls-dashboard-key" = {
        owner = username;
        group = "users";
        mode = "0400";
      };
      "wazuh-internal-users-yml" = {
        owner = username;
        group = "users";
        mode = "0400";
      };
      "wazuh-tls-root-ca-key" = {
        path = "${certDir}/root-ca.key";
        mode = "0400";
      };
      "wazuh-tls-root-ca-manager-key" = {
        path = "${certDir}/root-ca-manager.key";
        mode = "0400";
      };
    };

    templates = {
      "wazuh-manager.env" = {
        mode = "0400";
        restartUnits = ["docker-wazuh.manager.service"];
        content = ''
          INDEXER_PASSWORD=${config.sops.placeholder."wazuh-admin-password"}
          API_PASSWORD=${config.sops.placeholder."wazuh-api-password"}
        '';
      };
      "wazuh-dashboard.env" = {
        mode = "0400";
        restartUnits = ["docker-wazuh.dashboard.service"];
        content = ''
          INDEXER_PASSWORD=${config.sops.placeholder."wazuh-admin-password"}
          DASHBOARD_PASSWORD=${config.sops.placeholder."wazuh-dashboard-password"}
          API_PASSWORD=${config.sops.placeholder."wazuh-api-password"}
        '';
      };
      # The dashboard's saved API connection. Upstream ships this file with a
      # plaintext password, so it is rendered, never committed.
      "wazuh-dashboard-wazuh.yml" = {
        owner = username;
        group = "users";
        mode = "0400";
        restartUnits = ["docker-wazuh.dashboard.service"];
        content = ''
          hosts:
            - 1513629884013:
                url: "https://wazuh.manager"
                port: 55000
                username: wazuh-wui
                password: "${config.sops.placeholder."wazuh-api-password"}"
                run_as: false
        '';
      };
    };
  };

  systemd = {
    tmpfiles.rules = [
      "d ${stateDir} 0755 root root -"
      "d ${confDir} 0755 root root -"
      "d ${confDir}/wazuh_cluster 0755 root root -"
      "d ${confDir}/wazuh_indexer 0755 root root -"
      "d ${confDir}/wazuh_dashboard 0755 root root -"
      "d ${confDir}/wazuh_agent 0755 root root -"
      # Populated out-of-band with the python `docker` package (pip install
      # --target, python 3.9) for the agent's docker-listener wodle — the
      # wazuh-agent image ships no pip packages. See the handoff runbook.
      "d ${confDir}/wazuh_agent/site-packages 0755 root root -"
      "d ${certDir} 0755 root root -"
      "L+ ${confDir}/wazuh_cluster/wazuh_manager.conf - - - - ${./wazuh/config/wazuh_manager.conf}"
      "L+ ${confDir}/wazuh_agent/ossec.conf - - - - ${./wazuh/config/wazuh_agent_ossec.conf}"
      "L+ ${confDir}/wazuh_indexer/wazuh.indexer.yml - - - - ${./wazuh/config/wazuh.indexer.yml}"
      "L+ ${confDir}/wazuh_dashboard/opensearch_dashboards.yml - - - - ${./wazuh/config/opensearch_dashboards.yml}"
      "L+ ${certDir}/root-ca.pem - - - - ${./wazuh/certs/root-ca.pem}"
      "L+ ${certDir}/root-ca-manager.pem - - - - ${./wazuh/certs/root-ca-manager.pem}"
      "L+ ${certDir}/admin.pem - - - - ${./wazuh/certs/admin.pem}"
      "L+ ${certDir}/wazuh.indexer.pem - - - - ${./wazuh/certs/wazuh.indexer.pem}"
      "L+ ${certDir}/wazuh.manager.pem - - - - ${./wazuh/certs/wazuh.manager.pem}"
      "L+ ${certDir}/wazuh.dashboard.pem - - - - ${./wazuh/certs/wazuh.dashboard.pem}"
    ];

    services = {
      docker-network-wazuh = repoConfig.mkDockerNetwork pkgs "wazuh";
      "docker-wazuh.manager" = {
        after = ["docker-network-wazuh.service"];
        requires = ["docker-network-wazuh.service"];
      };
      "docker-wazuh.indexer" = {
        after = ["docker-network-wazuh.service"];
        requires = ["docker-network-wazuh.service"];
      };
      "docker-wazuh.dashboard" = {
        after = ["docker-network-wazuh.service"];
        requires = ["docker-network-wazuh.service"];
      };
      "docker-wazuh.agent" = {
        after = ["docker-network-wazuh.service"];
        requires = ["docker-network-wazuh.service"];
      };
    };
  };

  virtualisation.oci-containers.containers = {
    "wazuh.manager" = {
      image = "wazuh/wazuh-manager:${version}";
      hostname = "wazuh.manager";
      environment = {
        INDEXER_URL = "https://wazuh.indexer:9200";
        INDEXER_USERNAME = "admin";
        FILEBEAT_SSL_VERIFICATION_MODE = "full";
        SSL_CERTIFICATE_AUTHORITIES = "/etc/ssl/root-ca.pem";
        SSL_CERTIFICATE = "/etc/ssl/filebeat.pem";
        SSL_KEY = "/etc/ssl/filebeat.key";
        API_USERNAME = "wazuh-wui";
      };
      environmentFiles = [config.sops.templates."wazuh-manager.env".path];
      ports = [
        "${tailscaleIp}:1514:1514"
        "${tailscaleIp}:1515:1515"
        "${tailscaleIp}:514:514/udp"
        "127.0.0.1:55000:55000"
      ];
      volumes = [
        "wazuh_wazuh_api_configuration:/var/ossec/api/configuration"
        "wazuh_wazuh_etc:/var/ossec/etc"
        "wazuh_wazuh_logs:/var/ossec/logs"
        "wazuh_wazuh_queue:/var/ossec/queue"
        "wazuh_wazuh_var_multigroups:/var/ossec/var/multigroups"
        "wazuh_wazuh_integrations:/var/ossec/integrations"
        "wazuh_wazuh_active_response:/var/ossec/active-response/bin"
        "wazuh_wazuh_agentless:/var/ossec/agentless"
        "wazuh_wazuh_wodles:/var/ossec/wodles"
        "wazuh_filebeat_etc:/etc/filebeat"
        "wazuh_filebeat_var:/var/lib/filebeat"
        "${certDir}/root-ca-manager.pem:/etc/ssl/root-ca.pem:ro"
        "${certDir}/wazuh.manager.pem:/etc/ssl/filebeat.pem:ro"
        "${managerKey}:/etc/ssl/filebeat.key:ro"
        "${confDir}/wazuh_cluster/wazuh_manager.conf:/wazuh-config-mount/etc/ossec.conf:ro"
      ];
      extraOptions = [
        "--network=wazuh"
        "--ulimit=memlock=-1:-1"
        "--ulimit=nofile=655360:655360"
      ];
    };

    "wazuh.indexer" = {
      image = "wazuh/wazuh-indexer:${version}";
      hostname = "wazuh.indexer";
      environment = {
        OPENSEARCH_JAVA_OPTS = "-Xms4g -Xmx4g";
      };
      ports = ["127.0.0.1:9200:9200"];
      volumes = [
        "wazuh_wazuh-indexer-data:/var/lib/wazuh-indexer"
        "${certDir}/root-ca.pem:/usr/share/wazuh-indexer/config/certs/root-ca.pem:ro"
        "${indexerKey}:/usr/share/wazuh-indexer/config/certs/wazuh.indexer.key:ro"
        "${certDir}/wazuh.indexer.pem:/usr/share/wazuh-indexer/config/certs/wazuh.indexer.pem:ro"
        "${certDir}/admin.pem:/usr/share/wazuh-indexer/config/certs/admin.pem:ro"
        "${adminKey}:/usr/share/wazuh-indexer/config/certs/admin-key.pem:ro"
        "${confDir}/wazuh_indexer/wazuh.indexer.yml:/usr/share/wazuh-indexer/config/opensearch.yml:ro"
        "${internalUsers}:/usr/share/wazuh-indexer/config/opensearch-security/internal_users.yml:ro"
      ];
      extraOptions = [
        "--network=wazuh"
        "--ulimit=memlock=-1:-1"
        "--ulimit=nofile=65536:65536"
      ];
    };

    "wazuh.dashboard" = {
      image = "wazuh/wazuh-dashboard:${version}";
      hostname = "wazuh.dashboard";
      environment = {
        INDEXER_USERNAME = "admin";
        WAZUH_API_URL = "https://wazuh.manager";
        DASHBOARD_USERNAME = "kibanaserver";
        API_USERNAME = "wazuh-wui";
      };
      environmentFiles = [config.sops.templates."wazuh-dashboard.env".path];
      ports = ["127.0.0.1:443:5601"];
      volumes = [
        "${certDir}/wazuh.dashboard.pem:/usr/share/wazuh-dashboard/certs/wazuh-dashboard.pem:ro"
        "${dashboardKey}:/usr/share/wazuh-dashboard/certs/wazuh-dashboard-key.pem:ro"
        "${certDir}/root-ca.pem:/usr/share/wazuh-dashboard/certs/root-ca.pem:ro"
        "${confDir}/wazuh_dashboard/opensearch_dashboards.yml:/usr/share/wazuh-dashboard/config/opensearch_dashboards.yml:ro"
        "${config.sops.templates."wazuh-dashboard-wazuh.yml".path}:/usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml:ro"
        "wazuh_wazuh-dashboard-config:/usr/share/wazuh-dashboard/data/wazuh/config"
        "wazuh_wazuh-dashboard-custom:/usr/share/wazuh-dashboard/plugins/wazuh/public/assets/custom"
      ];
      dependsOn = ["wazuh.manager" "wazuh.indexer"];
      extraOptions = ["--network=wazuh"];
    };

    "wazuh.agent" = {
      image = "wazuh/wazuh-agent:${version}";
      environment = {
        WAZUH_MANAGER_SERVER = "wazuh.manager";
        WAZUH_AGENT_NAME = "bandit-lab";
      };
      volumes = [
        "${confDir}/wazuh_agent/ossec.conf:/wazuh-config-mount/etc/ossec.conf:ro"
        "${confDir}/wazuh_agent/site-packages:/usr/local/lib64/python3.9/site-packages:ro"
        # The docker-listener wodle needs the daemon socket. `:ro` only makes
        # the bind mount read-only — the Docker API over the socket is fully
        # writable, so this container is effectively host-root. Accepted risk,
        # same as portainer-agent (webhost.nix); a socket-proxy like
        # traefik-docker-proxy (traefik.nix) is the alternative if the wodle
        # endpoint set ever stabilises.
        "/var/run/docker.sock:/var/run/docker.sock:ro"
        "/etc/machine-id:/etc/machine-id:ro"
        "/var/log/journal:/var/log/journal:ro"
        "/etc:/host/etc:ro"
        "/home:/host/home:ro"
        "/root:/host/root:ro"
        "/srv/containers:/host/srv/containers:ro"
        "wazuh_wazuh_agent_etc:/var/ossec/etc"
      ];
      dependsOn = ["wazuh.manager"];
      extraOptions = ["--network=wazuh"];
    };
  };
}

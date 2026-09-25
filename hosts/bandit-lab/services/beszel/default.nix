{lib, ...}: {
  services.beszel = {
    hub = {
      enable = true;
      host = "127.0.0.1";
      port = 8090;
    };

    agent = {
      enable = true;
      environment = {
        DOCKER_HOST = "";
        HUB_URL = "http://127.0.0.1:8090";
        LISTEN = "127.0.0.1:45876";
      };
      environmentFile = "/etc/beszel/agent.env";
    };
  };

  systemd.services.beszel-hub.serviceConfig = {
    MemoryMax = "512M";
    CPUQuota = "50%";
    TasksMax = 128;
  };

  systemd.services.beszel-agent = {
    # The hub must be bootstrapped before these credentials exist. Keep the
    # agent stopped instead of creating a restart loop during the first switch.
    unitConfig.ConditionFileNotEmpty = "/etc/beszel/agent.env";

    serviceConfig = {
      MemoryMax = "256M";
      CPUQuota = "25%";
      TasksMax = 128;
      SupplementaryGroups = lib.mkForce [];
    };
  };
}

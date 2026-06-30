{pkgs, ...}: {
  # Local coding LLM service — exposed on LAN (192.168.1.0/24 only).
  #
  # Primary model:  qwen3-coder:30b
  # Fallback model: dolphincoder:15b
  systemd.tmpfiles.rules = [
    "d /srv/ollama 0750 ollama ollama -"
    "d /srv/ollama/models 0750 ollama ollama -"
  ];

  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
    host = "0.0.0.0";
    port = 11434;
    openFirewall = false;
    user = "ollama";
    group = "ollama";
    home = "/srv/ollama";
    models = "/srv/ollama/models";
    loadModels = [
      "qwen3-coder:30b"
      "dolphincoder:15b"
    ];
    environmentVariables = {
      OLLAMA_FLASH_ATTENTION = "1";
      OLLAMA_KEEP_ALIVE = "30m";
      OLLAMA_MAX_LOADED_MODELS = "1";
      OLLAMA_NUM_PARALLEL = "1";
    };
  };

  # Allow ollama only on LAN interface — WAN stays blocked.
  networking.firewall.interfaces."enp44s0".allowedTCPPorts = [11434];

  environment.systemPackages = [
    pkgs.ollama-cuda
  ];
}

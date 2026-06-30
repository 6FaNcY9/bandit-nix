{
  lib,
  pkgs,
  ...
}: {
  # Local coding LLM service.
  #
  # Primary model:
  #   qwen3-coder:30b   current agentic coding model; best default on this host.
  #
  # Fallback model:
  #   dolphincoder:15b  uncensored coding model; weaker, but useful when you
  #                    explicitly want fewer refusals from a local model.
  #
  # Access from another machine:
  #   ssh -L 11434:127.0.0.1:11434 vino@bandit-lab
  #   OLLAMA_HOST=http://127.0.0.1:11434 ollama run qwen3-coder:30b
  systemd.tmpfiles.rules = [
    "d /srv/ollama 0750 ollama ollama -"
    "d /srv/ollama/models 0750 ollama ollama -"
  ];

  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
    host = "127.0.0.1";
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
      OLLAMA_ORIGINS = "http://127.0.0.1:* http://localhost:*";
    };
  };

  # CUDA JIT needs W+X mmap; nixpkgs hardens this to true by default
  systemd.services.ollama.serviceConfig.MemoryDenyWriteExecute = lib.mkForce false;

  environment.systemPackages = [
    pkgs.ollama-cuda
  ];
}

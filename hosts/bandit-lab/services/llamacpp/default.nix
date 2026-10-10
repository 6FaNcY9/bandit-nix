# Optional Andy-4.2 replay backend; model bytes stay outside the Nix closure.
# Both backends may not fit on one GPU. After the Ollama replay, stop its
# consumers (mcagents), then `systemctl stop docker-ollama` for the A/B.
# Ollama removes /var/lib/ollama-import/andy.gguf after import; stage and verify
# it again per AGENT-TRAINING.md before enabling this container.
{
  config,
  lib,
  ...
}: let
  cfg = config.bandit-lab.llamacpp;
in {
  options.bandit-lab.llamacpp = {
    enable = lib.mkEnableOption "the loopback-only llama.cpp Andy-4.2 replay server";
    mmproj = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/import/mmproj.gguf";
      description = "Optional vision projector GGUF path inside the container, under the read-only /import mount.";
    };
  };

  config = lib.mkIf cfg.enable {
    hardware.nvidia-container-toolkit.enable = true;

    virtualisation.oci-containers.containers.llamacpp = {
      # GHCR server-cuda linux/amd64 manifest, resolved 2026-10-10 (b11515).
      image = "ghcr.io/ggml-org/llama.cpp@sha256:e3f1cdbb7bd8c4d64df34e97336f2b56f67735fb988e074280805b587179f874";
      ports = ["127.0.0.1:8081:8080"];
      volumes = ["/var/lib/ollama-import:/import:ro"];
      cmd =
        [
          "--model"
          "/import/andy.gguf"
          "--alias"
          "andy-4.2-baseline"
          "--host"
          "0.0.0.0"
          "--port"
          "8080"
          "--jinja"
          "--chat-template-kwargs"
          ''{"enable_thinking":false}''
          "--ctx-size"
          "8192"
          "--parallel"
          "1"
          "--n-gpu-layers"
          "99"
          # Match tools/mcagents/agent.js SAMPLING and the Andy-4.2 model card.
          "--temp"
          "0.6"
          "--top-k"
          "20"
          "--top-p"
          "0.95"
          "--min-p"
          "0"
          "--repeat-penalty"
          "1.0"
        ]
        ++ lib.optionals (cfg.mmproj != null) ["--mmproj" cfg.mmproj];
      extraOptions = ["--device=nvidia.com/gpu=all" "--security-opt=no-new-privileges"];
    };

    systemd.services.docker-llamacpp = {
      after = ["nvidia-container-toolkit-cdi-generator.service"];
      wants = ["nvidia-container-toolkit-cdi-generator.service"];
    };
  };
}

# Ollama for the Minecraft agents (Andy-4.2), loopback only, GPU via CDI.
#
# The official image, not nixpkgs' ollama-cuda: that one is not in
# cache.nixos.org (unfree CUDA) and compiled for ~50 min on the laptop - in CI
# (120-minute Cachix job) and on the lab at every nixpkgs bump. The model is
# downloaded once at runtime with its SHA256 checked, so the 5.6 GB GGUF stays
# out of the system closure (and Cachix). Before the first activation stop the
# old user unit on the same port: `systemctl --user disable --now mcagents-ollama`.
{pkgs, ...}: let
  model = {
    url = "https://huggingface.co/Mindcraft-CE/Andy-4.2-GGUF/resolve/d3efcb8137c88cd3c23466ddabf985ea59b52fdf/andy-4.2.q4_k_m.gguf";
    sha256 = "3cfccaa17be8d2ded998fab8bd4b7032f91f2a916ac2aa03a412908342228eb1";
  };
in {
  hardware.nvidia-container-toolkit.enable = true; # writes the CDI spec for nvidia.com/gpu

  virtualisation.oci-containers.containers.ollama = {
    image = "ollama/ollama@sha256:da6e0dc5651df159e45686fd663c4dbe1624a52c44d7280eeac1551d8f865532"; # 0.34.2
    ports = ["127.0.0.1:11434:11434"];
    volumes = ["/srv/ollama:/root/.ollama"];
    environment = {
      OLLAMA_NUM_PARALLEL = "4";
      OLLAMA_KEEP_ALIVE = "30m";
    };
    extraOptions = ["--device=nvidia.com/gpu=all" "--security-opt=no-new-privileges"];
  };

  systemd.tmpfiles.rules = ["d /srv/ollama 0700 root root -"];

  systemd.services.docker-ollama = {
    after = ["nvidia-container-toolkit-cdi-generator.service"];
    wants = ["nvidia-container-toolkit-cdi-generator.service"];
  };

  # Import andy-4.2 once; a later start finds it in Ollama's store and exits.
  systemd.services.ollama-andy = {
    description = "Import the Andy-4.2 model into Ollama";
    after = ["docker-ollama.service"];
    requires = ["docker-ollama.service"];
    wantedBy = ["multi-user.target"];
    path = [pkgs.docker pkgs.curl pkgs.coreutils pkgs.gnugrep];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "1h";
      NoNewPrivileges = true;
      PrivateTmp = true;
    };
    script = ''
      set -euo pipefail
      for _ in $(seq 60); do docker exec ollama ollama list >/dev/null 2>&1 && break; sleep 2; done
      if docker exec ollama ollama list | grep -q '^andy-4.2:'; then exit 0; fi
      d=/srv/ollama/import
      mkdir -p "$d"
      curl -fL --retry 3 -o "$d/andy.gguf" ${model.url}
      echo "${model.sha256}  $d/andy.gguf" | sha256sum -c
      printf 'FROM /root/.ollama/import/andy.gguf\nPARAMETER temperature 0.6\nPARAMETER num_ctx 8192\n' > "$d/Modelfile"
      docker exec ollama ollama create andy-4.2 -f /root/.ollama/import/Modelfile
      rm -f "$d/andy.gguf" # Ollama copied it into its blob store
    '';
  };
}

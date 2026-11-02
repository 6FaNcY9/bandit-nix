# ComfyUI (image generation, Z-Image-Turbo) on the lab GPU via CDI, loopback
# only; reachable by name as the Tailscale Service svc:comfyui
# (hosts/bandit-lab/services/tailnet-https.nix). Same shape as the Ollama
# container in bandit-craft. Models and outputs stay out of the Nix closure
# under /srv/comfyui; the owner drops model files into models/ without sudo.
# Runbook: docs/runbooks/comfyui.md. The GPU (16 GB) is shared with Ollama:
# a generation while Andy-4.2 is resident ends in a CUDA OOM, not in a crash.
{
  config,
  repoConfig,
  ...
}: let
  username = repoConfig.workstation.username;
in {
  hardware.nvidia-container-toolkit.enable = true; # CDI spec for nvidia.com/gpu

  virtualisation.oci-containers.containers.comfyui = {
    image = "docker.io/yanwk/comfyui-boot@sha256:4172d960fe57c630d33f6bd8891aa7ecf55e7768559565c6b74e8d57e44512a9"; # cu128-slim, 2026-05-18
    ports = ["127.0.0.1:8188:8188"];
    volumes = [
      "/srv/comfyui/models:/root/ComfyUI/models"
      "/srv/comfyui/output:/root/ComfyUI/output"
      "/srv/comfyui/user:/root/ComfyUI/user" # saved workflows and settings
    ];
    extraOptions = ["--device=nvidia.com/gpu=all" "--security-opt=no-new-privileges"];
  };

  systemd = {
    tmpfiles.rules = [
      "d /srv/comfyui 0755 root root -"
      "d /srv/comfyui/models 0775 ${username} users -"
      "d /srv/comfyui/output 0755 root root -"
      "d /srv/comfyui/user 0700 root root -"
    ];
    services.docker-comfyui = {
      after = ["nvidia-container-toolkit-cdi-generator.service"];
      wants = ["nvidia-container-toolkit-cdi-generator.service"];
    };
  };
}

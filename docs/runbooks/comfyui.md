# ComfyUI (image generation) on bandit-lab

## State

Trial only (2026-11-02): a throwaway Docker container started by hand, GPU via
CDI like Ollama, GUI bound to `127.0.0.1:8188` on the lab. Nothing in Nix yet.
Model files live in `~vino/comfy/models` on the lab (Z-Image-Turbo, bf16).

Target (not built): an `oci-containers` unit in bandit-craft next to
`hosts/bandit-lab/services/ollama/`, models under `/srv/comfyui`, port published
on `repoConfig.lab.tailscaleIp` with a DOCKER-USER allow-list for Jerry's tailnet
IPs (phone `100.120.86.122`, container `100.102.212.56`, from
`hosts/bandit-lab/services/backup/peer.nix`). ComfyUI has no user accounts, no
per-user limits and one shared queue, so "Jerry limited, owner unlimited" means
two containers (Jerry's with CPU/RAM limits, lower `Nice`), never one shared
instance. VRAM cannot be split on a consumer GPU: both share the 16 GB with
Ollama (`OLLAMA_KEEP_ALIVE=30m`) and the first one that does not fit gets an OOM.

## Model: Z-Image-Turbo

6B, Apache 2.0, 8 steps, fits 16 GB in bf16 (peak ~14.6 GB). Files from
`Comfy-Org/z_image_turbo` on Hugging Face, split layout:

| ComfyUI folder | File | Size |
| --- | --- | --- |
| `diffusion_models/` | `z_image_turbo_bf16.safetensors` | 12.3 GB |
| `text_encoders/` | `qwen_3_4b.safetensors` | 8.0 GB |
| `vae/` | `ae.safetensors` | 0.3 GB |

Alternative with image editing and reference images: FLUX.2 [klein] 4B (Apache
2.0, ~13 GB). Anything bigger (FLUX.2 dev, Qwen-Image) needs 24 GB or more.

## Run the trial (lab, as vino, docker group)

```sh
docker run --rm -d --name comfy --device nvidia.com/gpu=all --security-opt no-new-privileges \
  -p 127.0.0.1:8188:8188 -v ~/comfy/models:/root/ComfyUI/models -v ~/comfy/output:/root/ComfyUI/output \
  docker.io/yanwk/comfyui-boot:cu128-slim
docker logs -f comfy      # until "To see the GUI go to: http://0.0.0.0:8188"
docker stop comfy         # done; --rm removes the container, models stay
```

Laptop: `ssh -N -L 8188:127.0.0.1:8188 bandit-lab`, then http://127.0.0.1:8188
(the trial container is loopback only; the unit will get a `tailscale serve`
port like the other UIs, see `docs/runbooks/tailnet-https.md`).

## Using the GUI

First start shows the default SD 1.5 workflow and a "Missing Models" dialog for
`v1-5-pruned-emaonly-fp16.safetensors`: that is not our model, close it. The
same dialog appears when a template is opened before its files exist or before
ComfyUI has re-read the folders (it caches the listing): press `R` in the canvas,
or reload the page, and open the template again. The dialog's Download button
fetches the file into the right folder, so it is also the lazy way to add a
template's models (needs HF access from the lab, which works).

Templates (top left, or the Workflow menu → Browse Templates) → Image → "Z-Image
Turbo" is the one that matches the three files. The ControlNet and 2k-upscaler
variants need `Z-Image-Turbo-Fun-Controlnet-Union.safetensors` /
`RealESRGAN_x4plus.safetensors` in addition and will report them missing.

- The graph: Load Diffusion Model (`z_image_turbo_bf16`), Load CLIP
  (`qwen_3_4b`, type `lumina2`), Load VAE (`ae`), two CLIP Text Encode nodes
  (positive prompt, the negative is ignored at cfg 1), Empty Latent (size,
  batch), KSampler (seed, steps, cfg), VAE Decode, Save Image.
- Run: the Run button or Ctrl+Enter. Progress bar on the sampler; the image
  shows in Save Image and under Queue (sidebar) → history. First run loads 20 GB
  from disk (a minute), afterwards a few seconds per image.
- Outputs: `~/comfy/output` on the lab (`scp bandit-lab:comfy/output/\*.png .`).
- Knobs: `steps` 8 (turbo, more is not better), `cfg` 1, resolution up to
  1024x1024 is safe in 16 GB; 2048 OOMs without the tiled VAE decode node.
  `seed` control "randomize" for variations, "fixed" to iterate on one image.
  Batch size > 1 costs VRAM linearly.
- Queue is shared: a second user's job waits, nothing runs in parallel.
- `R` refreshes node file lists after adding models; Ctrl+S saves the workflow
  (stored in the container's `user/` dir, gone with `--rm`: export via Workflow
  → Export if it matters).

## Adding models

Copy the file into the matching folder under `~/comfy/models` (later
`/srv/comfyui/models`), then press `R` in the GUI (refresh node lists), or let
the Missing Models dialog of a template download it. Folders:
`checkpoints/` (single-file SD/SDXL), `diffusion_models/` (split models like
Z-Image, FLUX), `text_encoders/`, `vae/`, `loras/`, `controlnet/`, `upscale_models/`.
Download on the lab, not the laptop: `wget -c -O <folder>/<file> <hf-url>`
(`-c` resumes). Only safetensors; refuse `.ckpt`/pickle files from strangers,
they execute code on load.

## If it fails

- `docker: Error response from daemon: could not select device driver`: CDI spec
  missing; `systemctl status nvidia-container-toolkit-cdi-generator`.
- `CUDA out of memory`: Ollama still resident; `docker exec docker-ollama ollama ps`,
  wait for keep-alive or restart the generation after 30 minutes.
- GUI empty node lists: the mount path is wrong; the image expects
  `/root/ComfyUI/models` (check `docker exec comfy ls /root/ComfyUI/models/vae`).

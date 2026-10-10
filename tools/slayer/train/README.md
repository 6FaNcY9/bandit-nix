# Andy-4.2 LoRA on albert

Fine-tune the bots' model (Andy-4.2 = Qwen3.5-9B) with a QLoRA on our own logged decisions, serve the
result through the watcher as a candidate model, and compare it with the idle replay. Windows-native
(no WSL), everything under `A:\bandit-ai\train` (C: is nearly full). Nothing here is run by the
repository; you run it on albert. The PowerShell scripts could not be executed when they were written
(Linux), so expect to fix small things on the first run: that is what step 7 (smoke test) is for.

| Script | What |
| --- | --- |
| `setup.ps1` | uv, Python 3.12, torch 2.14.1+cu130, transformers 5.19, peft, bitsandbytes, llama.cpp b11541 converter |
| `fetch-model.ps1` | Andy-4.2 bf16 safetensors at a pinned revision (19.3 GB), verified |
| `train.py` | QLoRA training, checkpoints, auto-resume, eval loss, `summary.json` |
| `run-guarded.ps1` | runs `train.py` only while the PC is free (uses `C:\bandit-ai\busy.ps1` and `training.lock`) |
| `merge-and-convert.ps1` + `merge.py` | merge adapter, convert to GGUF, quantize to Q4_K_M, print `candidate.json` |

## Sequence

1. **Lab export (once the change is deployed).** The timer `mcagents-dataset.timer` runs daily at ~04:20.
   To get data now: `sudo systemctl start mcagents-dataset && cat /var/lib/mcagents-export/stats.json`.
   `sft.jsonl` has one row per good decision (`source: decision`) or good solver call
   (`source: solver`) with a `split` of train/val/test. Check `rows`: below ~300 rows a LoRA mostly
   learns the format, so let the bots run longer first.
2. **Update the watcher on albert (once).** `watch.ps1` now dot-sources `C:\bandit-ai\busy.ps1` and
   honours `C:\bandit-ai\training.lock`. Sign out of albert (the installer refuses while the watcher
   runs), then from an elevated PowerShell run `install.ps1` again with the original arguments (it
   rewrites `watch.ps1`, the new `busy.ps1` and the rest, and starts nothing); sign in again. Check
   `C:\bandit-ai\runtime\watch.log` shows the server starting as before.
3. **Copy these scripts to albert** (admin ssh from the laptop, repo root):
   `ssh albert "mkdir A:\bandit-ai\train\scripts"` then
   `scp -r tools/slayer/train/. albert:A:/bandit-ai/train/scripts/`
   (if scp rejects the drive path, copy any other way; the folder name does not matter).
4. **Setup** (about 10-20 min, 2 GB torch wheel at 15 MB/s, Idle priority, safe while someone plays):
   `powershell -ExecutionPolicy Bypass -File A:\bandit-ai\train\scripts\setup.ps1`.
   It ends with a line naming the GPU and compute capability `(12, 0)`. Rerun anytime; it only does missing work.
5. **Model** (19.3 GB, about 25 min at 15 MB/s): `...\scripts\fetch-model.ps1`. Rerun to resume.
6. **Data:** `mkdir A:\bandit-ai\train\data` and
   `scp bandit-lab:/var/lib/mcagents-export/sft.jsonl albert:A:/bandit-ai/train/data/` (or run the `scp` on
   the lab towards albert, whichever path your tailnet allows).
7. **Smoke test** (needs a free PC; 5-10 min including model load): 
   `...\scripts\run-guarded.ps1 -Run smoke -TrainArgs '--max-steps','2','--accum','2'`.
   Expect `runs\smoke\summary.json` and no error logs `runs\smoke.err.*.log`. Look at `peak_vram_gb` in
   `runs\smoke\log.jsonl`: under ~14.5 is fine for 16 GB. If it runs out of memory, add
   `'--max-seq','2048'` to `-TrainArgs`.
8. **Train** detached, so it survives the ssh session:
   `Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','A:\bandit-ai\train\scripts\run-guarded.ps1','-Run','andy-lora-1'`.
   Follow `runs\andy-lora-1\log.jsonl` (`step` lines have the loss; `eval` lines the held-out loss) and
   `runs\andy-lora-1.guard.log`. The eval loss should fall in epoch 1 and flatten or rise after epoch 2-3: if
   it rises, merge an earlier checkpoint (`-Adapter runs\andy-lora-1\ckpt-<n>`).
9. **Merge and convert** after `summary.json` exists (about 30-40 min, needs ~20 GB RAM, 18 GB scratch):
   `...\scripts\merge-and-convert.ps1 -Run andy-lora-1`. It prints the `candidate.json` content.
10. **Serve it:** write that JSON to `C:\bandit-ai\candidate.json` (see the candidate section of
    `tools/slayer/README.md`). The watcher uses it the next time it starts the server (restart it by
    starting any game, or stop the server process). The lab sees the model name `andy-lora-andy-lora-1`.
11. **Compare:** the lab's idle replay (`mcagents-idle-replay`) now scores replays with the candidate
    alias; compare its scores in `/var/lib/mcagents/replays` with the earlier `andy-4.2-baseline` ones on
    the same decisions (`tools/mcagents/README.md`). Only the `test` split is untouched by training: replay
    those rows first. Switching the bots to the new model is a separate decision.

## Sizes and times (estimates; the first real run replaces these)

* Disk: downloads/venv ~12 GB, base 19.3 GB, merged 18 GB, final GGUF ~5.5 GB (temporary bf16 GGUF 18 GB),
  checkpoints ~1.5 GB each (two kept). Well within the 1.3 TB.
* VRAM during training: roughly 12-14 GB peak (4-bit body 4.5 GB + bf16 embeddings/lm_head 4 GB + vision 1 GB +
  LoRA/optimizer 1.5 GB + activations). Tight on 16 GB with the desktop; `--max-seq 2048` if needed.
* Speed: batch of one sequence, gradient checkpointing, and no fast kernels for Qwen3.5's linear-attention
  layers on Windows (the slower PyTorch fallback is used), so guess 1,000-2,000 tokens/s. 1,000 rows of
  ~2,500 tokens, 3 epochs: about 1.5-3 hours of free GPU time, spread over however many free windows
  there are. Rows are sequences of about 1,500-3,500 tokens (system prompt + state), loss is only on the reply.

## Stop, pause, roll back

* Pause: `New-Item A:\bandit-ai\train\STOP` (the guard stops training within 15 s, removes the lock and the file).
  Rerun `run-guarded.ps1 -Run <same name>` to continue from the last checkpoint (the data are frozen in the run).
  Anything busy (game, fullscreen app, other GPU load) pauses it the same way by itself.
* Emergency: `taskkill /IM python.exe /F`, then `Remove-Item C:\bandit-ai\training.lock`. A crashed guard leaves the
  lock; the watcher ignores it after 24 h, or delete it.
* Back to Andy-4.2: delete `C:\bandit-ai\candidate.json`. The next server start serves `andy.gguf` again.
  `andy.gguf` and the lab's Ollama model are never touched by any of this.
* Clean up: delete `A:\bandit-ai\train\runs\<name>`, `merged\<name>`, and the model in `A:\bandit-ai\models` plus
  its symlink in `C:\bandit-ai\models`.

## Pins

uv 0.13.0 (SHA256 `088962f9...a656c`), torch 2.14.1+cu130 (wheel SHA256 `0a09031e...15be9`), transformers
5.19.0, peft 0.21.2, bitsandbytes 0.50.2, accelerate 1.15.0, safetensors 0.8.0, sentencepiece 0.2.2,
tokenizers 0.23.3, llama.cpp source b11541 (zip SHA256 `0c05472c...a6870f`; GitHub archives are not guaranteed
byte-stable, so a mismatch means check the tag, not necessarily tampering), Andy-4.2 revision `2992e6f8...`.
Python is uv's managed 3.12 (patch version and its download are not pinned or hash-checked).

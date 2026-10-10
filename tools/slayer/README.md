# Slayer idle inference

`watch.ps1` lives at `C:\bandit-ai\watch.ps1`. Every 15 seconds it yields to
any foreground fullscreen window, the listed game processes, or >=20% GPU engine
use from processes other than llama-server. GPU/window probe errors also stop
inference. A different active console session also pauses inference, so another
Windows user cannot game alongside yassi's watcher. Idle launchers (Steam, Epic,
Battle.net, Riot) do not stop inference; their installed games do, by name or
`steamapps\common`/`Epic Games`/`Riot Games` path. Extend the process list for
games installed outside those paths.
Light games listed one per line in `C:\bandit-ai\light-games.txt` (`#` lines and
blank lines ignored) never count as games and skip the fullscreen rule while
focused; `isaac-ng.exe` and `isaac.exe` are built in. The existing
Andy flags and loopback port 8081 are preserved; only matching bandit-ai server
PIDs are stopped. Logs rotate `watch.log` at 5 MiB to `watch.log.1`.

Install from **yassi's interactive PowerShell**, without elevation, after copying
watch.ps1 to C:\bandit-ai (do not start it while a replay needs the server):

```powershell
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\bandit-ai\watch.ps1'
$trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:COMPUTERNAME\yassi"
$principal = New-ScheduledTaskPrincipal -UserId "$env:COMPUTERNAME\yassi" -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -Hidden -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName bandit-ai-watch -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force
# Optional: start now when no replay needs the server.
Start-ScheduledTask bandit-ai-watch
```

Uninstall (stopping the watcher leaves its last server running):

```powershell
Stop-ScheduledTask bandit-ai-watch
Unregister-ScheduledTask bandit-ai-watch -Confirm:$false
Remove-Item C:\bandit-ai\watch.ps1
# If desired, stop only the bandit-ai server PID shown by this query:
Get-CimInstance Win32_Process -Filter "Name='llama-server.exe'" | Select-Object ProcessId,ExecutablePath,CommandLine
```

Live self-check: use `powershell -NoProfile -ExecutionPolicy Bypass -File
C:\bandit-ai\watch.ps1 -Once -TestPort 28082 -GpuPercent 0` to start an isolated
CPU server, then the same command with `-GpuPercent 99` to stop it. For an SSH
check, execute both in the same remote session (Windows SSH cleans up child
processes at session end). `TestPort` cannot be 8081. The fake GPU value does not
bypass the game/fullscreen checks. Without test parameters the server uses GPU
layers 99, exactly as run.bat does. Interactive fullscreen checks require the
interactive logon task; an SSH one-shot cannot validate another desktop session.

## Lab setup (owner only)

The module is imported but `bandit-lab.slayerTunnel.enable` defaults to false.
Nothing activates until the owner adds the secret and enables the option.
A dedicated public key was installed in Slayer's
`C:\ProgramData\ssh\administrators_authorized_keys`, with
`restrict,port-forwarding,permitopen="127.0.0.1:8081"` restrictions. The private
key remains outside Git at
`/home/vino/.codex/scratchpads/slayer-offload/slayer-tunnel-key` (0600).
Do not replace or remove the owner's other authorized keys.

From the repository root, the owner can encrypt the generated key directly via
stdin (no plaintext key in argv or repository files):

```sh
jq -Rs . /home/vino/.codex/scratchpads/slayer-offload/slayer-tunnel-key |
  sops set --value-stdin secrets/lab.yaml '["slayer-tunnel-key"]'
```

Then set `bandit-lab.slayerTunnel.enable = true;` in the lab host configuration,
review and commit the encrypted secret plus configuration, and follow the normal
committed build/deployment procedure. Do not change .sops.yaml recipients. The
module declares the SOPS secret and uses systemd LoadCredential for its DynamicUser;
it pins Slayer's previously trusted ed25519 host key, retries SSH every 30 seconds,
and listens only on 127.0.0.1:18081. No remote binding or firewall opening is needed.
`mcagents` receives ANDY_URL_2 only when enabled; its existing localhost allow rule
already covers this port. Slayer being busy/offline falls back to lab Ollama.

## Verification in this session

- Hidden, limited interactive logon task registered, left Ready (not started).
- Isolated CPU server reached /health; fake busy GPU stopped only its PID in
  413 ms, preserving the replay's port-8081 PID 4068.
- Dedicated restricted SSH key authenticated and forwarded on laptop port 28081;
  lab Ollama used a separate laptop tunnel on 21435. No existing tunnel was stopped.
- Actual routing, automated routing tests and committed Nix checks are reported
  in the session handoff. No lab activation or push is part of this change.

Limit: fullscreen detection is conservative (fullscreen apps also pause inference)
and background/borderless games rely on the process/path list and GPU counters.
No live game session or real high-GPU-load session was exercised.
||||||| parent of 5e7a8c9 (feat(mcbots): slayer card shows what the gaming PC does)

## slayer (owner's gaming PC)

`slayerpc` runs llama-server (llama.cpp, Andy-4.2) for the Minecraft agents when no game is
running; the lab reaches it at `http://127.0.0.1:18081` through a systemd tunnel. The
dashboard's "slayer" card (`docs/runbooks/minecraft/BOTS.md`, "Slayer card") shows what it does.

## Status file for the GPU line

llama-server cannot serve files, so the watcher (`C:\bandit-ai\watch.ps1`) writes
`C:\bandit-ai\status.json` every 60 s:

```json
{"state": "serving", "gpu": {"util": 31, "vramUsedMB": 9000, "vramTotalMB": 16376, "tempC": 64}}
```

- `state`: `serving` (llama-server is up), `paused-game` (a game runs, llama-server stopped) or `offline`.
- `gpu`: from `nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits`.
  Integers (percent, MB, MB, degrees C). Omit `gpu` when nvidia-smi fails.
- Write it atomically (temp file, then rename) and keep it under 4 KB. A UTF-8 BOM is fine.
- Games win: the file keeps being written while llama-server is stopped, so the card says
  `paused-game` instead of `offline`.

The lab reads it with `SLAYER_STATUS_CMD` (a JSON array, run without a shell every 60 s):

```
SLAYER_URL=http://127.0.0.1:18081
SLAYER_STATUS_CMD=["ssh","slayer","type","C:\\bandit-ai\\status.json"]
```

Output that is not JSON, longer than 4 KB, or has a wrong key/value is ignored; a status older
than 3 minutes is ignored, so a dead watcher or tunnel shows `offline`.
Start llama-server with `--metrics` so the card can show tok/s.
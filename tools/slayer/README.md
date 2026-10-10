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

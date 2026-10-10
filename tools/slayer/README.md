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
focused; `isaac-ng.exe`, `isaac.exe` and Wallpaper Engine (`wallpaper64.exe`,
`wallpaper32.exe`, which lives under `steamapps\common`) are built in. The existing
Andy flags and loopback port 8081 are preserved; only matching bandit-ai server
PIDs are stopped. Any listening socket on the configured port prevents a second
launch, even when another session's process command line cannot be read. While a
child is loading, `watch-$port.pid` records its PID and creation time. A stop
requires the exact executable path plus either a matching listener PID, a
matching command line in the watcher's session, or that recorded identity.
Unidentified listeners are logged and left running when busy. Logs and watcher
state live under `C:\bandit-ai\runtime`; logs rotate `watch.log` at 5 MiB to
`watch.log.1`.

Install from **Windows PowerShell as administrator**, logged in as the gaming
account (or pass its local account name with `-UserName`). No download, archive
extraction or model hashing runs in the foreground. Allow about two minutes for
local setup; OpenSSH installation and low-priority BITS downloads continue in a
hidden SYSTEM task, including after logout. That timing has not been measured on
a clean Windows install.

The watcher task is enabled for the next logon with a limited interactive user,
hidden settings and `wscript.exe C:\bandit-ai\watch.vbs`; it is never started or
restarted by the installer. The VBS launcher prevents console flash/focus theft.
If a watcher is already running, installation stops before making changes; sign
out before upgrading. Existing light-games entries, unrelated authorized keys
and an existing llama-server installation are preserved. The same command can
be rerun after provisioning finishes; do not run it from `C:\bandit-ai\runtime`.

**SCP + run**, when the PC already has SSH access (replace the IP/account/key
for another PC). From the laptop in this repository:

```sh
scp -o IdentitiesOnly=yes -i ~/.ssh/slayerKey tools/slayer/install.ps1 yassi@100.76.40.98:C:/Users/yassi/Desktop/bandit-install.ps1
```

The owner pastes this one command into elevated Windows PowerShell, substituting
real public keys for the two placeholders:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\Desktop\bandit-install.ps1" -UserName yassi -TunnelPublicKey 'ssh-ed25519 AAAA... lab-tunnel' -CoordinatorPublicKey 'ssh-ed25519 AAAA... coordinator'
```

**Paste-the-file**, including a fresh PC without SSH: open Notepad, paste the
entire repository `install.ps1`, and save it as `bandit-install.ps1` on the
Desktop (Save as type **All files**, not `.txt`). Paste the same command above
into elevated Windows PowerShell with that PC's account name and public keys.
The installer embeds the watcher, VBS launcher and default allowlist; no other
file or remote script evaluation is needed. `test-install.ps1` checks payload
parity when those source files change. Never use `irm | iex`.

The tunnel key receives
`restrict,port-forwarding,permitopen="127.0.0.1:8081"`; coordinator keys receive
normal login access. Prior copies of the supplied keys are replaced, other keys
are preserved. ACLs use SYSTEM/Administrators SIDs rather than localized group
names. Only `runtime` is writable by the limited watcher user. The built-in
OpenSSH firewall rule is disabled before sshd starts; the replacement allows
TCP 22 from `100.64.0.0/10` only. Tailscale must already be installed and joined.

The pinned [llama.cpp b11541 assets](https://github.com/ggml-org/llama.cpp/releases/expanded_assets/b11541)
are the CUDA 13.4 x64 build and its companion CUDA runtime ZIP, both checked
against the release's SHA-256 values in `install.ps1`. This meets the CUDA 12.8+
requirement for RTX 50xx; the PC must already have a driver supporting CUDA 13.4
and the Microsoft Visual C++ x64 runtime. The installer does not upgrade GPU
drivers during a game. The Andy URL pins commit
`d3efcb8137c88cd3c23466ddabf985ea59b52fdf`, SHA-256
`3cfccaa17be8d2ded998fab8bd4b7032f91f2a916ac2aa03a412908342228eb1`.
The watcher checks that hash before serving and rechecks after a file changes;
it samples game activity again after hashing. Its verification cache is in
memory, never a writable "verified" file.

Provisioning retries failures three times at five-minute intervals. Inspect
`Get-ScheduledTaskInfo bandit-ai-provision` for `LastTaskResult`; zero means
completion. A running server is left untouched and causes a deferred retry.
After a transient failure beyond those retries, rerun the installer to retry.
A pre-existing model with a different checksum is preserved and blocks
provisioning until the owner explicitly moves it aside.

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

`test-watch.ps1` checks listener and process ownership with mocked CIM results.
`test-watch-live.ps1`, beside the watcher on Slayer, checks duplicate suppression,
idle start and busy stop on CPU-only port 28083, preserving the healthy port-8081
server. Run with `powershell -NoProfile -ExecutionPolicy Bypass -File <test>` in
an idle session; the live test requires port 28083 to be free and cleans up its
own listener and child.

## Lab integration

The existing `bandit-lab.slayerTunnel.enable = true;` remains compatible, with
Slayer's address, host key, port 18081, system user and `slayer-tunnel-key` secret.
For another PC, add a host to the lab configuration:

```nix
bandit-lab.inferenceHosts.second = {
  enable = true;
  address = "100.64.1.2";
  user = "gamer";
  hostKey = "ssh-ed25519 AAAA..."; # verify the PC's public host key separately
  localPort = 18082; # distinct loopback port per PC
};
```

Each enabled host gets a `<name>-tunnel` system user and service, a pinned SSH
host key and systemd `LoadCredential` from `<name>-tunnel-key`. The matching
private key must already be provisioned by the owner through SOPS; enabling a
new host does not generate or encrypt keys. This change edits neither
`secrets/` nor `.sops.yaml`. Keep private keys outside Git.

`mcagents` receives comma-separated `ANDY_URLS` and `ANDY_BACKEND_NAMES` for
enabled hosts, Slayer first, then alphabetical names. `ANDY_URL_2` remains the
Slayer alias. Healthy backends with fewer in-flight calls win; ties follow that
order, with lab Ollama last. Request failures try the remaining backends.
Decision logs record the backend name. Disabling a host removes its tunnel and
routing entry. Nothing here activates the lab; build and follow the normal
owner deployment procedure separately.

Limit: fullscreen detection is conservative (fullscreen apps also pause inference)
and background/borderless games rely on the process/path list and GPU counters.
No live game session or real high-GPU-load session was exercised.

## slayer (owner's gaming PC)

`slayerpc` runs llama-server (llama.cpp, Andy-4.2) for the Minecraft agents when no game is
running; the lab reaches it at `http://127.0.0.1:18081` through a systemd tunnel. The
dashboard's "slayer" card (`docs/runbooks/minecraft/BOTS.md`, "Slayer card") shows what it does.

## Optional status file for the GPU line

The separate Slayer dashboard probe can consume `C:\bandit-ai\status.json`
from an independently configured status writer. This repository watcher does
not produce that file. The restricted inference key permits forwarding only,
so status-file collection requires a separately authorized coordinator key.

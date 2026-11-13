# bandit-net Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One view of all the user's devices, commands from one place, and Ollama requests routed to the idle PCs `albert` and `slayer` without anyone at those PCs noticing.

**Architecture:** Each Windows PC runs a small agent (`bnet-agent`) that classifies the PC as `unavailable | heavy | light | media | idle` every 5 s, serves that state over Tailscale, and controls a local Ollama (start/stop, GPU power limit on albert). On bandit-lab a router service (`bnet-router`) polls the agents, exposes an Ollama-compatible endpoint that forwards each request to a PC that may take it (else the lab's own Ollama), and publishes a device list that the memory page shows. Hardware metrics come from the Beszel hub that already runs on the lab; commands are a thin SSH fan-out CLI (`bnet`) used from pong or the laptop.

**Tech Stack:** PowerShell 7 + Pester 5 (Windows agent), Python 3 stdlib + pytest (router), NixOS module in `bandit-nix`, Beszel agent (Windows/Linux), Ollama, Tailscale, OpenSSH, zsh/sh (CLI).

**Spec:** `2026-11-13-device-net-design.md` (same folder, docs/specs/bnet/).

## Global Constraints

- Idle = **10 minutes without mouse/keyboard input**; a job stops **immediately** when the PC leaves the allowed state.
- Media playing, a fullscreen app, or a "display required" request = **in use** (state `media`), never idle.
- Heavy use (GPU and CPU both high) = no job. Light use with headroom = job allowed at lowest priority: GPU < 50 % and CPU < 50 % averaged over the last **3 min**, re-checked every **5 s**.
- albert (RTX 5090) must never be audible: jobs run with the GPU power limit at **40 %** of default (`silence_power_pct = 40`); if the limit cannot be applied, albert takes no job.
- Locked screen or nobody logged in = `unavailable`. No Wake-on-LAN, no keeping PCs awake.
- Visible: while a job runs on a PC, a tray icon/toast on that PC says so.
- Only the user may send commands or jobs: every agent/router endpoint that changes anything requires the token in `/etc/bnet/token` (lab) / `C:\ProgramData\bnet\token` (PCs). Read-only `GET /state` and `GET /devices` require it too (they reveal presence).
- Albert: push access to aiia repos only, no shell on bandit-lab. No status written into Basic Memory notes.
- Devices of other tailnet users are never polled or listed. Device list is the fixed table in `bnet-router` config.
- Lab changes go through `bandit-nix` (flake, deploy as the repo already does via `lab-apply`); pong rules from CLAUDE.md still apply (no `/data/adb` changes without the user's OK).

## Review Focus

1. A film paused on albert for 30 min (no input, no media playing, fullscreen player still open) → must stay `media`, not `idle` (fullscreen check). Test in Task 1.
2. Agent unreachable mid-request (PC goes to sleep) → router retries the request on the next allowed worker or the lab, the caller gets one answer, not an error. Test in Task 4.
3. State flaps between `light` and `heavy` every few seconds during a game → no job start/stop storm: a job only (re)starts after the state held `idle`/`light` for 60 s. Test in Task 1.
4. `nvidia-smi -pl` fails (driver update, no admin) on albert → albert reports `job_allowed=false`, router never sends there. Test in Task 3.
5. Token missing/wrong → 401 on every agent and router endpoint, including GET. Tests in Tasks 2 and 4.

---

### Task 0: Repo home

**Files:**
- Create: `bandit-nix/docs/superpowers/specs/2026-11-13-device-net-design.md` (copy of spec)
- Create: `bandit-nix/docs/superpowers/plans/2026-11-13-device-net-plan.md` (this file)
- Create: `bandit-nix/tools/bnet/` (Windows agent, CLI), `bandit-nix/hosts/bandit-lab/services/bnet/` (router + module)

- [ ] **Step 1:** On the laptop, new worktree `~/src/bandit-nix-bnet` on branch `feat/bnet` from `origin/main`; copy spec and plan in.
- [ ] **Step 2:** Commit `docs: bandit-net design and phase-1 plan`.

### Task 1: State classifier (Windows agent core)

**Files:**
- Create: `tools/bnet/windows/BnetState.psm1`
- Test: `tools/bnet/windows/tests/BnetState.Tests.ps1`

**Interfaces:**
- Produces: `Get-BnetState -Sample <hashtable> -History <object[]> -Now <datetime>` → `[pscustomobject]@{ State = 'unavailable'|'heavy'|'light'|'media'|'idle'; JobAllowed = [bool]; Since = [datetime] }`.
  Sample keys: `SessionActive [bool]`, `Locked [bool]`, `InputIdleSec [int]`, `Fullscreen [bool]`, `MediaPlaying [bool]`, `DisplayRequired [bool]`, `CpuPct [double]`, `GpuPct [double]`, `Time [datetime]`.
  History = previous samples (last 3 min) and the previous result.

- [ ] **Step 1: Write the failing tests**

```powershell
Describe 'Get-BnetState' {
  It 'no session or locked is unavailable'        { (Get-BnetState (S @{SessionActive=$false}) @() $t).State | Should -Be 'unavailable'
                                                     (Get-BnetState (S @{Locked=$true}) @() $t).State | Should -Be 'unavailable' }
  It 'fullscreen with no input for 30 min is media' { (Get-BnetState (S @{InputIdleSec=1800; Fullscreen=$true}) @() $t).State | Should -Be 'media' }
  It 'media or display-required is media'          { (Get-BnetState (S @{MediaPlaying=$true}) @() $t).State | Should -Be 'media'
                                                     (Get-BnetState (S @{DisplayRequired=$true}) @() $t).State | Should -Be 'media' }
  It '10 min no input is idle, 9 min is not'      { (Get-BnetState (S @{InputIdleSec=600}) @() $t).State | Should -Be 'idle'
                                                     (Get-BnetState (S @{InputIdleSec=540; CpuPct=80; GpuPct=80}) (H 80 80) $t).State | Should -Be 'heavy' }
  It 'both under 50% over 3 min with input is light' { (Get-BnetState (S @{InputIdleSec=5; CpuPct=20; GpuPct=30}) (H 20 30) $t).State | Should -Be 'light' }
  It 'one spike over 50% in the window is heavy'  { (Get-BnetState (S @{InputIdleSec=5; CpuPct=20; GpuPct=30}) (H 20 30 -Spike) $t).State | Should -Be 'heavy' }
  It 'job allowed only after 60 s in idle/light'  { $r = Get-BnetState (S @{InputIdleSec=600}) (Prev 'heavy' $t.AddSeconds(-5)) $t; $r.JobAllowed | Should -BeFalse
                                                     $r = Get-BnetState (S @{InputIdleSec=600}) (Prev 'idle' $t.AddSeconds(-61)) $t; $r.JobAllowed | Should -BeTrue }
}
```
(`S` builds a sample with defaults `SessionActive=$true, Locked=$false, InputIdleSec=0, Fullscreen=$false, MediaPlaying=$false, DisplayRequired=$false, CpuPct=10, GpuPct=10`; `H` builds 36 samples (3 min at 5 s); `Prev` builds a history whose last result has that state and `Since`.)

- [ ] **Step 2:** `pwsh -c "Invoke-Pester tools/bnet/windows/tests"` → FAIL (module missing).
- [ ] **Step 3:** Implement `Get-BnetState` in `BnetState.psm1`. Order of checks: unavailable → media → idle (≥ 600 s) → light/heavy by 3-min averages *and* max (any sample ≥ 50 % in either metric = heavy). `JobAllowed` = state in (idle, light) and that state (or the other of the two) held ≥ 60 s.
- [ ] **Step 4:** Run tests → PASS. (Pester runs on the laptop via `nix shell nixpkgs#powershell`.)
- [ ] **Step 5:** Commit `feat(bnet): windows state classifier`.

### Task 2: Agent service, sensors and HTTP endpoint

**Files:**
- Create: `tools/bnet/windows/bnet-agent.ps1` (SYSTEM service loop + HTTP), `tools/bnet/windows/bnet-sensor.ps1` (runs in the user session at logon, writes `C:\ProgramData\bnet\session.json` every 5 s), `tools/bnet/windows/install.ps1`
- Test: `tools/bnet/windows/tests/Agent.Tests.ps1`

**Interfaces:**
- Consumes: `Get-BnetState` (Task 1).
- Produces: HTTP on the PC's Tailscale IP, port **47800**, header `Authorization: Bearer <token>`:
  - `GET /state` → `{"host":"albert","state":"idle","job_allowed":true,"since":"…","gpu_pct":3,"cpu_pct":4,"job":null|"ollama","silence":true|false}`
  - `POST /job/start` body `{"kind":"ollama"}` → 200 / 409 if `job_allowed=false`
  - `POST /job/stop` → 200
  Ollama on the PC listens only on `127.0.0.1:11434`; the agent proxies `POST /ollama/*` to it while a job is allowed (so Ollama is never exposed directly).

- [ ] **Step 1: Write failing tests**: `GET /state` without token → 401; with token → 200 and keys above; `POST /job/start` when `job_allowed=false` → 409; session.json older than 30 s → state `unavailable`.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement. Sensor uses `GetLastInputInfo`, foreground-window-covers-monitor for `Fullscreen`, `Windows.Media.Control` session manager for `MediaPlaying`, `powercfg /requests` (in the SYSTEM part) for `DisplayRequired`; agent reads CPU via `Get-Counter '\Processor(_Total)\% Processor Time'`, GPU via `nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits`. Listener: `System.Net.HttpListener` bound to the Tailscale IP only. `install.ps1`: creates `C:\ProgramData\bnet\` (ACL: SYSTEM + Administrators), writes token, registers scheduled task `bnet-agent` (SYSTEM, at startup) and `bnet-sensor` (any user, at logon), opens firewall port 47800 for the Tailscale interface only.
- [ ] **Step 4:** Run tests → PASS.
- [ ] **Step 5:** Commit `feat(bnet): windows agent service and sensor`.

### Task 3: Job control, silence and visibility

**Files:**
- Modify: `tools/bnet/windows/bnet-agent.ps1`
- Create: `tools/bnet/windows/config.albert.json` (`{"silence": true, "silence_power_pct": 40}`), `config.slayer.json` (`{"silence": false}`)
- Test: `tools/bnet/windows/tests/Jobs.Tests.ps1`

**Interfaces:**
- Produces: `Start-BnetJob`, `Stop-BnetJob`, `Set-BnetSilence -On/-Off` (internal); `GET /state` field `silence` and `job`.

- [ ] **Step 1: Failing tests:** state leaves idle/light while job runs → `Stop-BnetJob` called within one tick and Ollama model unloaded (`ollama stop <model>` mocked); albert with failing `nvidia-smi -pl` (mock exit 1) → `job_allowed=false`, `POST /job/start` → 409; job start shows toast (mocked `New-BurntToastNotification` or `msg.exe`) and tray state; job stop restores the GPU default power limit.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement. Ollama runs as a Windows service set to *Manual*; start = `Start-Service ollama` + (albert) `nvidia-smi -pl <40 % of default>` first, refuse job if it fails; job process priority `Idle`; stop = `ollama stop` all loaded models, `Stop-Service ollama`, restore power limit. Light state: CPU affinity left alone, priority Idle only.
- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit `feat(bnet): job control with silence limit and notice`.
- [ ] **Step 6 (manual, at albert with the user):** run a model while the room is quiet; confirm fans inaudible at 40 %. If audible, lower `silence_power_pct` and note the value in the config.

### Task 4: Router on bandit-lab

**Files:**
- Create: `hosts/bandit-lab/services/bnet/router.py`, `hosts/bandit-lab/services/bnet/default.nix`, `hosts/bandit-lab/services/bnet/devices.json`
- Modify: `hosts/bandit-lab/default.nix` (import `./services/bnet`)
- Test: `hosts/bandit-lab/services/bnet/test_router.py`

**Interfaces:**
- Consumes: agent API (Task 2/3).
- Produces (listen on the lab's Tailscale IP, port **47810**, bearer token):
  - `GET /devices` → `[{"host","kind":"pc|phone|laptop|server","online":bool,"state":str|null,"job":str|null,"last_seen":iso}]`
  - `POST /api/*` and `GET /api/*` → Ollama API, forwarded to the first worker in `devices.json` order with `job_allowed=true` (agent `/ollama/*`), else the lab's own Ollama (`127.0.0.1:11434`).
  - `pick_worker(states: dict[str, dict]) -> str | None` (pure; tested directly).

- [ ] **Step 1: Failing tests:** `pick_worker` prefers albert over slayer when both allowed, skips `job_allowed=false` and stale (> 15 s) states, returns None → lab; worker connection drop mid-request → retried once on next worker/lab, client gets 200; missing/wrong token → 401 on `/devices` and `/api/tags`; `devices.json` hosts outside the list are never polled.
- [ ] **Step 2:** `pytest hosts/bandit-lab/services/bnet` → FAIL.
- [ ] **Step 3:** Implement with `http.server.ThreadingHTTPServer` + `urllib`; poll agents every 5 s in a thread. Before forwarding, `POST /job/start` on the chosen worker (409 → next). Streamed Ollama responses are relayed chunk by chunk. `default.nix`: systemd service `bnet-router` (DynamicUser, `LoadCredential=token:/etc/bnet/token`), firewall port 47810 on `tailscale0` only.
- [ ] **Step 4:** Run → PASS; `nix build .#nixosConfigurations.bandit-lab.config.system.build.toplevel` (targeted, not full `flake check`).
- [ ] **Step 5:** Commit `feat(bnet): lab router for devices and ollama`.

### Task 5: Status on the memory page + Beszel agents

**Files:**
- Modify: `hosts/bandit-lab/services/memory/ui/index.html` (new "Geräte" section), `hosts/bandit-lab/services/memory/default.nix` (memory-web proxies `/bnet/devices` → router with the token server-side, so the browser never holds it)
- Create: `docs/runbooks/bnet-beszel-agents.md`

- [ ] **Step 1: Failing check:** `curl -s https://memory.tail7facc9.ts.net/bnet/devices` from pong returns JSON with all hosts of `devices.json` (fails before the change).
- [ ] **Step 2:** Implement the proxy route and the section: one row per device, columns Gerät, online, Zustand (idle/light/heavy/media/unavailable in the Pong Retro colours), Job, zuletzt gesehen; link per device to its Beszel page.
- [ ] **Step 3:** Install Beszel agents on albert, slayer (Windows agent, `winget install henrygd.beszel-agent` or the release MSI) and the laptop (NixOS `services.beszel.agent`), registered to the existing hub; document in the runbook. Phones: no Beszel (status from `bnet` CLI ping only).
- [ ] **Step 4:** Re-run the check → PASS; open the page and see all devices.
- [ ] **Step 5:** Commit `feat(bnet): devices on memory page, beszel agents runbook`.

### Task 6: `bnet` CLI for commands

**Files:**
- Create: `tools/bnet/bnet` (POSIX sh; runs on pong/Termux and the laptop), `tools/bnet/hosts` (name → ssh target, group)
- Test: `tools/bnet/test_bnet.sh`

**Interfaces:**
- Produces: `bnet status` (calls router `/devices`), `bnet run <host|group> -- <cmd>` (parallel ssh, prefixes output with host), `bnet run --disruptive <host|group> -- <cmd>`: per PC, if agent state is not `idle`/`unavailable`, show a notice on that PC (`msg * "…"` ) and wait 2 min, abort on Ctrl-C.

- [ ] **Step 1: Failing tests** (ssh mocked by a stub on PATH): group `pcs` expands to albert + slayer; output lines prefixed `[albert]`; `--disruptive` on a `light` PC sends the notice before the command; unknown host → exit 2.
- [ ] **Step 2:** Run `sh tools/bnet/test_bnet.sh` → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit `feat(bnet): command cli`.

### Task 7: Rollout and access

- [ ] **Step 1:** With the user at albert: create the user-controlled local admin account, enable OpenSSH key login for it from the laptop and pong (accept host keys), run `install.ps1` with `config.albert.json`. Same at slayer (admin account exists) with `config.slayer.json`.
- [ ] **Step 2:** Generate the token (`openssl rand -hex 32`), place it on the lab (`/etc/bnet/token`, root 0600) and both PCs (installer); never into Basic Memory or git.
- [ ] **Step 3:** Merge `feat/bnet`, deploy the lab the usual way, check `systemctl status bnet-router` and `bnet status` from pong.
- [ ] **Step 4:** Verify Albert's path: he pushes aiia work the way he already does (GitHub → lab image); confirm he has no shell account on the lab (`getent passwd` shows only `vino`) and cannot reach port 47810 without the token.
- [ ] **Step 5:** End-to-end: with nobody at albert for 10 min, `curl` an Ollama generate through the router → served by albert, toast visible, fans inaudible; move the mouse → job stops within 5 s, next request goes to slayer or the lab.
- [ ] **Step 6:** Update `projects/pong-phone` (and a new `projects/bandit-net` note) in Basic Memory: what is live, how to use `bnet`, open phase-2 items (bots, builds, Tab S9 once rooted).

## Side item (not part of bnet)

- The phone's `~/.claude/memory-proxy.js` got a re-login-on-404 fix on 2026-11-13; the repo copy `bandit-nix/tools/memory-proxy.js` still has the old code. Port it in the same branch (one small commit).

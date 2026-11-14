# Device network ("bandit-net") — design

Date: 2026-11-13. Owner: the user (admin of all devices below). Written on pong from the brainstorming conversation.

## Intent

The user wants all of their devices to work as one network that they manage from one place, and wants the
idle PCs to give their compute to bandit-lab. bandit-lab already runs the user's Minecraft worlds with bots,
the `aiia` stack that friend Albert works on, Ollama and the shared memory server. Two friends use two of the
user's PCs: Albert uses PC `albert` (works on aiia), Yassin uses PC `slayer`. bandit-lab should be able to give
both of them work: tasks for them as people, and compute jobs for their PCs while nobody uses them.

## Devices (from `tailscale status`, 2026-11-13)

| Device | Tailnet name | OS | Role |
|---|---|---|---|
| bandit-lab | bandit-lab (tagged) | NixOS 26.11 | hub: runs aiia (podman), mc-public container, Ollama (docker), memory server |
| laptop bandit | bandit | NixOS + Hyprland | the user's workstation |
| PC albert | albert | Windows, OpenSSH on :22, RTX 5090 | Albert's seat; silent worker when idle |
| PC slayer | slayerpc | Windows, OpenSSH on :22 (often offline) | Yassin's seat; worker when idle |
| phone pong | pong | Android 16, rooted, Termux | status + commands only |
| Galaxy Tab S9 | not in tailnet yet | Android (user is about to root it) | status + commands only |
| user's other tablet | unknown | unknown | status + commands only |

The tailnet is shared with devices of other people (jerrecode, reumanno, klapetz.velislav, 6m9jsftdky).
Those are not part of this project and must not be managed or scanned.

## Goals

1. **One place to see everything:** for each of the user's devices: online, idle or in use, load, battery
   (mobile), last seen. Shown on the existing memory web page (memory.tail7facc9.ts.net) rather than a new
   dashboard.
2. **Commands from the hub:** the user can run a command on one device or a group from bandit-lab or pong
   (e.g. update, reboot a PC, show status).
3. **Idle compute:** `albert` and `slayer` accept compute jobs from bandit-lab only while idle. Job kinds in
   order of value: Ollama inference (bigger models than the lab can run alone), bot/simulation runs for the
   Minecraft worlds, builds (e.g. the pong kernel; KMI android12-5.10, normally built in GitHub Actions).
4. **Tasks for people:** Albert and Yassin get their tasks through the task lists that already exist in the
   shared memory (`projects/<name>` notes, `## Tasks` checkboxes, shown on the memory page). bandit-lab may
   add tasks there.
5. **Tab S9 joins** once rooted: Tailscale + Termux + the same status agent as pong.

## Non-goals

- Phones and tablets do no compute jobs (battery, heat).
- No cluster scheduler (Kubernetes, Nomad, Slurm). Jobs are few and coarse.
- No remote desktop takeover of the friends' sessions; no access to their files.
- Devices of other tailnet users are out of scope.

## Anti-goals (would count as failure even if it technically works)

- Albert or Yassin notice lag, fan noise or a slow game because of a job.
- A job keeps running after someone touches the PC.
- Compute happens silently: the friends must be able to see when their PC works for the lab.
- Anything that weakens the pong's root hiding / Play Integrity, or writes secrets to the shared memory.

## Decided (by the user or as the agreed proposal)

- bandit-lab is the hub. Tailscale is the network (already in place); no new VPN.
- Idle rule: a PC counts as idle after **10 minutes without mouse/keyboard input**; a job must stop or pause
  **immediately** when input returns.
- Status and tasks are shown on the existing memory page.
- PCs show visibly when they work for the lab (assistant's call: a tray icon or toast on Windows).
- The user owns both PCs; Albert and Yassin are informed and agree (confirmed by the user 2026-11-13).

## Constraints

- Windows idle time cannot be read from an SSH session (session 0 isolation): it needs a small agent running
  in the logged-in user's session (e.g. a scheduled task at logon) that reports `GetLastInputInfo`.
- slayer is often offline; everything must tolerate devices coming and going.
- pong: the shared Basic Memory store holds no secrets; pong's root rules (no /data/adb changes without the
  user's OK) still apply to any agent installed there.
- The Tab S9 is not rooted yet; rooting trips Samsung Knox permanently (the user has been told).

## Settled after the builder check (assistant's calls unless marked)

- Memory page: it is the user's own `memory-web` service on bandit-lab (built 2026-11-11, see
  `projects/shared-memory`), so a live status section is a small change there. Status is NOT written into
  memory notes (would flood the store); it lives in the hub's own state.
- bandit-lab currently has a single login user (`vino`). From the laptop there is no SSH trust to `albert`
  yet (unknown host key), so the Windows agents need a first manual install at each PC.
- "No logged-in session" or a locked screen with no recent input counts as **unavailable**, not idle
  (no detector there). No Wake-on-LAN and no keeping PCs awake in v1.
- Ollama goal means **routing whole requests** to a PC with a bigger GPU, not splitting one model across
  machines (splitting clashes with "stop immediately").
- Tasks for Albert and Yassin go into the existing project notes they work on (e.g. aiia); automatic task
  writes by the hub need the user's review first.
- Bot runs and builds on Windows (needing WSL2/Docker) are phase 2; v1 = status, commands, Ollama routing.

## Quiet rules (user, 2026-11-13)

- **albert** (the tower with the RTX 5090): its fans must never be audible, because people watch films and
  sleep near it. Jobs there run with the GPU power-limited and fans capped so the PC stays silent; the
  builder measures and sets the limit (assistant's call: start low, e.g. ~40% power, raise only while
  inaudible). If silence cannot be held, no job runs.
- **slayer**: no quiet hours.
- **Idle needs more than "no input"** (assistant's call, follows from the above): watching a film means no
  mouse/keyboard for a long time while the PC is in use. A PC playing media, showing a fullscreen app or
  holding a "display required" power request counts as **in use**, never idle.
- **Sharing while someone is at the PC (user, 2026-11-13):** "in use" is not all-or-nothing. A heavy game
  (GPU and CPU both under high load) means **no job**. If the person is doing something light (a light game,
  browsing) and there is clear headroom, a job may use the **spare capacity** at the lowest CPU/GPU priority.
  It stops at once when load rises. Thresholds are the builder's call (assistant's suggestion: GPU and CPU each
  under ~50% over the last few minutes, re-checked every few seconds). The albert silence rule still wins:
  on albert, no job may make the fans audible, whatever the load.

## Access roles (user, 2026-11-13)

- **The user** is the only admin: device control, commands and jobs are reachable for the user only
  (own login, not open to other processes or accounts on bandit-lab).
- **Albert** does design work on aiia and must be able to **push his work** (git) to the lab. He gets
  push access to the aiia repo(s) only: no shell on bandit-lab, no access to the device controls.
- **On albert and slayer** the user gets full admin (shell), like on the own devices. Disruptive actions
  (reboot, updates that restart, heavy jobs) only run when the PC is idle or after a visible notice to the
  person sitting there (user's "jup" to full admin; the idle/notice guard is the assistant's call).
- **Windows admin accounts:** slayer already has an admin account the user controls; albert does not yet.
  The user owns both towers, so creating a user-controlled admin account on albert is part of setup
  (done once at the PC).
- **Yassin**: not specified yet; assume the same pattern as Albert (push to his own repos only).

## Left to the builder

- How status is collected (agent push vs. hub polling over Tailscale SSH) and where it is stored.
- How jobs are queued, sent and stopped; how Ollama on the PCs is exposed to the lab (e.g. only on the
  Tailscale interface).
- How the Windows agent is installed and updated; tray/toast implementation.
- Tailscale ACL changes needed so only the user's devices can reach the agents.
- Exact layout of the status section on the memory page.

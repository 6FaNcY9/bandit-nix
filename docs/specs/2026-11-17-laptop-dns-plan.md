# Laptop DNS (only Blocky on the tailnet) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On the tailnet the laptop asks only Blocky; when Blocky is unreachable it falls back to router + Cloudflare/Quad9 by itself.

**Architecture:** A laptop-only module forces the global resolved `Domains` to empty, so `tailscale0` (`~.`) is the only best route. A root service `dns-guard` probes Blocky every 10 s and flips `tailscale set --accept-dns` after 2 equal results in a row.

**Tech Stack:** NixOS module, `pkgs.writeShellApplication`, bash, `dig` (bind), `tailscale`, `resolvectl`.

**Spec:** `docs/specs/2026-11-17-laptop-dns-design.md`

## Global Constraints

- Laptop only. Do not edit `modules/system/network.nix` (the lab imports it via `modules/server/default.nix`). Import the new module from `modules/system/default.nix` (laptop-only list).
- Blocky address `100.125.161.81`; probe `dig +time=1 +tries=1 @100.125.161.81 p<random>.example.com`; interval 10 s.
- OK = dig output contains `status: NOERROR` or `status: NXDOMAIN`; anything else is a fail.
- 2 fails in a row → `tailscale set --accept-dns=false`; 2 OKs in a row → `tailscale set --accept-dns=true`; after each successful set → `resolvectl flush-caches`.
- Start state is unknown: the first 2-in-a-row verdict always applies. State changes only when `tailscale set` exits 0.
- The loop never exits; unit has `Restart=always`. writeShellApplication adds `set -euo pipefail`, so every command that may fail must be guarded.
- No change to `tools/waybar-dns.sh`, the lab, or the Tailscale admin console. No full `nix flake check` (OOM on the laptop).

## Review Focus

- dig times out (exit 9, no `status:` line) → counted as fail, script keeps running (test `timeout keeps running`).
- tailscaled stopped / `tailscale set` exits non-zero → no flush, retried on the next tick (test `set fails retries`).
- Flaky link (alternating ok/fail) → no switch at all (test `alternating no switch`).
- Boot with `accept-dns=false` left over and Blocky reachable → set true after 2 ticks (test `unknown start sets`).
- Same state repeated → `tailscale set` called once only (test `no repeat set`).

---

### Task 1: `tools/dns-guard.sh` with stub test

**Files:**
- Create: `tools/dns-guard.sh`
- Test: `tools/dns-guard.test.sh` (same shape as `tools/waybar.test.sh`: `set -euo pipefail`, ERR trap, temp dir, `stub`, stubs first on PATH, final `echo ok`)

**Interfaces:**
- Produces: `tools/dns-guard.sh`, no args, runs forever; on each state change prints one line `dns-guard: blocky ok -> accept-dns=true` / `dns-guard: blocky unreachable -> accept-dns=false` (journal).

- [ ] **Step 1: Write the failing test.** Stubs:
  - `dig`: logs its args to `$t/dig.log`, pops the next word from `$t/seq` (`ok` → prints `;; ->>HEADER<<- opcode: QUERY, status: NOERROR`; `nx` → `status: NXDOMAIN`; `servfail` → `status: SERVFAIL`; `timeout` → prints `;; connection timed out` and exits 9).
  - `tailscale`: logs args to `$t/ts.log`; exits 1 while `$t/ts-fail` holds a number > 0 (decrement it), else 0.
  - `resolvectl`: logs args to `$t/rv.log`.
  - `sleep`: counts calls in `$t/n`; when the count reaches the number of words in `$t/seq`, `kill -TERM "$PPID"`.
  - Helper `run <words…>`: writes words to `$t/seq`, clears logs, runs `bash "$here/dns-guard.sh"` and ignores its exit status.

  Cases (assert exact log contents with `diff <(printf …) file` or `grep -c`):
  - `unknown start sets`: `ok ok` → ts.log = `set --accept-dns=true`; rv.log = `flush-caches`.
  - `no repeat set`: `ok ok ok ok` → ts.log has exactly 1 line.
  - `alternating no switch`: `ok ok timeout ok timeout ok` → ts.log only the one `true` line.
  - `fallback and back`: `ok ok timeout timeout ok ok` → ts.log = `true`, `false`, `true`; rv.log 3× `flush-caches`.
  - `servfail is fail`: `servfail servfail` → ts.log = `set --accept-dns=false`.
  - `nxdomain is ok`: `nx nx` → ts.log = `set --accept-dns=true`.
  - `set fails retries`: `ts-fail`=1, `ok ok ok` → ts.log 2× `set --accept-dns=true`; rv.log 1× `flush-caches`.
  - `timeout keeps running`: `timeout timeout timeout` → dig.log has 3 lines.
  - Probe args: every dig.log line contains `+time=1`, `+tries=1`, `@100.125.161.81` and a name matching `^p[0-9]+\.example\.com$`; the first two names differ.

- [ ] **Step 2: Run** `tools/dns-guard.test.sh` → FAIL (`dns-guard.sh` missing).

- [ ] **Step 3: Implement `tools/dns-guard.sh`.** Header comment: what it does + "Display/rollback: docs/runbooks/lab-dns.md". Start with `set -uo pipefail` (writeShellApplication adds `-e` in Nix; guard `out=$(dig …) || true` and `if tailscale set …; then`). Variables: `state=""`, `last=""`, `count=0`. Per tick: verdict ok/fail; same as `last` → `count+1`, else `count=1`; when `count -ge 2` and verdict ≠ `state`: `tailscale set --accept-dns=<true|false>` → on exit 0: `resolvectl flush-caches || true`, print the line, `state=$verdict`. Then `sleep 10`.

- [ ] **Step 4: Run** `tools/dns-guard.test.sh` → last line `ok`; `shellcheck tools/dns-guard.sh tools/dns-guard.test.sh` (via `nix shell nixpkgs#shellcheck` if missing) → clean.

- [ ] **Step 5: Commit** `feat(dns): dns-guard probe loop with stub test`.

### Task 2: Laptop module, service and runbook

**Files:**
- Create: `modules/system/tailnet-dns.nix`
- Modify: `modules/system/default.nix` (add `./tailnet-dns.nix` after `./network.nix`)
- Modify: `docs/runbooks/lab-dns.md` (new section `## Laptop (bandit)`, 4-6 lines)

**Interfaces:**
- Consumes: `tools/dns-guard.sh` (Task 1).
- Produces: system unit `dns-guard.service`.

- [ ] **Step 1: Write the module.** `{lib, pkgs, ...}:`
  - `services.resolved.settings.Resolve.Domains = lib.mkForce [];` with a one-line why comment (global `~.` races tailscale0; lab keeps it).
  - `systemd.services.dns-guard`: `description`, `wantedBy = ["multi-user.target"]`, `wants`/`after = ["tailscaled.service"]`, `serviceConfig = {ExecStart = "${guard}/bin/dns-guard"; Restart = "always"; RestartSec = 5;}`, where `guard = pkgs.writeShellApplication {name = "dns-guard"; runtimeInputs = [pkgs.dig pkgs.tailscale pkgs.systemd pkgs.coreutils pkgs.gnugrep]; text = builtins.readFile ../../tools/dns-guard.sh;}` (use `config.services.tailscale.package` instead of `pkgs.tailscale` so the CLI matches the daemon).
- [ ] **Step 2: Runbook section:** what dns-guard does (2 lines), how to see it (`journalctl -u dns-guard`), rollback (`sudo systemctl stop dns-guard && sudo tailscale set --accept-dns=true`; permanent: remove the import).
- [ ] **Step 3: Check (eval, no full flake check):**
  - `nix eval --raw .#nixosConfigurations.bandit.config.environment.etc."systemd/resolved.conf".text | grep -c 'Domains=~\.'` → `0`.
  - same for `bandit-lab` → `1` (lab unchanged).
  - `nix eval --raw .#nixosConfigurations.bandit.config.systemd.services.dns-guard.serviceConfig.Restart` → `always`.
  - `nix build --no-link .#nixosConfigurations.bandit.config.system.build.toplevel` → success (run in the background).
  - `tools/dns-guard.test.sh` → `ok`.
- [ ] **Step 4: Commit** `feat(dns): laptop asks only Blocky on the tailnet, dns-guard falls back`.

### Task 3: Live switch and checks on the laptop

**Files:**
- Create (outside the repo): `~/laptop-dns-switch.sh` (like `~/palette-switch.sh`: checks branch `fix/laptop-dns` in `~/src/bandit-nix-laptop-dns`, `nh os switch .`, prints next step) and `~/laptop-dns-test.sh` (the root checks below, needs sudo).

- [ ] **Step 1:** Owner runs `sh ~/laptop-dns-switch.sh` in a normal terminal.
- [ ] **Step 2: Check** `resolvectl status`: Global has no `~.`; tailscale0 is the only link with `~.`. `journalctl -u dns-guard -b` shows `accept-dns=true`.
- [ ] **Step 3: Check** 10× `resolvectl query --cache=no doubleclick.net` → `0.0.0.0` every time.
- [ ] **Step 4: Check** (owner, `sh ~/laptop-dns-test.sh`): `nft` table dropping output to `100.125.161.81` → within ~25 s journal shows `accept-dns=false` and `getent hosts example.org` resolves; remove the table → within ~25 s `accept-dns=true` and doubleclick.net → `0.0.0.0`. Script always removes the table on exit (trap).
- [ ] **Step 5: Check later (owner):** after one suspend, `journalctl -u dns-guard -b`; after `tailscale down`, `getent hosts example.org` resolves.
- [ ] **Step 6:** Update `projects/bandit-nix` (basic-memory) `## Stand`; merge to main needs vino's signature.

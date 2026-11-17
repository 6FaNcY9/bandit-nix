# Bar part 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Font 16, and five new Waybar items on the laptop: agents, AI limit, hacking target, stream mode, DNS shield.

**Architecture:** Agent state comes from a new `lage bar` subcommand in `tools/lage.py` (same classification as the
LAGE pane). The other items are small bash scripts in `tools/waybar-*.sh`, each wrapped by `pkgs.writeShellApplication`
in `modules/user/desktop/waybar.nix` (the way `tools/lage.py` is read into `hyprland/scripts.nix`), so tests can run the
raw scripts with stubs on `PATH`. Stream mode is two flag files in `$XDG_RUNTIME_DIR` plus a mako mode and a Waybar signal.

**Tech Stack:** Nix/Home Manager, Waybar custom modules (JSON), bash + jq + iproute2, Python 3 (lage), mako, Hyprland.

**Spec:** `docs/specs/2026-11-17-bar-ai-design.md`

## Global Constraints

- Hosts build from `modules/`; `nixos/` and `home/` are dead. Format changed Nix files with `nix fmt -- <file>` (Alejandra).
- Palette tokens only (`colors.base0C` teal ok, `base0A` yellow warn, `base08` red crit, `base03` grey stale/dim,
  `base0B` green); no new hex values in Nix.
- Every module prints one JSON line `{"text","tooltip","class"}`; empty `text` hides it. Errors or missing data → `{"text":""}`, never a crash or a hang (`timeout` on every external call).
- No full `nix flake check` (OOM on the laptop). Build: `nix build .#nixosConfigurations.bandit.config.system.build.toplevel --no-link --no-update-lock-file`.
- The bar never changes network, DNS or Tailscale settings. Only stream mode mutes notifications (mako mode `stream`).
- No credentials read; the usage file is claude-hud's own 0600 snapshot.
- Commits unsigned in this worktree, message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. No push.

## Review Focus

1. A transcript of tens of MB: `lage bar` must stay fast (tail read) and still classify like the pane.
2. A transcript whose last 256 KiB hold no assistant/user line (one huge tool result): tail read must fall back to a full read, not report "wartet".
3. Stale `.pentest-session` from an old engagement: target shows (by design, it is `pt`'s current state) — no crash on a file without `target=`, with CRLF, or with spaces.
4. Waybar restart or reboot during/after a share: no stale `bar-stream-auto` flag keeps masking or muting.
5. `makoctl`, `hyprctl` or `pkill` missing or failing (mako not running, Waybar not running): scripts still exit 0 and print valid JSON.

Tests for each line are in Tasks 1, 1, 3, 5 and 5/6.

---

### Task 1: `lage bar` (agent count JSON, tail read)

**Files:**
- Modify: `tools/lage.py` (Transcript gets `tail()`; new `bar_json()`; `main()` handles `bar`; docstring line)
- Test: `tools/lage.test.sh` (new block before the final `echo ok`)

**Interfaces:**
- Produces: CLI `lage bar` → stdout one JSON line `{"text": str, "class": "waiting"|"busy", "tooltip": str}` or `{"text": ""}`; exit 0 always.
- Produces: `Transcript.tail(self, nbytes=262144) -> None`; `session_state(s) -> (state: str, since: datetime|None, line: str)` used by Task 2.

- [ ] **Step 1: Write the failing tests** (in `lage.test.sh`, using its `fresh`, `session`, `entry`, `assistant`, `status`, `live` helpers)

```bash
# lage bar: counts like the pane; helpers count as busy; dead pids do not count
fresh; live; p1=$pid; session $p1 $s1 src-a "$HOME/w"
entry $s1 "$(assistant 14:12:00 '"tool_use"' '[{"type":"tool_use","name":"Read","input":{"file_path":"/x"}}]')"
out=$(lage bar); jq -e '.text == "● 1" and .class == "busy"' <<<"$out"
status $p1 waiting "Erlaubnis"; out=$(lage bar); jq -e '.text == "▲ 1" and .class == "waiting"' <<<"$out"
jq -e '.tooltip | test("^▲ src-a")' <<<"$out"
status $p1 idle; out=$(lage bar); jq -e '.text == "▲ 1"' <<<"$out"            # idle = wartet, like the pane
sub=$HOME/.claude/projects/p/$s1/subagents; mkdir -p "$sub"
echo '{}' >"$sub/agent-1.meta.json"; : >"$sub/agent-1.jsonl"
out=$(lage bar); jq -e '.text == "● 1" and .class == "busy"' <<<"$out"        # helfer = busy
live; session $pid bbbbbbbb-2 src-b "$HOME/w"; status $pid waiting
out=$(lage bar); jq -e '.text == "● 1 ▲ 1" and .class == "waiting"' <<<"$out"
fresh; session 999999 $s1 src-a "$HOME/w"; jq -e '.text == ""' <<<"$(lage bar)"  # dead pid: hidden
# tail read: 1 MiB of filler before the last entry classifies like a full read; no marker in the tail falls back
fresh; live; session $pid $s1 src-a "$HOME/w"
entry $s1 "$(assistant 14:11:00 '"end_turn"' '[{"type":"text","text":"fertig"}]')"
head -c 1048576 /dev/zero | tr '\0' 'x' | fold -w 1000 | sed 's/^/{"type":"progress","d":"/; s/$/"}/' >>"$HOME/.claude/projects/p/$s1.jsonl"
jq -e '.text == "▲ 1"' <<<"$(lage bar)"                                       # fallback found the end_turn
entry $s1 "$(assistant 14:12:00 '"tool_use"' '[{"type":"tool_use","name":"Read","input":{"file_path":"/x"}}]')"
jq -e '.text == "● 1"' <<<"$(lage bar)"                                       # tail sees the newest entry
```

- [ ] **Step 2: Run to verify it fails**

Run: `tools/lage.test.sh` · Expected: FAIL at the first `lage bar` line (unknown argument).

- [ ] **Step 3: Implement**
  - `Transcript.tail(nbytes=262144)`: only when `self.pos == 0` and the file is larger than `nbytes`: seek to `size - nbytes`, drop the partial first line, set `self.pos` there, then the normal `update()` loop. If after that `self.last is None`, reset (`pos = 0`, fields as in `__init__`) and call `update()` (full read).
  - `session_state(s)`: `tr = transcripts.setdefault(...)`, `tr.tail()`, `lines, state = jetzt(tr, clock(), s)`; `since` = timestamp of `tr.last if s.get("status") else tr.settled` (None if missing). Returns `(state, since, lines[0])`.
  - `bar_json()`: live sessions only; `wartet` → waiting, `tool`/`denkt`/`helfer` → busy. Text `● N` / `▲ M` joined by a space, zero parts left out. Tooltip: waiting first (oldest first), then busy; one line each `▲|● <name>: <line>` with the name rule of `wartet_lines` (custom title, ai title, name, sid[:6]). Print `json.dumps(..., ensure_ascii=False)`.
  - `main()`: `if sys.argv[1:2] == ["bar"]:` before argparse (like `hook`); `cols()` must not depend on a TTY here (set `COLUMNS=80` default for this path if needed).
  - Docstring: add `lage bar [--focus]   Waybar: one JSON line with busy/waiting session counts; --focus jumps to the waiting session`.

- [ ] **Step 4: Run to verify it passes** — `tools/lage.test.sh` → last line `ok`.

- [ ] **Step 5: Commit** — `git add tools/lage.py tools/lage.test.sh && git commit -m "feat(lage): bar subcommand with busy/waiting counts and tail read"`

### Task 2: `lage bar --focus`

**Files:** Modify `tools/lage.py` (`bar_focus()`), Test `tools/lage.test.sh`

**Interfaces:**
- Consumes: `session_state(s)` (Task 1), `claude_session_under(pid)`, `run(*cmd)`.
- Produces: CLI `lage bar --focus` → focuses one window via `hyprctl dispatch "hl.dsp.focus({ window = \"address:<addr>\" })"`; exit 0 when focused, 1 when nothing matched.

- [ ] **Step 1: Write the failing test** — fake `claude` process (copy of `sleep` named `claude`) under a wrapper shell = the "window"; stub `hyprctl` on `PATH`:

```bash
fresh; bin=$t/bin$n; mkdir -p "$bin"; cp "$(command -v sleep)" "$bin/claude"
bash -c "exec -a win bash -c '\"$bin/claude\" 600 & wait'" & win=$!; sl+=($win); sleep 0.3
cpid=$(pgrep -P $win -x claude); session $cpid $s1 src-a "$HOME/w"; status $cpid waiting
cat >"$bin/hyprctl" <<EOF
#!/usr/bin/env bash
if [[ \$1 == clients ]]; then echo '[{"address":"0xother","pid":1},{"address":"0xwin","pid":$win}]'; else echo "\$*" >>"$t/dispatch$n"; fi
EOF
chmod +x "$bin/hyprctl"
PATH=$bin:$PATH lage bar --focus
grep -qF 'address:0xwin' "$t/dispatch$n"
fresh; PATH=$bin:$PATH lage bar --focus && false || true                      # no session: exit 1, no dispatch
```

- [ ] **Step 2: Run** `tools/lage.test.sh` → FAIL (no `--focus`).
- [ ] **Step 3: Implement `bar_focus() -> int`**: target = longest-waiting live session (oldest `since`), else longest-busy; for each client of `hyprctl clients -j` (via `run`, parse JSON, skip bad), `claude_session_under(client["pid"])`; first whose `sessionId` matches → dispatch, return 0. Downward probe only (design: walking up from tmux never reaches a window).
- [ ] **Step 4: Run** `tools/lage.test.sh` → `ok`. Then live, on the laptop: open two kitty tabs in one group, a waiting Claude session in the inactive tab, run `lage bar --focus` → that tab is active. If `hl.dsp.focus` does not switch the group tab, add the group-tab switch the same way `hyprland/scripts.nix:80-98` handles groups, and note it in the commit.
- [ ] **Step 5: Commit** — `feat(lage): bar --focus jumps to the waiting session`

### Task 3: `waybar-ai` (weekly limit)

**Files:** Create `tools/waybar-ai.sh`, Create `tools/waybar.test.sh` (shared by Tasks 3-6, same style as `lage.test.sh`: `set -euo pipefail`, temp dir, `echo ok` at the end)

**Interfaces:**
- Produces: `waybar-ai` → JSON; env `BAR_AI_FILE` (snapshot path), `BAR_NOW` (epoch seconds, tests only).
- Test harness (used by Tasks 3-6): one stub dir first on `PATH` with `ip`, `getent`, `waybar-stream`, `makoctl`,
  `pkill`, `wl-copy`, `notify-send`, each steered by an env var given per call: `VPN=tun|none`, `TS=up|none`,
  `GETENT=block|real|hang`, `STREAM=on|off`, `MAKO=ok|fail` (defaults: the first value, `STREAM=off`); `makoctl`/`pkill` append their args to
  `$t/mako` / `$t/pkill`, `wl-copy` writes stdin to `$t/clip`. Helpers `ai`, `tg`, `st`, `dns` run the raw script with
  `bash "$here/waybar-<x>.sh"` and the env the test needs (`BAR_PENTEST_SESSION=$t/ps`, `XDG_RUNTIME_DIR=$t/run`).

- [ ] **Step 1: Write the failing tests**

```bash
ai() { BAR_AI_FILE=$t/u.json BAR_NOW=1794880000 bash "$here/waybar-ai.sh"; }
snap() { jq -n --argjson p "$1" --arg u "$2" '{updated_at:$u, five_hour:{used_percentage:12, resets_at:"2026-11-17T02:00:00Z"}, seven_day:{used_percentage:$p, resets_at:"2026-11-20T08:00:00Z"}}' >"$t/u.json"; }
now=$(date -u -d @1794880000 +%FT%TZ)
snap 68 "$now";  jq -e '.text == "AI ▰▰▰▰▰▰▰▱▱▱ 68%" and .class == "ok"' <<<"$(ai)"
snap 80 "$now";  jq -e '.class == "warn"' <<<"$(ai)"
snap 95 "$now";  jq -e '.class == "crit"' <<<"$(ai)"
snap 68 "$(date -u -d @$((1794880000 - 601)) +%FT%TZ)"; jq -e '.class == "stale"' <<<"$(ai)"
jq -e '.tooltip | test("Woche 68 % · reset in ") and test("5 h 12 % · reset in ")' <<<"$(ai)"
rm "$t/u.json"; jq -e '.text == ""' <<<"$(ai)"
echo '{"seven_day":{"used_percentage":null}}' >"$t/u.json"; jq -e '.text == ""' <<<"$(ai)"
echo garbage >"$t/u.json"; jq -e '.text == ""' <<<"$(ai)"
```

- [ ] **Step 2: Run** `tools/waybar.test.sh` → FAIL (no script).
- [ ] **Step 3: Implement `tools/waybar-ai.sh`**: one `jq` program; cells = `round(pct/10)` of 10 (`▰`/`▱`); class `ok` < 80 ≤ `warn` < 95 ≤ `crit`; `stale` when `now - updated_at > 600` (wins over the others); reset durations as `Xd Yh` (≥1 day) or `Xh Ym`. Any jq/parse failure → `{"text":""}`.
- [ ] **Step 4: Run** → `ok`.
- [ ] **Step 5: Commit** — `feat(waybar): AI weekly limit module script`

### Task 4: `waybar-target` (VPN + target)

**Files:** Create `tools/waybar-target.sh`, Test `tools/waybar.test.sh`

**Interfaces:**
- Produces: `waybar-target [copy target|vpn]`; env `BAR_PENTEST_SESSION`, `BAR_GREEN`, `BAR_RED` (pango colours, defaults `#61bb46`/`#ed4749`). Masks with `•••` while `waybar-stream status` (Task 5) exits 0; tests stub it on `PATH`.

- [ ] **Step 1: Write the failing tests** (stubs on `PATH`: `ip` prints canned `ip -4 -j addr` JSON with `tun0` 10.10.14.7 or without; `waybar-stream` exits 1 or 0; `wl-copy` writes stdin to a file; `notify-send` no-op)

```bash
printf 'engagement=x\r\ntarget=10.10.11.5\r\n' >"$t/ps"                       # CRLF tolerated
jq -e '.text | test("10.10.14.7") and test("10.10.11.5")' <<<"$(tg)"
rm "$t/ps"; jq -e '.text | test("10.10.14.7") and (test("→") | not)' <<<"$(tg)"  # VPN only
jq -e '.text == ""' <<<"$(VPN=none tg)"                                       # neither: hidden
echo 'scope=a' >"$t/ps"; jq -e '.text == ""' <<<"$(VPN=none tg)"             # no target= line
echo 'target=10.10.11.5' >"$t/ps"; jq -e '(.text | test("10\\.") | not) and (.text | test("•••"))' <<<"$(STREAM=on tg)"
tg copy target; [[ $(cat "$t/clip") == 10.10.11.5 ]]
```

- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement**: VPN = first IPv4 of an `ifname` starting with `tun` from `timeout 2 ip -4 -j addr`; target = value of the last `target=` line, `\r` and spaces stripped. Text `<span color="$BAR_GREEN">󰖂 VPN</span> → <span color="$BAR_RED">󰓾 TARGET</span>` with missing parts and their arrow dropped (escape `&<>`). Tooltip `VPN <ip>\nZiel <ip>` (or `•••`). `copy` mirrors `waybar-ip copy` (notify + exit 1 when empty).
- [ ] **Step 4: Run** → `ok`.  **Step 5: Commit** — `feat(waybar): hacking target module script`

### Task 5: `waybar-stream` + mako mode

**Files:** Create `tools/waybar-stream.sh`, Modify `modules/user/desktop/mako.nix:44-46` (add `"mode=stream" = { invisible = 1; };` next to `mode=dnd`), Test `tools/waybar.test.sh`

**Interfaces:**
- Produces: `waybar-stream status` (exit 0 = on), `waybar-stream toggle` (manual flag), `waybar-stream auto on|off`, `waybar-stream text <value>` (prints `{"text": value}` or `{"text":"•••"}`). Flags `$XDG_RUNTIME_DIR/bar-stream-auto`, `$XDG_RUNTIME_DIR/bar-stream-manual`. Every change runs `makoctl mode -a stream` (on) or `makoctl mode -r stream` (only when both flags are gone) and `pkill -RTMIN+8 -x waybar`; both `|| true`. Signal number `8` is used by Task 7.

- [ ] **Step 1: Write the failing tests** (stub `makoctl` and `pkill` log their args to files; `XDG_RUNTIME_DIR=$t/run`)

```bash
st status && false || true                                                   # off at start
st auto on;  st status; grep -qx 'mode -a stream' "$t/mako"
st toggle;   st auto off; st status                                          # manual keeps it on
grep -c 'mode -r stream' "$t/mako" | grep -qx 0
st toggle;   st status && false || true; grep -qx 'mode -r stream' "$t/mako"
grep -q -- '-RTMIN+8' "$t/pkill"
jq -e '.text == "bandit"' <<<"$(st text bandit)"; st toggle; jq -e '.text == "•••"' <<<"$(st text bandit)"
MAKO=fail st toggle                                                          # makoctl fails: still exit 0
```

- [ ] **Step 2: Run** → FAIL.  **Step 3: Implement** (plain flag files, `mkdir -p "$XDG_RUNTIME_DIR"` not needed — fail if unset with a message to stderr and exit 0 for `text`).
- [ ] **Step 4: Run** → `ok`.  **Step 5: Commit** — `feat(waybar): stream mode flags, mako stream mode`

### Task 6: `waybar-dns` (shield)

**Files:** Create `tools/waybar-dns.sh`, Test `tools/waybar.test.sh`

**Interfaces:** Produces `waybar-dns` → JSON; env `BAR_DNS_PROBE` (default `doubleclick.net`).

- [ ] **Step 1: Write the failing tests** (stubs: `ip` with/without a `tailscale0` 100.x address; `getent` printing `0.0.0.0 STREAM doubleclick.net`, a real address, or sleeping 10 s)

```bash
jq -e '.text == ""' <<<"$(TS=none dns)"                                      # not on the tailnet: no shield
jq -e '.class == "ok" and (.tooltip | test("Werbeblocker aktiv"))' <<<"$(TS=up GETENT=block dns)"
jq -e '.class == "off" and (.tooltip | test("Werbung kommt durch"))' <<<"$(TS=up GETENT=real dns)"
s=$SECONDS; jq -e '.class == "off"' <<<"$(TS=up GETENT=hang dns)"; (( SECONDS - s <= 4 ))
```

- [ ] **Step 2: Run** → FAIL.  **Step 3: Implement**: tailnet = IPv4 on `tailscale0` via `timeout 2 ip -4 -j addr show dev tailscale0`; probe `timeout 3 getent ahostsv4 "$BAR_DNS_PROBE"`, first field `0.0.0.0` → `{"text":"󰒃 DNS","class":"ok"}`, else `{"text":"󰦞 DNS","class":"off"}`.
- [ ] **Step 4: Run** → `ok`.  **Step 5: Commit** — `feat(waybar): DNS shield module script`

### Task 7: Wire everything into the bars, font 16

**Files:**
- Modify: `lib/repository.nix:168-175` (all four sizes `16`; comment: 16 frees room for agents/AI/target/DNS)
- Modify: `modules/user/desktop/waybar.nix` (wrappers, module configs, `modules-*`, privacy loop, CSS)
- Modify: `modules/user/desktop/hyprland/bindings.nix` (one line after `:119`)
- Owner-home, by the implementer: `~/.claude/plugins/claude-hud/config.json` (back up to `config.json.bak-bar` first)

**Interfaces:** Consumes everything above. Wrapper pattern: `pkgs.writeShellApplication { name = "waybar-ai"; runtimeInputs = [...]; text = builtins.readFile ../../../tools/waybar-ai.sh; }`; colours/paths via a first text line, e.g. `text = "BAR_GREEN='${colors.base0B}' BAR_RED='${colors.base08}'\n" + builtins.readFile ...`. Paths: `BAR_AI_FILE=${config.xdg.cacheHome}/claude-hud/usage.json`, `BAR_PENTEST_SESSION=${config.home.homeDirectory}/src/sec/.pentest-session`. `lage` is reached as `${config.home.homeDirectory}/.local/bin/lage` (installed by `hyprland/scripts.nix:37`), like `net-menu`.

- [ ] **Step 1: Top bar** — `modules-right = ["custom/agents" "custom/ai"]` (drop `hyprland/window` and its CSS). `custom/agents`: `exec = "<lage> bar"`, `return-type = "json"`, `interval = 5`, `on-click = "<lage> bar --focus"`. `custom/ai`: `interval = 30`. `custom/host` becomes `exec = "waybar-stream text ${osConfig.networking.hostName}"`, `return-type = "json"`, `signal = 8`, keeps its `on-click`.
- [ ] **Step 2: Bottom bar** — `modules-left = ["group/admin" "custom/target"]`, `custom/target` `interval = 5`, `signal = 8`, `on-click`/`on-click-right` = `copy target`/`copy vpn`. `custom/dns` before `network` in `modules-right`, `interval = 60`. `custom/ip` gets `signal = 8` and masks (`waybar-ip` checks `waybar-stream status`; masked text `LAN ••• │ TS •••`, tooltip `•••`).
- [ ] **Step 3: Privacy loop** — keep the `pw-dump` detection; on a SCREEN on/off change (first loop always counts as a change) call `waybar-stream auto on|off`; while `waybar-stream status` is 0, add `STREAM` to the shown items (so a manual toggle without a share is visible).
- [ ] **Step 4: CSS** — new ids in the shared padding rule; `#custom-agents.busy, #custom-ai.ok, #custom-dns.ok {color: base0C}`, `.waiting, .warn {color: base0A}`, `.crit, #custom-dns.off {color: base08}`, `.stale {color: base03}`.
- [ ] **Step 5: Key** — `(execBinding "${mod} + SHIFT + p" "~/.local/bin/waybar-stream toggle" "toggle stream mode (hide IPs, mute)")`; install it with `home.file.".local/bin/waybar-stream".source`. (`SUPER+SHIFT+p` is free on main 04234e9.)
- [ ] **Step 6: claude-hud** — `xdg.cacheFile."claude-hud/.keep".text = "";` (creates the directory); implementer runs once: `cp config.json config.json.bak-bar && jq '.display.externalUsageWritePath = "/home/vino/.cache/claude-hud/usage.json"' config.json.bak-bar > config.json` in `~/.claude/plugins/claude-hud/`.
- [ ] **Step 7: Verify** — `nix fmt -- lib/repository.nix modules/user/desktop/waybar.nix modules/user/desktop/hyprland/bindings.nix modules/user/desktop/mako.nix`; `tools/lage.test.sh` and `tools/waybar.test.sh` → `ok`; `nix build .#nixosConfigurations.bandit.config.system.build.toplevel --no-link --no-update-lock-file` → succeeds (writeShellApplication runs shellcheck on every script); `nix build .#checks.x86_64-linux.theme-contract --no-link` → succeeds.
- [ ] **Step 8: Commit** — `feat(waybar): agents, AI limit, target, DNS shield, stream mode; font 16`

### Task 8: Owner handoff

**Files:** Create `~/bar-switch.sh` (not in the repo), update `docs/specs/2026-11-17-bar-ai-design.md` only if something changed during the build.

- [ ] **Step 1:** `~/bar-switch.sh`: `cd ~/src/bandit-nix-bar && nh os switch .` (one short command for the owner, laptop, normal terminal; fingerprint/sudo). Never a bare `nh os switch` in `~/src/bandit-nix`.
- [ ] **Step 2:** Short owner checklist (German, simple) in the session's final message: bars fit; `▲` matches LAGE pane; click jumps; AI % = statusline; `pt` target shows; browser screen share masks + mutes; `Super+Shift+P` toggles; shield teal with Tailscale up, gone with it down.
- [ ] **Step 3:** Update `projects/bandit-nix` in basic-memory (task line `Laptop-Rice Teil 1`) with branch head and the owner step.

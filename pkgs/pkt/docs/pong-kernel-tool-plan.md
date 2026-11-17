# Pong Kernel Tool Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Termux command, `pkt`, that finds compatible BakaSU kernels, installs the chosen one to the inactive slot with backup and verification, prompts for a restart, then checks the result.

**Architecture:** Small Python modules behind one CLI. All root access goes through one `Device` class so logic is tested with a fake. Each command starts from a saved state file, so a reboot between steps loses nothing.

**Tech Stack:** Python 3 standard library and `unittest`; Telethon only for Tasks 7-8; existing `magiskboot`, `bootctl`, `boot-backup.sh`.

**Spec:** `/storage/emulated/0/Download/pong-kernel-tool-design.md`

## Global Constraints

- Project: `~/projects/pong-kernel-tool`, new local git repo with no remote. State: `~/.local/state/pong-kernel-tool/`. Telegram credentials: `~/.config/pong-kernel-tool/telegram.env`, mode 600.
- Never write the running slot or the known-good slot. Enforce it in code, not only by convention.
- Nothing from a zip is executed. Only the member named exactly `Image` is read, and `anykernel.sh` is displayed.
- Root type: BakaSU only. KMI: 5.10.x android12. Boot partition limit: 100663296 bytes.
- Truth sources: `bootctl get-current-slot` and `/proc/version` as root, plus hashes. Never `uname` or boot-state props. Without root (only on clean slot B) `ro.boot.slot_suffix` is allowed.
- Out of scope: other root types, keyboxes and Yurikey material, compiling, doing OTAs, updating `ksud`/manager/modules, background polling.
- Secrets never appear in output, logs, reports, git, or shared storage.
- Writing partitions, switching slots and rebooting need the user's approval every time. The tool never reboots; the user does.
- Tests never write partitions, use `su`, or touch the network. Real-file tests skip if the file is absent.
- Every commit message ends with: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`

## Review Focus

1. Unsafe moment to flash (battery under 30%, snapshot merge not `none`, slots mismatched after an OTA): refuse with the reason. Test in Task 1.
2. Write interrupted or read-back mismatch: don't activate the slot, keep the old slot active, and report. Test in Task 5.
3. Picking the kernel already installed, or one recorded as bad: refuse. Test in Task 4.
4. Malformed or hostile zip (no `Image`, oversized `Image`, `../` member names): reject without extracting anything else. Test in Task 4.
5. Telegram crash mid-run, or a credentials file with loose permissions: still logs out; refuses to read the file. Test in Task 7.

---

### Task 1: Device access, state and safety preflight

**Files:**
- Create: `pkt/__init__.py`, `pkt/device.py`, `pkt/state.py`, `pkt/preflight.py`, `.gitignore`, `README.md`
- Create: `tests/fakes.py`, `tests/test_preflight.py`, `tests/test_state.py`

**Interfaces:**
- Produces: `class Device` with `root(cmd: str) -> str` (raises `RootError` on failure), and `caps_full() -> bool` (`CapEff` of `su` includes `CAP_SYS_ADMIN` and `CAP_DAC_OVERRIDE`), `current_slot() -> str` (`"a"`/`"b"`), `set_active(slot: str)`, `real_kernel() -> str`, `partition_hash(name: str) -> str`, `merge_status() -> str`, `battery() -> int`, `fingerprint() -> str`, `modules() -> dict[str, str]` (id to `on`/`OFF`/`REMOVE`).
- Produces: `tests.fakes.FakeDevice(answers: dict)`, subclass of `Device`, overriding `root`.
- Produces: `State.load() -> State`, `State.save()` (write to temp file, then `os.replace`), fields: `baseline: dict|None`, `b_booted_at: str|None`, `known_good: str|None`, `pending: dict|None`, `bad_kernels: list[str]`, `last_backup: str|None`.
- Produces: `preflight(dev: Device, state: State, need_rehearsal: bool = True) -> list[str]`, returning reasons to refuse (empty means OK).

- [ ] **Step 1: `git init` the project and write failing tests**

`test_preflight.py`: `test_refuses_low_battery` (battery 29 gives a reason containing "battery"; 30 gives none), `test_refuses_merge_in_progress` (`merging`), `test_refuses_missing_caps`, `test_refuses_without_rehearsal`, `test_refuses_slot_mismatch` (baseline `vendor_boot` hash differs), `test_all_ok_returns_empty`. `test_state.py`: round trip; missing file gives defaults; `test_corrupt_file_raises_not_resets` (a corrupt state must not silently forget the known-good slot).

- [ ] **Step 2: Run `python -m unittest` and verify it fails**

Expected: import errors.

- [ ] **Step 3: Implement the files above**

Slots match means equal `vbmeta_system_a`/`_b` hashes and `vendor_boot_a`/`_b` hashes, plus `fingerprint()` equal to the baseline's. On a mismatch, the reason says an OTA is the likely cause and to rerun the rehearsal.

- [ ] **Step 4: Run `python -m unittest` and verify all pass**

- [ ] **Step 5: Commit** `feat: device access, state and preflight`

### Task 2: Rehearsal, rescue runbook, CLI and guard

**Files:**
- Create: `pkt/rehearsal.py`, `pkt/runbook.py`, `pkt/cli.py`, `bin/pkt`
- Create: `tests/test_rehearsal.py`, `tests/test_runbook.py`
- Modify: `~/.claude/hooks/root-guard.sh`, `~/.claude/hooks/root-guard.test.sh`

**Interfaces:**
- Consumes: Task 1.
- Produces: `rehearse_start(dev, state, backup_runner)`: refuses unless on slot A; runs `~/.claude/scripts/boot-backup.sh`, stores the `OK: <path>` path in `state.last_backup`, then `dev.set_active("b")`.
- Produces: `rehearse_check(state, getprop)`: no root; if `ro.boot.slot_suffix` is `_b`, sets `b_booted_at`, otherwise errors.
- Produces: `rehearse_finish(dev, state)`: needs current slot `a`, root working and `b_booted_at` set; then stores `baseline` and `known_good="a"`.
- Produces: `write_runbook(state, path) -> str`, saving to `/storage/emulated/0/Download/pkt-rescue.md`, naming current slots, the backup folder, and `fastboot flash boot_<slot> boot_<slot>.img`, `fastboot boot orangefox-stock-kernel-boot.img`, `fastboot --set-active=<known_good>`.
- CLI: `pkt status | runbook | rehearse-start | rehearse-check | rehearse-finish`. `bin/pkt` is a shell wrapper with a Termux shebang, since `/usr/bin/env` fails under Claude's launcher.

- [ ] **Step 1: Write failing tests**

`test_start_refuses_from_slot_b`, `test_start_stops_if_backup_fails` (no `set_active` call), `test_check_refuses_on_slot_a`, `test_finish_requires_b_booted`, `test_finish_records_baseline`, `test_runbook_names_known_good_and_backup`. Add to `root-guard.test.sh`: `t ask "pkt install --confirmed-copy"`, `t ask "pkt rehearse-start"`, `t ask "pkt switch-back"`, `t ok "pkt status"`, `t ok "pkt find"`.

- [ ] **Step 2: Run both test suites and verify the new tests fail**

- [ ] **Step 3: Implement, adding `pkt (install|rehearse-start|switch-back)` to the guard's slot-change branch**

- [ ] **Step 4: Run `python -m unittest` and `~/.claude/hooks/root-guard.test.sh`; both pass**

- [ ] **Step 5: Commit** `feat: rehearsal, rescue runbook and guard` (guard files sit outside the repo; report their change instead of committing them)

### Task 3: Run the real rehearsal (manual gate)

Stop here for the user. **If this fails, don't start Task 4.** Report it and rethink the design with the user.

- [ ] **Step 1: User sets full root for Termux in the manager; `pkt status` shows capabilities full**
- [ ] **Step 2: User confirms `fastboot devices` sees the phone from the chosen second device, and copies the backup's boot images and `orangefox-stock-kernel-boot.img` to it**
- [ ] **Step 3: With the user's OK, run `pkt rehearse-start`; expected: slot B set active. If `bootctl` fails, stop and report**
- [ ] **Step 4: User reboots. On slot B, without root, run `pkt rehearse-check`; expected: `b_booted_at` set**
- [ ] **Step 5: User reboots to OrangeFox from slot B, switches to A in its reboot menu, and reboots**
- [ ] **Step 6: Run `pkt rehearse-finish` and `~/.claude/scripts/root-doctor.sh`; expected: baseline saved, root and modules as before**

### Task 4: Find and check kernels

**Files:**
- Create: `pkt/github.py`, `pkt/zipcheck.py`
- Create: `tests/test_github.py`, `tests/test_zipcheck.py`, `tests/test_real_zips.py`, `tests/data/releases.json`
- Modify: `pkt/cli.py`

**Interfaces:**
- Produces: `@dataclass Candidate(name, version: tuple, source: str, url: str, sha256: str|None, verified: bool, path: str|None)`.
- Produces: `github.find(fetch) -> list[Candidate]`, reading `WildKernels/GKI_KernelSU_SUSFS` releases, asset regex `^5\.10\.\d+-android12-(\d{4}-\d{2}|lts)-BakaSU-AnyKernel3\.zip$`, newest first; `fetch` is injected for tests.
- Produces: `github.download(c, dest_dir) -> str`, which deletes the file and raises on a digest mismatch.
- Produces: `check_zip(path, dev, state) -> CheckResult(ok: bool, rejects: list[str], unknowns: list[str], info: dict, image_sha: str)`.
- Constants: `BAKASU_MARKERS` (from the real r22 `Image`), `MAX_IMAGE = 100663296`.
- CLI: `pkt find` saves `candidates.json` in the state folder; `pkt check <n|path>`.

Rules: `uapi` different from `ksud`: reject. susfs major.minor different from the installed module: reject. Value unreadable: `unknowns`. Version older than running: reject. `image_sha` equal to the running kernel or in `bad_kernels`: reject.

- [ ] **Step 1: Find `BAKASU_MARKERS`: compare `strings Image` from the two 5.10.269 zips in Downloads, then record which strings are BakaSU-only, and whether uapi and susfs versions are readable**

Expected: at least one marker in the BakaSU zip and absent from the ReSukiSU zip. If uapi isn't readable, it stays "unknown".

- [ ] **Step 2: Write failing tests**

`test_filters_to_bakasu_510` (fixture has ReSukiSU, KernelSU-Next, other KMI), `test_digest_mismatch_deletes_file`, `test_rate_limit_gives_clear_error`, `test_no_image_rejected`, `test_oversized_image_rejected` (without reading it all, using declared size), `test_traversal_names_ignored`, `test_not_a_zip_rejected`, `test_older_rejected`, `test_already_running_rejected`, `test_bad_kernel_rejected`, `test_unreadable_susfs_is_unknown`. `test_real_zips.py`: `test_r22_bakasu_zip_identical_to_running_hash` uses `29a6ec00fcfe41fb` as the Image hash prefix; `test_resukisu_zip_rejected`.

- [ ] **Step 3: Run, verify failing; implement; run `python -m unittest`, verify all pass**

- [ ] **Step 4: Run `pkt find` for real; expected: r22 BakaSU 5.10.269 listed as verified, or a clear error if rate limited**

- [ ] **Step 5: Commit** `feat: find and check BakaSU kernels`

### Task 5: Prepare and install

**Files:**
- Create: `pkt/bootimg.py`, `pkt/install.py`
- Create: `tests/test_install.py`, `tests/test_bootimg_real.py`
- Modify: `pkt/cli.py`

**Interfaces:**
- Consumes: `check_zip`, `preflight`, `write_runbook`.
- Produces: `build_boot(image: str, source_boot: str, workdir: str, magiskboot: str) -> str`: unpack, replace `kernel`, repack, reject over `MAX_IMAGE`, returning the new image path.
- Produces: `prepare(zip_path, dev, state, accept_unverified=False, accept_unknown=False) -> dict`: preflight, check, backup, build from the inactive slot's backup image; saves `state.pending` with `slot, image_path, boot_sha, kernel_version, image_sha, source, modules, stage="prepared"`. Writes nothing to partitions.
- Produces: `install(dev, state, confirmed_copy: bool)`: reruns preflight; refuses without `confirmed_copy`; refuses if the target is the current or known-good slot; writes with `dd`, reads back and compares; only then `set_active`; sets `stage="installed"`.
- CLI: `pkt prepare <n|path> [--accept-unverified] [--accept-unknown]`; `pkt install --confirmed-copy` ends by printing a clear "Ready: restart your phone now" and never reboots. If capabilities aren't full, install stops and prints the image path plus Kernel Flasher steps.

Target slot rule: known-good slot is what's running after a good check, so target is the other slot; before the first install that's B (A known good).

- [ ] **Step 1: Write failing tests**

`test_prepare_writes_no_partition` (no `dd of=` command), `test_refuses_unverified_without_flag`, `test_refuses_unknown_without_flag`, `test_install_refuses_without_confirmed_copy`, `test_never_targets_current_slot`, `test_never_targets_known_good`, `test_readback_mismatch_skips_activate`, `test_dd_failure_skips_activate`, `test_activate_only_after_match`, `test_low_caps_prints_manual_steps`. `test_bootimg_real.py`: build from `boot_b.img` backup plus r22 `Image`, then unpack the result: kernel hash equals `Image`, ramdisk hash unchanged.

- [ ] **Step 2: Run, verify failing; implement; run, verify all pass**

- [ ] **Step 3: Run `pkt prepare` on the r22 zip; expected: rejected as the kernel already running, with no partition written**

- [ ] **Step 4: Commit** `feat: prepare and install to inactive slot`

### Task 6: After-restart checks and switch back

**Files:**
- Create: `pkt/postcheck.py`, `tests/test_postcheck.py`
- Modify: `pkt/cli.py`

**Interfaces:**
- Produces: `post_check(dev, state) -> Report(outcome: str, details: list[str])`, with outcomes `good`, `checks_failed`, `fell_back`, `no_pending`.
- Produces: `switch_back(dev, state)`, activating `state.known_good`; refuses if there's no known good or it's the current slot.
- CLI: `pkt post-check`, `pkt switch-back`.

Rules: Current slot isn't `pending.slot`: `fell_back`, add `image_sha` to `bad_kernels`, clear pending. Slot matches and these pass (real kernel contains `kernel_version`, `boot_<slot>` hash equals `boot_sha`, root OK, modules unchanged, `rezygisk` and `susfs4ksu` descriptions without a failure mark): `good`, set `known_good` to this slot, clear pending, rewrite runbook, remind the user to check Play Integrity in their app. Otherwise `checks_failed`, keeping pending and `known_good`, and offer `pkt switch-back`. Root not working means the message gives the OrangeFox route.

- [ ] **Step 1: Write failing tests**

`test_good_moves_known_good`, `test_next_target_alternates` (after good on B, next prepare targets A), `test_fallback_records_bad_kernel`, `test_module_change_fails_with_name`, `test_no_root_gives_orangefox_route`, `test_switch_back_refuses_without_known_good`, `test_run_twice_is_safe`.

- [ ] **Step 2: Run, verify failing; implement; run, verify all pass**

- [ ] **Step 3: Commit** `feat: post-boot checks and switch back`

### Task 7: Telegram find (run by the user)

**Files:**
- Create: `pkt/tg.py`, `tests/test_tg.py`, `requirements-telegram.txt`
- Modify: `pkt/cli.py`

**Interfaces:**
- Produces: `load_credentials(path) -> tuple[int, str]`, refusing if group/other permissions exist; missing file means prompt with `getpass`, never echoed.
- Produces: `session(api_id, api_hash)`, an async context manager using an in-memory `StringSession` that always calls `log_out()` on exit, including on errors.
- Produces: `CHANNELS = {"WildKernelsTG": "all", "yurikernel": "all", "BakaSU_Grp": "admins"}`; `tg_find(client) -> list[Candidate]`, with `verified=False`, filtered by the Task 4 filename rule. While still logged in, the command lists finds, downloads the ones the user picks, and sets `Candidate.path`, because `pkt prepare` runs after logout.
- CLI: `pkt telegram-find` requires a real terminal (`isatty`) and merges results into `candidates.json`.

- [ ] **Step 1: Write failing tests with a fake client**

`test_loose_permissions_refused`, `test_logout_called_on_exception`, `test_non_admin_group_post_ignored`, `test_candidates_are_unverified`, `test_refuses_without_tty`, `test_no_credentials_in_output_or_state`, `test_flood_wait_stops_with_message`.

- [ ] **Step 2: Run, verify failing; `pip install telethon`; implement; run, verify all pass**

- [ ] **Step 3: User runs `pkt telegram-find` in Termux with fresh credentials; expect a list and a logout (confirm in Telegram's active sessions)**

- [ ] **Step 4: Commit** `feat: Telegram kernel search`

### Task 8: Crawl report (run by the user)

**Files:**
- Create: `pkt/crawl.py`, `tests/test_crawl.py`
- Modify: `pkt/cli.py`

**Interfaces:**
- Consumes: `session`, `CHANNELS`.
- Produces: `crawl(client, limit: int = 2000) -> list[Finding(source, date, link, text, files: list[str], label)]`; `write_report(findings, path)`, saving to `/storage/emulated/0/Download/pkt-crawl-<date>.md`.
- CLI: `pkt crawl [--limit N]`.

Keywords: kernel, root, BakaSU, susfs, GKI, 5.10, module, zygisk, flash, bootloop. Excluded: posts matching keybox, yurikey, `.xml` attachments. All labels start as "someone's claim". Text truncated to 500 characters, marked in the report as untrusted.

- [ ] **Step 1: Write failing tests**

`test_keeps_relevant_posts`, `test_excludes_keybox_posts`, `test_no_sender_names_in_report`, `test_downloads_nothing`, `test_limit_respected`, `test_labels_are_claims`.

- [ ] **Step 2: Run, verify failing; implement; run, verify all pass**

- [ ] **Step 3: User runs `pkt crawl`; Claude reads the report as data and summarizes it**

- [ ] **Step 4: Commit** `feat: Telegram crawl report`

### Task 9: Hook into Claude and finish

**Files:**
- Modify: `~/.claude/skills/kernel-update/SKILL.md`, `~/.claude/CLAUDE.md`, `README.md`

- [ ] **Step 1: Replace the skill's zip and flash steps with the `pkt` flow, and add `bin/pkt` to PATH with a symlink in `~/.local/bin`**

Keep the OTA section. Add: Claude never passes `--confirmed-copy`, `--accept-unverified` or `--accept-unknown` without the user saying so in that run.

- [ ] **Step 2: Add `pkt` to `CLAUDE.md` and mark the slot rule: the known-good slot is never written**

- [ ] **Step 3: Run `python -m unittest`, the guard test, `pkt status`, `pkt find`; all pass**

- [ ] **Step 4: Commit** `docs: connect pkt to the kernel-update skill`

- [ ] **Step 5: First real flash is a separate user decision, when a newer BakaSU kernel exists and with the second device ready**

# mrija-watch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A lab job that watches mrija.org's mail, web files and DNS, sends one short German daily digest to the owner's phone, and pushes instantly only on the danger rules in the spec.

**Architecture:** One Python module (`mrija_watch.py`, stdlib + `maxminddb`) with pure analysis functions (mail scan, manifest diff, DNS diff, report builder) and thin impure collectors (read Maildir, `rsync --list-only`, `dig`, `curl` to ntfy). A NixOS service module runs it on two timers (04:00 collect+instant, 07:00 digest), as user `vino`, sandboxed like `mrija-archive-sync`, reusing the archive SSH key. Analysis is unit-tested on synthetic fixtures; the wiring is tested in a flake check with command stubs, mirroring `jerry-box/report-test.nix`.

**Tech Stack:** Python 3 (stdlib + `python3Packages.maxminddb`), `dbip-country-lite` mmdb, rsync, dig, ntfy (curl), NixOS systemd, Nix flake checks.

**Spec:** `docs/superpowers/specs/2026-11-15-mrija-watch-design.md` (approved 2026-11-15). Owner Part 1 steps: `docs/superpowers/specs/2026-11-15-mrija-owner-checklist.md`.

## Global Constraints

- Python: stdlib only, plus `maxminddb`. No network libraries; collectors shell out to rsync/dig/curl.
- **Privacy, hard rule:** notification text, the digest, journal lines and the state file may contain only: mailbox name, a number, a 2-letter country code, a rule name, a web path. Never a mail subject, body, attachment filename, or any third-party address. Some incident subjects contain a plaintext password.
- Instant push (ntfy priority high) only for the exact rules in the spec "Instant push" list. Everything else is digest-only. The digest is always sent (heartbeat), at most 6 short German lines, simple words (owner has dyslexia + ADHD).
- Code lives in `hosts/bandit-lab/services/mrija-watch/`. Do not edit `services/monitoring/notify.nix` or `alerting.nix` (four open branches touch them); set `OnFailure` inside this module only.
- Run as `vino`; the Maildir is `/srv/containers/mrija-archive/maildir` (0750 vino). State in `/var/lib/mrija-watch` (0700). Reuse the archive key `~/.ssh/thehost_mrija` via `LoadCredential`.
- Web manifest via `rsync --list-only` (the restricted shell rejects `find -printf`). Reachability + cert checked in Python, not blackbox.
- `nix build .#checks.x86_64-linux.mrija-watch-test` and `alejandra` must pass. Do not run a full `nix flake check` (OOM on the laptop).
- Commit attribution: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

## Review Focus

- **Empty / first run:** no prior state (first ever run) must send a digest and set a baseline, never a flood of "new file" pushes for all 35,500 files. Test in Task 3 (first manifest = baseline, no web findings) and Task 7 report builder.
- **A rule's source header is absent:** an NDR with no included original, or a mail with no `Authentication-Results`, must be skipped, not crash or miscount. Test in Task 2.
- **rsync / dig / curl fails or times out:** a failed collector must leave the cursor/state unchanged, go into the digest as an error, and not push or crash. Test in Task 6 and the flake check (Task 8, `CURL_EXIT`/`RSYNC_EXIT`).
- **A subject carrying a password reaches a code path:** the password-test rule must match without storing or emitting the subject. Test in Task 2 and the redaction assertion in Task 5.
- **Maildir filename with Seen flag vs new:** attachment "seen" counting depends on the `:2,S` flag; a malformed name must not crash. Test in Task 2.

---

### Task 1: Module skeleton, state, CLI

**Files:**
- Create: `hosts/bandit-lab/services/mrija-watch/mrija_watch.py`
- Create: `hosts/bandit-lab/services/mrija-watch/test_mrija_watch.py`

**Interfaces:**
- Produces: `load_state(path: Path) -> dict`, `save_state(path: Path, state: dict) -> None` (JSON, atomic write), and a `main(argv)` dispatching `collect` (04:00) and `digest` (07:00) subcommands. `state` holds `maildir_cursor` (map mailbox→last-seen filename), `web_manifest` (list[str]), `dns` (dict), `last_sync_mtime`.

- [ ] **Step 1: Write failing tests** `test_state_roundtrip` (save then load returns the same dict) and `test_load_state_missing_returns_empty` (missing file → `{}`).
- [ ] **Step 2: Run, verify fail** — `python -B -m pytest test_mrija_watch.py -k state -v`, expect "function not defined".
- [ ] **Step 3: Implement** `load_state`/`save_state` (atomic: write temp, `os.replace`) and an `argparse` `main` with `collect`/`digest` subcommands that currently only load/save state.
- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: Commit** `feat(mrija-watch): module skeleton, state, CLI`.

### Task 2: Mail scan

**Files:**
- Modify: `mrija_watch.py`
- Modify: `test_mrija_watch.py`
- Create: `hosts/bandit-lab/services/mrija-watch/testdata/` (synthetic Maildir, no real mail)

**Interfaces:**
- Consumes: state from Task 1; a `GeoIP` wrapper `country_of(ip: str) -> str|None` (thin `maxminddb` wrapper, injected so tests pass a fake).
- Produces: `scan_mail(maildir: Path, cursor: dict, geoip) -> MailFindings` where `MailFindings` (a dataclass) has: `ndr_per_mailbox: dict[str,int]`, `auth_ndr_foreign: list[tuple[str,str]]` (mailbox, country), `password_test_hits: int`, `risky_attach_total: int`, `risky_attach_seen: int`, `spoof_spf_fail: int`, `new_cursor: dict`. It reads only files newer than `cursor[mailbox]` in each `cur/`/`new/`.

- [ ] **Step 1: Write failing tests** against `testdata/`:
  - `test_ndr_counted_per_mailbox` — a mailbox with 3 bounce files → `ndr_per_mailbox["postmaster"] == 3`.
  - `test_auth_ndr_foreign` — a bounce whose included original has `Received: from [91.92.241.54] ... with esmtpsa` and geoip returns `NL` → `("postmaster","NL")` in `auth_ndr_foreign`; a `with esmtps` (no auth) or an AT IP is excluded.
  - `test_password_test_subject_hit_not_stored` — a mail whose subject matches `mrija.org:587 postmaster@mrija.org …` → `password_test_hits == 1`, and assert the subject string appears in no field of `MailFindings`.
  - `test_risky_attachment_seen_flag` — a `:2,S` mail with a `.js` attachment and a `:2,` mail with a `.iso` → `risky_attach_total == 2`, `risky_attach_seen == 1`.
  - `test_spoof_from_spf_fail` — `From: x@mrija.org` with `Authentication-Results: ... spf=fail` → `spoof_spf_fail == 1`.
  - `test_ndr_without_original_skipped` — a bounce with no embedded original → counted as an NDR but contributes nothing to `auth_ndr_foreign`, no crash.
  - `test_malformed_maildir_name` — a file without `:2,` → processed without crashing.
- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement** `scan_mail` and `GeoIP`. Use `email.parser.BytesParser`. Detect auth sends with `re.search(r"with esmtps?a\b", ...)` on `Received` lines of the included `message/rfc822` part; take the IP from the first `[...]`. Risky extensions: `iso img vhd js vbs hta lnk scr exe` plus encrypted zip (central-directory flag); match on the part's filename **length/extension only**, never store the name. Password-test subject: `re.search(r"mrija\.org:(25|465|587)\s+\S+@mrija\.org", subject)` — use the boolean result only.
- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: Commit** `feat(mrija-watch): mail scan with geoip and privacy-safe counts`.

### Task 3: Web manifest diff

**Files:** Modify `mrija_watch.py`, `test_mrija_watch.py`.

**Interfaces:**
- Produces: `parse_manifest(text: str) -> dict[str, tuple[str,int,str]]` (path → perms, size, mtime, from `rsync --list-only` lines) and `diff_web(old: dict, new: dict) -> WebFindings` with `added: list[str]`, `removed: list[str]`, `changed: list[str]`, `instant: list[str]` (rule names + path), `digest_groups: dict[str,int]` (top dir → changed count). When `old` is empty (first run) → no findings (`instant == []`), it is a baseline.

- [ ] **Step 1: Write failing tests:**
  - `test_parse_manifest_line` — one rsync line → correct path/size/mtime.
  - `test_first_run_is_baseline` — `diff_web({}, new)` → `instant == []`, `added == []`.
  - `test_instant_rules` — a new `wp-content/mu-plugins/x/index.php`, a `uploads/evil.php`, a changed `.htaccess`, a new top-level `33vgh/`, and `wp-inmri.php` each appear in `instant`; a normal `wp-content/plugins/elementor/foo.js` change does not, it lands in `digest_groups["wp-content/plugins/elementor"]`.
  - `test_core_update_not_flagged` — PHP files under `wp-includes` changed **together with** `wp-includes/version.php` → not instant.
- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement.** Rule table from the spec "Instant push" web list. "Changed root PHP without a core update" = `version.php` unchanged in this diff. Group digest by the first two path segments under `wp-content`, else the top segment.
- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: Commit** `feat(mrija-watch): web manifest diff and instant rules`.

### Task 4: DNS diff

**Files:** Modify `mrija_watch.py`, `test_mrija_watch.py`.

**Interfaces:**
- Produces: `diff_dns(old: dict, new: dict) -> DnsFindings` with `changed: list[str]` (record names) and `instant: list[str]` (only `NS` or `MX` changes). `old`/`new` map record type → sorted list of values.

- [ ] **Step 1: Write failing tests:** `test_mx_change_is_instant`, `test_txt_change_digest_only` (SPF/DMARC/DKIM change → `changed` but not `instant`), `test_first_run_baseline`.
- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement** `diff_dns` (set compare per record type).
- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: Commit** `feat(mrija-watch): dns diff`.

### Task 5: Report builder + redaction guard

**Files:** Modify `mrija_watch.py`, `test_mrija_watch.py`.

**Interfaces:**
- Consumes: `MailFindings`, `WebFindings`, `DnsFindings`, plus `meta` (`sync_age_hours: float`, `errors: list[str]`, `http_ok: bool`, `cert_days: int`, `updates: dict`).
- Produces: `build_report(mail, web, dns, meta) -> Report` with `instant: list[tuple[str,str]]` (title, body — both start "Mrija: ") and `digest: str` (≤6 lines, German). And `assert_clean(text: str, forbidden: list[str]) -> None` raising if any forbidden token (a real subject/address from the inputs) appears.

- [ ] **Step 1: Write failing tests:**
  - `test_instant_from_each_source` — a password-test hit, 20+ NDRs, a mu-plugins file, and an MX change each yield one `instant` item titled "Mrija: …".
  - `test_digest_at_most_six_lines` — a rich finding set → `digest` has ≤6 non-empty lines.
  - `test_quiet_digest` — all-zero findings → digest still produced, says "alles ruhig".
  - `test_digest_has_no_secrets` — feed findings built from a fixture whose subject contains a password token; `assert_clean(report.digest, [that token])` passes (token absent) and `assert_clean` raises when given a text that does contain it.
- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement** `build_report` (map each instant rule to a fixed German title + a body of counts/paths only) and `assert_clean`. Call `assert_clean` inside `build_report` against the raw subjects/addresses it never copied, as a self-check.
- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: Commit** `feat(mrija-watch): german report builder with redaction guard`.

### Task 6: Collectors and run loop

**Files:** Modify `mrija_watch.py`, `test_mrija_watch.py`.

**Interfaces:**
- Produces: thin wrappers `run_rsync_manifest(remote, keypath) -> str`, `run_dig(name) -> dict`, `post_ntfy(url, topic, token, title, body) -> bool`, `check_http(url) -> tuple[bool,int]`, and `run_collect(cfg)`/`run_digest(cfg)` that wire Tasks 2–5. Each collector reads its binary path from env (`RSYNC`, `DIG`, `CURL`) so the flake check can stub them; a non-zero exit returns an error that goes to `meta.errors` and leaves state unchanged.

- [ ] **Step 1: Write failing tests** (subprocess stubbed via a temp PATH dir, like `report-test.nix`): `test_rsync_failure_keeps_state` (RSYNC_EXIT≠0 → `run_collect` does not advance `web_manifest`, adds an error), `test_post_ntfy_failure_returns_false`.
- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement** the wrappers with `subprocess.run([...], env=..., timeout=...)`; `run_collect` sends instant pushes and writes state only for collectors that succeeded; `run_digest` posts the digest.
- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: Commit** `feat(mrija-watch): collectors and collect/digest run loop`.

### Task 7: NixOS service module + ntfy topic

**Files:**
- Create: `hosts/bandit-lab/services/mrija-watch/default.nix`
- Modify: `hosts/bandit-lab/services/ntfy/default.nix` (add `auth-access` lines `"mrija:mcbots:wo"`, `"phone:mrija:ro"`)
- Modify: `hosts/bandit-lab/default.nix` (add `./services/mrija-watch` to imports, after `./services/mrija-archive`)

**Interfaces:**
- Consumes: `config.sops` only indirectly (the SSH key is already on disk at `~/.ssh/thehost_mrija` from the mrija-archive module). Produces two systemd services + timers.

- [ ] **Step 1:** Write `default.nix`: a Python env `pkgs.python3.withPackages (p: [p.maxminddb])`; package `mrija_watch.py` with `writers.writePython3Bin` or a `writeShellApplication` wrapper that sets `RSYNC`/`DIG`/`CURL`, `MRIJA_GEOIP=${pkgs.dbip-country-lite}/share/dbip/dbip-country-lite.mmdb`, `NTFY_URL=http://127.0.0.1:2586`, `NTFY_TOPIC=mrija`, `STATE_DIR=/var/lib/mrija-watch`, and loads `NTFY_TOKEN` from the ntfy publisher env file. Two `systemd.services` (`mrija-watch-collect`, `mrija-watch-digest`) + two `systemd.timers` (`OnCalendar=*-*-* 04:00`/`07:00`, `Persistent=true`), `User=vino`, `StateDirectory=mrija-watch`, `LoadCredential` for the key, the same sandbox block as `mrija-archive-sync`, and `OnFailure` → a oneshot that curls an ntfy "Mrija: watcher crashed" to topic `mrija`.
- [ ] **Step 2:** `alejandra hosts/bandit-lab/services/mrija-watch/ hosts/bandit-lab/services/ntfy/default.nix hosts/bandit-lab/default.nix`.
- [ ] **Step 3:** `nix eval .#nixosConfigurations.bandit-lab.config.systemd.timers.mrija-watch-collect.timerConfig.OnCalendar` → `*-*-* 04:00:00`.
- [ ] **Step 4: Commit** `feat(mrija-watch): nixos service, timers, ntfy topic`.

### Task 8: Flake check

**Files:**
- Create: `hosts/bandit-lab/services/mrija-watch/test.nix`
- Modify: `flake.nix` (add `mrija-watch-test = import ./hosts/bandit-lab/services/mrija-watch/test.nix {inherit pkgs;};` near line 254, beside `jerry-report-test`)

**Interfaces:** Consumes the packaged script from Task 7. Produces a `runCommand` check.

- [ ] **Step 1:** Write `test.nix` mirroring `jerry-box/report-test.nix`: stub `rsync`, `dig`, `curl` on PATH (curl records posts to `posts-*`, honours `CURL_EXIT`); lay down a synthetic Maildir and two manifests under a temp `STATE_DIR`; run `collect` then `digest`. Assert: (A) a planted `mu-plugins` file in the new manifest produces one high-priority post titled `Mrija: …`; (B) all-clean input → `digest` posts exactly one message containing "ruhig"; (C) `CURL_EXIT=7` → exit 0 and state not advanced; (D) no post body contains the fixture password token.
- [ ] **Step 2:** `nix build .#checks.x86_64-linux.mrija-watch-test -L`, expect success.
- [ ] **Step 3:** `alejandra flake.nix hosts/bandit-lab/services/mrija-watch/test.nix`.
- [ ] **Step 4: Commit** `test(mrija-watch): flake check with stubbed rsync/dig/curl`.

## Self-Review notes

- Spec coverage: mail rules → Task 2; web rules → Task 3; DNS → Task 4; instant-vs-digest + privacy + German → Task 5; collectors/failure handling → Task 6; timers/sandbox/key/topic/OnFailure → Task 7; CI → Task 8. Owner Part 1 is out of scope (checklist file).
- Deferred per spec (not in this plan): Cloudflare API, hidden-admin DB check, exact `$wp_version` content read, content-hash diff, the escalation probe (owner step 9, needs TheHost approval).
- GeoIP absence: `maxminddb` + `dbip-country-lite` confirmed present, so `country_of` has a DB; if the mmdb path is missing at runtime, `scan_mail` degrades to no-country (rule 2 then needs ≥3 foreign-marked NDRs it cannot mark, so it simply won't fire — acceptable, logged to digest).

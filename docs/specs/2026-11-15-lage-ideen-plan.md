# lage: ideas via terminal, full task lines — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `lage` shows waiting tasks in full (wrapped), while `lagebild.md` stays short; ideas typed as `Idee: …` land in the shared memory.

**Architecture:** `index.sh` (lab, gawk) writes a second, hidden note `.wartet.md` per store with the same waiting rows uncut. `lage.py` fetches that file instead of `lagebild.md` and wraps long rows. Ideas need only one rule line in `~/.claude/CLAUDE.md`.

**Tech Stack:** bash + gawk (lab service), Python 3 stdlib (`lage`), bash tests.

**Spec:** `docs/specs/2026-11-15-lage-ideen-design.md`

## Global Constraints

- `lagebild.md` output stays byte-identical (all existing `index.test.sh` checks pass unchanged).
- Each `.wartet.md` row is at most 280 characters (lage cuts fetched rows at 300; a cut tail breaks the `TASK` regex).
- `.wartet.md` keeps the heading `## Waiting for a human`, the same order and the same top 10 as lagebild; `Nothing.` when empty.
- Temp file + `cmp` + `mv`: an unchanged state rewrites nothing and prints nothing.
- No new dependencies; Python stdlib only; match existing style.
- Branch `feat/lage-ideen` in `/home/vino/src/bandit-nix-ideen` (based on `origin/main`).

## Review Focus

- A row whose head (project + store) plus tail (who + LATE date) is long: title budget must not go negative → covered by the `y`×300 test in Task 1.
- A single task longer than the pane budget (`n` lines): it is cut with `…`, never pushes the box past `n` → test in Task 2.
- Very narrow pane (`COLUMNS=30`): no line wider than 30 → existing test, now with a long row (Task 2).
- `n = 1` with several tasks: only `+N weitere`, as today → kept by the budget rule in Task 2.
- Old cache from before the switch (cut rows with `…`): still parses and shows → no change needed, the regex already accepts it.

---

### Task 1: index.sh writes `.wartet.md`

**Files:**
- Modify: `hosts/bandit-lab/services/memory/index.sh:33-35` (temp + trap), `:50-54` (flush), `:89-95` (END), `:104-110` (cmp/mv)
- Test: `hosts/bandit-lab/services/memory/index.test.sh`

**Interfaces:**
- Produces: `$MEMORY_INDEX_DST/.wartet.md`, content `## Waiting for a human\n` then `N. <project> (<store>): <title> (<who>)[ LATE <date>| <date>]` rows (max 10) or `Nothing.`. Served by Caddy at `/notes/.wartet.md`.

- [ ] **Step 1: Write the failing tests** (append before the "second run" block, after line 66, where `zz.md` holds the 120×`y` row)

```bash
# .wartet.md: same rows as lagebild's Waiting, uncut, each at most 280 chars.
w=$v/.wartet.md
[ -f "$w" ] || fail ".wartet.md missing"
[ "$(head -1 "$w")" = "## Waiting for a human" ] || fail "wartet heading"
[ "$(grep -c '^[0-9]*\. ' "$w")" = "$(sed -n '/^## Waiting/,/^## Projects/p' "$v/lagebild.md" | grep -c '^[0-9]*\. ')" ] || fail "wartet row count"
grep -qx "1\. zz (firma): $(printf 'y%.0s' {1..120}) (Albert) LATE 2000-01-05" "$w" || fail "wartet row cut"
grep -q '^[0-9]*\. aiia (firma): Ship the form / fix x\{100\} (owner)$' "$w" || fail "aiia row cut in wartet"
printf -- '- [ ] %s (Albert, 2000-01-05)\n' "$(printf 'y%.0s' {1..300})" > "$f/projects/zz.md"
run > /dev/null
first=$(grep -m1 '^1\. ' "$w")
[[ $first == *"… (Albert) LATE 2000-01-05" && ${#first} -le 280 ]] || fail "long wartet row: ${#first}"
while IFS= read -r line; do [ "${#line}" -le 280 ] || fail "wartet line too long"; done < "$w"
[[ $(cat "$f/.wartet.md") != *CANARY* ]] || fail "vino content in firma's wartet"
```

and in the "second run" block add next to the lagebild mtime check:

```bash
touch -d '2000-01-01' "$v/.wartet.md"   # together with the existing touch of lagebild.md
[ "$(stat -c %Y "$v/.wartet.md")" = "$(date -d 2000-01-01 +%s)" ] || fail "unchanged wartet touched"
```

Also extend the empty case: in the firma-only run at line 27 the store has waiting rows; add one check that a store with no human steps gets exactly `## Waiting for a human` + `Nothing.` (use a fresh temp store `e=$t/empty` with `mkdir -p "$e/projects"` and one `- [ ] x (claude)` note, `MEMORY_INDEX_DST=$e MEMORY_INDEX_SOURCES="empty=$e"`).

- [ ] **Step 2: Run, expect FAIL**

Run: `bash hosts/bandit-lab/services/memory/index.test.sh`
Expected: `FAIL: .wartet.md missing`

- [ ] **Step 3: Implement in `index.sh`**

- Bash: `tmp2=$(mktemp "$dst/.lagebild.XXXXXX") || exit 1`; trap removes `"$tmp" "$tmp2"`; pass `-v full="$tmp2"` to gawk.
- `flush()`: next to `wait[...] = ...` set `fullw[<same key>] = head clean(htitle[w], 276 - length(head) - length(tail)) tail` (276 mirrors the existing 76, so a numbered row stays ≤ 280).
- `END`, after the existing Waiting loop (`sorted_in` already set): print `## Waiting for a human` to `full`, then the first 10 `fullw` rows as `i ". " row`, or `Nothing.`; `close(full)`.
- After the existing lagebild `cmp`/`mv`: the same block for `"$tmp2"` → `"$dst/.wartet.md"` with `chmod 0644` and `echo "wrote $dst/.wartet.md"`.
- Header comment (line 1): mention `.wartet.md` in one line (hidden: not indexed by basic-memory, skipped by the UI).

- [ ] **Step 4: Run, expect PASS**

Run: `bash hosts/bandit-lab/services/memory/index.test.sh`
Expected: `index.test.sh: ok`

- [ ] **Step 5: Commit** — `feat(memory): full-length waiting rows in .wartet.md for lage`

---

### Task 2: lage reads `.wartet.md` and wraps rows

**Files:**
- Modify: `tools/lage.py:58-59` (URL + comment), `:583-607` (`task_lines`)
- Test: `tools/lage.test.sh` (test_tasks block, ~197-227)

**Interfaces:**
- Consumes: the `.wartet.md` format from Task 1 (same heading and row format as lagebild, so `fetch_tasks` and `TASK` stay unchanged).
- Produces: `task_lines(cols, n)` unchanged signature; returns heading + at most `n` lines.

- [ ] **Step 1: Write the failing tests** (in the test_tasks block)

```bash
# a long row wraps with a hanging indent instead of ending in …
long="Eine sehr lange Aufgabe die nicht mehr in eine Zeile passt und darum umbricht"
printf '## Waiting for a human\n1. a (vino): %s (vino)\n2. b (vino): zwei (vino)\n' "$long" >"$t/long.md"
out=$(LAGE_TASKS_URL=file://$t/long.md COLUMNS=40 lage --dir "$HOME/w" --once)
[[ $out == *$'\n a  Eine sehr lange Aufgabe die nicht\n    mehr in eine Zeile passt und darum\n'* && $out == *"umbricht"* && $out == *" b  zwei"* ]]
[[ $(LAGE_TASKS_URL=file://$t/long.md COLUMNS=30 lage --dir "$HOME/w" --once | widest) -le 30 ]]
# one task longer than the box: cut with …, the box never grows past its lines
out=$(LAGE_TASKS_URL=file://$t/long.md COLUMNS=20 LINES=8 lage --dir "$HOME/w" --once)
[[ $(wc -l <<<"$out") -le 7 && $out == *"…"* ]]
```

(Adjust the exact wrap points in the first assertion to what `textwrap.wrap(text, 40 - 1 - w - 2)` yields with `w = 1`; the shape — first line after the project, continuation indented by `w + 2` spaces after the leading space — is what is pinned.)

- [ ] **Step 2: Run, expect FAIL**

Run: `bash tools/lage.test.sh`
Expected: fails at the new wrap assertion (today the row is cut with `…` on one line).

- [ ] **Step 3: Implement**

- Line 58: `TASKS_URL = "https://memory.tail7facc9.ts.net/notes/.wartet.md"`; line 59 comment: rows are full length (cut only at 280 by `index.sh`).
- `task_lines`: `w` from `mine[:n]`; per task `parts = textwrap.wrap(text, max(cols - 1 - w - 2, 1), max_lines=3, placeholder="…") or [""]`; budget rule: `room = n - used - (1 if more tasks follow else 0)`; if `len(parts) > room`: when nothing is shown yet and `room > 0`, keep `parts[:room]` with the last ending in `…`, else stop. First line `f"{project[:w]:<{w}}  {part}"` with the project painted as today; continuation lines `" " * (w + 2) + part`; every line prefixed with `" "`. `+N weitere` for the tasks not shown. Short rows must give exactly today's output (existing test at ~206 stays green).

- [ ] **Step 4: Run, expect PASS**

Run: `bash tools/lage.test.sh`
Expected: exit 0, all old and new checks pass.

- [ ] **Step 5: Commit** — `feat(lage): full task rows from .wartet.md, wrapped`

---

### Task 3: idea rule in `~/.claude/CLAUDE.md` (only after vino's yes)

**Files:**
- Modify: `~/.claude/CLAUDE.md`, section "Shared memory (all devices)" (not in the repo)

- [ ] **Step 1:** Ask vino for yes. Back up: `cp ~/.claude/CLAUDE.md ~/.claude/CLAUDE.md.bak-2026-11-15`.
- [ ] **Step 2:** Add the bullet: "A prompt starting with `Idee:`: append `- [ ] <text> (vino)` at the end of `## Tasks` in `projects/<project>` (its store; note `ideen` when none fits), confirm in one line, continue."
- [ ] **Step 3:** Check: `diff ~/.claude/CLAUDE.md.bak-2026-11-15 ~/.claude/CLAUDE.md` shows exactly that one added line.

---

### Finish

- `graphify update .` in the worktree.
- Owner steps (exact commands in the final report): signed merge to main; lab deploy first; then `curl -s https://memory.tail7facc9.ts.net/notes/.wartet.md | head -3` must show the heading; then laptop rebuild.

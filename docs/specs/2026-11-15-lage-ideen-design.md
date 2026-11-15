# lage: ideas via terminal, full task lines (design)

Status: approved by vino 2026-11-15 (shown in the visual companion). Small change.

## Intent

vino hardly uses the ideas window of `lage`; he writes ideas straight into the Claude terminal. He wants ideas kept in the shared memory so he does not forget them. When he looks at `lage`, task lines end in "…" and he has to guess what they mean.

## Goals

1. A prompt starting with `Idee:` makes Claude store the idea as a task in the shared memory, confirm in one line and continue.
2. `lage` shows the waiting tasks in full, wrapping long lines.

## Non-goals / anti-goals

- `lagebild.md` stays short and byte-identical: every session reads it at start (token cost).
- The `i` key and the "Deine Ideen" board section stay untouched; nothing is removed.
- No hook for ideas; no new dependencies.

## Approaches

- **A** Drop the 76-char cut in `lagebild`: smallest, but ~300 more tokens per session start. Rejected (vino wants to save tokens).
- **B (picked by vino)** `lagebild` stays short; the view gets full lines on its own.
  - B1 (architect's pick): `index.sh` also writes a hidden `.wartet.md` per store with the same rows, order and top 10, rows up to 280 chars instead of 76. `lage.py` reads it and wraps.
  - B2: `lage` fetches the project notes itself. Rejected: duplicates the gawk parser and ordering.

## Design

- `hosts/bandit-lab/services/memory/index.sh`: second temp file `mktemp "$dst/.lagebild.XXXXXX"`, passed as `-v full=`; `flush()` fills a second array with title budget `276 - length(head) - length(tail)` (mirrors the existing 76, so a numbered row stays ≤ 280); `END` prints `## Waiting for a human` and the rows (or `Nothing.`) to `full`; trap removes both temps; temp + `cmp` + `mv`, no rewrite when unchanged. Dotfile because the lab `.bmignore` has `.*` (not indexed by basic-memory) and the UI `walk()` skips dot names; the mirror copies only `mirroredNotes`.
- Whole row stays under 300 chars (lage's `clean(line, 300)`; a cut tail breaks the `(who)`/date parse).
- `tools/lage.py`: `TASKS_URL` → `/notes/.wartet.md`; `task_lines` wraps like `board_lines` (`textwrap.wrap`, `max_lines=3`, `placeholder="…"`, hanging indent).
- `~/.claude/CLAUDE.md`, section "Shared memory" (the "Lage board" section is skipped when there is no board): "A prompt starting with `Idee:`: append `- [ ] <text> (vino)` at the end of `## Tasks` in `projects/<project>` (its store; note `ideen` when none fits), confirm in one line, continue." Needs vino's yes and a backup first.

## Checks

- `index.test.sh`: full row uncut without "…"; row count equals lagebild; long row keeps `(Albert) LATE 2000-01-05` and is under 300 chars; no CANARY in the firma file; unchanged run keeps the mtime; `lagebild.md` unchanged.
- `tools/lage.test.sh`: a long row at `COLUMNS=30` wraps, widest line ≤ 30; existing tests pass.
- After the lab deploy: `curl -s https://memory.tail7facc9.ts.net/notes/.wartet.md | head -3`.

## Owner steps

1. Yes to the CLAUDE.md line. 2. Signed merge. 3. Lab deploy first. 4. Laptop rebuild.

## Risks / left to the builder

- Caddy serving a dotfile is unverified; on 404 use `wartet.txt`.
- An idea tagged `(vino)` counts as a human step and can become a project's waiting row (accepted).
- Before the lab deploy, the new `lage` falls back to the old cache.
- `.bmignore` of the firma and albert stores not checked.

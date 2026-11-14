# Memory Lagebild: one overview per store

## Intent

The owner could not see the company project `aiia` (in firma) on vino's page,
the Karte put group names where they read as the next cluster's heading, and
session dots and cross-cluster lines buried the projects. Claude sessions on
every device also need one entry note that says what waits on whom.

## Approaches

- Repair the graph only: fixes the Karte, still no cross-store view and no entry note.
- JSON twin of the note: a second format to keep in step, and agents read notes, not JSON.
- Chosen: a generated note `lagebild.md` per store (index.sh, timer every 5 min)
  plus a card grid on the Übersicht. Agents and the page read the same note.

## Shape

- `memory-index` writes into a store only rows from the stores listed for it,
  that store first (checked, exit 1 otherwise): vino = vino + firma (minus the
  mirrored copies), firma = firma, albert = albert.
- Project front matter: `status: active|paused|done`, `repo: <path> <branch>`.
- Page: own cards built live from the loaded notes; other stores' rows parsed
  from the loaded lagebild, shown read-only with a link to that store's page.
- Karte: a box per cluster with the name inside, session count in the name,
  no session dots, no lines across clusters, non-project groups as `Importe`.

## Constraints

- No CORS headers, no page fetches another store, nothing from vino is ever
  written into firma or albert; `lagebild.md` may not be in `mirroredNotes`.
- Lab has bash, gawk, coreutils only (no python); unit sandboxed like the mirror.
- Byte-identical output when nothing changed: no timestamps, write only on diff.

## Out of scope

- Last session per project in the note.
- Deep links into a single note of another store.
- A start hook that injects the lagebild into new sessions.
- Albert's store in vino's view.

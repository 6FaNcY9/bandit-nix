# Cockpit: what fills the free rows (draft for the owner)

Status: three variants, designed with architect (Fable) on 2026-11-19 for src-c5. The owner chose variant A the same
day; it is built on `feat/lage-cockpit-space`. B and C stay drafts and are not pursued.

## Why

The new overview went live 2026-11-19 10:47. The owner: "schaut akzeptabel aus, aber viel Platz frei". The pane is
56 columns x 30 rows (measured on the live process); the view used 12 of its 29 lines. He reads short, simple German
(dyslexia + ADHD): few full lines rather than many small ones. Font size 16 stays.

## Variant A: NEU + GELIEFERT (chosen by the owner, built)

```
LAGE  src                                          10:51
 DU
 1  liefern tippen (Laptop, normales Terminal)
 2  Mrija-Brief an die Datenschutzbehörde
 3  Handy
────────────────────────────────────────────────────────
 ● Auto-Dev-Run  Helfer arbeiten (1)
 ● Authentication st…  arbeitet  Aktuelle Ansicht 56x30…
 ● Minecraft bot mon…  arbeitet  denkt nach
 ● Samsung Tab S9 Bo…  arbeitet  denkt nach
────────────────────────────────────────────────────────
 NEU
 10:49  Auto-Dev-Run
    Auto-Dev-Lauf ist vorbereitet: 8 Karten in ~/Docum…
 10:44  Authentication st…
    Cockpit neu gebaut: DU oben, eine Zeile pro Sitzung…
 10:32  Minecraft bot mon…
    Welle 2 ist LIVE seit 09:51 (craft 293ce83, …
 10:43  Samsung Tab S9 Bo…
    7-Tage-/RMM-Trick greift NICHT (Gerät schon csc_st…
────────────────────────────────────────────────────────
 GELIEFERT heute (7)
 10:47  Neues Cockpit-Fenster: oben deine nächsten Sch…
 10:37  Backup der öffentlichen Welt reparieren und ei…
 09:51  Bot-Fixes aus dem Code-Check, Welle 2 (15 Stüc…
────────────────────────────────────────────────────────
 f alles   i Idee   ⏎ zur Sitzung             Woche 41 %
```

- NEU: the newest Fund of each live session (one per board), in the order of the session rows, so places stay put.
  The time is HH:MM, or DD.MM. for another day.
- GELIEFERT heute (N): today's done liefern entries, the newest 3, with the owner's own sentence.
- Both come from local files (boards, `~/.local/state/liefern/fertig/`), no network. Neither depends on sessions
  closing `!` lines with "→".
- Head, DU, the session rows, the foot and their order of dropping in a small pane stay exactly as they are. The new
  blocks only take the rows left after them: NEU in whole pairs (at least one), GELIEFERT with at least one row. An
  empty block disappears with its heading and rule.
- Changes no approved rule.

## Variant B: the Fund under each session (changes an approved rule: draft only)

```
LAGE  src                                          10:51
 DU
 1  liefern tippen (Laptop, normales Terminal)
 2  Mrija-Brief an die Datenschutzbehörde
 3  Handy
────────────────────────────────────────────────────────
 ● Auto-Dev-Run  Helfer arbeiten (1)
    10:49  Auto-Dev-Lauf ist vorbereitet: 8 Karten in …
 ● Authentication st…  arbeitet  Aktuelle Ansicht 56x30…
    10:44  Cockpit neu gebaut: DU oben, eine Zeile pro…
 ● Minecraft bot mon…  arbeitet  denkt nach
    10:32  Welle 2 ist LIVE seit 09:51 (craft 293ce83, …
 ● Samsung Tab S9 Bo…  arbeitet  denkt nach
    10:43  7-Tage-/RMM-Trick greift NICHT (Gerät schon…
────────────────────────────────────────────────────────
 GELIEFERT heute (7)
 10:47  Neues Cockpit-Fenster: oben deine nächsten Sch…
 10:37  Backup der öffentlichen Welt reparieren und ei…
 09:51  Bot-Fixes aus dem Code-Check, Welle 2 (15 Stüc…
 09:48  liefern fest in den Laptop einbauen…
 09:20  Sicherheits-Fixes der öffentlichen Welt…
────────────────────────────────────────────────────────
 f alles   i Idee   ⏎ zur Sitzung             Woche 41 %
```

The tidiest look (each name once), but it breaks "one line per session" and the small-pane folding
("+N weitere Sitzungen" would cut a pair in half).

## Variant C: important findings + not checked (not recommended)

```
LAGE  src                                          10:51
 DU
 1  liefern tippen (Laptop, normales Terminal)
 2  Mrija-Brief an die Datenschutzbehörde
 3  Handy
────────────────────────────────────────────────────────
 ● Auto-Dev-Run  Helfer arbeiten (1)
 ● Authentication st…  arbeitet  Aktuelle Ansicht 56x30…
 ● Minecraft bot mon…  arbeitet  denkt nach
 ● Samsung Tab S9 Bo…  arbeitet  denkt nach
────────────────────────────────────────────────────────
 WICHTIG
 10:44  Auto-Dev-Run
    bot21 hat 10:34–10:40 beim Erde-Holen 37 gebaute B…
 10:42  Auto-Dev-Run
    bot2 wartet: „Weg zu den Kisten ist blockiert“. Ich…
 07:25  Authentication st…
    M1 schlimmer: Velocity 3.5.1 ohne Support seit 30.…
    + weitere
────────────────────────────────────────────────────────
 NICHT GEPRÜFT  31   Auto 4 · Auth 7 · Bots 18 · Tab 2
────────────────────────────────────────────────────────
 GELIEFERT heute (7)
 10:47  Neues Cockpit-Fenster: oben deine nächsten Sch…
 10:37  Backup der öffentlichen Welt reparieren und ei…
 09:51  Bot-Fixes aus dem Code-Check, Welle 2 (15 Stüc…
────────────────────────────────────────────────────────
 f alles   i Idee   ⏎ zur Sitzung             Woche 41 %
```

## Dropped ideas

- A block of important (`!`) findings: stale by construction (the bot session alone had 23 open ones today, many
  long settled), a second red area next to DU; red that is usually old teaches him to ignore red.
- A "nicht geprüft" counter: a number he cannot act on; it belongs in the full view (`f`).
- Bots in one line: needs `botchef` and the network (seconds) in the render loop, removed on purpose today; it would
  need a cache writer outside lage.
- A second line per session: kept only as variant B, because it changes a rule.

## Open

- With 6 or more live sessions NEU takes all the room and GELIEFERT disappears (a later cap: the 4 newest).
- A session without a Fund has no NEU entry: honest, but he may wonder.
- A stale DU step ("liefern tippen" after liefern ran) now stands above a GELIEFERT list that contradicts it: a board
  line that was never closed with "→", not a lage bug.
- The cut rule now cuts only when the head has at least 2 words (owner, 2026-11-19; built on this branch).

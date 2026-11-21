# lage: work view for step-by-step work (design)

Status: designed 2026-11-21 by src-05 with architect (Fable) from the owner's order
(basic-memory `notizen/auftrag-lage-arbeitsansicht`, written by the sec session). The three calls the order left to
the owner were made as proposals (owner rule: propose and do, he says "Stopp"); see "Owner calls" below.

## Why

The owner (beginner, goal bug bounty; dyslexia + ADHD) wants to follow live what a session does at a target: what it
does, why, what it sends, what comes back, and what that means. It must help both sides, not only look nice. Today a
hand-made browser page in the sec repo (`live/home-router/notes/karte.py` + `live.tsv`) does part of it, per target,
without "warum"/"bedeutung" fields and without a way back.

Goals: one step file per session, a work view in the Cockpit, the same step in the bottom bar, a way back (Stopp,
Frage, Idee), a one-line writer for sessions. Non-goals: the router test itself; the phone page and the palette
(they would need their own logic). Anti-goals: secrets in steps; a view the owner must decode.

## Step file

- Next to the session's board: `board_path()` with `.md` replaced by `.schritte.jsonl`
  (`~/.local/state/lage/<sid>.schritte.jsonl`, or `<lab>/.claude/lage.schritte.jsonl`; sessions in one lab folder share
  it as they share the board). Append-only, one JSON object per line, always all nine keys:
  `zeit` (ISO 8601 with offset), `ziel`, `weg`, `was`, `warum`, `gesendet`, `antwort`, `bedeutung` (text, first line,
  at most 200 characters, control characters shown as `?`), `status` (`laeuft | fund | zu | offen | warn`).
- Readers skip broken lines and unknown statuses; lage reads the last 500 lines.

## Writer: `lage schritt`

`lage schritt [WAS] [--warum T] [--gesendet T] [--antwort T] [--bedeutung T] [--status S] [--ziel T] [--weg T]`

- Finds its session by walking up its parent pids to the claude process listed in `~/.claude/sessions/*.json`
  (Bash tool calls are its children). No session: a short message, exit 1, nothing written.
- With WAS: a new step, status `laeuft` unless given.
- Without WAS: changes the newest step: a copy of it with the given fields, the status kept unless given, written as a
  new line. So `lage schritt --antwort … --bedeutung … --status fund` finishes the running step.
- A side effect is its own step with `--status warn`. A way to try later is a step with `--weg … --status offen`.

## Reading the steps (no ids)

- `offen` lines only seed the way list; they are no steps.
- A `laeuft` line followed directly by a line with the same `was` is replaced by it (an update or the finish).
  Any other `laeuft` line that is not the newest stays, shown with `·` (started, no result reported).
- Same `(status, weg, was)` anywhere in the list: one row with `×N`, at the newest one's place, with its answer.
- A way's status: its newest `fund`/`zu`/`offen` line (`warn` and `laeuft` never change it; none = `offen`).
  The running way is marked `▶`; "als Nächstes" = the first way, in order of first appearance, that is `offen` and not
  the running one.

## Work view (key `a`)

```
LAGE  sec-36 · ARBEIT                              08:46
ZIEL  Heim-Router
▶ Zeitdienst (NTP) genauer abfragen          seit 40 s
  warum   Verrät vielleicht die Firmware-Version
  sendet  3 NTP-Pakete an UDP 123
  ←       noch keine Antwort
────────────────────────────────────────────────────────
✔ 08:31  UDP-Dienste über IPv6
  ← DNS (53) und NTP (123) antworten
  = Neu: der Router hat einen Zeitdienst
⚠ 08:29  IPv4 fällt aus  ×16
  = Netz-Aussetzer, Ursache offen
+9 ältere
────────────────────────────────────────────────────────
WEGE  ✔ 2  ✖ 8  ? 3
▶ UDP-Dienste über IPv6
? Hohe Ports über IPv6                → als Nächstes
+11 weitere
────────────────────────────────────────────────────────
 s Stopp  ? Frage  i Idee  a zurück          Woche 41 %
```

- Source: the followed session's step file; when it has no steps, the live session with the newest step (as the bar).
  The head names that session; the way back writes to that session's board.
- Top: the newest step with every field it has (`←  noch keine Antwort` while it runs). Then older steps, newest
  first. WEGE at most 6 rows. A short pane drops older steps first. Symbols and colours: `▶` laeuft (teal), `✔` fund
  (yellow), `✖` zu, `?` offen (dim), `⚠` warn (red), `·` started without result (dim).
- `a` switches overview ↔ work view, `f` still switches the full board.
- Way back: `s`, `?`, `i` each ask one line (`Stopp`, `Frage`, `Idee`; Enter sends; an empty Frage/Idee is dropped) and
  add an owner idea to the board: `Stopp bei „<was>“[: text]`, `Frage zu „<was>“: text`, `Idee zu „<was>“: text`.
  The existing hook tells the session (`Neue Idee von vino: …`) at its next prompt or tool call, so a Stopp is not
  instant; the view promises nothing more. (My call over "s fires at once": a stray key in the pane must not stop a
  session, and the line can carry a reason.)

## Bottom bar: `custom/schritt` next to `custom/target`

- `lage bar schritt`: the newest step over the live sessions; a `fund`/`warn` younger than 120 s wins over a running
  step (warn first), so the flip is visible. Text `<symbol> <was>` cut to 40 characters, class = status, tooltip with
  session, Ziel/Weg and the fields. Empty when the newest step is older than 30 minutes. Stream mode
  (`$XDG_RUNTIME_DIR/bar-stream-{auto,manual}`): the symbol only, no tooltip. Interval 2 s, signal 8.
- Click `lage bar schritt --open`: focus that session's window, touch `$XDG_RUNTIME_DIR/lage-arbeit`, and run
  `hypr-cockpit` when that workspace has no Cockpit yet. A view switches to the work view when that file is newer than
  it last saw (start: 10 s before its own start, so a Cockpit opened by the click starts there).
- CSS: running teal text; fund yellow and warn red as background, so the field visibly flips.

## Owner calls (proposed, he can say Stopp)

1. Work view per key `a` and per bar click; the overview stays as it is.
2. The way back is in version 1.
3. The CLAUDE.md rule holds for all projects, but only for work against a target (security, debugging,
   investigations). It goes into `~/.claude/CLAUDE.md` (a plain file) with the delivery, not before: before the switch
   `lage schritt` does not exist.

## Delivery

The laptop runs exactly main 9925636 (checked: same system path), the commit before the nixpkgs bump; the bump needs
a reboot and waits for the owner. So the owner's `liefern` script signs the branch onto origin/main and pushes it, then
switches the laptop from a local tree = 9925636 + these commits (only lage, Waybar and scripts change), then adds the
CLAUDE.md line. The Cockpit shows the new lage after Super+C twice.

## Left to the builder

Exact cut widths, the empty-state text, test layout.

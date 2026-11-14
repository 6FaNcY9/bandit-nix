# Memory stores for vino, Albert and the company: design

Date: 2026-11-14. Status: waiting for the owner's approval. Design reviewed by the architect agent (Fable).

## Intent

vino and Albert work together like a small company. They need one shared memory and one planning board for company projects. Albert connects his devices and keeps his own projects there too. Private notes stay separate. vino, as admin, can see everything.

## Today

- Basic Memory 1.0.0 runs in one container on bandit-lab, published as Tailscale Service `svc:memory` (page at `/`, MCP at `/mcp`).
- It has no login. Whoever reaches it reads and writes everything. Everything is in one project `main`, including vino's private notes.
- Albert's PC `albert` (and `slayerpc`) are logged in to Tailscale under vino's account. If the live grant is "owner identity → `tag:lab-mem`", those PCs can reach vino's private store today. Not verified against the live policy.

## Goals

- Three stores: `vino` (private, unchanged), `albert` (Albert's, vino may read), `firma` (shared).
- Tailscale decides who reaches which store. No self-written access code.
- The `firma` page is the joint planning board.
- vino's existing setup keeps working with no client change.

## Non-goals (v1)

- Auto-save of sessions on Windows.
- Albert's phone, and the Termux bridge for `firma`.
- One combined page over all stores.
- Logins or per-note rights inside a store.

## Anti-goals

- Albert can read vino's private store.
- CORS headers on any store front (would open a path from `firma` into the private store).
- A change that breaks vino's current memory, hooks or page.

## Approaches

- A: one store plus a self-written proxy that checks the caller. Rejected: new security code, and Basic Memory picks the project inside the request body, so Tailscale cannot split by path.
- **B: three instances of the same container, each its own Tailscale Service. Chosen by the owner ("do what works best") and confirmed by the architect.** Access is enforced by Tailscale grants only.
- C: hosted cloud service with logins. Rejected: cost, data leaves home.

## Design

- **Stores.** One store list in `hosts/bandit-lab/services/memory/default.nix`. `vino` stays as is (`svc:memory`, ports 8765/8766, `/srv/containers/memory`, same unit names). New: `albert` (8767/8768) and `firma` (8769/8770) with `/srv/containers/memory-{albert,firma}/{data,home}`. Each container mounts only its own data dir. Each store keeps project name `main`, so page and scripts stay unchanged.
- **Tailnet.** New Services `memory-albert` and `memory-firma`, both `tag:lab-mem`, so the existing owner grant covers them ("admin sees all"). Albert's PC gets `tag:albert` instead of vino's identity. New policy lines:
  - `tagOwners: tag:albert → autogroup:admin`
  - grant `tag:albert → svc:memory-firma, svc:memory-albert tcp:443`
  - grant `<owner login>, tag:lab → tag:albert *` (keeps SSH, bnet agent, Beszel working)
  - tests: `tag:albert` accepts the two new services and is denied `svc:memory` and `svc:grafana`; the owner accepts all three.
- **Board.** The same `ui/` on each store. Only new code: a three-link store switcher in the header. Links a viewer may not reach simply fail. `/bnet/devices` stays on vino's front only.
- **Links between stores** (owner request 2026-11-14). A note may point at a note in another store with `[[firma:projects/aiia]]`, `[[vino:…]]` or `[[albert:…]]`. The page renders it as a normal link to that store's page. A viewer without access to the target store gets a failed page, nothing more. No store reads another store, so no CORS. The map does not draw lines across stores in v1. Rule: a link text in `firma` must not carry private content.
- **Clients.** vino adds one MCP server `firma` and a CLAUDE.md rule: listed company projects go to `firma`, everything else stays in `basic-memory`, never copy private notes to `firma`. Albert adds `firma` and `albert` plus a short CLAUDE.md. vino reads Albert's store on the page only.
- **Summariser.** Unchanged; only vino's store has an inbox.
- **Migration.** Only the notes the owner names as company projects: read from `basic-memory`, write to `firma`, leave a one-line pointer.
- **Backup and alerts.** Add the two data dirs to `hosts/bandit-lab/services/backup/shared.nix` and `OnFailure` for the two new containers in `monitoring/notify.nix`.

## Order (step → check)

1. Claude: store list refactor → vino's container and Caddy block evaluate the same as before.
2. Claude: services, backup, alerts, switcher, runbook → targeted build of the bandit-lab toplevel.
3. Owner, Tailscale console: define the two Services, add policy lines and tests → save passes.
4. Owner, console: set `tag:albert` on `albert` → from that PC the private store fails; SSH and bnet still work.
5. Owner: signed commit and lab deploy → three memory blocks in `tailscale serve status`; all three pages load on the laptop.
6. Owner: add MCP server `firma` and the CLAUDE.md rule on the laptop → `firma` answers.
7. Albert: two `claude mcp add` commands and his CLAUDE.md → he writes a test note; vino sees it.
8. Claude: create or move the company project notes → visible on the firma board.

Steps 3 and 4 must pass before Albert gets any address.

## Risks

- Until step 4, Albert's PCs may reach the private store (not verified).
- vino can read all of Albert's store (page, files, backups). Albert must be told.
- `firma` has no login: either person can overwrite or delete; the restic backup is the only undo.
- A Claude session that picks the wrong server shows a private note to Albert at once.
- Removing `tag:albert` needs a login as vino; the owner should sign out of his identity provider in the browser on Albert's PC.

## Open (owner or Albert)

1. Is `slayerpc` Albert's? Untagged it keeps vino's access.
2. Does Albert use Claude Code or the Claude Desktop app? Desktop needs a stdio bridge.
3. Which projects count as company (aiia for sure; others)?
4. Board look: the big orange group names on the map are hard to match to their notes at first glance (owner feedback, exact view to confirm). Separate small design step with a mockup.

## Done 2026-11-14

- Services `svc:memory-albert` (100.77.141.91) and `svc:memory-firma` (100.82.77.24) defined via the Tailscale API, `tcp:443`, `tag:lab-mem`. No host serves them yet.
- Live policy read: the memory grant is one user login → `tag:lab-mem` `tcp:443`, and `tag:lab` auto-approves `tag:lab-mem`. So devices under the owner's login (Albert's PCs) reach the private store until step 4.

## Not verified

- What the PC loses once tagged.
- That Tailscale grants cannot split by path (from knowledge, not today's docs).
- Whether company notes exist outside `projects/`.

## Left to the builder

Exact Nix shape of the store list, Caddy site blocks, switcher markup, runbook wording.

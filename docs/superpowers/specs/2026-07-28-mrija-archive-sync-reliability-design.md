# Mrija Archive Sync Reliability Design

**Date:** 2026-07-28
**Status:** Reviewed design; implementation pending

## Problem

The `bandit-lab` Mrija archive container can authenticate to
`mrija_org@s16.thehost.com.ua` with its unattended Ed25519 key, and the rsync
phase succeeds. The current full sync then fails while indexing SQLite with:

```text
Sync failed: views may not be indexed
```

The application has two competing schema assumptions:

- `archive_emails` and `archive_attachments` are the canonical writable tables.
- `emails` and `attachments` are compatibility views for older readers.

The sync path must never create indexes on, or write through, those views.
There are also three adjacent reliability gaps:

- attachment upserts must use the canonical argument and stored-path contract;
- rsync uses `--delete`, but rows for files deleted upstream are not reconciled;
- the systemd trigger can read a final status from the preceding run before the
  new background worker enters `updating`.

The repositories and deployed source checkout contain unrelated changes. No
implementation or deployment may consume those changes implicitly.

## Goals

1. Make a full sync complete without indexing or writing through compatibility
   views.
2. Keep SQLite consistent with the successfully mirrored Maildir and attachment
   tree, including upstream deletions.
3. Make the systemd unit fail truthfully when the run it triggered fails.
4. Replace disabled SSH host verification with a pinned TheHost server host key.
5. Preserve every unrelated local and server-side change.
6. Provide a reversible deployment with a verified database backup.

## Non-goals

- Privilege escalation on TheHost.
- Changing the TheHost account, mailbox quotas, or remote hosting control panel.
- Replacing SQLite, FastAPI, rsync, Docker, or the archive UI.
- Folding the broader `hosts/bandit-lab` cleanup into this repair. That will be
  a separate audited refactor after this task.
- Deploying by pulling, merging, or building from the dirty server checkout.

## Worktree and source-of-truth boundaries

Implementation will use isolated worktrees created from these design-time
committed revisions:

- application: `/home/vino/Projects/mrijaPageClean` at committed local `HEAD`
  `2c91592`; its existing uncommitted patch remains untouched;
- infrastructure: `/home/vino/src/bandit-nix` at committed `HEAD` `8bb1999`; its
  existing uncommitted patch remains untouched.

The exact revisions and branch relationships must be rechecked when execution
starts. Each repository gets a focused feature branch. Existing dirty changes
may be inspected for prior reasoning, but must not be copied wholesale or
staged. Reviewed commits are integrated deliberately after validation.

The laptop is the source of truth. The application artifact and NixOS closure
are built from explicit reviewed commits on the laptop. Normal deployment does
not ask `bandit-lab` to pull, merge, evaluate, or compile.

## Application design

### Canonical schema

Only these physical tables are writable:

- `archive_emails`
- `archive_attachments`

`emails` and `attachments` remain read-only compatibility views. Schema
initialization and migration will:

1. inspect each object through `sqlite_master`;
2. create or migrate the canonical tables;
3. create indexes only on canonical tables;
4. recreate compatibility views only after the tables are valid;
5. reject an ambiguous object collision instead of partially modifying it.

Migration runs in a transaction. A failure rolls back to the pre-migration
database.

### Indexing contract

Email upserts accept the database connection, mailbox name, and parsed email
record. Attachment upserts accept the database connection, mailbox name,
parsed MIME part, and parent email stable ID.

Attachment `stored_path` is always relative:

```text
mailboxes/<mailbox>/attachments/<filename>
```

It must not contain a host path, container mount prefix, or absolute path.

### Transactional reconciliation

Each mailbox scan records the stable IDs observed in the successful filesystem
walk. Within one transaction, the indexer:

1. upserts observed emails and attachments;
2. removes attachment rows no longer observed for that mailbox;
3. removes email rows no longer observed for that mailbox;
4. commits only after parsing and reconciliation succeed.

Attachment rows are removed before parent email rows. Reconciliation is scoped
to the mailbox being scanned. If rsync, parsing, or database work fails, the
transaction rolls back and the previous index remains usable. A mailbox is
never purged merely because its scan failed or returned an unreadable path.

After rsync succeeds, the indexer records the authoritative mailbox set from a
successful archive-root enumeration. Once every present mailbox has scanned
and reconciled successfully, a final transaction:

1. removes attachment rows belonging to mailboxes absent from that set;
2. removes email rows belonging to mailboxes absent from that set;
3. commits only after both deletions succeed.

If rsync, archive-root enumeration, or any present-mailbox scan fails, this
whole-mailbox purge is skipped. This distinguishes a confirmed upstream mailbox
deletion from an incomplete or unreadable scan.

The SQLite connection is checkpointed or closed cleanly before the application
reloads the database.

### Run-state handshake

The trigger endpoint must claim the run synchronously:

1. acquire the existing update lock;
2. reject a genuinely active run;
3. set state to `updating` and initialize progress;
4. start the worker;
5. return `started`.

The worker no longer depends on a later, racy transition to `updating`. Every
terminal path records either a new success or a new failure for that run.

The API response used by automation must identify the newly triggered run. A
small opaque run ID is preferred; the trigger returns it, status exposes it,
and final state retains it. This prevents a stale terminal state from a prior
run being accepted as the outcome of the new run.

## `bandit-lab` systemd design

The oneshot sync service will:

1. POST `/api/sync` and capture the returned run ID;
2. poll `/api/status` with a bounded startup timeout until that run is
   `updating`;
3. poll the same run to a bounded terminal timeout;
4. print progress without exposing the API key;
5. exit zero only for that run's explicit success state;
6. exit nonzero for failure, timeout, malformed responses, container loss, or
   a mismatched run ID.

This makes systemd reflect the asynchronous result instead of merely confirming
that the POST returned HTTP 200. The polling logic will be a generated,
testable script rather than a long shell fragment embedded directly in
`ExecStart`.

## SSH host verification

The user authentication key and the remote server host key are different
objects. The already-working unattended private key remains the user
credential.

Before changing configuration, retrieve the TheHost server public host key over
the independently trusted existing connection and compare its fingerprint with
the live SSH handshake. Store the approved public host-key entry in a
Nix-managed `known_hosts` file, then use:

```text
StrictHostKeyChecking=yes
UserKnownHostsFile=<Nix-managed known_hosts path>
IdentitiesOnly=yes
BatchMode=yes
```

Do not use `StrictHostKeyChecking=no`, `accept-new`, or `/dev/null` for the
deployed sync.

## Tests

Application tests are written first and must initially fail for the intended
reason:

1. schema initialization with compatibility views reproduces and then prevents
   `views may not be indexed`;
2. canonical tables and compatibility views have the expected SQLite object
   types;
3. attachment upserts use the correct parent ID and relative stored path;
4. a successful rescan deletes stale attachment and email rows only in the
   scanned mailbox;
5. removing an entire mailbox directory deletes its attachment and email rows
   only after successful rsync, root enumeration, and all present-mailbox scans;
6. rsync, root-enumeration, or present-mailbox scan failure skips whole-mailbox
   deletion;
7. a failed scan rolls back upserts and deletions;
8. the trigger returns a run ID before the worker proceeds;
9. status cannot confuse two consecutive runs.

Infrastructure validation covers:

- generated monitor-script behavior for success, failure, stale status, startup
  timeout, terminal timeout, and malformed JSON;
- Nix formatting and focused evaluation of `bandit-lab`;
- a dry-run of the `bandit-lab` system closure.

Broader repository failures are reported separately and do not authorize edits
outside this task.

## Deployment and verification

1. Reconfirm clean feature worktrees, commits, target identity, and container
   paths.
2. Run focused tests and linters in both repositories.
3. Build the application artifact and exact `bandit-lab` NixOS closure on the
   laptop.
4. Create a timestamped, SQLite-consistent backup of the live database and
   verify it with `PRAGMA integrity_check`.
5. Record the current container image/configuration and NixOS generation as
   rollback points.
6. Transfer the reviewed application artifact and recreate the container.
7. Transfer the exact Nix closure, activate it with `nixos-rebuild test`, and
   run health checks before `switch`.
8. Trigger one full sync through the same systemd unit used by the timer.
9. Verify:
   - systemd exits zero;
   - the matching run ID ends in success;
   - SSH host verification is strict;
   - SQLite integrity is `ok`;
   - canonical table counts are plausible;
   - compatibility views remain readable;
   - a sampled attachment path resolves beneath the archive root;
   - no new failed units or container restart loop appears.

If application health, indexing, or integrity verification fails, restore the
database backup and previous container artifact. If NixOS health checks fail,
return to the recorded prior generation. No backup is removed during this task.

## Acceptance criteria

- A real full sync completes through systemd and the API under the same run ID.
- No code attempts to index or mutate `emails` or `attachments` views.
- Deleted mirrored content, including an absent mailbox directory, is removed
  transactionally from canonical tables only after authoritative enumeration.
- The deployed SSH command uses a pinned server host key.
- The live database passes `PRAGMA integrity_check`.
- Existing unrelated changes in all three dirty checkouts remain untouched.
- The timer's unit becomes failed when its triggered sync fails.

## Follow-up

After this repair is deployed and observed, perform a separate full
`bandit-lab` structure audit and cleanup. That work begins with an import and
service inventory, identifies duplicate/dead settings, proposes module
ownership, and is validated independently so it cannot obscure this incident
fix.

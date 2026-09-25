# Backup restore verification

Restore testing is separate from archive-integrity testing. The current
archives have passed gzip/tar checks and checksum verification, but no live
database or world has been replaced.

## PostgreSQL

Run only during an approved maintenance window, using a temporary data
directory and a non-production port:

1. Copy `all.sql.gz` to private temporary storage without changing the source.
2. Initialize a temporary PostgreSQL cluster owned by `postgres`.
3. Start it on an unused loopback port, restore the dump with `psql`, and
   confirm that the expected databases and roles exist.
4. Stop the temporary instance, remove only the temporary directory, and
   record the restore result.

This proves that the dump can be imported into the tested PostgreSQL version;
it does not prove application-level recovery or off-host recoverability.

## Minecraft

1. Make a fresh consistent backup after `save-all flush` and a graceful stop.
2. Extract a copy into an isolated temporary directory; never extract over
   `/srv/containers/minecraft/data`.
3. Verify the world directory, `level.dat`, player data, plugins, and archive
   ownership/modes.
4. If gameplay validation is approved, start a separate temporary Paper
   instance with no production port or network exposure.
5. Remove only the temporary copy after recording the result.

This proves archive extraction and, if the temporary instance is tested, basic
world startup. It does not prove that a production replacement is safe.

## Current status

The above tests remain pending explicit maintenance approval. Existing backup
paths, timestamps, checksums, and integrity results are recorded in
[`services.md`](../services.md).

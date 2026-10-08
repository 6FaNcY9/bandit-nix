# Data and consistent-snapshot logic shared by the Backblaze job (default.nix)
# and the peer job (peer.nix), so both back up exactly the same thing. Each job
# gets its own staging directory so they can never clobber each other.
{pkgs}: let
  docker = "${pkgs.docker}/bin/docker";
  sqlite = "${pkgs.sqlite}/bin/sqlite3";
  rsync = "${pkgs.rsync}/bin/rsync";
  minecraftSnapshot = "${(import ../minecraft/scripts.nix {inherit pkgs;}).snapshot}/bin/minecraft-snapshot";
in {
  # Run after the containers whose databases are dumped.
  after = ["docker-aiia-mysql.service" "docker-vaultwarden.service" "docker-minecraft.service"];

  paths = staging: [
    staging
    # Existing local dumps from services.postgresqlBackup (03:15).
    "/var/backup/postgresql"
    # Ghost content (uploads); the database is dumped into the staging area.
    "/srv/containers/aiia/content-images"
    "/srv/containers/aiia/content-media"
    "/srv/containers/aiia/content-files"
    "/srv/containers/aiia/content-data"
    # Mrija archive mail; the SQLite index is snapshotted into staging.
    "/srv/containers/mrija-archive/maildir"
  ];

  # Consistent snapshots, taken just before restic reads the staging area.
  # Failing here fails the whole run (and alerts) instead of backing up a
  # torn copy. No secret appears on a command line: mysqldump reads the root
  # password from the container's own environment.
  prepare = staging: ''
    set -euo pipefail
    find ${staging} -mindepth 1 -delete
    install -d -m 0700 ${staging}/vaultwarden ${staging}/mrija ${staging}/aiia

    # Vaultwarden: everything except the live SQLite files, then an online
    # SQLite snapshot (safe while the container runs).
    ${rsync} -a --exclude 'db.sqlite3*' --exclude 'icon_cache' \
      /srv/containers/vaultwarden/data/ ${staging}/vaultwarden/
    ${sqlite} /srv/containers/vaultwarden/data/db.sqlite3 \
      ".backup '${staging}/vaultwarden/db.sqlite3'"

    # Mrija archive: everything in data/ (audit log included) except the
    # live SQLite index, which is snapshotted consistently.
    ${rsync} -a --exclude 'mail_index.sqlite*' \
      /srv/containers/mrija-archive/data/ ${staging}/mrija/
    if [ -e /srv/containers/mrija-archive/data/mail_index.sqlite ]; then
      ${sqlite} /srv/containers/mrija-archive/data/mail_index.sqlite \
        ".backup '${staging}/mrija/mail_index.sqlite'"
    fi

    # AiiA / Ghost MySQL: single-transaction dump of every database.
    ${docker} exec aiia-mysql sh -c \
      'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysqldump --single-transaction --routines --events --all-databases -uroot' \
      | ${pkgs.gzip}/bin/gzip -c > ${staging}/aiia/mysql.sql.gz

    # Minecraft: saves flushed and frozen while rsync copies the data
    # directory, then re-enabled (a plain copy of a live world is torn).
    # Runs last so a flush timeout cannot cancel the other dumps; it still fails the run instead of uploading an inconsistent world.
    ${minecraftSnapshot} ${staging}/minecraft
  '';
}

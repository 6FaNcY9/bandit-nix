{pkgs, ...}: let
  maildir = "/srv/containers/mrija-archive/maildir";
  data = "/srv/containers/mrija-archive/data";
  sshKey = "/home/vino/.ssh/thehost_mrija";
  remoteHost = "mrija_org@s16.thehost.com.ua";
  # Adjust remotePath to match actual Maildir location on thehost.com.ua.
  # Verify with: ssh -i ${sshKey} ${remoteHost} 'find ~ -name cur -maxdepth 4'
  remotePath = "Maildir/";
in {
  systemd.tmpfiles.rules = [
    "d ${maildir} 0750 vino users -"
    "d ${data} 0750 vino users -"
  ];

  systemd.services.mrija-archive-sync = {
    description = "Sync mrija.org Maildir and reindex";
    after = ["network-online.target" "docker.service"];
    requires = ["docker.service"];
    serviceConfig = {
      Type = "oneshot";
      User = "vino";
      ExecStart = pkgs.writeShellScript "mrija-sync" ''
        set -euo pipefail

        echo "Syncing Maildir from ${remoteHost}…"
        ${pkgs.rsync}/bin/rsync -az --delete \
          -e "${pkgs.openssh}/bin/ssh -i ${sshKey} -o StrictHostKeyChecking=accept-new" \
          ${remoteHost}:${remotePath} ${maildir}/

        echo "Reindexing…"
        ${pkgs.docker}/bin/docker run --rm \
          -v ${maildir}:/maildir:ro \
          -v ${data}:/data \
          mrija-archive:latest \
          python -m maildir_report.index_mailbox \
            --maildir /maildir \
            --db /data/mail_index.sqlite

        echo "Sync complete."
      '';
    };
  };

  systemd.timers.mrija-archive-sync = {
    description = "Periodic mrija.org mail sync";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "*-*-* 03:00:00";
      Persistent = true;
    };
  };
}

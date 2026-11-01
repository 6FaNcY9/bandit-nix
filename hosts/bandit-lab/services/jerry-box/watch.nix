# Audit of the container's execs and ntfy reports: hourly summary, ssh logins, backup activity.
{pkgs, ...}: let
  report = pkgs.callPackage ./report.nix {};
  watch = pkgs.callPackage ./watch-wrapper.nix {};
  # Run the journal through the filter; pipefail and the filter's exit 1 at EOF make the unit restart.
  pipe = journal: mode: "${pkgs.bash}/bin/bash -o pipefail -c '${journal} | ${watch}/bin/jerry-watch ${mode}'";
  sshWatch = pipe "${pkgs.systemd}/bin/journalctl -M jerry -u sshd -f -n0 -o cat" "ssh";
  resticWatch = pipe "${pkgs.systemd}/bin/journalctl -u restic-rest-server -f -n0 -o cat" "restic";
  ntfy = {
    after = ["ntfy-seed.service"];
    requires = ["ntfy-seed.service"];
  };
  env = {
    EnvironmentFile = "/var/lib/mcbots/ntfy/publisher.env";
    Environment = ["NTFY_URL=http://127.0.0.1:2586" "NTFY_TOPIC=mcbots"];
  };
  watcher = exec: {
    serviceConfig =
      env
      // {
        ExecStart = exec;
        Restart = "on-failure";
        RestartSec = 30;
      };
  };
in {
  security.auditd.enable = true;
  security.audit = {
    enable = true;
    rules = [
      "-a always,exit -F arch=b64 -S execve -F uid>=524288 -F uid<=589823 -k jerry"
      "-a always,exit -F arch=b32 -S execve -F uid>=524288 -F uid<=589823 -k jerry"
    ];
  };

  systemd.services = {
    jerry-report =
      ntfy
      // {
        description = "Hourly summary of Jerry box processes over ntfy";
        serviceConfig =
          env
          // {
            Type = "oneshot";
            StateDirectory = "jerry-report";
            ExecStart = "${report}/bin/jerry-report";
          };
      };
    jerry-ssh-watch =
      ntfy
      // watcher sshWatch
      // {
        description = "ntfy on ssh logins into the Jerry box";
        wantedBy = ["multi-user.target"];
        after = ntfy.after ++ ["container@jerry.service"];
      };
    jerry-restic-watch =
      ntfy
      // watcher resticWatch
      // {
        description = "ntfy on Jerry's restic backup activity";
        wantedBy = ["multi-user.target"];
      };
  };

  systemd.timers.jerry-report = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
    };
  };
}

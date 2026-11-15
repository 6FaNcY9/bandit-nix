# Audit of each guest container's execs and ntfy reports: hourly summary, ssh logins, and for jerry backup activity.
{
  lib,
  pkgs,
  ...
}: let
  guests = import ./guests.nix;
  report = name: pkgs.callPackage ./report.nix {guest = name;};
  watch = name: pkgs.callPackage ./watch-wrapper.nix {guest = name;};
  # Run the journal through the filter; pipefail and the filter's exit 1 at EOF make the unit restart.
  pipe = name: journal: mode: "${pkgs.bash}/bin/bash -o pipefail -c '${journal} | ${watch name}/bin/${name}-watch ${mode}'";
  sshWatch = name: pipe name "${pkgs.systemd}/bin/journalctl -M ${name} -u sshd -f -n0 -o cat" "ssh";
  resticWatch = pipe "jerry" "${pkgs.systemd}/bin/journalctl -u restic-rest-server -f -n0 -o cat" "restic";
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
  auditRules = name: g: let
    range = "-F uid>=${toString g.uid} -F uid<=${toString (g.uid + 65535)} -k ${name}";
  in [
    "-a always,exit -F arch=b64 -S execve -S execveat ${range}"
    "-a always,exit -F arch=b32 -S execve -S execveat ${range}"
  ];
  services = name: _: {
    "${name}-report" =
      ntfy
      // {
        description = "Hourly summary of ${lib.toSentenceCase name} box processes over ntfy";
        serviceConfig =
          env
          // {
            Type = "oneshot";
            StateDirectory = "${name}-report";
            ExecStart = "${report name}/bin/${name}-report";
          };
      };
    "${name}-ssh-watch" =
      ntfy
      // watcher (sshWatch name)
      // {
        description = "ntfy on ssh logins into the ${lib.toSentenceCase name} box";
        wantedBy = ["multi-user.target"];
        after = ntfy.after ++ ["container@${name}.service"];
        bindsTo = ["container@${name}.service"]; # stop cleanly with the container instead of failing the switch
      };
  };
in {
  security.auditd.enable = true;
  security.audit = {
    enable = true;
    rules = lib.concatLists (lib.mapAttrsToList auditRules guests);
  };

  systemd.services = lib.mkMerge (lib.mapAttrsToList services guests
    ++ [
      {
        jerry-restic-watch =
          ntfy
          // watcher resticWatch
          // {
            description = "ntfy on Jerry's restic backup activity";
            wantedBy = ["multi-user.target"];
          };
      }
    ]);

  systemd.timers = lib.mapAttrs' (name: _:
    lib.nameValuePair "${name}-report" {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "hourly";
        Persistent = true;
      };
    })
  guests;
}

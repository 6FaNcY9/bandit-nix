# Read-only ops dashboard on bandit-lab's built-in panel (tty1).
#
# Split privilege:
#   lab-console-collect (root, hardened, every 30 s) -> /run/lab-console/status.json
#   lab-console (user `console`, tty1, no shell)     <- reads only that file
# The JSON carries names, states, counts and times only — no secrets, tokens or
# environment. tty2+ keep normal gettys for emergency login.
{
  pkgs,
  repoConfig,
  ...
}: let
  # Palette roles ("#rrggbb", dark variant) baked in at build time.
  roles = pkgs.writeText "lab-console-roles.json" (builtins.toJSON (repoConfig.palette.roles "dark"));

  python = pkgs.python3.withPackages (ps: [ps.textual]);

  # Also the `console` user's login shell: any arguments are ignored, so a
  # login through this binary can never reach a shell.
  app = pkgs.writeShellScriptBin "lab-console" ''
    export LAB_CONSOLE_ROLES=${roles}
    export LAB_CONSOLE_STATUS=/run/lab-console/status.json
    exec ${python}/bin/python3 -I ${./app.py}
  '';

  collect = pkgs.writeShellScript "lab-console-collect" ''
    exec ${pkgs.python3}/bin/python3 -I ${./collect.py}
  '';
in {
  users = {
    groups.console = {};
    users.console = {
      isSystemUser = true;
      group = "console";
      description = "tty1 status dashboard";
      shell = app;
      hashedPassword = "!"; # locked: no password login anywhere
      home = "/var/empty";
      createHome = false;
    };
  };

  systemd = {
    services = {
      lab-console-collect = {
        description = "Collect bandit-lab status for the tty1 console";
        after = ["docker.service" "tailscaled.service"];
        # Status refresh only; never block or fail a switch.
        restartIfChanged = false;
        # systemctl, journalctl, docker, tailscale, cscli (wrapped) and git
        # from the system profile; the collector uses bare command names.
        path = ["/run/current-system/sw" pkgs.git pkgs.docker pkgs.systemd];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = collect;
          User = "root";
          RuntimeDirectory = "lab-console";
          RuntimeDirectoryMode = "0755";
          RuntimeDirectoryPreserve = "yes";
          UMask = "0022";
          TimeoutStartSec = "60s";

          NoNewPrivileges = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          ProtectClock = true;
          ProtectHostname = true;
          ProtectProc = "default";
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
          MemoryDenyWriteExecute = true;
          SystemCallArchitectures = "native";
          SystemCallFilter = ["@system-service" "~@privileged"];
          RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_INET6" "AF_NETLINK"];
          # Read the crowdsec state dir and journal; nothing else is needed.
          CapabilityBoundingSet = ["CAP_DAC_READ_SEARCH"];
          # Not applied, and why:
          # - PrivateNetwork: cscli queries the local LAPI over 127.0.0.1 and
          #   tailscale/docker use host sockets; a private netns breaks all three.
          # - DynamicUser / non-root User: docker.sock, the journal and
          #   `cscli decisions list` (crowdsec-owned config/credentials) need root.
          #   Adding a `docker`-group user would be root-equivalent anyway.
          # - ProtectProc=invisible: systemctl/journalctl need peer PIDs.
          # - IPAddressDeny: cscli needs loopback HTTP; allow-listing localhost
          #   adds little over AF_* restriction on a unit without listeners.
          # - If the wrapped cscli re-execs via setuid (sudo/su), NoNewPrivileges
          #   makes it fail; the collector then reports crowdsec {"error"} only.
        };
      };

      # tty1 belongs to the dashboard; no getty or autovt there.
      "getty@tty1".enable = false;
      "autovt@tty1".enable = false;

      lab-console = {
        description = "bandit-lab status dashboard on tty1";
        wantedBy = ["multi-user.target"];
        after = ["systemd-user-sessions.service" "lab-console-collect.service"];
        conflicts = ["getty@tty1.service" "autovt@tty1.service"];
        serviceConfig = {
          ExecStart = "${app}/bin/lab-console";
          User = "console";
          Group = "console";
          TTYPath = "/dev/tty1";
          TTYReset = true;
          TTYVHangup = true;
          TTYVTDisallocate = true;
          StandardInput = "tty-force";
          StandardOutput = "tty";
          StandardError = "journal";
          Environment = ["TERM=linux" "HOME=/var/empty" "LANG=C.UTF-8"];
          Restart = "always";
          RestartSec = "2s";
          UtmpIdentifier = "tty1";

          NoNewPrivileges = true;
          PrivateTmp = true;
          PrivateNetwork = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          ProtectClock = true;
          ProtectHostname = true;
          ProtectProc = "invisible";
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
          SystemCallArchitectures = "native";
          SystemCallFilter = ["@system-service" "~@privileged @resources"];
          RestrictAddressFamilies = ["AF_UNIX"];
          CapabilityBoundingSet = [""];
          # PrivateDevices is not set: it would hide /dev/tty1.
          # MemoryDenyWriteExecute is not set: CPython/textual deps may need it off.
        };
      };
    };

    timers.lab-console-collect = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "15s";
        OnUnitActiveSec = "30s";
        AccuracySec = "5s";
      };
    };
  };

  # Night blanking deliberately skipped: power.nix documents that this panel
  # does not come back from DPMS off (NVIDIA eDP), and keeps blanking disabled.
}

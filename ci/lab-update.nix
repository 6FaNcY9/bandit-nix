{
  pkgs,
  lib,
  lab,
}: let
  updater =
    lib.findFirst (p: p.name or "" == "lab-update") (throw "lab-update package missing from bandit-lab systemPackages")
    lab.environment.systemPackages;
  # The manual history-rewrite override must never be reachable from a
  # unit (timer or otherwise): unattended runs are fast-forward only.
  # This is a lint (a wrapper script hides its text); the updater itself
  # also refuses the flag whenever INVOCATION_ID shows a systemd unit.
  unitText = svc:
    lib.concatStringsSep " " (
      lib.concatMap (k: map toString (lib.toList (svc.serviceConfig.${k} or [])))
      ["ExecStart" "ExecStartPre" "ExecStartPost" "ExecStop" "ExecStopPost" "ExecReload"]
      ++ map (k: toString (svc.${k} or "")) ["script" "preStart" "postStart" "preStop" "postStop" "reload"]
      ++ map toString (lib.toList (svc.scriptArgs or []))
    );
  overrideUnits =
    lib.attrNames (lib.filterAttrs (_: svc: lib.hasInfix "--allow-non-ff" (unitText svc))
      (lab.systemd.services // lab.systemd.user.services));
in
  assert lib.assertMsg (overrideUnits == [])
  "units must not pass --allow-non-ff to lab-update: ${toString overrideUnits}";
    pkgs.runCommand "lab-update-regressions" {
      nativeBuildInputs = [pkgs.python3 pkgs.git pkgs.bash pkgs.coreutils];
    } ''
      python3 ${./test-lab-update.py} ${updater}/bin/lab-update
      touch "$out"
    ''

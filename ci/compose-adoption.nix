# Compose adoption contract for the monitoring and Mrija archive projects.
{
  pkgs,
  lib,
  lab,
}: let
  monitoringUnit = lab.systemd.services.compose-monitoring;
  mrijaUnit = lab.systemd.services.compose-mrija-archive;
  monitoringExec = monitoringUnit.serviceConfig.ExecStart;
  mrijaExec = mrijaUnit.serviceConfig.ExecStart;
in
  assert lib.assertMsg (lib.hasInfix "--project-name monitoring" monitoringExec)
  "monitoring lifecycle unit must use the monitoring Compose project";
  assert lib.assertMsg (lib.hasInfix "--project-name deploy" mrijaExec)
  "Mrija lifecycle unit must preserve the live deploy Compose project";
  assert lib.assertMsg (monitoringUnit.wantedBy == [] && mrijaUnit.wantedBy == [])
  "Compose adoption units must remain manual until the approved live handoff";
  assert lib.assertMsg (!monitoringUnit.restartIfChanged && !mrijaUnit.restartIfChanged)
  "Nix activation must not restart adopted Compose projects";
  assert lib.assertMsg (lib.hasSuffix " start" monitoringExec && lib.hasSuffix " start" mrijaExec)
  "Compose lifecycle units must start existing containers without reconciling them";
    pkgs.runCommand "compose-adoption-check" {
      nativeBuildInputs = [pkgs.gnugrep];
    } ''
      ! grep -q '^[[:space:]]*ports:' ${../hosts/bandit-lab/services/monitoring/compose.yml}
      grep -q '/run/secrets/rendered/mrija-archive.env' ${../hosts/bandit-lab/services/mrija-archive/compose.yml}
      touch "$out"
    ''

# ARTEX — self-hosted autonomous pentest platform (github:BaaRai/ARTEX), run from a
# hand-cloned docker-compose checkout at /home/vino/artex (the image is built there
# with `docker compose build`; there is no registry tag).
#
# This module does NOT package ARTEX. It wraps the existing compose project in one
# systemd unit so a test run also throttles the lab: ARTEX is resource-hungry (LLM
# workers, a recording MITM proxy, real scanners), so while it runs we free the box.
#
# Owner's choice (2026-11-16):
#   - Minecraft: stop it entirely — Paper (6 G heap) + Velocity + the 5 mcbots.
#   - Guest boxes jerry/martin: freeze (suspend; state kept, no CPU), thaw on stop.
# Everything is reversed when ARTEX stops. ExecStopPost runs on a clean stop AND on
# a failed start or crash, so the lab is never left throttled with ARTEX down.
#
# The unit is manual (wantedBy = []): it does not start on boot, because starting it
# tears Minecraft down. The owner starts it for a test (`systemctl start artex`) and
# stops it when done (`systemctl stop artex`).
{
  pkgs,
  lib,
  ...
}: let
  artexDir = "/home/vino/artex";
  docker = "${pkgs.docker}/bin/docker";

  # Stopped while ARTEX runs. minecraft-server-sandbox is intentionally left alone
  # (not part of the owner's "Paper + Velocity + bots" choice); add it here if wanted.
  mcUnits = [
    "minecraft-server-paper.service"
    "minecraft-server-velocity.service"
    "docker-mcbots.service"
    "docker-mcbots-worker-2.service"
    "docker-mcbots-worker-3.service"
    "docker-mcbots-worker-4.service"
    "docker-mcbots-worker-5.service"
  ];
  # Suspended (not stopped) while ARTEX runs; real guests, state is kept.
  guestUnits = [
    "systemd-nspawn@jerry.service" # Debian guest (guest-box/guests.nix os = "debian")
    "container@martin.service"
  ];

  throttleDown = pkgs.writeShellApplication {
    name = "artex-throttle-down";
    runtimeInputs = [pkgs.systemd];
    text = ''
      set -euo pipefail
      # `|| true`: a unit already down (or absent) must not block ARTEX from starting.
      # `stop` blocks until Paper has saved and exited, so ARTEX gets the RAM first.
      systemctl stop ${lib.concatStringsSep " " mcUnits} || true
      for u in ${lib.concatStringsSep " " guestUnits}; do
        systemctl freeze "$u" || true
      done
    '';
  };

  throttleUp = pkgs.writeShellApplication {
    name = "artex-throttle-up";
    runtimeInputs = [pkgs.systemd];
    text = ''
      set -euo pipefail
      for u in ${lib.concatStringsSep " " guestUnits}; do
        systemctl thaw "$u" || true
      done
      systemctl start ${lib.concatStringsSep " " mcUnits} || true
    '';
  };
in {
  systemd.services.artex = {
    description = "ARTEX pentest platform (docker compose) + lab resource throttle";
    wantedBy = []; # manual only — starting it stops Minecraft and freezes the guests
    after = ["docker.service" "network-online.target"];
    wants = ["network-online.target"];
    requires = ["docker.service"];
    path = [pkgs.docker];
    serviceConfig = {
      Type = "simple";
      WorkingDirectory = artexDir;
      ExecStartPre = "${throttleDown}/bin/artex-throttle-down";
      # Foreground compose; systemd owns it. `down` on stop removes the containers
      # (they run under dockerd, not as children of this process), then the restore runs.
      # Needs the image built once: `cd ${artexDir} && docker compose build`.
      ExecStart = "${docker} compose up";
      ExecStop = "${docker} compose down";
      ExecStopPost = "${throttleUp}/bin/artex-throttle-up";
      # Stopping Paper (world save) can take a while; keep the start timeout generous.
      TimeoutStartSec = "600";
      TimeoutStopSec = "180";
      Restart = "no";
    };
  };
}

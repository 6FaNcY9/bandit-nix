{
  lib,
  pkgs,
  ...
}: let
  # Vendored from SZanko/nur-packages: the upstream dub-lock.json pins a stale
  # fetchgit hash for Dadoum/Provision, so the NUR package no longer builds.
  anisette = pkgs.callPackage ../../pkgs/anisette-v3-server {};
in {
  environment.systemPackages = [
    anisette
  ];

  users.groups.anisette = {};

  users.users.anisette = {
    isSystemUser = true;
    group = "anisette";
    description = "Anisette v3 service account";
    home = "/var/lib/anisette-v3";
    createHome = true;
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/anisette-v3 0750 anisette anisette -"
  ];

  systemd.services.anisette-v3 = {
    description = "SideStore Anisette v3 Server";

    wantedBy = [
      "multi-user.target"
    ];

    after = [
      "network-online.target"
    ];

    wants = [
      "network-online.target"
    ];

    environment = {
      HOME = "/var/lib/anisette-v3";
      XDG_CONFIG_HOME = "/var/lib/anisette-v3";
    };

    serviceConfig = {
      Type = "simple";

      User = "anisette";
      Group = "anisette";

      ExecStart = ''
        ${lib.getExe anisette} \
          --host 127.0.0.1 \
          --port 6969 \
          --adi-path /var/lib/anisette-v3
      '';

      Restart = "on-failure";
      RestartSec = "5s";

      StateDirectory = "anisette-v3";
      StateDirectoryMode = "0750";
    };
  };
}

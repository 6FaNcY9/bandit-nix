# The packaged mrija-watch script, shared by the NixOS module (default.nix)
# and the flake check (test.nix). Real rsync/dig/curl/ssh go on PATH; the check
# overrides them with RSYNC/DIG/CURL env vars pointing at stubs.
{
  writeShellApplication,
  python3,
  rsync,
  dnsutils,
  curl,
  openssh,
  dbip-country-lite,
}: let
  pythonEnv = python3.withPackages (p: [p.maxminddb]);
in
  writeShellApplication {
    name = "mrija-watch";
    runtimeInputs = [rsync dnsutils curl openssh];
    text = ''
      export MRIJA_GEOIP=${dbip-country-lite}/share/dbip/dbip-country-lite.mmdb
      exec ${pythonEnv}/bin/python -B ${./mrija_watch.py} "$@"
    '';
  }

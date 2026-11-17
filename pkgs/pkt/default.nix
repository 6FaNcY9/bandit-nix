# pkt: finds, checks and installs BakaSU kernels to the phone's inactive slot.
# Moved here from the phone (~/projects/pong-kernel-tool) so a reset cannot lose
# it. Pure Python; it calls KSU's own binaries in /data/adb/ksu/bin at runtime.
{
  lib,
  stdenvNoCC,
  python3,
  makeWrapper,
}: let
  # telethon is only imported by the Telegram crawl commands.
  py = python3.withPackages (ps: [ps.telethon]);
in
  stdenvNoCC.mkDerivation {
    pname = "pkt";
    version = "0-unstable-2026-11-16";
    src = lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.unions [./pkt ./tests];
    };
    nativeBuildInputs = [makeWrapper];

    dontBuild = true;
    doCheck = true;
    # Tests that need real kernel zips or the phone's partitions skip themselves.
    checkPhase = ''
      runHook preCheck
      HOME=$TMPDIR ${py.interpreter} -m unittest discover -s tests -t .
      runHook postCheck
    '';
    installPhase = ''
      runHook preInstall
      mkdir -p $out/share/pkt $out/bin
      cp -r pkt $out/share/pkt/
      makeWrapper ${py.interpreter} $out/bin/pkt \
        --add-flags "-m pkt.cli" \
        --prefix PYTHONPATH : $out/share/pkt
      runHook postInstall
    '';

    meta = {
      description = "Kernel tool for the owner's rooted Nothing Phone (2)";
      mainProgram = "pkt";
      platforms = lib.platforms.linux;
    };
  }

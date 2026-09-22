{pkgs, ...}: let
  atomics = pkgs.fetchurl {
    url = "https://codeload.github.com/redcanaryco/atomic-red-team/tar.gz/388942adbd9641f4dfdcf079d7efe9a75ec0ac43";
    hash = "sha256-oFWKlFCTFoz0o8SgplVqZb/Mbi1YA+a2JJLOa0/Ooco=";
  };
  invoke = pkgs.fetchurl {
    url = "https://codeload.github.com/redcanaryco/invoke-atomicredteam/tar.gz/8af478bb9e4637df568ac1e596553b025b16cd1b";
    hash = "sha256-wYB9v4bWu4+ja7M5bKaHDsLX6AgRda1KSHx7QDLA06c=";
  };
  yaml = pkgs.fetchurl {
    url = "https://www.powershellgallery.com/api/v2/package/powershell-yaml/0.4.12";
    hash = "sha256-1GArx6Sgk3ZlIEItU8qLCazeFiKG+uEeLubI7f6geBA=";
  };
  atomicFiles = pkgs.runCommand "atomic-red-team-files" {nativeBuildInputs = [pkgs.unzip];} ''
    mkdir -p "$out/tests" "$out/modules/Invoke-AtomicRedTeam" "$out/modules/powershell-yaml"
    tar xf ${atomics} --strip-components=1 -C "$out/tests"
    tar xf ${invoke} --strip-components=1 -C "$out/modules/Invoke-AtomicRedTeam"
    unzip -q ${yaml} -d "$out/modules/powershell-yaml"
    # Guard against a truncated upstream archive: the catalogue holds
    # one T*.yaml per technique, currently around 340 of them.
    count=$(find "$out/tests/atomics" -name 'T*.yaml' | wc -l)
    if [ "$count" -lt 300 ]; then
      echo "atomics extraction looks incomplete: $count technique files" >&2
      exit 1
    fi
  '';
in {
  _module.args.atomicFiles = atomicFiles;
  system.build.atomicCheck =
    pkgs.runCommand "atomic-runner-check" {
      nativeBuildInputs = [pkgs.powershell pkgs.inetutils];
    } ''
      export HOME="$TMPDIR" PSModulePath="${atomicFiles}/modules"
      pwsh -NoLogo -NoProfile -Command '
        $ErrorActionPreference = "Stop"
        Import-Module Invoke-AtomicRedTeam
        $technique = Get-AtomicTechnique -Path "${atomicFiles}/tests/atomics/T1059.004/T1059.004.yaml"
        if ($technique.atomic_tests.Count -lt 1) { throw "No atomic tests parsed" }
      '
      touch "$out"
    '';
}

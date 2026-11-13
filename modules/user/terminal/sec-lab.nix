{
  pkgs,
  bandit,
  ...
}: let
  # The security "house": ~/src/sec (the re-homed pentest repo). The global
  # `pt` shim forwards into its devenv so `pt`, `pt re|ctf|live`, etc. work from
  # anywhere. Inside the devenv the `pt` shell function shadows this bin.
  secDir = "${bandit.workstation.homeDirectory}/src/sec";
in {
  home.packages = [
    (pkgs.writeShellApplication {
      name = "pt";
      runtimeInputs = [pkgs.direnv];
      text = ''
        sec="${secDir}"
        if [ ! -d "$sec" ]; then
          echo "pt: $sec not found — the security repo is expected there." >&2
          echo "    (it is the re-homed pentest repo; see ~/src/sec)." >&2
          exit 1
        fi
        # Run the dispatcher inside the repo's devenv so the tools are on PATH.
        exec direnv exec "$sec" bash "$sec/nix/pt-entry.sh" "$@"
      '';
    })
  ];
}

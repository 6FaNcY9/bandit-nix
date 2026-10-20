# Forces evaluation of every top-level output's derivation path.
{
  pkgs,
  nixosConfigurations,
  homeConfigurations,
}: let
  evaluatedPath = builtins.unsafeDiscardStringContext;
in
  pkgs.writeText "bandit-nix-output-evaluation.json" (builtins.toJSON {
    bandit = evaluatedPath nixosConfigurations.bandit.config.system.build.toplevel.drvPath;
    bandit-ci = evaluatedPath nixosConfigurations.bandit-ci.config.system.build.toplevel.drvPath;
    bandit-lab = evaluatedPath nixosConfigurations.bandit-lab.config.system.build.toplevel.drvPath;
    home = evaluatedPath homeConfigurations.vino.activationPackage.drvPath;
  })

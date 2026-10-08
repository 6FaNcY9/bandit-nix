# Mineflayer bot runner + dashboard (app/). Shared by the lab image and the
# laptop runner (`nix run .#mcbots`).
{
  lib,
  buildNpmPackage,
  nodejs_22,
}:
buildNpmPackage {
  pname = "mcbots";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ./app;
    fileset = lib.fileset.difference ./app (lib.fileset.maybeMissing ./app/node_modules);
  };
  nodejs = nodejs_22;
  npmDepsHash = "sha256-Gemg3W0kL+4JCdQCOptq922Il9g8DgSfFBq+1Wo6cM0=";
  dontNpmBuild = true;
  npmFlags = ["--ignore-scripts"];
  meta.mainProgram = "mcbots";
}

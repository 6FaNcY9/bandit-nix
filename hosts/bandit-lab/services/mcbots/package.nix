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
  # prismarine-physics resolves collisions Y, X, Z; the server does Y, then
  # the smaller of X/Z last. Sliding along a wall mid-jump then lands
  # differently and the server pulls the bot back in a loop (2026-10-08).
  postInstall = ''
    patch -d $out/lib/node_modules/mcbots/node_modules/prismarine-physics -p1 < ${./prismarine-physics-axis-order.patch}
  '';
  meta.mainProgram = "mcbots";
}

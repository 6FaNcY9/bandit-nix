# Phase 2 scaffolding: bandit-v2 (modules/) must build the same system as
# bandit (nixos/). Pure eval: the toplevel drvPaths must be identical.
{
  pkgs,
  old,
  new,
}:
assert pkgs.lib.assertMsg (old.drvPath == new.drvPath)
"bandit-v2 toplevel differs from bandit: ${old.drvPath} vs ${new.drvPath}";
  pkgs.runCommand "laptop-parity" {} "touch $out"

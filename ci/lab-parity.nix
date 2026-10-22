# Phase 3 scaffolding: bandit-lab-v2 (modules/server) must build the same system
# as bandit-lab (nixos/server). Pure eval: the toplevel drvPaths must be identical.
{
  pkgs,
  old,
  new,
}:
assert pkgs.lib.assertMsg (old.drvPath == new.drvPath)
"bandit-lab-v2 toplevel differs from bandit-lab: ${old.drvPath} vs ${new.drvPath}";
  pkgs.runCommand "lab-parity" {} "touch $out"

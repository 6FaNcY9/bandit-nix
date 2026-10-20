{pkgs, ...}: {
  packages = [pkgs.git pkgs.nixd pkgs.alejandra pkgs.statix pkgs.deadnix];
  enterShell = ''echo "nix dev shell"'';
}

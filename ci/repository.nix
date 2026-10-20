{
  pkgs,
  src,
}:
pkgs.runCommand "bandit-nix-repository-checks" {
  nativeBuildInputs = with pkgs; [alejandra deadnix statix];
  inherit src;
} ''
  cp -r "$src" source
  chmod -R u+w source
  cd source
  alejandra --check .
  deadnix --fail .
  statix check .
  touch "$out"
''

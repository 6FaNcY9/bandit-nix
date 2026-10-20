{pkgs, ...}: {
  packages = [pkgs.git];
  enterShell = ''echo "devenv shell"'';
}

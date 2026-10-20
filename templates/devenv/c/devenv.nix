{pkgs, ...}: {
  languages.c.enable = true;
  packages = [pkgs.git pkgs.gdb pkgs.valgrind pkgs.cmake pkgs.pkg-config];
  enterShell = ''echo "c/c++ dev shell"'';
}

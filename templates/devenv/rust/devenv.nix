{pkgs, ...}: {
  languages.rust.enable = true;
  packages = [pkgs.git pkgs.cargo-watch pkgs.cargo-edit];
  enterShell = ''echo "rust $(rustc --version 2>/dev/null)"'';
}

{pkgs, ...}: {
  languages.go.enable = true;
  packages = [pkgs.git pkgs.gopls pkgs.golangci-lint];
  enterShell = ''echo "go $(go version 2>/dev/null)"'';
}

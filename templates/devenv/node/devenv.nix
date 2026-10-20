{pkgs, ...}: {
  languages.javascript = {
    enable = true;
    npm.enable = true;
  };
  languages.typescript.enable = true;
  packages = [pkgs.git];
  enterShell = ''echo "node $(node --version 2>/dev/null)"'';
}

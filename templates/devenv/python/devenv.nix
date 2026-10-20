{pkgs, ...}: {
  languages.python = {
    enable = true;
    uv.enable = true;
    venv.enable = true;
  };
  packages = [pkgs.git pkgs.ruff];
  enterShell = ''echo "python $(python --version 2>/dev/null)"'';
}

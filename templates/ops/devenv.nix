# Per-engagement tooling. Keep tools scoped to this directory via direnv so
# nothing is installed system-wide. Add what each engagement needs under
# packages; the system stays clean.
{pkgs, ...}: {
  packages = [pkgs.git pkgs.jq pkgs.ripgrep];
  enterShell = ''echo "ops engagement shell: $(basename "$PWD")"'';
}

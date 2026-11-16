{pkgs}:
pkgs.runCommand "guest-debian-init-test" {
  nativeBuildInputs = [(pkgs.callPackage ./debian-init.nix {})];
} ''
  status() {
    mkdir -p "$1/var/lib/dpkg"
    cat > "$1/var/lib/dpkg/status" <<'EOF'
  Package: vim
  Status: install ok installed
  Architecture: amd64

  Package: libfoo1
  Status: install ok installed
  Architecture: amd64

  Package: oldpkg
  Status: deinstall ok config-files
  Architecture: amd64
  EOF
  }

  # A: libfoo1 auto-installed, oldpkg removed: only vim is manual
  status A
  mkdir -p A/var/lib/apt
  printf 'Package: libfoo1\nArchitecture: amd64\nAuto-Installed: 1\n\nPackage: vim\nArchitecture: amd64\nAuto-Installed: 0\n' > A/var/lib/apt/extended_states
  test "$(guest-debian-init --manual-packages A)" = vim

  # B: no extended_states: every installed package counts as manual
  status B
  test "$(guest-debian-init --manual-packages B)" = "$(printf 'libfoo1\nvim')"

  # C: no subvolume: refuse, name it, create nothing
  guest-debian-init nosuchguest 2>err && exit 1
  grep -q /var/lib/machines/nosuchguest err
  test ! -e /var/lib/machines/nosuchguest
  test ! -e /srv/nosuchguest

  touch $out
''

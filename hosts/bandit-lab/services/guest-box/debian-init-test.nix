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

  # D: guest-planted links in the old rootfs are refused, not followed
  mkdir -p D/var/lib/dpkg E/var/lib
  ln -s "$PWD/A/var/lib/dpkg/status" D/var/lib/dpkg/status
  guest-debian-init --manual-packages D 2>err && exit 1
  grep -q 'goes through a symlink' err
  status E
  ln -s "$PWD/A/var/lib/apt" E/var/lib/apt
  guest-debian-init --manual-packages E 2>err && exit 1
  grep -q 'goes through a symlink' err

  # Q: qgroup output with a referenced or exclusive limit passes, without one it does not
  hdr='Qgroupid    Referenced    Exclusive Max referenced Max exclusive   Path
  --------    ----------    --------- -------------- -------------   ----'
  printf '%s\n0/257 16384 16384 21474836480 none machines/jerry\n' "$hdr" | guest-debian-init --has-limit
  printf '%s\n0/257 16384 16384 none 1073741824 machines/jerry\n' "$hdr" | guest-debian-init --has-limit
  printf '%s\n0/257 16384 16384 none none machines/jerry\n' "$hdr" | guest-debian-init --has-limit && exit 1
  printf "" | guest-debian-init --has-limit && exit 1

  # C: no subvolume: refuse, name it, create nothing
  guest-debian-init nosuchguest 2>err && exit 1
  grep -q /var/lib/machines/nosuchguest err
  test ! -e /var/lib/machines/nosuchguest
  test ! -e /srv/nosuchguest

  touch $out
''

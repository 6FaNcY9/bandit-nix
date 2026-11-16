# guest-debian-init <name>: fill the empty btrfs subvolume /var/lib/machines/<name> with Debian 13 for the
# stock systemd-nspawn@<name>, as root on the lab. Runbook: docs/runbooks/guest-box.md (Jerry, migration).
# guest-debian-init --manual-packages <rootfs>: the manually installed packages of a Debian rootfs.

die() {
  echo "guest-debian-init: $*" >&2
  exit 1
}

# Installed in dpkg's status minus those apt marked Auto-Installed; without extended_states all count.
manual_packages() {
  local ext=$1/var/lib/apt/extended_states
  [ -f "$ext" ] || ext=/dev/null
  awk -v ext="$ext" '
    /^Package: / { p = $2 }
    /^$/ { p = "" }
    FILENAME == ext && /^Auto-Installed: 1$/ { auto[p] = 1 }
    FILENAME != ext && /^Status: install ok installed$/ { inst[p] = 1 }
    END { for (x in inst) if (!(x in auto)) print x }
  ' "$ext" "$1/var/lib/dpkg/status" | LC_ALL=C sort -u
}

if [ "${1:-}" = --manual-packages ]; then
  manual_packages "${2:?usage: guest-debian-init --manual-packages <rootfs>}"
  exit 0
fi

name=${1:?usage: guest-debian-init <name> | --manual-packages <rootfs>}
R=/var/lib/machines/$name
OLD=/var/lib/nixos-containers/$name
BOX=/srv/$name/box
seed=/etc/guest-seed/$name

[ -d "$R" ] || die "$R does not exist; create the btrfs subvolume first (runbook)"
uid=$(guest_uid "$name") || die "$name is not a Debian guest in guests.nix"
[ "$(id -u)" = 0 ] || die "run as root"
btrfs subvolume show "$R" >/dev/null 2>&1 || die "$R is not a btrfs subvolume"
[ -z "$(ls -A "$R")" ] || die "$R is not empty"
for u in "container@$name" "systemd-nspawn@$name"; do
  ! systemctl is-active -q "$u" || die "$u is still running; stop it first"
done
[ -d "$seed" ] || die "$seed missing; deploy the host config first"
[ -d "$BOX" ] || die "$BOX missing"

# Commands inside the new tree: plain root, host network, host DNS. --settings=no and its own machine name,
# else the guest's .nspawn file (user namespace, veth without internet, binds) would apply.
inside() {
  systemd-nspawn -q --settings=no -M "$name-init" -D "$R" --pipe --resolv-conf=copy-host \
    --setenv=DEBIAN_FRONTEND=noninteractive "$@"
}

debootstrap --variant=minbase --keyring="$KEYRING" \
  --include=systemd-sysv,dbus,openssh-server,ca-certificates,curl,git,python3,python3-venv,python3-pip,pipx,iproute2,htop,unattended-upgrades \
  trixie "$R" http://deb.debian.org/debian

# debootstrap lists only "trixie main"; unattended-upgrades needs the security suite and must be switched on.
cat >"$R/etc/apt/sources.list" <<'EOF'
deb http://deb.debian.org/debian trixie main
deb http://deb.debian.org/debian trixie-updates main
deb http://security.debian.org/debian-security trixie-security main
EOF
cat >"$R/etc/apt/apt.conf.d/20auto-upgrades" <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

inside sh -ec '
  curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg -o /usr/share/keyrings/tailscale-archive-keyring.gpg
  curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list -o /etc/apt/sources.list.d/tailscale.list
  apt-get update
  apt-get install -y tailscale
  PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install uv
'

# The old /root goes to /data/old-root (kept as it is, ownership included: it is already the guest's).
if [ -d "$OLD/root" ] && [ ! -e "$BOX/old-root" ]; then
  cp -a "$OLD/root" "$BOX/old-root"
fi
if [ ! -d "$BOX/old-root" ]; then
  mkdir "$BOX/old-root"
  chown "$uid:$uid" "$BOX/old-root"
fi

list() {
  echo "$1:"
  shift
  [ $# -eq 0 ] || printf "  %s\n" "$@"
}

# Reinstall what the guest installed by hand in his proot Debian.
oldroot=$BOX/debian/rootfs
if [ -f "$oldroot/var/lib/dpkg/status" ]; then
  report=$BOX/old-root/apt-reinstall.txt
  known=$(inside apt-cache pkgnames | LC_ALL=C sort -u)
  mapfile -t want < <(LC_ALL=C comm -12 <(manual_packages "$oldroot") <(printf '%s\n' "$known"))
  mapfile -t missing < <(LC_ALL=C comm -23 <(manual_packages "$oldroot") <(printf '%s\n' "$known"))
  installed=()
  if [ "${#want[@]}" -eq 0 ] || inside apt-get install -y "${want[@]}"; then
    installed=("${want[@]}")
  else
    for p in "${want[@]}"; do
      if inside apt-get install -y "$p"; then installed+=("$p"); else missing+=("$p"); fi
    done
  fi
  { list installed "${installed[@]}"; list missing "${missing[@]}"; } | tee "$report"
  chown "$uid:$uid" "$report"
else
  echo "No old Debian at $oldroot, nothing to reinstall."
fi

# Seed files, root-owned: nspawn's PrivateUsersOwnership=chown shifts the whole tree on first boot.
install -D -m 0644 "$seed/sshd_config.d/10-guest.conf" "$R/etc/ssh/sshd_config.d/10-guest.conf"
install -d -m 0700 "$R/root/.ssh"
install -m 0600 "$seed/authorized_keys" "$R/root/.ssh/authorized_keys"
install -D -m 0644 "$seed/10-host0.network" "$R/etc/systemd/network/10-host0.network"
rm -f "$R/etc/resolv.conf"
install -m 0644 "$seed/resolv.conf" "$R/etc/resolv.conf"
install -m 0644 "$seed/tailscale-up.service" "$R/etc/systemd/system/tailscale-up.service"
systemctl --root="$R" enable systemd-networkd ssh tailscaled tailscale-up

# Same tailnet node and host keys as the old box; root-owned for the same reason.
if [ -d "$OLD/var/lib/tailscale" ]; then
  mkdir -p "$R/var/lib/tailscale"
  cp -r --preserve=mode,timestamps "$OLD/var/lib/tailscale/." "$R/var/lib/tailscale/"
fi
for k in "$OLD"/etc/ssh/ssh_host_*; do
  if [ -e "$k" ]; then cp --preserve=mode,timestamps "$k" "$R/etc/ssh/"; fi
done

touch "$R/etc/guest-seeded"
echo "Done. Start it: systemctl start systemd-nspawn@$name"

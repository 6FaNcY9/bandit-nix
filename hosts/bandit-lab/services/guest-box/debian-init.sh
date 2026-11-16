# guest-debian-init <name>: fill the empty btrfs subvolume /var/lib/machines/<name> with Debian 13 for the
# stock systemd-nspawn@<name>, as root on the lab. Runbook: docs/runbooks/guest-box.md (Jerry, migration).
# guest-debian-init --manual-packages <rootfs>: the manually installed packages of a Debian rootfs.
# guest-debian-init --qgroup-free: bytes left under the tightest limit in `btrfs qgroup show -reF --raw` output
# on stdin; exit 1 when no qgroup has a limit.

die() {
  echo "guest-debian-init: $*" >&2
  exit 1
}

# True when no component of the path is a symlink: /srv/<name>/box and the old rootfs belong to the guest,
# and host root must not follow a link he planted.
real() { [ "$(realpath -m -- "$1")" = "$(realpath -ms -- "$1")" ]; }

# Columns: qgroupid rfer excl max_rfer max_excl [path] (btrfs-progs cmds/qgroup.c).
qgroup_free() {
  awk '$1 ~ /^[0-9]+\/[0-9]+$/ {
    if ($4 != "none") { f = $4 - $2; if (!n || f < m) m = f; n = 1 }
    if ($5 != "none") { f = $5 - $3; if (!n || f < m) m = f; n = 1 }
  }
  END { if (!n) exit 1; printf "%d\n", m }'
}

# Installed in dpkg's status minus those apt marked Auto-Installed; without extended_states all count.
manual_packages() {
  local st=$1/var/lib/dpkg/status ext=$1/var/lib/apt/extended_states
  real "$st" || die "$st goes through a symlink"
  real "$ext" || die "$ext goes through a symlink"
  [ -f "$ext" ] || ext=/dev/null
  awk -v ext="$ext" '
    /^Package: / { p = $2 }
    /^$/ { p = "" }
    FILENAME == ext && /^Auto-Installed: 1$/ { auto[p] = 1 }
    FILENAME != ext && /^Status: install ok installed$/ { inst[p] = 1 }
    END { for (x in inst) if (!(x in auto)) print x }
  ' "$ext" "$st" | LC_ALL=C sort -u
}

case "${1:-}" in
--manual-packages)
  manual_packages "${2:?usage: guest-debian-init --manual-packages <rootfs>}"
  exit 0
  ;;
--qgroup-free)
  qgroup_free
  exit
  ;;
esac

name=${1:?usage: guest-debian-init <name> | --manual-packages <rootfs>}
R=/var/lib/machines/$name
OLD=/var/lib/nixos-containers/$name
BOX=/srv/$name/box
seed=/etc/guest-seed/$name

[ -d "$R" ] || die "$R does not exist; create the btrfs subvolume first (runbook)"
uid=$(guest_uid "$name") || die "$name is not a Debian guest in guests.nix"
[ "$(id -u)" = 0 ] || die "run as root"
btrfs subvolume show "$R" >/dev/null 2>&1 || die "$R is not a btrfs subvolume"
qgroups=$(btrfs qgroup show -reF --raw "$R") || die "no qgroup for $R (quotas off?)"
printf '%s\n' "$qgroups" | qgroup_free >/dev/null || die "$R has no qgroup limit; set one: btrfs qgroup limit 20G $R"
[ -z "$(ls -A "$R")" ] || die "$R is not empty"
for u in "container@$name" "systemd-nspawn@$name"; do
  st=$(systemctl is-active "$u" || true)
  case "$st" in
  inactive | failed | unknown) ;;
  *) die "$u is $st; stop it first" ;;
  esac
done
[ -d "$seed" ] || die "$seed missing; deploy the host config first"
[ -d "$BOX" ] || die "$BOX missing"

# Guest-controlled paths: refuse links before anything is written (checked again where they are used).
oldhome=$BOX/old-root
oldroot=$BOX/debian/rootfs
for p in "$oldhome" "$OLD/root" "$OLD/var/lib/tailscale" "$OLD/var/lib/tailscale/tailscaled.state" \
  "$oldroot/var/lib/dpkg/status" "$oldroot/var/lib/apt/extended_states" "$OLD"/etc/ssh/ssh_host_*; do
  real "$p" || die "$p goes through a symlink"
done

# Without the old node state the box joins as a new tailnet node: other IP (peer.nix), and if the auth key is
# revoked, no ssh and no backup at all.
if [ -d "$OLD" ]; then
  [ -s "$OLD/var/lib/tailscale/tailscaled.state" ] || die "$OLD has no tailscale state; the box would become a new tailnet node"
else
  echo "WARNING: no old box at $OLD: $name joins the tailnet as a NEW node with the auth key (fix peer.nix IPs after)." >&2
fi

# The old /root lands under the /data qgroup; running out of it halfway costs a subvolume recreate.
if [ ! -e "$oldhome" ] && [ -d "$OLD/root" ]; then
  need=$(du -sx -B1 "$OLD/root" | cut -f1)
  echo "Old /root: $need bytes."
  boxq=$(btrfs qgroup show -reF --raw "$BOX") || die "no qgroup for $BOX (quotas off?)"
  if free=$(printf '%s\n' "$boxq" | qgroup_free); then
    [ "$need" -lt "$free" ] || die "old /root ($need bytes) does not fit under the $BOX qgroup ($free bytes left)"
  else
    echo "No qgroup limit on $BOX, size not checked."
  fi
fi

# Commands inside the new tree: plain root, host network, host DNS. --settings=no and its own machine name,
# else the guest's .nspawn file (user namespace, veth without internet, binds) would apply. PATH is set and
# programs are absolute: on NixOS nspawn's default PATH is its own store path.
inside() {
  systemd-nspawn -q --settings=no -M "$name-init" -D "$R" --pipe --resolv-conf=copy-host \
    --setenv=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    --setenv=DEBIAN_FRONTEND=noninteractive "$@"
}

# debootstrap's second stage is fine on NixOS: nixpkgs makes its chroot absolute and in_target sets PATH.
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

inside /bin/sh -ec '
  curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg -o /usr/share/keyrings/tailscale-archive-keyring.gpg
  curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list -o /etc/apt/sources.list.d/tailscale.list
  apt-get update
  apt-get install -y tailscale
  PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install uv
'

# The old /root goes to /data/old-root as it is (cp -a: ownership is already the guest's, links stay links).
# Copied under a temporary name first, so an interrupted copy is redone on the next run.
real "$oldhome" || die "$oldhome goes through a symlink"
if [ -e "$oldhome" ]; then
  echo "$oldhome exists, the old /root is not copied again."
elif [ -d "$OLD/root" ]; then
  real "$OLD/root" || die "$OLD/root goes through a symlink"
  rm -rf "$BOX/.old-root.tmp"
  cp -a "$OLD/root" "$BOX/.old-root.tmp"
  mv -T "$BOX/.old-root.tmp" "$oldhome"
else
  mkdir "$oldhome"
  chown -h "$uid:$uid" "$oldhome"
fi
[ -d "$oldhome" ] || die "$oldhome is not a directory"

list() {
  echo "$1:"
  shift
  [ $# -eq 0 ] || printf "  %s\n" "$@"
}

# Reinstall what the guest installed by hand in his proot Debian.
if [ -e "$oldroot/var/lib/dpkg/status" ] || [ -L "$oldroot/var/lib/dpkg/status" ]; then
  report=$oldhome/apt-reinstall.txt
  manual=$(manual_packages "$oldroot")
  known=$(inside /usr/bin/apt-cache pkgnames | LC_ALL=C sort -u)
  mapfile -t want < <(LC_ALL=C comm -12 <(printf '%s\n' "$manual") <(printf '%s\n' "$known"))
  mapfile -t missing < <(LC_ALL=C comm -23 <(printf '%s\n' "$manual") <(printf '%s\n' "$known"))
  installed=()
  if [ "${#want[@]}" -eq 0 ] || inside /usr/bin/apt-get install -y "${want[@]}"; then
    installed=("${want[@]}")
  else
    for p in "${want[@]}"; do
      if inside /usr/bin/apt-get install -y "$p"; then installed+=("$p"); else missing+=("$p"); fi
    done
  fi
  rm -f "$report" # the guest may have planted a link there; tee would follow it
  { list installed "${installed[@]}"; list missing "${missing[@]}"; } | tee "$report"
  chown -h "$uid:$uid" "$report"
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

# Same tailnet node and host keys as the old box; root-owned for the same reason. The old rootfs was the
# guest's: refuse links on the way, and copy links inside as links (cp -r, cp -P).
if [ -d "$OLD/var/lib/tailscale" ]; then
  real "$OLD/var/lib/tailscale" || die "$OLD/var/lib/tailscale goes through a symlink"
  mkdir -p "$R/var/lib/tailscale"
  cp -r --preserve=mode,timestamps "$OLD/var/lib/tailscale/." "$R/var/lib/tailscale/"
fi
for k in "$OLD"/etc/ssh/ssh_host_*; do
  [ -e "$k" ] || [ -L "$k" ] || continue
  real "$k" || die "$k goes through a symlink"
  cp -P --preserve=mode,timestamps "$k" "$R/etc/ssh/"
done

touch "$R/etc/guest-seeded"
echo "Done. Start it: systemctl start systemd-nspawn@$name"

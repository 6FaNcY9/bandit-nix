{
  writeShellApplication,
  debootstrap,
  debian-archive-keyring,
  btrfs-progs,
  systemd,
  coreutils,
  gawk,
  lib,
  guests ? import ./guests.nix,
}:
writeShellApplication {
  name = "guest-debian-init";
  runtimeInputs = [debootstrap btrfs-progs systemd coreutils gawk];
  # The Debian guests' uid bases from guests.nix, so /srv/<name>/box files go to the guest's mapped root.
  text =
    ''
      KEYRING=${debian-archive-keyring}/share/keyrings/debian-archive-keyring.gpg
      guest_uid() {
        case "$1" in
        ${lib.concatStrings (lib.mapAttrsToList (n: g: "${n}) echo ${toString g.uid} ;;\n") (lib.filterAttrs (_: g: (g.os or "nixos") == "debian") guests))}*) return 1 ;;
        esac
      }
    ''
    + builtins.readFile ./debian-init.sh;
}

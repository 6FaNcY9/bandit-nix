# One entry per guest box; read by default.nix, watch.nix and ci/lab-guests.nix.
# uid: base of the guest's 65536-id user namespace. Taken: 524288 jerry, 589824 mc-public, 655360 martin.
# net: the guest's veth /30 (host .1, guest .2). Taken: 10.251.0 jerry, 10.251.1 mc-public, 10.251.2 martin.
# os: "nixos" (default, containers.<name>) or "debian" (a Debian rootfs in /var/lib/machines/<name>, run by
# the stock systemd-nspawn@<name>; guest-debian-init fills it from /etc/guest-seed/<name>).
{
  jerry = {
    uid = 524288;
    os = "debian";
    net = "10.251.0";
    memory = "2G";
    key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID4PNbKtaXkyHqz7p8sXH1xtPpiP+FiIgeRpfm6x1/U+ jerry";
    hostAccept = ["-A nixos-fw -i ve-jerry -p udp --dport 41641 -j nixos-fw-accept"]; # host tailscaled (WireGuard authenticates): direct backup path
  };
  martin = {
    uid = 655360;
    net = "10.251.2";
    memory = "4G";
    key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG9CD8nqgC8lbrzUinbW8iKXhFkW5RQWeAOACpjheUAy martin";
    hostAccept = []; # no backup on the lab, so nothing on the host is open to him
  };
}

{
  pkgs,
  repoConfig,
  ...
}: {
  # Host integration and small daily-use security tools (bandit only).
  # Large coursework toolchains live in ~/Projects/pentest's devenv profiles so
  # routine NixOS rebuilds do not rebuild the full pentesting environment.
  # Wireshark gets a proper capture setup (setcap dumpcap + group) instead of
  # running the GUI as root; the user is added to the wireshark group here.
  programs.wireshark = {
    enable = true;
    package = pkgs.wireshark;
  };
  users.users.${repoConfig.workstation.username}.extraGroups = ["wireshark"];

  environment.systemPackages = with pkgs; [
    # ── Recon / network ──────────────────────────────────────────────────
    nmap # port scanner (includes ncat)
    tcpdump # packet capture CLI
    dnsutils # dig / nslookup / host
    whois
    arp-scan # LAN discovery

    # ── Small standalone tools not provided by the pentest devenv ────────
    thc-hydra # network logon cracker
    # seclists + rockyou instead of the `wordlists` wrapper: it drags in
    # wfuzz, which is currently broken in nixpkgs (pkg_resources removed
    # from setuptools on python 3.14). Lists land in …/share/seclists etc.
    seclists
    rockyou

    # ── VPN / pivoting ───────────────────────────────────────────────────
    openvpn
    wireguard-tools
    socat

    # ── Host diagnostics ─────────────────────────────────────────────────
    binutils # objdump / readelf / nm
    strace
    ltrace

    # ── Wireless ─────────────────────────────────────────────────────────
    # NOTE: the Framework 13's MediaTek Wi-Fi has no monitor mode/injection —
    # use a USB adapter (e.g. Alfa AWUS036ACM) for aircrack-ng labs.
    aircrack-ng
    wifite2 # wireless network auditor
    hcxtools # capture + convert to hashcat/John formats

    # ── Misc / post-exploitation ─────────────────────────────────────────
    pspy # monitor Linux processes without root

    # ── Privacy / metadata hygiene ───────────────────────────────────────
    exiftool # inspect/edit EXIF metadata
  ];
}

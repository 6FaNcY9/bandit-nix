{
  pkgs,
  config,
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
  users.users.${config.bandit.workstation.username}.extraGroups = ["wireshark"];

  environment.systemPackages = [
    # ── Recon / network ──────────────────────────────────────────────────
    pkgs.nmap # port scanner (includes ncat)
    pkgs.tcpdump # packet capture CLI
    pkgs.dnsutils # dig / nslookup / host
    pkgs.whois
    pkgs.arp-scan # LAN discovery

    # ── OSINT ────────────────────────────────────────────────────────────
    pkgs.maigret # collect account details by username across thousands of sites
    pkgs.sherlock # hunt social-media accounts by username
    pkgs.theharvester # emails, subdomains, and names from public sources
    # Shodan CLI (API key from sops, see shell wrapper). nixpkgs builds it
    # against setuptools >= 81, which removed pkg_resources — the CLI still
    # imports it for plugin entry points, so pin the setuptools_80 fallback.
    (pkgs.python3Packages.shodan.override {setuptools = pkgs.python3Packages.setuptools_80;})

    # ── Small standalone tools not provided by the pentest devenv ────────
    pkgs.thc-hydra # network logon cracker
    # seclists + rockyou instead of the `wordlists` wrapper: it drags in
    # wfuzz, which is currently broken in nixpkgs (pkg_resources removed
    # from setuptools on python 3.14). Lists land in …/share/seclists etc.
    pkgs.seclists
    pkgs.rockyou

    # ── VPN / pivoting ───────────────────────────────────────────────────
    pkgs.openvpn
    pkgs.wireguard-tools
    pkgs.socat

    # ── Host diagnostics ─────────────────────────────────────────────────
    pkgs.binutils # objdump / readelf / nm
    pkgs.strace
    pkgs.ltrace
    pkgs.lynis # local security audit
    pkgs.vulnix # scan the closure for known CVEs

    # ── Wireless ─────────────────────────────────────────────────────────
    # NOTE: the Framework 13's MediaTek Wi-Fi has no monitor mode/injection —
    # use a USB adapter (e.g. Alfa AWUS036ACM) for aircrack-ng labs.
    pkgs.aircrack-ng
    pkgs.wifite2 # wireless network auditor
    pkgs.hcxtools # capture + convert to hashcat/John formats

    # ── Misc / post-exploitation ─────────────────────────────────────────
    pkgs.pspy # monitor Linux processes without root

    # ── Privacy / metadata hygiene ───────────────────────────────────────
    pkgs.exiftool # inspect/edit EXIF metadata
  ];
}

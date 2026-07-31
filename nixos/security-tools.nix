{
  pkgs,
  repoConfig,
  ...
}: {
  # Offensive-security and privacy toolkit for coursework (bandit only).
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
    masscan # fast internet-scale scanner
    tcpdump # packet capture CLI
    dnsutils # dig / nslookup / host
    whois
    arp-scan # LAN discovery

    # ── Web application testing ──────────────────────────────────────────
    burpsuite # intercepting proxy (unfree — allowlisted in lib/repository.nix)
    gobuster # directory/DNS/vhost brute-forcer
    ffuf # web fuzzer
    sqlmap # automated SQL injection
    nikto # web server scanner

    # ── Password attacks ─────────────────────────────────────────────────
    hashcat # GPU cracking (uses the ROCm OpenCL stack from graphics.nix)
    john # John the Ripper (jumbo)
    thc-hydra # network logon cracker
    # seclists + rockyou instead of the `wordlists` wrapper: it drags in
    # wfuzz, which is currently broken in nixpkgs (pkg_resources removed
    # from setuptools on python 3.14). Lists land in …/share/seclists etc.
    seclists
    rockyou

    # ── Reverse engineering / pwn ────────────────────────────────────────
    gef # GDB enhanced for exploit dev (pwndbg is not packaged in nixpkgs)
    ghidra # NSA decompiler (GUI)
    radare2 # CLI reverse engineering framework
    binwalk # firmware analysis/extraction
    checksec # binary hardening checker
    binutils # objdump / readelf / nm
    strace
    ltrace

    # ── Exploitation ─────────────────────────────────────────────────────
    metasploit

    # ── Wireless ─────────────────────────────────────────────────────────
    # NOTE: the Framework 13's MediaTek Wi-Fi has no monitor mode/injection —
    # use a USB adapter (e.g. Alfa AWUS036ACM) for aircrack-ng labs.
    aircrack-ng

    # ── Privacy / metadata hygiene ───────────────────────────────────────
    mat2 # strip metadata from files before publishing/sharing
    exiftool # inspect/edit EXIF metadata
  ];
}

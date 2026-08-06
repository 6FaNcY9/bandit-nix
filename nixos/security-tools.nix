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

    # ── AD / Windows ─────────────────────────────────────────────────────
    netexec # maintained fork of CrackMapExec
    enum4linux-ng # Windows/Samba enumeration
    responder # LLMNR/NBT-NS/MDNS poisoner
    bloodhound # AD attack path management
    evil-winrm # WinRM shell
    kerbrute # Kerberos bruteforce
    mimikatz # Windows credential extraction
    chisel # TCP/UDP tunnel over HTTP
    ligolo-ng # TUN-based pivoting tunnel
    sshpass # non-interactive SSH password auth

    # ── Web application testing ──────────────────────────────────────────
    burpsuite # intercepting proxy (unfree — allowlisted in lib/repository.nix)
    gobuster # directory/DNS/vhost brute-forcer
    ffuf # web fuzzer
    sqlmap # automated SQL injection
    nikto # web server scanner
    feroxbuster # recursive content discovery
    nuclei # configurable targeted scanning
    dalfox # parameter/XSS analysis
    whatweb # web scanner / fingerprinting
    # wpscan is unfree (unfreeRedistributable) and not allowlisted.

    # ── Password attacks ─────────────────────────────────────────────────
    hashcat # GPU cracking (uses the ROCm OpenCL stack from graphics.nix)
    john # John the Ripper (jumbo)
    thc-hydra # network logon cracker
    haiti # hash type identification
    # seclists + rockyou instead of the `wordlists` wrapper: it drags in
    # wfuzz, which is currently broken in nixpkgs (pkg_resources removed
    # from setuptools on python 3.14). Lists land in …/share/seclists etc.
    seclists
    rockyou

    # ── VPN / pivoting ───────────────────────────────────────────────────
    openvpn
    wireguard-tools
    proxychains-ng
    socat
    sshuttle

    # ── Reverse engineering / pwn ────────────────────────────────────────
    gef # GDB enhanced for exploit dev (pwndbg is not packaged in nixpkgs)
    gdb # GNU debugger base
    ghidra # NSA decompiler (GUI)
    radare2 # CLI reverse engineering framework
    binwalk # firmware analysis/extraction
    checksec # binary hardening checker
    binutils # objdump / readelf / nm
    strace
    ltrace

    # ── Exploitation ─────────────────────────────────────────────────────
    metasploit

    # ── Forensics / steganography ────────────────────────────────────────
    steghide # steganography hide/extract
    stegseek # steganography cracker
    foremost # file carving
    sleuthkit # forensic/data recovery
    xortool # multi-byte XOR analysis
    zsteg # PNG/BMP stegano detection
    # volatility3 is unfree (VSL) and not allowlisted.

    # ── Wireless ─────────────────────────────────────────────────────────
    # NOTE: the Framework 13's MediaTek Wi-Fi has no monitor mode/injection —
    # use a USB adapter (e.g. Alfa AWUS036ACM) for aircrack-ng labs.
    aircrack-ng
    wifite2 # wireless network auditor
    hcxtools # capture + convert to hashcat/John formats

    # ── Misc / post-exploitation ─────────────────────────────────────────
    pspy # monitor Linux processes without root

    # ── Privacy / metadata hygiene ───────────────────────────────────────
    mat2 # strip metadata from files before publishing/sharing
    exiftool # inspect/edit EXIF metadata
  ];
}

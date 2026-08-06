_: {
  # Prevent overwriting the running kernel image while it is loaded.
  security.protectKernelImage = true;

  # Conservative kernel/sysctl hardening (SECURITY-PLAN Phase 5).
  # Settings are chosen to avoid breaking common desktop/server workloads.
  boot.kernel.sysctl = {
    # Hide kernel pointers from non-root users.
    "kernel.kptr_restrict" = 2;
    # Restrict the kernel ring buffer (dmesg) to root.
    "kernel.dmesg_restrict" = 1;
    # Disable unprivileged eBPF. This can break some container/perf tooling,
    # so it is left disabled here pending workload testing.
    # "kernel.unprivileged_bpf_disabled" = 1;
    # Harden the eBPF JIT compiler. This can affect some container tooling,
    # so it is left disabled here pending workload testing.
    # "net.core.bpf_jit_harden" = 2;
    # Restrict ptrace to parent/children and root.
    "kernel.yama.ptrace_scope" = 1;
    # Disable setuid core dumps.
    "fs.suid_dumpable" = 0;
    # Enable reverse-path filtering to mitigate spoofed packets.
    "net.ipv4.conf.all.rp_filter" = 1;
    # Log martian (impossible) packets.
    "net.ipv4.conf.all.log_martians" = 1;
    # Enable SYN flood protection.
    "net.ipv4.tcp_syncookies" = 1;
  };
}

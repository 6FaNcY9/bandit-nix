# Tor routing — removed, deferred

Tor routing is intentionally absent from both `bandit` and `bandit-lab`.
The shared module and laptop network-menu controls were removed after the
owner reported loss of networking and SSH access on `bandit-lab`, requiring
manual changes on the server to recover. The exact failure mechanism and
those manual changes have not been verified. The lab configuration in this
checkout already excluded the module when the removal was made.

The previous implementation is available in Git at
`2406045:nixos/tor.nix` and `2406045:home/desktop/netmenu.nix`.
It redirected host TCP and DNS traffic and blocked outbound non-loopback
UDP, ICMP, and IPv6. Its TCP exemptions did not include the Tailscale
`100.64.0.0/10` range. These are management-connectivity risks, not a
confirmed diagnosis of the incident.

Before considering Tor again:

- Prefer explicit application-level proxying or an isolated VM over
  transparent routing of the entire host. Keep it disabled by default.
- Test SSH, Tailscale, LAN access, DNS, IPv4, and IPv6 with routing enabled
  and disabled, including startup failure, partial rule installation, stop,
  and reboot. Verify cleanup restores the original networking behavior.
- Have local console access and a tested rollback before any host trial.
  Reconcile the lab's manual recovery changes before deploying configuration.

Removing repository code does not clean up rules on running hosts. No live
firewall cleanup or configuration activation was performed as part of this
removal.

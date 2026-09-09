# Security lab on bandit-lab — decision record (2026-09-09)

Direction from the owner: evolve bandit-lab into a cyber-security lab, full
authority to add/modify services. This document records the decisions and the
phase order so later sessions can continue without re-litigating.

## Hardware budget (measured 2026-09-09)

32 cores, 62 GiB RAM (4.1 GiB used), 2.5 TB NVMe (3% used), load ~0.06.
The box is >90% idle — resource weight is **not** a selection criterion;
operational complexity and attack surface are.

## Email server: NOT viable on this connection (verdict, evidence-based)

Measured from bandit-lab on 2026-09-09:

- Outbound TCP 25, 465, 587, 2525, 2587 → **all blocked** by the ISP
  (surfer.at cable), including to the mrija.org relay host
  `s16.thehost.com.ua`.
- Public IP `84.115.238.232` has PTR
  `84-115-238-232.cable.dynamic.surfer.at` — dynamic pool, no custom PTR.
- Inbound WAN is Cloudflare-Tunnel-only (HTTP) by design; no port 25 path in.

A public MTA here would neither send (port blocked) nor receive (no inbound
25, no PTR → instant spam-classification). **Decision:** no self-hosted public
email. `mrija.org` mail stays on TheHost shared hosting (as today;
mrija-archive mirrors it). A LAN/tailnet-only MTA remains an option for
phishing-simulation labs (phase 5) — it never touches real domains.

## Selected additions (phase order)

1. **Quick hardening wins** (this change set, Nix-native):
   - SearXNG: Traefik `rateLimit` middleware (public endpoint; unthrottled
     metasearch gets the host IP banned by upstream engines).
   - WatchYourLAN: drop `PROMETHEUS_ENABLE` — unreachable by Prometheus
     (GUI binds loopback on host net) and nothing scrapes it.
   - Remove `/srv/containers/jellyfin` leftover (2 MB, no container/image).
2. **Wazuh SIEM/XDR** — the core sec-lab piece. Deploy per existing runbook
   `docs/runbooks/wazuh.md` (Portainer/external compose stack, v4.12.0,
   indexer heap 4g, dashboard loopback-only). Manager watches the lab;
   laptop agent over tailnet later.
3. **CrowdSec** — LAPI + agent container parsing Traefik/sshd logs, Traefik
   bouncer plugin, crowdsec-firewall-bouncer for sshd. Replaces fail2ban's
   role with collaborative blocklists; keep fail2ban until CrowdSec proven.
4. **Analyst toolbox containers** (tiny, tunnel-publishable):
   OWASP Juice Shop (practice target), CyberChef, IT-Tools.
   Publish under `*.bandit-lab.mrija.org` behind existing Access policies.
5. **Optional later:** Gophish + maddy (internal-only mail, phishing-sim);
   Kasm Workspaces (browser Kali; heavy — only if the workflow proves out).

## Rejected, with reasons

- Public email server — see verdict above.
- OpenVAS/GVM — feed sync + scan churn on a server; ad-hoc scans run better
  from the laptop toolkit (`nixos/security-tools.nix`).
- MISP — threat-intel sharing platform for teams; single-user overkill.
- Cowrie/honeypots — no public TCP path (tunnel is HTTP-only); a LAN-only
  honeypot sees nothing.
- AdGuard Home — needs router DHCP/DNS control (out of repo scope); revisit
  if router access is granted.
- Suricata/Zeek/ntopng — Wi-Fi host interface sees only own+broadcast
  traffic; no span port. Wazuh's host telemetry covers the useful part.

## Invariants (do not break)

- NixOS repo is the source of truth; Portainer stays console-only.
- WAN exposure only via Cloudflare Tunnel + Access; admin UIs loopback/tailnet.
- New secrets go to sops, never plaintext in the repo.
- Every phase ends deployed: push → `lab-update apply` → health check green.

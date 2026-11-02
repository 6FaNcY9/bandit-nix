# Lab web UIs over the tailnet (no SSH tunnels)

Every admin UI on bandit-lab is published with `tailscale serve` on its own
HTTPS port of the lab's MagicDNS name, tailnet only (never Funnel). Tailscale
issues the certificate and terminates TLS; the tailnet ACL decides who may
connect (today: the owner's devices; Jerry's nodes reach port 8000 only). The
host firewall stays closed, which is why `ci/lab-surface.nix` is unaffected.
Public hostnames behind Cloudflare keep working as before; this is the
"from the phone/laptop in the tailnet without `ssh -L`" path.

| URL | Service | Backend | Unit |
| --- | --- | --- | --- |
| https://bandit-lab.tail7facc9.ts.net:8443 | Minecraft map | 127.0.0.1:8100 | `minecraft-panel-https` (bandit-craft) |
| https://bandit-lab.tail7facc9.ts.net:8445 | mcbots dashboard | mcbots | `mcbots-https` (bandit-craft) |
| https://bandit-lab.tail7facc9.ts.net:8446 | mcbots worker API | mcbots | `mcbots-https` (bandit-craft) |
| https://bandit-lab.tail7facc9.ts.net:8447 | ntfy | 127.0.0.1:2586 | `ntfy-https` |
| https://bandit-lab.tail7facc9.ts.net:8448 | Grafana | 127.0.0.1:3000 | `lab-https` |
| https://bandit-lab.tail7facc9.ts.net:8449 | Beszel | 127.0.0.1:8090 | `lab-https` |
| https://bandit-lab.tail7facc9.ts.net:8450 | Cockpit | https://127.0.0.1:9090 | `lab-https` |

Ports 8448+ are owned by `hosts/bandit-lab/services/tailnet-https.nix`; add a
line to its `serves` set for a new UI (next free: 8451; ComfyUI goes there once
it is a unit). Cockpit also needs the serve URL in `allowed-origins`, which the
same file sets.

Not published: Vaultwarden (its `DOMAIN` is `vault.atmosphaere.at`; another
origin breaks WebAuthn and client links), aiia (public site) and mail-archive
(Cloudflare Access gate is intended). Use their Cloudflare hostnames.

## Checks

```sh
ssh bandit-lab 'tailscale serve status'          # one https://...:<port> block per row above
ssh bandit-lab 'systemctl status lab-https'      # WARNING in the log = Serve/HTTPS certs not enabled in the admin console
curl -sI https://bandit-lab.tail7facc9.ts.net:8449 | head -1   # from any tailnet device
```

A first visit per port can take a few seconds while Tailscale fetches the
certificate. If a port keeps failing, `tailscale serve --https=<port> off` on
the lab (owner sudo) and restart `lab-https`.

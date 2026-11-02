# Lab web UIs as Tailscale Services (no SSH tunnels)

grafana, beszel and cockpit on bandit-lab are published as named Tailscale
Services: `https://<name>.tail7facc9.ts.net` from any tailnet device, listed
under Network, Services in the admin console. Tailscale terminates TLS and the
tailnet policy decides who connects (grant `group:trusted` to `tag:lab-svc`,
`tcp:443`). Tailnet only, never Funnel; the host firewall stays closed, so
`ci/lab-surface.nix` is unaffected. The unit is `lab-services` in
`hosts/bandit-lab/services/tailnet-https.nix`. Public Cloudflare hostnames keep
working as before.

## Owner console steps (once, before the deploy)

1. Access controls (JSON editor): merge into the policy file and add the two
   tests below under `"tests"`; save only if they pass.

   ```json
   "tagOwners": { "tag:lab": ["autogroup:admin"], "tag:lab-svc": ["autogroup:admin"] },
   "autoApprovers": { "services": { "tag:lab-svc": ["tag:lab"] } },
   "grants": [
     { "src": ["tag:lab"], "dst": ["100.102.247.30"], "ip": ["tcp:8000"] },
     { "src": ["group:trusted"], "dst": ["tag:lab-svc"], "ip": ["tcp:443"] },
     { "src": ["jerrecode@github", "tag:jerry-box"], "dst": ["100.125.161.81"], "ip": ["tcp:8000"] },
     { "src": ["jerrecode@github", "tag:jerry-box"], "dst": ["svc:comfyui"], "ip": ["tcp:443"] }
   ]
   ```

   Tests: `{"src": "group:trusted", "accept": ["svc:grafana:443"]}` and
   `{"src": "jerrecode@github", "accept": ["svc:comfyui:443"], "deny": ["svc:grafana:443"]}`.
2. Network, Services, Advertise, Define a Service: `grafana`, `beszel`,
   `cockpit`, `comfyui`, each endpoint `tcp:443`, tag `tag:lab-svc`.
3. Machines, bandit-lab, Edit ACL tags: `tag:lab`. Irreversible; IP and name
   stay.
4. Laptop: `ssh bandit-lab true && echo ok` prints `ok`.
5. Laptop: `ssh bandit-lab 'sudo systemctl start restic-backups-peer && systemctl is-active restic-backups-peer'`
   (owner password) prints `inactive` after a clean run; `journalctl -u restic-backups-peer -n 3`
   shows no `connection refused`.

Deploying before step 2/3 is safe: `lab-services` logs a WARNING per service and
still succeeds; restart it after the console is ready.

## Services

| URL | Service | Backend | Unit |
| --- | --- | --- | --- |
| https://grafana.tail7facc9.ts.net | Grafana | 127.0.0.1:3000 | `lab-services` |
| https://beszel.tail7facc9.ts.net | Beszel | 127.0.0.1:8090 | `lab-services` |
| https://cockpit.tail7facc9.ts.net | Cockpit | https://127.0.0.1:9090 | `lab-services` |
| https://comfyui.tail7facc9.ts.net | ComfyUI | once it is a unit | not yet |
| https://bandit-lab.tail7facc9.ts.net:8443 | Minecraft map | 127.0.0.1:8100 | `minecraft-panel-https` (bandit-craft), per-port serve, not a Service |
| https://bandit-lab.tail7facc9.ts.net:8445 | mcbots dashboard | mcbots | `mcbots-https` (bandit-craft), per-port serve, not a Service |
| https://bandit-lab.tail7facc9.ts.net:8446 | mcbots worker API | mcbots | `mcbots-https` (bandit-craft), per-port serve, not a Service |
| https://bandit-lab.tail7facc9.ts.net:8447 | ntfy | 127.0.0.1:2586 | `ntfy-https`, per-port serve, not a Service |

## Add a service

1. Console: define the Service (name, `tcp:443`, `tag:lab-svc`).
2. One line in the `services` set of `hosts/bandit-lab/services/tailnet-https.nix`
   (name = loopback target). For ComfyUI the target is the future unit's
   loopback port; the console definition and the Jerry grant already exist.
3. Cockpit-style UIs that check the Origin header also need the service URL in
   their allowed origins.

## Checks

```sh
ssh bandit-lab 'tailscale serve status'                       # one https://<name>.tail7facc9.ts.net block per Service plus the legacy ports
ssh bandit-lab "tailscale status --json | jq '.Self.Tags'"    # ["tag:lab"]
ssh bandit-lab 'systemctl status lab-services --no-pager'     # WARNING in the log = console definition or tag missing
curl -sI https://beszel.tail7facc9.ts.net | head -1           # from the laptop
```

## Not published

Vaultwarden (its `DOMAIN` is `vault.atmosphaere.at`; another origin breaks
WebAuthn and client links), aiia (public site) and mail-archive (Cloudflare
Access gate is intended). Use their Cloudflare hostnames.

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
   `cockpit`, `comfyui`, `ntopng`, each endpoint `tcp:443`, tag `tag:lab-svc`.
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
| https://comfyui.tail7facc9.ts.net | ComfyUI | 127.0.0.1:8188 | `lab-services` |
| https://memory.tail7facc9.ts.net (page), `/mcp` (agents) | Shared LLM memory (Basic Memory) | 127.0.0.1:8766 | `lab-services` |
| https://memory-albert.tail7facc9.ts.net (page), `/mcp` | Albert's memory store | 127.0.0.1:8768 | `lab-services` |
| https://memory-firma.tail7facc9.ts.net (page), `/mcp` | Shared company memory store | 127.0.0.1:8770 | `lab-services` |
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

## Shared LLM memory (`svc:memory`)

Basic Memory's MCP endpoint (`hosts/bandit-lab/services/memory`) has no login,
so it does not use `tag:lab-svc` (open to `group:trusted`). It carries its own
tag `tag:lab-mem` (tagOwners `autogroup:admin`, autoApprovers
`"tag:lab-mem": ["tag:lab"]`) with one grant: owner identity to `tag:lab-mem`,
`tcp:443`. Invite a device or person by adding it to that grant's `src`.
Clients: `claude mcp add -s user -t http basic-memory https://memory.tail7facc9.ts.net/mcp`.
Notes live in `/srv/containers/memory/data` (in the restic backup).

### Three stores (`svc:memory`, `svc:memory-albert`, `svc:memory-firma`)

Design: `docs/superpowers/specs/2026-11-14-memory-stores-design.md`. Three
copies of the same container (store list in `services/memory/default.nix`),
each with its own data dir, front and Service, all `tag:lab-mem`. Each keeps
project `main`. Only vino's store has the summariser and `/bnet/devices`.

| Store | Service | Ports (MCP/page) | Data | Who reaches it |
| --- | --- | --- | --- | --- |
| vino (private) | `svc:memory` | 8765/8766 | `/srv/containers/memory/data` | owner only |
| albert | `svc:memory-albert` | 8767/8768 | `/srv/containers/memory-albert/data` | Albert (`tag:albert`) and owner |
| firma (shared) | `svc:memory-firma` | 8769/8770 | `/srv/containers/memory-firma/data` | Albert (`tag:albert`) and owner |

Access is the tailnet policy only; no store has a login, and no front sends
CORS headers. The page links stores with `[[firma:path]]`, `[[vino:path]]`,
`[[albert:path]]`; a viewer without access gets a failed page. All data dirs
are in the restic backup (the only undo for an overwritten note).

Owner steps (design steps 3-7, in order; 1 and 2 must pass before Albert gets any address):

1. Tailscale console, policy: add `tagOwners` `"tag:albert": ["autogroup:admin"]`;
   grant `tag:albert` to `svc:memory-firma`, `svc:memory-albert` `tcp:443`;
   grant owner login and `tag:lab` to `tag:albert` `*`; tests: `tag:albert`
   accepts the two new Services and is denied `svc:memory` and `svc:grafana`,
   the owner accepts all three. Save must pass.
2. Console: set `tag:albert` on the device `albert`. Check from that PC: the
   private store fails, SSH and bnet still work.
3. Signed commit and lab deploy. Check on the lab:
   `tailscale serve status` shows three memory blocks; all three pages load
   on the laptop.
4. Laptop: `claude mcp add -s user -t http firma https://memory-firma.tail7facc9.ts.net/mcp`
   and a CLAUDE.md rule (listed company projects go to `firma`, never copy
   private notes there). Check: `firma` answers.
5. Albert: `claude mcp add -s user -t http firma https://memory-firma.tail7facc9.ts.net/mcp`
   and `claude mcp add -s user -t http albert https://memory-albert.tail7facc9.ts.net/mcp`,
   plus his CLAUDE.md. Check: he writes a test note, the owner sees it.

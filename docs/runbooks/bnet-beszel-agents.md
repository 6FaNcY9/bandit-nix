# bandit-net: Beszel agents and lab secrets

Spec: `docs/specs/bnet/2026-11-13-device-net-design.md`. Beszel (hub on bandit-lab, `services/beszel`) supplies the
hardware numbers (CPU, RAM, GPU, temperatures); bandit-net (`services/bnet`) supplies who-is-using-it and the jobs.

## Secrets on bandit-lab (once, as root; never in git or the shared memory)

```sh
install -d -m 0700 /etc/bnet
openssl rand -hex 32 > /etc/bnet/token && chmod 0600 /etc/bnet/token
printf 'BNET_TOKEN=%s\n' "$(cat /etc/bnet/token)" > /etc/bnet/router.env && chmod 0600 /etc/bnet/router.env
systemctl restart bnet-router memory-web
```

The same token goes to each PC with `install.ps1 -Token` (tools/bnet/windows).

## Tailscale Service svc:bnet

Define `svc:bnet` with tag `tag:lab-svc` in the admin console like the other lab services
(docs/runbooks/tailnet-services.md), grant it only to the user's own devices, then `systemctl restart lab-services`.

## Beszel agents

1. Open https://beszel.<tailnet>.ts.net → **Add System**. Name = tailnet host (`albert`, `slayerpc`, `bandit`).
2. The dialog shows the install command with this system's key and token:
   - **albert, slayer (Windows):** copy the Windows command and run it in an elevated PowerShell at the PC.
   - **bandit (NixOS laptop):** add `services.beszel.agent` like `hosts/bandit-lab/services/beszel` with the key in
     `/etc/beszel/agent.env` (not in git).
3. Phones and tablets get no Beszel agent; the bnet device list shows them as online/offline from Tailscale.

## Check

- From pong: `curl -s https://memory.<tailnet>.ts.net/bnet/devices` lists albert, slayer, bandit-lab, bandit, pong.
- Memory page → **Geräte** shows the same list; the Beszel link opens the hardware view.

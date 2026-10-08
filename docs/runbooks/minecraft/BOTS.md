# Minecraft bots (Mineflayer)

Phase 1+2 of the bot system: Mineflayer bots join Paper through Velocity and
BotGate and are controlled from a small web dashboard. Code:
`hosts/bandit-lab/services/mcbots/` (`app/` is the Node app, `default.nix` the
lab deployment). Crafting and schematic building are later phases; a new job
type is one entry in `JOBS` and one in `VALIDATE` in `app/bots.js`.

## How it fits together

- Bots are named `bot1`..`bot4` on the lab (`bot5`+ on the laptop). BotGate
  admits offline logins only for `^bot[0-9]{1,2}$` from the owner laptop
  (`100.102.247.30/32`) or the `mcbots` Docker network (`10.250.77.0/29`).
- Lab: container `mcbots` (nix-built image, non-root uid 1000, 2 GiB / 2 CPUs,
  no capabilities, no mounts) on network `mcbots`, connecting to `velocity:25565`.
  The dashboard listens on `127.0.0.1:8095` (host) and is published to the
  tailnet by the oneshot `mcbots-https` (`tailscale serve`, never Funnel).
- Protocol: Mineflayer 4.39.0 supports up to 26.1; bots join with
  `version: '26.1'` and ViaBackwards translates to the Paper 26.2 server.
- Logins are staggered (4.5 s apart); reconnects back off 5 s, 10 s, ... up to
  5 min (at least 30 s after "logging in too fast").

## Deploy / disable

Deploy like any lab change (see `bandit-lab-updates.md`). Port 8445 must be
served once: Serve and HTTPS Certificates are already enabled for the panel;
after the first activation run `sudo systemctl restart mcbots-https`.

Disable: set `bandit-lab.mcbots.enable = false;` (or remove the
`./services/mcbots` import in `hosts/bandit-lab/default.nix`) and deploy.
Immediate stop without a deploy: `sudo systemctl stop docker-mcbots mcbots-https`.

## Dashboard

Open `https://bandit-lab.tail7facc9.ts.net:8445` from a tailnet device.
`tailscale serve` adds the header `Tailscale-User-Login`; the app answers 403 to
anything (HTTP or WebSocket) whose login is not in `ALLOWED_TS_LOGINS`
(`6FaNcY9@github`). POSTs and WebSocket upgrades also need a same-origin
`Origin`. Without `ALLOWED_TS_LOGINS` (laptop) the dashboard binds to
`127.0.0.1` only and refuses any other `DASHBOARD_HOST`.

The page shows every bot (online, health/food, position and dimension, job and
queue, inventory summary, last error). Pick a target (one bot or `all`), then
enqueue jobs. "Come to me" uses the player name typed into "your player name".

## Laptop

```bash
BOT_NAMES=bot5,bot6 MC_HOST=100.125.161.81 nix run .#mcbots
# dashboard: http://127.0.0.1:8095
```

Other variables: `MC_PORT` (25565), `DASHBOARD_PORT` (8095). Use at most the
names not used by the lab. Ctrl-C quits the bots cleanly.

## Jobs

Each bot runs its queue one job at a time. Chat is never read as a command.

| Job | Arguments | Notes |
| --- | --- | --- |
| `goto` | x y z | walks within 1 block; gives up after 90 s |
| `follow` | player | until `stop`; fails if the player is out of render distance |
| `come` | player | walks to the player's current position |
| `mine` | block, count | `mine iron_ore 8`; nearest block within 64, best tool is equipped |
| `chop` | count | any `*_log` within 64 blocks |
| `deposit` | x y z | puts everything except tools and food into the chest/barrel there |
| `say` | text | up to 200 characters; text starting with `/` is rejected |
| `stop` | | clears the queue and stops walking/digging |

## Limits

- Bots never attack. They do not avoid mobs, lava or players' builds beyond
  not tunnelling or placing blocks while walking.
  `mine`/`chop` do break blocks: do not point them at player builds.
- Pathing cannot dig or bridge, so a goal behind solid rock is reported as
  "could not reach".
- Velocity admits at most the `/29` network: gateway, Velocity and 4 bots.
- The dashboard trusts the `Tailscale-User-Login` header. Only `tailscale serve`
  (host) and containers on `mcbots` (Velocity) can reach it; keep it that way.

## Troubleshooting

- Bot offline, "logging in too fast" / throttled: wait; the runner backs off
  itself. Do not restart repeatedly.
- Kicked with a not-whitelisted/online-mode message: BotGate refused it. Check
  `sudo docker logs velocity 2>&1 | grep -i botgate` for the decision line (name
  pattern or source address). The name must match `^bot[0-9]{1,2}$` and come
  from the allowlisted source.
- Other Velocity problems: `sudo docker logs --tail 100 velocity`.
- Dashboard: `sudo journalctl -u docker-mcbots -u mcbots-https -n 50`,
  `sudo docker logs --tail 100 mcbots`. HTTPS unreachable: `tailscale serve status`,
  then `sudo systemctl restart mcbots-https`. 403: your Tailscale login is not in
  `ALLOWED_TS_LOGINS`, or the request bypassed `tailscale serve`.
- Image changed but the old one runs: the image tag is the Nix store hash;
  `sudo systemctl restart docker-mcbots` after activation.

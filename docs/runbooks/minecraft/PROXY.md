# Minecraft behind Velocity: bots without paid accounts

Prepared, not deployed. Players and bots join through a Velocity proxy
(`docker-velocity.service`, itzg/mc-proxy, Velocity 3.5.1 build 615, Java 21).
Paper no longer publishes a game port; it is reachable only from the proxy over the
`minecraft` Docker network, with modern forwarding (shared secret) and
`online-mode=false` in `server.properties`.

## Authentication model

- Everyone is authenticated by Mojang at the proxy (`online-mode = true`), so premium
  players keep their existing online UUIDs through forwarding.
- The BotGate plugin (`hosts/bandit-lab/services/minecraft/botgate/`) forces offline mode
  for a login only when the name matches `^bot[0-9]{1,2}$` (case-sensitive) **and** the
  source address is inside `BOTGATE_SOURCES`: the laptop `bandit` tailnet IP
  (`repoConfig.lab.workstationTailscaleIp`) and the `mcbots` network. It logs
  `botgate: offline login <name> from <ip>` for each one. A missing or malformed
  `BOTGATE_SOURCES` aborts plugin load (fail closed, the proxy still enforces Mojang auth).
- Never allowlist the `minecraft` network, the default bridge or the lab's own tailnet IP;
  `lab-minecraft` rejects those.
- Velocity 3.5.1 loads BotGate from `velocity-plugin.json` (no `@Plugin` annotation) and
  creates it through Guice, so the constructor is `@Inject BotGate(Logger)`.
- Networks: `minecraft` (Docker-assigned subnet; Paper and Velocity only) and `mcbots`,
  pinned `10.250.77.0/29` (gateway .1, velocity .2, up to 4 bot containers).

## How bots connect

- Laptop: Mineflayer to `100.125.161.81:25565`, username `bot1`..`bot99`, `auth` unset
  or `offline`. Must originate from the laptop's tailnet address.
- Lab bots: containers started with `--network mcbots` connect to `velocity:25565`.
- Any other name or source gets normal Mojang authentication, so a bot name from
  elsewhere is kicked ("Failed to verify username").
- If bots are kicked for unsigned chat, set `enforce-secure-profile=false` in
  `server.properties` through the panel and restart the server.

## Secret

`secrets/lab.yaml` key `minecraft-velocity-secret` (owner adds it with `sops`). It is
rendered into `/run/secrets/rendered/minecraft-velocity.env` as
`VELOCITY_FORWARDING_SECRET` (proxy) and `CFG_VELOCITY_SECRET` (Paper's
`paper-global.yml` via the itzg patch set `/data/nix-patches/velocity.json`, staged by
`minecraft-plugins`). Rotating means changing the key and restarting both
`docker-minecraft` and `docker-velocity`.

## Runtime verification after the GO

1. `sudo systemctl restart docker-minecraft docker-velocity` (once, after a backup),
   then `systemctl status docker-network-mcbots docker-velocity`.
2. `docker network inspect mcbots -f '{{(index .IPAM.Config 0).Subnet}}'` prints
   `10.250.77.0/29`; `docker exec velocity java -version` shows Java 21.
3. `docker logs velocity` shows `Loaded plugin botgate` and no BotGate error; the
   Paper log shows Velocity forwarding enabled.
4. `ss -ltn` on the lab: `100.125.161.81:25565` is the proxy; nothing else publishes
   25565 (`docker ps --format '{{.Names}} {{.Ports}}'`).
5. A premium player joins from the tailnet and keeps their existing UUID/inventory.
6. From the laptop `bot1` joins, and `docker logs velocity | grep botgate` shows one
   line with the laptop address. `bot1` from any other tailnet node, and `Bot1` or
   `bot100` from the laptop, are refused.
7. From a throwaway container on `mcbots`, a bot joins `velocity:25565`; the same
   from the default bridge is refused.
8. `docker exec minecraft env | grep -c CFG_VELOCITY_SECRET` is 1 and Paper is not
   reachable directly (`nc 100.125.161.81 25565` reaches the proxy only).

## Rollback

1. `sudo systemctl stop docker-velocity docker-minecraft`.
2. Set `proxies.velocity.enabled: false` in
   `/srv/containers/minecraft/data/config/paper-global.yml` (the patch re-enables it
   at every start until the revert is deployed) and `online-mode=true` in
   `server.properties` (itzg stops managing that key once `ONLINE_MODE` is gone).
3. Deploy the revert commit as a fast-forward (`lab-update apply` refuses rewrites).
4. Start `docker-minecraft`; verify players join on `100.125.161.81:25565`.

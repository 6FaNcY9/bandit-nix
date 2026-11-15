# mc-public firewall (host side)

The box itself is documented in bandit-craft `docs/runbooks/minecraft/PUBLIC.md`; this page covers the host
rules in `hosts/bandit-lab/services/mc-public/default.nix` (contract: `ci/lab-mc-public.nix`).

- v4 `nixos-fw`: replies to host-opened connections (the playit agent -> Velocity 10.251.1.2:25565) are
  accepted, everything else from `ve-mc-public` is refused.
- v6 `nixos-fw`: everything from `ve-mc-public` is refused at the top (the box has no IPv6; an accepted
  router advertisement would rewrite the host's routes).
- `mangle FORWARD` (not `DOCKER-USER`, which fails open while Docker is down): the box may leave via
  `enp44s0` only, never to 10/8, 172.16/12, 192.168/16, 169.254/16 or 100.64/10, and nothing NEW is
  forwarded into it.

## After deploying the change of 2026-11-15

As root on the lab:

```sh
ip6tables -S nixos-fw | head -3                   # 2nd line: -A nixos-fw -i ve-mc-public -j nixos-fw-refuse
iptables -t mangle -S FORWARD | grep ve-mc-public  # seven DROP rules
iptables -S DOCKER-USER | grep ve-mc-public        # old rules, see below
```

Players can still join: connect through the public playit address, or run check 5 of PUBLIC.md
(`timeout 3 bash -c '</dev/tcp/10.251.1.2/25565' && echo OPEN` on the lab host -> `OPEN`).

The box still reaches the internet (as root on the lab):

```sh
nixos-container run mc-public -- bash -c 'getent hosts api.playit.gg && timeout 3 bash -c "</dev/tcp/1.1.1.1/443" && echo OUT-OK'
nixos-container run mc-public -- tailscale status | head -3
```

The firewall reload runs the new generation's stop commands only, so the four `DOCKER-USER` rules of the
previous generation stay until the next reboot. They only drop, so they are harmless; to remove them by
hand (as root on the lab):

```sh
iptables -w -D DOCKER-USER -i ve-mc-public -d 192.168.0.0/24 -j DROP
iptables -w -D DOCKER-USER -i ve-mc-public -d 10.250.77.0/29 -j DROP
iptables -w -D DOCKER-USER -i ve-mc-public ! -o enp44s0 -j DROP
iptables -w -D DOCKER-USER -o ve-mc-public -m conntrack --ctstate NEW -j DROP
```

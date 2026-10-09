# Blueprints

Blueprints for the `build` job (`app/build.js`, BOTS.md "Building"). Coordinates are relative to an
origin that the job adds (`"origin": {"x","y","z"}`); the origin is floor level, **one above the
ground**. Drafted 2026-10-10. Every file except `base-v1.json` passes today's `validate()` with an
origin outside the protected areas, and building the eight shell parts in order on flat ground
places all 168 blocks (simulated with `step()`; not yet built live).

| File | Blocks | Buildable now? |
| --- | --- | --- |
| `test-pad-3x3.json` | 9 cobblestone | yes: live-test pad |
| `base-v1-shell-01.json` .. `-08.json` | 41, 22, 22, 10, 34, 16, 16, 7 cobblestone (168 total) | yes: build 01..08 in order, **same origin for all** |
| `base-v1.json` | the whole storage hut: shell + 8 chests, crafting table, furnace, bed, 2 torches | no: needs R4 (bigger than 5x5x3, block states) |

## base-v1: storage hut

7x7 outside, 5 high: floor (y 0), walls (y 1-3) with an open doorway in the middle of the front
wall (front = -z, x 3, y 1-2), flat roof (y 4). Inside 5x5, 3 high:

```
z=6  # # # # # # #        back wall
z=5  # C C C C T #        C = chests, two layers (y 1 and 2) = four double chests, T = crafting table
z=4  # . . . . F #        F = furnace (faces the room)
z=3  # t . . . B #        B = bed head, t = torch
z=2  # . . . . B #        B = bed foot (respawn point for every bot, R5)
z=1  # t . . . . #
z=0  # # # . # # #        front wall, doorway at x=3
     x=0 . . . . . 6
```

Chest roles (`storage` in `base-v1.json`, for the planner in R6/R7): supply (kits, food, torches),
iron, gold, coal plus rare ores. Material: 168 cobblestone + 1 furnace (8 cobblestone) + 8 chests
(64 planks = 16 logs) + crafting table (1 log) + bed (3 wool + 3 planks) + 2 torches.

Where (**a guess**, the owner decides): a flat 7x7 spot next to the forest site `-260 65 -213`
where the lab bots already work, so the hut becomes their base. Mark it with a `site` marker.

## Building the shell today

```bash
B=hosts/bandit-lab/services/mcbots/blueprints
for n in 01 02 03 04 05 06 07 08; do
  ARGS=$(jq -c '{blocks, origin: {x: -250, y: 66, z: -200}}' $B/base-v1-shell-$n.json)
  # POST {"bots":["bot1"],"type":"build","args":ARGS} to /api/job and wait until idle
done
```

The upper parts (05-08, the top wall row and the roof) are 4-5 blocks above the ground. The bot
places them from inside the hut, standing on the floor and entering through the doorway. That
reach has not been tested live; if a block is out of reach the job reports it instead of pillaring.

## Format for later (R4)

`state` on a block (`{"facing": "north"}`) is ignored by today's validator, which refuses chests,
beds, furnaces and torches outright. R4 has to place these with their facing: chests on one row
with the same facing join into double chests, a bed is one entry (the foot) and the head follows
from `facing`.

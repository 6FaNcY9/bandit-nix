# Goal: Base Command, guiding the bots with ease

Owner's wish (2026-10-09): one page where I see my bots, the world and my base, and tell the
bots what to do and what they need, without typing coordinates. In the end the bots gather
everything the automated base needs, build parts of it and keep themselves alive. Not in one
day; each stage below is usable on its own and is shipped when it is done.

Where we are: dashboard with terrain map (click a bot, player or spot), in-game view per bot,
per-bot settings, guard, shifts, standing orders, torches, safe digging, crit/sweep combat.

## Stage 1 - the map is the controller (next)

- Right-click (long-press on phone) anywhere opens every action that fits there: mine/chop/shift
  here, guard, go, place a chest, "light up this area", "send N bots".
- Drag a box on the map: "mine everything in this box down to Y", "clear trees", "light it up",
  "guard it". The box shows on the map with its progress.
- Places are map markers I create, move and name: supply chest(s), work sites, home, AFK spots
  (gold farm). Saved in the state volume, not in `default.nix`, so the supply marker is where the
  chest really is. Hover a chest: its contents.
- Roles per bot (miner, lumberjack, guard, AFK, builder) with their own default site and job, set
  from the bot's card or the map.

Done when: I can run a normal play session without opening the job form or typing coordinates.

## Stage 2 - orders, not jobs

- Projects: "512 iron ingots", "64 hoppers", "a stack of torches". The planner splits them into
  jobs (mine at the right Y, smelt, craft), shares them among idle bots and shows one progress bar.
- Standing orders editable on the page (quotas, site, on/off per item), stock read from all
  chests, not only the supply chest.
- Bots fetch what they need on their own: an axe for chopping (no more golden carrots), a
  pickaxe tier for the ore, food, torches, spare armour from the supply chest.

Done when: I ask for an item count and come back to it in the chest.

## Stage 3 - they do not die

- Safe digging (done), skeletons fought within 8 (done); next: arrow side-step, MLG water bucket,
  no swimming in lava lakes, retreat to a lit spot at night.
- After a death: walk back to the drops or grave and pick everything up.
- Spare kits kept stocked in the supply chest by the keeper.

Done when: a full day of shifts without a lost kit.

## Stage 4 - mine like a pro

- Ore Y-levels (26.2 = 1.18 distribution): diamond/redstone -59, gold -16, lapis 0, iron 16,
  copper 48, coal 96. A bot goes to the band, branch-mines there, finishes each vein.
- A cave layer on the map (slice at the bot's height) to watch tunnels and pick a spot.
- Precision tricks where they pay: instant tool swap (done), perfect crits (done), bridging.

Done when: iron and redstone arrive in hundreds per hour from two bots.

## Stage 5 - storage and building

- Storage: bots sort the base chests; a search box answers "where is my redstone".
- Build: import a schematic (.schem/.litematic), preview on the map, material list checked
  against storage, bots build it with block claims (design in BOTS.md). Starts with farms and
  redstone modules MidariBread designs.

Done when: a farm from a schematic is built by the bots from materials they gathered.

## Stage 6 - polish

- Phone layout, notifications (death, project done, chest full), 3D view later.

## Rules for every stage

- Ship mcbots-only changes (no `docker-minecraft` restart) through `tools/ship-claude`.
- Tests for every API field; live check on the local stage (bot6/bot7) before shipping.
- No duplication glitches or chat spam; protected areas stay protected.

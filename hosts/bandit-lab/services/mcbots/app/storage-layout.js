'use strict';
// The storage hall (live 2026-10-10, x -264..-249 y 58..60 z -219..-214): 56 DOUBLE chests, one cell each
// (the smaller-x half), rows z -219 and -216 face south, -217 and -214 face north, levels y 58 and 59,
// pairs along x from the door outwards. Aisles z -218 (rows -219/-217) and z -215 (rows -216/-214) are
// where a bot stands. Categories are contiguous runs of this fixed slot order, so "where does iron go"
// needs no data; the index (world.chests) says what a chest actually holds.
const PAIR_X = [-263, -261, -259, -257, -255, -253, -251];
const ROWS = [{z: -219, stand: -218}, {z: -217, stand: -218}, {z: -216, stand: -215}, {z: -214, stand: -215}];

const SLOTS = [];
for (const x of PAIR_X) for (const r of ROWS) for (const y of [58, 59]) SLOTS.push({x, y, z: r.z, stand: {x, y: 58, z: r.stand}});

const LAYOUT = [['ore', 4], ['stone', 10], ['dirt_sand', 6], ['wood', 8], ['farm_food', 5], ['mobs', 5], ['tools_gear', 5], ['redstone', 3], ['build', 6], ['misc', 4]];
const BY_CAT = {};
let at = 0;
for (const [cat, n] of LAYOUT) { BY_CAT[cat] = SLOTS.slice(at, at + n); at += n; }

const RULES = [ // first match wins; misc is the fallback
  ['tools_gear', /_(pickaxe|axe|shovel|hoe|sword|helmet|chestplate|leggings|boots)$|^(bow|crossbow|shield|shears|trident|fishing_rod|flint_and_steel|elytra|totem_of_undying)$/],
  ['redstone', /^(redstone|repeater|comparator|piston|sticky_piston|observer|hopper|dropper|dispenser|lever|tnt|target|daylight_detector)$|_(button|pressure_plate)$/],
  ['ore', /^(raw_.+|coal|charcoal|diamond|emerald|lapis_lazuli|quartz|amethyst_shard|netherite_.+)$|_(ingot|nugget|ore)$/],
  ['wood', /_(log|wood|planks|sapling|stem|hyphae|leaves)$|^(stick|bamboo)$/],
  ['stone', /^(cobblestone|cobbled_deepslate|stone|deepslate|andesite|diorite|granite|tuff|calcite|netherrack|blackstone|basalt|end_stone|obsidian|sandstone|red_sandstone)$/],
  ['dirt_sand', /^(dirt|coarse_dirt|grass_block|podzol|mycelium|clay|sand|red_sand|gravel|mud|moss_block)$/],
  ['mobs', /^(bone|string|gunpowder|rotten_flesh|spider_eye|ender_pearl|slime_ball|blaze_rod|ghast_tear|phantom_membrane|feather|leather|ink_sac|glow_ink_sac|arrow|honeycomb|egg|prismarine_shard)$/],
  ['farm_food', /_seeds$|^(wheat|carrot|potato|beetroot|sugar_cane|pumpkin|melon_slice|cactus|kelp|sweet_berries|cocoa_beans|bone_meal|hay_block)$/],
  ['build', /_(wool|carpet|glass|glass_pane|bricks|stairs|slab|wall|fence|fence_gate|door|trapdoor|terracotta|concrete|sign|bed|banner)$|^(glass|torch|lantern|ladder|chest|barrel|crafting_table|furnace)$/],
];
const categoryOf = (name, isFood = () => false) => (isFood(name) ? 'farm_food' : (RULES.find(([, re]) => re.test(name)) || ['misc'])[0]);
const chestsFor = (cat) => BY_CAT[cat] || BY_CAT.misc;
const keyOf = (c) => `${c.x},${c.y},${c.z}`;

// Chests of a category to try for `items`, best first: ones the index says already hold one, then the rest of the run.
function order(cat, items, chests) {
  const run = chestsFor(cat);
  const has = (c) => items.some((i) => chests.get(keyOf(c))?.items?.[i]);
  return [...run.filter(has), ...run.filter((c) => !has(c))];
}

// Which chests to open for `item` (a name predicate), in order: those the index says hold it (nearest
// `from` first), then the item's category run, then the old wall; only chests that `exists`. Never all 64.
const GENERIC = {logs: 'oak_log', wool: 'white_wool', coal: 'coal'};
function withdrawOrder({item, match, chests, wall, exists, from}) {
  const holds = (c) => Object.keys(chests.get(keyOf(c))?.items || {}).some(match);
  const dist = (c) => Math.abs(c.x - from.x) + Math.abs(c.z - from.z) + Math.abs(c.y - from.y);
  const seen = new Set(), out = [];
  const add = (list) => list.forEach((c) => { if (!seen.has(keyOf(c)) && exists(c)) { seen.add(keyOf(c)); out.push(c); } });
  add([...SLOTS, ...wall].filter(holds).sort((a, b) => dist(a) - dist(b)));
  add(chestsFor(categoryOf(GENERIC[item] || item)));
  add(wall);
  return out;
}

module.exports = {SLOTS, LAYOUT, BY_CAT, categoryOf, chestsFor, keyOf, order, withdrawOrder};

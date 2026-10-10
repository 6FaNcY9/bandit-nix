'use strict';
// Storage roles for a deposit at the base chest: what the keeper, the plan and crafting draw from it
// stays there ('base'); everything else (stone variants, flowers, mob drops, ...) goes to the
// storage-room chests ('room'), so junk cannot fill the chest the jobs depend on (2026-10-10).
const BASE_RE = /^(stick|[a-z_]+_(log|planks|sapling|wool|bed|pickaxe|axe|shovel|hoe|sword|helmet|chestplate|leggings|boots)|cobblestone|stone_bricks|coal|charcoal|torch|raw_iron|iron_ingot|crafting_table|furnace|chest|scaffolding|bow|crossbow|shield|shears)$/;
// The base chest keeps an item only up to its keeper quota (cobblestone 569 / logs 509 / saplings 310 filled it and
// left no room for torches, 2026-10-10): the rest goes to the hall like 'room' items. Mirrors KEEPER_QUOTAS
// (default.nix) and the plan's stock-basics; saplings are no quota but capped too. Kinds: any *_log is "logs".
const CAPS = [['logs', 64], ['cobblestone', 128], ['stone_bricks', 128], ['coal', 32], ['torch', 64], ['raw_iron', 32], ['sapling', 32]];
const kindOf = (n) => (n.endsWith('_log') ? 'logs' : n.endsWith('_sapling') ? 'sapling' : n === 'charcoal' ? 'coal' : n);
// Is the chest already at (or, with delta < 0, would it stay at) the cap of this item's kind? stock: {name: count}.
const overCap = (name, stock, delta = 0, caps = CAPS) => {
  const cap = caps.find(([k]) => k === kindOf(name));
  return !!cap && Object.entries(stock).reduce((s, [n, c]) => s + (kindOf(n) === cap[0] ? c : 0), delta) >= cap[1];
};
const storeFor = (name, foods = () => false, over = () => false) => ((BASE_RE.test(name) || foods(name)) && !over(name) ? 'base' : 'room');

const sameXYZ = (a, b) => !!a && !!b && a.x === b.x && a.y === b.y && a.z === b.z;
module.exports = {storeFor, overCap, CAPS, sameXYZ};

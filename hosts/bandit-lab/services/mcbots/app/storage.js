'use strict';
// Storage roles for a deposit at the base chest: what the keeper, the plan and crafting draw from it
// stays there ('base'); everything else (stone variants, flowers, mob drops, ...) goes to the
// storage-room chests ('room'), so junk cannot fill the chest the jobs depend on (2026-10-10).
const BASE_RE = /^(stick|[a-z_]+_(log|planks|sapling|wool|bed|pickaxe|axe|shovel|hoe|sword|helmet|chestplate|leggings|boots)|cobblestone|coal|charcoal|torch|raw_iron|iron_ingot|crafting_table|furnace|chest|scaffolding|bow|crossbow|shield|shears)$/;
const storeFor = (name, foods = () => false) => BASE_RE.test(name) || foods(name) ? 'base' : 'room';

const sameXYZ = (a, b) => !!a && !!b && a.x === b.x && a.y === b.y && a.z === b.z;
module.exports = {storeFor, sameXYZ};

'use strict';
// Iron gear a bot should craft next (pure: test.js feeds it plain names). `owned` is every item
// name carried or worn. Pickaxe and sword count as done at iron or better; an armour slot is done
// with any piece in it, so nothing worn is ever replaced or melted down. Cheapest armour first.
const COST = {iron_pickaxe: 3, iron_sword: 2, iron_boots: 4, iron_helmet: 5, iron_leggings: 7, iron_chestplate: 8};
const OWNED = (kind) => (/pickaxe|sword/.test(kind) ? new RegExp(`^(iron|diamond|netherite)_${kind}$`) : new RegExp(`_${kind}$`));

function gearPlan(ingots, owned) {
  const plan = [];
  for (const [item, cost] of Object.entries(COST)) {
    if (owned.some((n) => OWNED(item.slice(5)).test(n)) || cost > ingots) continue;
    ingots -= cost;
    plan.push(item);
  }
  return plan;
}

// Ingots every missing piece needs together.
const ingotsWanted = (owned) => gearPlan(Infinity, owned).reduce((n, item) => n + COST[item], 0);

module.exports = {gearPlan, ingotsWanted, COST};

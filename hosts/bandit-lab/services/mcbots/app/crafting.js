'use strict';
// Crafting and smelting for one bot, built on mineflayer's recipe API.
// ensureItem() crafts missing intermediates (planks -> sticks -> pickaxe),
// places a crafting table or furnace when none is near, and smelt() runs a
// furnace until the requested output is collected. Helpers come from bots.js
// (goNear/guard/sleep) so walking keeps the movement and protection rules.
const {Vec3} = require('vec3');
const {insideAreas} = require('./world');

const MAX_DEPTH = 4;
const FUELS = ['coal', 'charcoal', 'coal_block', 'oak_planks', 'spruce_planks', 'birch_planks', 'jungle_planks',
  'acacia_planks', 'dark_oak_planks', 'mangrove_planks', 'cherry_planks', 'pale_oak_planks', 'bamboo_planks',
  'oak_log', 'spruce_log', 'birch_log', 'jungle_log', 'acacia_log', 'dark_oak_log', 'mangrove_log', 'cherry_log', 'pale_oak_log', 'stick'];

// The combat loop (eat, equip a weapon) must not move items while a craft or
// furnace is in progress: a swap mid-click silently voids the craft.
async function holding(r, fn) {
  r.inventoryBusy = (r.inventoryBusy || 0) + 1;
  try {
    return await fn();
  } finally {
    r.inventoryBusy--;
  }
}

// The crafted item shows up a moment after bot.craft() resolves on 26.x.
async function arrived(test, ms = 3000) {
  for (const end = Date.now() + ms; Date.now() < end; await new Promise((res) => setTimeout(res, 100))) if (test()) return true;
  return test();
}

const count = (bot, name) => bot.inventory.items().filter((i) => i.name === name).reduce((n, i) => n + i.count, 0);

// Smelts per item of fuel: coal 8, logs/planks 1.5, stick 0.5.
const burn = (f) => (/coal/.test(f) ? 8 : /log|planks/.test(f) ? 1.5 : 0.5);
// The first fuel the bot has enough of for `n` smelts (not counting what it is about to smelt).
const fuelFor = (bot, input, n) => FUELS.find((f) => count(bot, f) - (f === input ? n : 0) >= Math.ceil(n / burn(f)));

function nearBlock(bot, name, maxDistance = 24) {
  const id = bot.registry.blocksByName[name]?.id;
  return id === undefined ? null : bot.findBlock({matching: id, maxDistance});
}

// Place an item from the inventory on a free spot next to the bot.
// Grass, flowers and leaf litter count as free: placing replaces them.
const open = (b) => b && b.boundingBox === 'empty' && !/water|lava/.test(b.name);
async function placeNear(bot, itemName, areas = [], check = () => {}) {
  const item = bot.inventory.items().find((i) => i.name === itemName);
  if (!item) throw new Error(`no ${itemName} to place`);
  const me = bot.entity.position.floored();
  // Same level first, then on top of a neighbouring block (bot in a pit), then one down.
  for (const dy of [-1, 0, -2]) {
    for (const [dx, dz] of [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [-1, -1], [1, -1], [-1, 1]]) {
      const ground = bot.blockAt(me.offset(dx, dy, dz));
      const spot = bot.blockAt(me.offset(dx, dy + 1, dz));
      if (ground?.boundingBox === 'block' && open(spot) && !insideAreas(areas, spot.position.x, spot.position.z)) {
        check();
        await bot.equip(item, 'hand');
        check(); // a Stop during the equip places nothing (Codex R3-2)
        await bot.placeBlock(ground, new Vec3(0, 1, 0)).catch(() => {}); // 26.x may not echo the update in time
        for (let i = 0; i < 20; i++) {
          const placed = bot.blockAt(spot.position);
          if (placed?.name === itemName) return placed;
          await new Promise((res) => setTimeout(res, 100));
        }
        throw new Error(`placing ${itemName} did not take`);
      }
    }
  }
  throw new Error(`no free spot next to the bot to place ${itemName}`);
}

function makeCrafting({goNear, guard}) {
  // Get or place a station block (crafting_table, furnace) near the bot.
  // Get or place a station block (crafting_table, furnace) near the bot. A
  // known one out of reach is walked to; if that fails (bot down a pit), a new
  // one is placed instead. ponytail: leaves stations behind, pick them up if it litters.
  async function station(r, job, name, depth) {
    const {bot} = r;
    let block = nearBlock(bot, name);
    if (block && bot.entity.position.distanceTo(block.position.offset(0.5, 0.5, 0.5)) > 4) {
      try {
        await goNear(r, job, block.position.x, block.position.y, block.position.z, 3);
      } catch (e) {
        guard(job);
        block = null;
      }
    }
    if (!block) {
      await ensureItem(r, job, name, 1, depth + 1);
      block = await placeNear(bot, name, r.protectedAreas, () => guard(job));
    }
    return bot.blockAt(block.position);
  }

  const isPlanks = (n) => n.endsWith('_planks');
  const isLog = (n) => /_(log|stem)$/.test(n);
  const planksTotal = (bot) => bot.inventory.items().filter((i) => isPlanks(i.name)).reduce((n, i) => n + i.count, 0);
  // Recipes take planks of one wood (mineflayer lists a variant per wood), so
  // 1 oak + 1 spruce plank do not make sticks: count the biggest single kind.
  const planksHeld = (bot) => {
    const by = {};
    for (const i of bot.inventory.items()) if (isPlanks(i.name)) by[i.name] = (by[i.name] || 0) + i.count;
    return Math.max(0, ...Object.values(by));
  };

  // Turn logs (any wood) into planks until `want` planks are held.
  async function ensurePlanks(r, job, want) {
    const {bot} = r;
    while (planksHeld(bot) < want) {
      guard(job);
      const log = bot.inventory.items().filter((i) => isLog(i.name)).sort((a, b) => b.count - a.count)[0];
      if (!log) throw new Error(`need ${want - planksHeld(bot)} more planks and have no logs (chop first)`);
      const plank = bot.registry.itemsByName[log.name.replace(/^stripped_/, '').replace(/_(log|stem)$/, '_planks')];
      const recipe = plank && bot.recipesFor(plank.id, null, 1, null)[0];
      if (!recipe) throw new Error(`cannot turn ${log.name} into planks`);
      const before = planksTotal(bot);
      await holding(r, () => bot.craft(recipe, Math.min(log.count, Math.ceil((want - planksHeld(bot)) / 4)), null));
      if (!(await arrived(() => planksTotal(bot) > before))) throw new Error(`turning ${log.name} into planks did not take`);
    }
  }

  // Make sure the inventory holds `want` of `name`. One plan per item: pick
  // the recipe variant that needs the fewest missing ingredients, treat planks
  // of any wood as interchangeable, make missing ingredients first, then craft
  // once. No retrying across variants (that burned materials).
  async function ensureItem(r, job, name, want, depth = 0) {
    const {bot} = r;
    guard(job);
    const have = count(bot, name);
    if (have >= want) return;
    const item = bot.registry.itemsByName[name];
    if (!item) throw new Error(`unknown item: ${name}`);
    if (depth > MAX_DEPTH) throw new Error(`need ${want - have} more ${name}`);
    const all = bot.recipesAll(item.id, null, true);
    if (!all.length) throw new Error(`need ${want - have} more ${name}: it cannot be crafted (gather or smelt it)`);
    const missing = (recipe, times) => recipe.delta.filter((d) => d.count < 0).reduce((n, d) => {
      const ing = bot.registry.items[d.id].name;
      const held = isPlanks(ing) ? planksHeld(bot) : count(bot, ing);
      return n + Math.max(0, -d.count * times - held);
    }, 0);
    const timesOf = (recipe) => Math.ceil((want - have) / recipe.result.count);
    const recipe = [...all].sort((a, b) => missing(a, timesOf(a)) - missing(b, timesOf(b)))[0];
    const times = timesOf(recipe);
    // The table first: its 4 planks must not come out of the planks made for the recipe.
    let where = null;
    if (recipe.requiresTable) where = await station(r, job, 'crafting_table', depth);
    // Planks last: making sticks eats planks, so planks made first fall short.
    const rank = (d) => (isPlanks(bot.registry.items[d.id].name) ? 1 : 0);
    for (const d of recipe.delta.filter((x) => x.count < 0).sort((a, b) => rank(a) - rank(b))) {
      const ing = bot.registry.items[d.id].name;
      const need = -d.count * times;
      if (isPlanks(ing) && !isPlanks(name)) await ensurePlanks(r, job, need);
      else await ensureItem(r, job, ing, need, depth + 1);
    }
    const ready = bot.recipesFor(item.id, null, 1, where);
    if (!ready.length) throw new Error(`have the ingredients but no matching recipe for ${name}`);
    job.progress = `crafting ${name}`;
    if (job.t) job.t.doing = `crafting ${name}`;
    // ponytail: blind retry; the result slot sometimes is not filled yet when mineflayer clicks it.
    for (let attempt = 1; ; attempt++) {
      await holding(r, () => bot.craft(ready[0], times, where));
      if (await arrived(() => count(bot, name) > have)) return;
      if (attempt === 3) throw new Error(`crafting ${name} did not take after 3 tries`);
      guard(job);
    }
  }

  // Smelt `n` of `input` into whatever it smelts into, using any fuel carried.
  async function smelt(r, job, input, n) {
    const {bot} = r;
    if (count(bot, input) < n) throw new Error(`need ${n} ${input}, have ${count(bot, input)}`);
    const needOf = (f) => Math.ceil(n / burn(f));
    const fuel = fuelFor(bot, input, n);
    if (!fuel) throw new Error(`not enough fuel to smelt ${n} (coal, charcoal, planks or logs)`);
    if (job.t) job.t.doing = `smelting ${n} ${input}`;
    const block = await station(r, job, 'furnace', 0);
    r.inventoryBusy = (r.inventoryBusy || 0) + 1;
    const furnace = await bot.openFurnace(block).catch((e) => {
      r.inventoryBusy--;
      throw e;
    });
    try {
      await furnace.putFuel(bot.registry.itemsByName[fuel].id, null, needOf(fuel));
      await furnace.putInput(bot.registry.itemsByName[input].id, null, n);
      let got = 0;
      const until = Date.now() + n * 12000 + 20000; // 10 s per item plus slack
      while (got < n) {
        guard(job);
        if (Date.now() > until) throw new Error(`furnace stalled after ${got}/${n} (out of fuel?)`);
        await new Promise((res) => setTimeout(res, 2000));
        if (furnace.outputItem()) got += (await furnace.takeOutput())?.count || 0;
        job.progress = `${got}/${n}`;
      }
    } finally {
      furnace.close();
      r.inventoryBusy--;
    }
  }

  return {ensureItem, ensurePlanks, smelt, count};
}

// mineflayer's craft fakes the result slot locally and takes it right after
// the last ingredient click; Paper 26.x fills the result a tick later, so the
// take often grabbed nothing and the craft silently failed. putAway(0) is only
// used for that take: give the server a moment first.
function fixCraftTiming(bot) {
  bot.once('login', () => { // the inventory plugin has injected putAway by then
    const putAway = bot.putAway.bind(bot);
    bot.putAway = async (slot) => {
      if (slot === 0) await new Promise((res) => setTimeout(res, 250));
      return putAway(slot);
    };
  });
}

module.exports = {makeCrafting, placeNear, holding, fixCraftTiming, FUELS, count, fuelFor, nearBlock};

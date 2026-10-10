'use strict';
// Alerts for the lead agent: things it cannot notice from job results (2026-10-10: a creeper blew up
// the supply chest and the agent kept sending shifts to it). Fed every few seconds with what a local
// bot sees; each alert is an event of kind "alert" that the agent turns into a prompt.
const NIGHT = [13000, 23000]; // timeOfDay range in which hostile mobs spawn outside
const MOB_EVERY_MS = 120000; // at most one "mobs near the base" alert per 2 minutes

const FULL_BELOW = 4; // free slots in the supply chest
const FOOD = /^(bread|apple|golden_apple|golden_carrot|carrot|baked_potato|cooked_\w+|melon_slice|sweet_berries|pumpkin_pie|cookie|beetroot_soup|mushroom_stew|rabbit_stew|dried_kelp)$/;

// What the supply chest lacks (items: {name: count} as last counted, free: free slots or null when unknown).
function chestWarnings(items, free) {
  const has = (re) => Object.keys(items).some((n) => re.test(n));
  const w = [];
  if (free != null && free < FULL_BELOW) w.push(`full (${free} free slots)`);
  if (!has(FOOD)) w.push('no food');
  if (!has(/^(torch|coal|charcoal)$/)) w.push('no torches or coal');
  if (!has(/_pickaxe$/)) w.push('no pickaxes');
  if (!has(/_sapling$/)) w.push('no saplings');
  return w;
}

class Alerts {
  constructor({events, now = Date.now}) {
    Object.assign(this, {events, now, chestGone: false, chestFull: false, night: null, mobAt: -Infinity});
  }

  // stock: world.stock ({items, free}) or null. One alert when the chest turns full, none until it was emptied.
  checkChest(stock) {
    if (!stock || stock.free == null) return;
    const full = stock.free < FULL_BELOW;
    if (full && !this.chestFull) this.events.add('base', 'alert', `the supply chest is full (${stock.free} free slots): empty it or build another chest`);
    this.chestFull = full;
  }

  // view: {chestBlock: block name at the supply chest or null when unknown, timeOfDay, hostiles: [{type}] as world.js stores mobs}
  check(view, chest) {
    const add = (text) => this.events.add('base', 'alert', text);
    if (chest && view.chestBlock) {
      const gone = !/chest|barrel/.test(view.chestBlock);
      if (gone && !this.chestGone) add(`the supply chest at ${chest.x} ${chest.y} ${chest.z} is gone (${view.chestBlock} there now)`);
      if (!gone && this.chestGone) add(`the supply chest at ${chest.x} ${chest.y} ${chest.z} is back`);
      this.chestGone = gone;
    }
    if (Number.isFinite(view.timeOfDay)) {
      const night = view.timeOfDay >= NIGHT[0] && view.timeOfDay < NIGHT[1];
      if (this.night !== null && night !== this.night) add(night ? 'night falls: hostile mobs spawn outside' : 'morning: the night mobs burn or leave');
      this.night = night;
    }
    const mobs = view.hostiles || [];
    if (mobs.length && this.now() - this.mobAt >= MOB_EVERY_MS) {
      const count = {};
      for (const m of mobs) count[m.type] = (count[m.type] || 0) + 1;
      add(`hostile mobs near the base: ${Object.entries(count).map(([n, c]) => `${n} x${c}`).join(', ')}`);
      this.mobAt = this.now();
    }
  }
}

module.exports = {Alerts, chestWarnings, NIGHT, MOB_EVERY_MS};

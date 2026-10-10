'use strict';
// Alerts for the lead agent: things it cannot notice from job results (2026-10-10: a creeper blew up
// the supply chest and the agent kept sending shifts to it). Fed every few seconds with what a local
// bot sees; each alert is an event of kind "alert" that the agent turns into a prompt.
const NIGHT = [13000, 23000]; // timeOfDay range in which hostile mobs spawn outside
const MOB_EVERY_MS = 120000; // at most one "mobs near the base" alert per 2 minutes

class Alerts {
  constructor({events, now = Date.now}) {
    Object.assign(this, {events, now, chestGone: false, night: null, mobAt: -Infinity});
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

module.exports = {Alerts, NIGHT, MOB_EVERY_MS};

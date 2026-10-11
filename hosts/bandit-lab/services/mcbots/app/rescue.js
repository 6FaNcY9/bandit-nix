'use strict';
// Stranded bots in the sandbox (lab 2026-10-11: bot4 at the bottom of an unfinished shaft with neither pickaxe
// nor blocks, bot17 walled in by its own seal): after STRANDED walks in a row that found no path, the hub
// teleports the bot to the base over the SANDBOX console. Never the real server; every rescue is an event, so the
// causes stay visible (and the fix memory sees the failures).
const {NAME_RE} = require('./admin');

const STRANDED = 3;
const GAP_MS = 10 * 60000; // one rescue per bot per 10 min
const NO_PATH = /No path to the goal|Took to long to decide path/;

class Rescue {
  // call(commands[]) -> replies (sandbox RCON); target() -> {x, y, z} where a rescued bot lands.
  constructor({call, events, target, now = Date.now}) {
    Object.assign(this, {call, events, target, now, fails: new Map(), last: new Map()});
  }

  event(e) {
    if (e.kind === 'done' || (e.kind === 'fail' && !NO_PATH.test(e.text))) return this.fails.delete(e.bot);
    if (e.kind !== 'fail') return;
    const n = (this.fails.get(e.bot) || 0) + 1;
    this.fails.set(e.bot, n);
    if (n >= STRANDED && !(this.now() - this.last.get(e.bot) < GAP_MS)) this.rescue(e.bot, n).catch(() => {}); // never rescued: NaN, not < GAP
  }

  async rescue(bot, n) {
    const t = this.target();
    if (!NAME_RE.test(bot) || !t) return;
    this.last.set(bot, this.now());
    this.fails.delete(bot);
    await this.call([`minecraft:tp ${bot} ${t.x} ${t.y} ${t.z}`]);
    this.events.add(bot, 'info', `rescued: no path ${n} times in a row, teleported to the base (sandbox)`);
  }
}

module.exports = {Rescue, STRANDED};

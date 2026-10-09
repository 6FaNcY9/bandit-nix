'use strict';
// Per-bot settings, changed from the dashboard. Kept in STATE_DIR/settings.json
// when STATE_DIR is set (the lab mounts /var/lib/mcbots there), else in memory.
const fs = require('node:fs');
const path = require('node:path');

const DEFAULTS = Object.freeze({
  defend: true, // attack hostile mobs (retreat and creeper back-off stay on)
  fightRange: 8, // blocks: walk up to a hostile this close and fight it (4 = only when it is next to the bot)
  retreatHealth: 8, // retreat below this health, come back 4 higher
  eatBelow: 15, // eat when food is below this
});
const LIMITS = {fightRange: [2, 16], retreatHealth: [0, 18], eatBelow: [1, 19]};

// Unknown keys are dropped; wrong types or ranges throw.
function clean(input) {
  const out = {};
  for (const [k, v] of Object.entries(input || {})) {
    if (!(k in DEFAULTS)) continue;
    if (k === 'defend') {
      if (typeof v !== 'boolean') throw new Error('defend must be true or false');
      out.defend = v;
    } else {
      const [lo, hi] = LIMITS[k];
      if (!Number.isInteger(v) || v < lo || v > hi) throw new Error(`${k} must be a whole number from ${lo} to ${hi}`);
      out[k] = v;
    }
  }
  return out;
}

class Settings {
  constructor(dir) {
    this.file = dir ? path.join(dir, 'settings.json') : null;
    this.all = {};
    if (this.file) {
      try {
        const raw = JSON.parse(fs.readFileSync(this.file, 'utf8'));
        for (const [name, s] of Object.entries(raw)) {
          try {
            this.all[name] = clean(s);
          } catch {} // a bad entry falls back to the defaults
        }
      } catch {} // missing or unreadable: defaults
    }
  }

  get(name) {
    return {...DEFAULTS, ...this.all[name]};
  }

  set(name, input) {
    this.all[name] = {...this.all[name], ...clean(input)};
    if (this.file) {
      const tmp = `${this.file}.tmp`;
      fs.writeFileSync(tmp, JSON.stringify(this.all, null, 2));
      fs.renameSync(tmp, this.file);
    }
    return this.get(name);
  }
}

module.exports = {Settings, DEFAULTS, LIMITS, clean};

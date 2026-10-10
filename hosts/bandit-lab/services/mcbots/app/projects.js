'use strict';
// The last project (shaft, build, ...) each bot was given, kept in STATE_DIR/projects.json so the
// dashboard can pause, resume and stop it. `paused`: the owner (or a stop) ended it on purpose.
const fs = require('node:fs');
const path = require('node:path');

const PROJECTS = new Set(['shaft', 'excavate', 'level', 'rim', 'treefarm', 'homebed', 'build', 'grave']);
const obj = (v) => (v && typeof v === 'object' && !Array.isArray(v) ? v : null);

// One line for the board: scalars as they are, lists as a count, {x,y,z} as coordinates.
const summary = (args) => Object.entries(args).map(([k, v]) => (Array.isArray(v) ? `${v.length} ${k}` : obj(v) ? `${k} ${v.x} ${v.y} ${v.z}` : v)).join(' ').slice(0, 100);

class Projects {
  constructor(dir) {
    this.file = dir ? path.join(dir, 'projects.json') : null;
    this.all = {};
    if (this.file) {
      try {
        for (const [bot, p] of Object.entries(JSON.parse(fs.readFileSync(this.file, 'utf8')))) {
          if (PROJECTS.has(p?.type) && obj(p.args)) this.all[bot] = {type: p.type, args: p.args, t: Number(p.t) || 0, paused: p.paused === true};
        }
      } catch {} // missing or unreadable: none
    }
  }

  get(bot) {
    return this.all[bot] || null;
  }

  note(bot, type, args) {
    this.all[bot] = {type, args, t: Date.now(), paused: false};
    this.save();
  }

  pause(bot) {
    if (this.all[bot]?.paused === false) {
      this.all[bot].paused = true;
      this.save();
    }
  }

  forget(bot) {
    if (delete this.all[bot]) this.save();
  }

  // What the dashboard needs (not the arguments: a blueprint is several KB).
  view() {
    return Object.fromEntries(Object.entries(this.all).map(([bot, p]) => [bot, {type: p.type, summary: summary(p.args), paused: p.paused, t: p.t}]));
  }

  save() {
    if (!this.file) return;
    const tmp = `${this.file}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(this.all));
    fs.renameSync(tmp, this.file);
  }
}

module.exports = {Projects, PROJECTS};

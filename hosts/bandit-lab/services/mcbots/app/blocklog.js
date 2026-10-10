'use strict';
// "What was built or destroyed where": every block change a bot's loaded chunks show inside the watched area,
// kept in a ring (persisted to STATE_DIR/blocklog.jsonl) and exported every 15 s as JSON for the BlueMap overlay
// (../../minecraft/overlay.js). Bots of this process report directly, worker bots through the hub's observe frame.
const fs = require('node:fs');
const path = require('node:path');

const AIRS = new Set(['air', 'cave_air', 'void_air']);
const FLUIDS = new Set(['water', 'lava', 'bubble_column', 'flowing_water', 'flowing_lava']);
const quiet = (n) => AIRS.has(n) || FLUIDS.has(n);
const DEFAULT_AREA = {x1: -330, z1: -280, x2: -210, z2: -170};
const PAD = 16;
const DEDUPE_MS = 2000;
const OWN_MS = 15000; // a dig or place this recent explains the change it causes
const EXPORT_WINDOW_MS = 7 * 24 * 3600 * 1000; // the overlay offers 1 h / 24 h / all
const EXPORT_CAP = 20000;

// 'built', 'removed' or null. Same block (crop age, furnace lit, ... only differ in state: names are equal) and
// air/fluid exchanges (water and lava flowing) are noise.
function classify(from, to) {
  if (!from || !to || from === to) return null;
  if (quiet(from) && quiet(to)) return null;
  return quiet(to) ? 'removed' : 'built';
}

const inBox = (b, x, z) => x >= b.x1 && x <= b.x2 && z >= b.z1 && z <= b.z2;

// Boxes to watch: BLOCKLOG_AREA "x1,z1,x2,z2" if valid, else every overworld zone box padded by 16, else the fixed default.
function areaBoxes(places, override = '') {
  const o = String(override || '').split(',').map(Number);
  if (o.length === 4 && o.every(Number.isFinite)) return [{x1: Math.min(o[0], o[2]), z1: Math.min(o[1], o[3]), x2: Math.max(o[0], o[2]), z2: Math.max(o[1], o[3])}];
  const boxes = places.filter((p) => p.box && p.dim === 'overworld').map(({box: b}) => ({x1: b.x1 - PAD, z1: b.z1 - PAD, x2: b.x2 + PAD, z2: b.z2 + PAD}));
  return boxes.length ? boxes : [DEFAULT_AREA];
}

class BlockLog {
  constructor({file = null, max = 50000, now = Date.now, areas = () => [DEFAULT_AREA], rotateBytes = 20e6} = {}) {
    Object.assign(this, {file, max, now, areas, rotateBytes});
    this.list = []; // {t, x, y, z, from, to, by}, oldest first
    this.recent = new Map(); // `${x},${y},${z},${to}` -> entry, for dedupe
    this.pending = []; // lines not yet appended to the file
    this.version = 0;
    if (file) {
      try {
        for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
          try {
            const c = JSON.parse(line);
            if (Number.isFinite(c.t) && [c.x, c.y, c.z].every(Number.isInteger) && typeof c.from === 'string' && typeof c.to === 'string') this.list.push(c);
          } catch {} // a torn last line
        }
        if (this.list.length > max) this.list.splice(0, this.list.length - max);
      } catch {} // no file yet
    }
  }

  // Returns true when stored. `by` is the bot whose own dig/place caused it, else "world".
  record({x, y, z, from, to, by = 'world'}) {
    if (!classify(from, to) || !this.areas().some((b) => inBox(b, x, z))) return false;
    const t = this.now(), key = `${x},${y},${z},${to}`, seen = this.recent.get(key);
    if (seen && t - seen.t <= DEDUPE_MS) {
      if (seen.by === 'world' && by !== 'world') seen.by = by; // ponytail: the file keeps the first record's `by`
      return false;
    }
    if (this.recent.size > 5000) for (const [k, e] of this.recent) if (t - e.t > DEDUPE_MS) this.recent.delete(k);
    const e = {t, x, y, z, from, to, by};
    this.recent.set(key, e);
    this.list.push(e);
    if (this.list.length > this.max * 1.1) this.list.splice(0, this.list.length - this.max);
    this.pending.push(JSON.stringify(e));
    this.version++;
    return true;
  }

  // Append what is pending (called from the export tick and at shutdown); rotate at rotateBytes.
  flush() {
    if (!this.file || !this.pending.length) return;
    const lines = this.pending.splice(0);
    try {
      fs.appendFileSync(this.file, `${lines.join('\n')}\n`);
      if (fs.statSync(this.file).size > this.rotateBytes) fs.renameSync(this.file, `${this.file}.1`);
    } catch {} // a full or read-only disk must not stop the bots
  }
}

// Last change per block inside the window, newest first, at most `cap`.
function aggregate(list, {now, windowMs = EXPORT_WINDOW_MS, cap = EXPORT_CAP}) {
  const last = new Map();
  for (const c of list) if (now - c.t <= windowMs) last.set(`${c.x},${c.y},${c.z}`, c);
  return [...last.values()].sort((a, b) => b.t - a.t).slice(0, cap).map((c) => ({x: c.x, y: c.y, z: c.z, k: classify(c.from, c.to), from: c.from, to: c.to, t: c.t, by: c.by}));
}

// Zones for the overlay: overworld boxes only.
const zonesOf = (places) => places.filter((p) => p.box && p.dim === 'overworld').map((p) => ({name: p.name, kind: p.kind, box: p.box}));

// Writes changes.json and zones.json into `dir` when their content changed.
class Exporter {
  constructor({log, places, dir, now = Date.now, windowMs = EXPORT_WINDOW_MS, say = () => {}}) {
    Object.assign(this, {log, places, dir, now, windowMs, say});
    this.last = {};
  }

  write(name, body) {
    const text = JSON.stringify(body);
    if (this.last[name] === text) return;
    const file = path.join(this.dir, name), tmp = `${file}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify({generated: this.now(), ...body}), {mode: 0o644});
    fs.renameSync(tmp, file);
    this.last[name] = text;
  }

  tick() {
    this.log.flush();
    try {
      const t = this.now();
      this.write('changes.json', {windowMs: this.windowMs, changes: aggregate(this.log.list, {now: t, windowMs: this.windowMs})});
      this.write('zones.json', {zones: zonesOf(this.places())});
    } catch (e) {
      this.say(`overlay export failed: ${e.message}`);
    }
  }
}

// Reports block changes of one bot to `sink({x,y,z,from,to,by})`. Wraps bot.dig and bot.placeBlock (the pathfinder
// and every job go through them) to remember which blocks this bot is working on.
function watchBlocks(bot, name, sink, now = Date.now) {
  const own = new Map();
  const mark = (x, y, z) => {
    if (own.size > 200) for (const [k, t] of own) if (t < now()) own.delete(k);
    own.set(`${x},${y},${z}`, now() + OWN_MS);
  };
  const dig = bot.dig;
  bot.dig = function (block, ...a) {
    if (block?.position) mark(block.position.x, block.position.y, block.position.z);
    return dig.call(this, block, ...a);
  };
  const place = bot.placeBlock;
  bot.placeBlock = function (ref, face, ...a) {
    if (ref?.position && face) mark(ref.position.x + face.x, ref.position.y + face.y, ref.position.z + face.z);
    return place.call(this, ref, face, ...a);
  };
  bot.on('blockUpdate', (o, n) => {
    if (!o || !n?.position || !classify(o.name, n.name) || !/overworld/.test(bot.game?.dimension || '')) return;
    const {x, y, z} = n.position;
    sink({x, y, z, from: o.name, to: n.name, by: (own.get(`${x},${y},${z}`) ?? 0) > now() ? name : 'world'});
  });
}

module.exports = {classify, areaBoxes, BlockLog, aggregate, zonesOf, Exporter, watchBlocks, DEFAULT_AREA};

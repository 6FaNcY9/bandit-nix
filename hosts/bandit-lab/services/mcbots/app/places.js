'use strict';
// Named places the owner puts on the map: the supply chest, work sites, home,
// AFK spots, other chests. Kept in STATE_DIR/places.json like settings.json.
// The first 'supply' place replaces SUPPLY_CHEST, the first 'site' KEEPER_SITE.
const fs = require('node:fs');
const path = require('node:path');

// Zone kinds carry a box (the owner's "markers where you can make zones"); the others are points.
const ZONE_KINDS = ['storage', 'shaft', 'treefarm', 'wheat', 'base', 'protected'];
const KINDS = ['supply', 'site', 'home', 'afk', 'chest', ...ZONE_KINDS];
const MAX_SIDE = 64; // a zone is at most 64 blocks wide
const DIMS = ['overworld', 'the_nether', 'the_end'];
const MAX = 64;

function clean(p) {
  const name = String(p?.name ?? '').trim();
  if (!/^[\w .'-]{1,32}$/.test(name)) throw new Error('name: 1-32 letters, digits, space . \' - _');
  if (!KINDS.includes(p.kind)) throw new Error(`kind must be one of ${KINDS.join(', ')}`);
  const dim = p.dim ?? 'overworld';
  if (!DIMS.includes(dim)) throw new Error(`dim must be one of ${DIMS.join(', ')}`);
  const n = (v, lo, hi, k) => {
    const x = Number(v);
    if (!Number.isInteger(x) || x < lo || x > hi) throw new Error(`${k} must be a whole number from ${lo} to ${hi}`);
    return x;
  };
  let box;
  if (p.box != null) {
    const b = p.box, c = (k, lo, hi) => n(b[k], lo, hi, `box.${k}`);
    const [x1, x2, z1, z2, y1, y2] = [c('x1', -3e7, 3e7), c('x2', -3e7, 3e7), c('z1', -3e7, 3e7), c('z2', -3e7, 3e7), c('y1', -64, 320), c('y2', -64, 320)];
    box = {x1: Math.min(x1, x2), y1: Math.min(y1, y2), z1: Math.min(z1, z2), x2: Math.max(x1, x2), y2: Math.max(y1, y2), z2: Math.max(z1, z2)};
    if (box.x2 - box.x1 >= MAX_SIDE || box.z2 - box.z1 >= MAX_SIDE) throw new Error(`a zone is at most ${MAX_SIDE} x ${MAX_SIDE} blocks wide`);
  } else if (ZONE_KINDS.includes(p.kind)) throw new Error(`a ${p.kind} zone needs a box`);
  // A zone's point is its centre unless given.
  const mid = (a, b) => (box ? Math.floor((box[a] + box[b]) / 2) : undefined);
  return {name, kind: p.kind, dim, x: n(p.x ?? mid('x1', 'x2'), -3e7, 3e7, 'x'), y: n(p.y ?? mid('y1', 'y2'), -64, 320, 'y'), z: n(p.z ?? mid('z1', 'z2'), -3e7, 3e7, 'z'), ...(box ? {box} : {})};
}

// The running Places (set once by server.js), so plan-config and VALIDATE read zones without being handed it.
let active = null;
const use = (places) => { active = places; };
// First overworld zone of a kind as {x1,z1,x2,z2,y1,y2}, else `fallback`: moving a zone moves the work.
const zoneBox = (kind, fallback = null) => active?.zone(kind)?.box || fallback;
// Is the block inside any overworld zone of this kind?
const inZone = (kind, x, y, z) => !!active?.list.some((p) => p.kind === kind && p.box && p.dim === 'overworld' && x >= p.box.x1 && x <= p.box.x2 && y >= p.box.y1 && y <= p.box.y2 && z >= p.box.z1 && z <= p.box.z2);
const zoneNamed = (name) => active?.list.find((p) => p.box && p.name === name)?.box || null;
// Zone boxes the build/dig jobs must keep out of, as protectedAreas entries [x1, z1, x2, z2].
const protectedBoxes = (list) => list.filter((p) => p.kind === 'protected' && p.box && p.dim === 'overworld').map(({box: b}) => [b.x1, b.z1, b.x2, b.z2]);

class Places {
  constructor(dir) {
    this.file = dir ? path.join(dir, 'places.json') : null;
    this.list = [];
    if (this.file) {
      try {
        for (const p of JSON.parse(fs.readFileSync(this.file, 'utf8'))) {
          try {
            this.list.push(clean(p));
          } catch {} // a bad entry is dropped
        }
      } catch {} // missing or unreadable: none
    }
  }

  first(kind) {
    return this.list.find((p) => p.kind === kind && p.dim === 'overworld') || null;
  }

  zone(kind) {
    return this.list.find((p) => p.kind === kind && p.box && p.dim === 'overworld') || null;
  }

  // First start only: no zone yet -> add these (clean() validates; a bad one is skipped).
  seed(zones) {
    if (this.list.some((p) => p.box)) return;
    for (const z of zones) {
      try { this.list.push(clean(z)); } catch {}
    }
    this.save();
  }

  // Add, or replace the place with the same name.
  set(input) {
    const p = clean(input);
    const i = this.list.findIndex((q) => q.name === p.name);
    if (i >= 0) this.list[i] = p;
    else if (this.list.length >= MAX) throw new Error(`at most ${MAX} places`);
    else this.list.push(p);
    this.save();
    return p;
  }

  remove(name) {
    const before = this.list.length;
    this.list = this.list.filter((p) => p.name !== name);
    if (this.list.length === before) throw new Error(`no place called ${name}`);
    this.save();
  }

  save() {
    if (!this.file) return;
    const tmp = `${this.file}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(this.list, null, 2));
    fs.renameSync(tmp, this.file);
  }
}

module.exports = {Places, KINDS, ZONE_KINDS, clean, use, inZone, zoneBox, zoneNamed, protectedBoxes};

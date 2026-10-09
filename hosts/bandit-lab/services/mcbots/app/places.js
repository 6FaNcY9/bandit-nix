'use strict';
// Named places the owner puts on the map: the supply chest, work sites, home,
// AFK spots, other chests. Kept in STATE_DIR/places.json like settings.json.
// The first 'supply' place replaces SUPPLY_CHEST, the first 'site' KEEPER_SITE.
const fs = require('node:fs');
const path = require('node:path');

const KINDS = ['supply', 'site', 'home', 'afk', 'chest'];
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
  return {name, kind: p.kind, dim, x: n(p.x, -3e7, 3e7, 'x'), y: n(p.y, -64, 320, 'y'), z: n(p.z, -3e7, 3e7, 'z')};
}

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

module.exports = {Places, KINDS, clean};

'use strict';
// The dashboard's 3D map: which blocks of a box are worth sending. A full 80 x 80 x 200 box is mostly
// buried rock the eye never sees, so a block is kept only where it touches something see-through (the
// pure part, tested in test.js); server.js feeds it bot.blockAt for a bot whose chunks cover the box.
const MAX_SIDE = 80, MAX_HIGH = 200, MAX_CELLS = 600000;
// Passable or tiny things that are never drawn: air and plants/torches/rails/signs (a model of them would add noise, not information).
const NOT_DRAWN = /^(air|cave_air|void_air|short_grass|tall_grass|grass|fern|large_fern|seagrass|tall_seagrass|kelp|kelp_plant|vine|cave_vines|cave_vines_plant|glow_lichen|dead_bush|sugar_cane|snow|cobweb|fire|torch|wall_torch|soul_torch|soul_wall_torch|redstone_torch|redstone_wall_torch|redstone_wire|ladder|rail|powered_rail|detector_rail|activator_rail|lever|[a-z_]*(_flower|_sapling|_carpet|_sign|_wall_sign|_button|_pressure_plate|_tulip|_orchid|_bluet|_mushroom)|dandelion|poppy|azure_bluet|cornflower|lily_of_the_valley|sweet_berry_bush|wheat|carrots|potatoes|beetroots)$/;
const FLUID = /^(water|lava|bubble_column)$/;
const SEE = (n) => NOT_DRAWN.test(n) || FLUID.test(n) || /(^|_)glass(_pane)?$|_leaves$|^(ice|barrier|light)$/.test(n);
const YIELD_EVERY = 20000; // reads between turns of the event loop (the hub also runs bot physics)
const DIRS = [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]];

// Validate a box from query strings: whole numbers, ordered corners, bounded size. Returns the box or throws.
function parseBox(q) {
  const v = {};
  for (const k of ['x1', 'y1', 'z1', 'x2', 'y2', 'z2']) {
    const n = Number(q[k]);
    if (q[k] === undefined || q[k] === null || q[k] === '' || !Number.isInteger(n) || Math.abs(n) > 3e7) throw new Error(`${k} must be a whole number`);
    v[k] = n;
  }
  const box = {x1: Math.min(v.x1, v.x2), y1: Math.min(v.y1, v.y2), z1: Math.min(v.z1, v.z2), x2: Math.max(v.x1, v.x2), y2: Math.max(v.y1, v.y2), z2: Math.max(v.z1, v.z2)};
  if (box.y1 < -64 || box.y2 > 319) throw new Error('y must be within -64..319');
  const [w, h, l] = [box.x2 - box.x1 + 1, box.y2 - box.y1 + 1, box.z2 - box.z1 + 1];
  if (w > MAX_SIDE || l > MAX_SIDE || h > MAX_HIGH || w * h * l > MAX_CELLS) throw new Error(`box too big: at most ${MAX_SIDE} x ${MAX_SIDE} columns, ${MAX_HIGH} high and ${MAX_CELLS} cells (this one is ${w} x ${l} x ${h})`);
  return box;
}

// nameAt(x,y,z) -> block name, or null where the chunk is not loaded. Returns {names, blocks: [[x,y,z,nameIndex]], unloaded}
// (`unloaded` counts cells). The box is read once with a one-block margin so edge blocks can see outwards.
function* collectGen(box, nameAt) {
  const names = [], index = new Map(), idx = (n) => { let i = index.get(n); if (i === undefined) { i = names.length; names.push(n); index.set(n, i); } return i; };
  const [W, H, L] = [box.x2 - box.x1 + 3, box.y2 - box.y1 + 3, box.z2 - box.z1 + 3]; // margin of 1 on each side
  const cell = new Int32Array(W * H * L).fill(-1); // -1: unloaded
  const at = (x, y, z) => (x * H + y) * L + z;
  let unloaded = 0, reads = 0;
  for (let x = 0; x < W; x++) for (let y = 0; y < H; y++) for (let z = 0; z < L; z++) {
    if (++reads % YIELD_EVERY === 0) yield;
    const n = nameAt(box.x1 - 1 + x, box.y1 - 1 + y, box.z1 - 1 + z);
    if (n === null || n === undefined) { if (x && y && z && x < W - 1 && y < H - 1 && z < L - 1) unloaded++; continue; }
    cell[at(x, y, z)] = idx(n);
  }
  const see = names.map(SEE), air = names.map((n) => NOT_DRAWN.test(n)), fluid = names.map((n) => FLUID.test(n));
  const blocks = [];
  for (let x = 1; x < W - 1; x++) for (let y = 1; y < H - 1; y++) for (let z = 1; z < L - 1; z++) {
    const i = cell[at(x, y, z)];
    if (i < 0 || air[i]) continue;
    const want = fluid[i] ? air : see; // a fluid shows only where it meets air; a solid wherever it meets anything see-through
    for (const [dx, dy, dz] of DIRS) {
      const j = cell[at(x + dx, y + dy, z + dz)];
      if (j >= 0 && want[j]) { blocks.push([box.x1 - 1 + x, box.y1 - 1 + y, box.z1 - 1 + z, i]); break; }
    }
  }
  return {names, blocks, unloaded};
}

// Surroundings: one block per column (the first non-air, non-plant block from the top down; water counts, so a lake shows its
// surface). Same query convention as parseBox, but x/z only and wider, since a column costs a few reads, not 200.
const MAX_SURF = 160, SURF_TOP = 120, SURF_BOTTOM = -64;
function parseSurface(q) {
  const v = {};
  for (const k of ['x1', 'z1', 'x2', 'z2']) {
    const n = Number(q[k]);
    if (q[k] === undefined || q[k] === null || q[k] === '' || !Number.isInteger(n) || Math.abs(n) > 3e7) throw new Error(`${k} must be a whole number`);
    v[k] = n;
  }
  const box = {x1: Math.min(v.x1, v.x2), z1: Math.min(v.z1, v.z2), x2: Math.max(v.x1, v.x2), z2: Math.max(v.z1, v.z2)};
  if (box.x2 - box.x1 + 1 > MAX_SURF || box.z2 - box.z1 + 1 > MAX_SURF) throw new Error(`surface too big: at most ${MAX_SURF} x ${MAX_SURF} columns`);
  return box;
}
// Returns {names, cols: [[x,y,z,nameIndex]], unloaded} (`unloaded` counts columns whose chunk is missing; they are skipped).
function* surfaceGen(box, nameAt, top = SURF_TOP, bottom = SURF_BOTTOM) {
  const names = [], index = new Map(), cols = [];
  let unloaded = 0, reads = 0;
  for (let x = box.x1; x <= box.x2; x++) for (let z = box.z1; z <= box.z2; z++) {
    for (let y = top; y >= bottom; y--) {
      if (++reads % YIELD_EVERY === 0) yield;
      const n = nameAt(x, y, z);
      if (n === null || n === undefined) { unloaded++; break; }
      if (NOT_DRAWN.test(n)) continue;
      let i = index.get(n); if (i === undefined) { i = names.length; names.push(n); index.set(n, i); }
      cols.push([x, y, z, i]); break;
    }
  }
  return {names, cols, unloaded};
}

// Sync (tests, small jobs) and async (the server: yields to the event loop every YIELD_EVERY reads) drivers of the generators.
const sync = (gen) => (...a) => { const g = gen(...a); for (;;) { const r = g.next(); if (r.done) return r.value; } };
const async_ = (gen) => async (...a) => { const g = gen(...a); for (;;) { const r = g.next(); if (r.done) return r.value; await new Promise(setImmediate); } };
const collect = sync(collectGen), surface = sync(surfaceGen), collectAsync = async_(collectGen), surfaceAsync = async_(surfaceGen);

module.exports = {collectAsync, surfaceAsync, MAX_SIDE, MAX_HIGH, MAX_CELLS, MAX_SURF, SEE, parseBox, collect, parseSurface, surface};

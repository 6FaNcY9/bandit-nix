'use strict';
// Seal job: wall off the cave openings around a box (the shaft and base plus a margin) so hostiles
// stop walking in from the sides. A cell on the box's four side faces that is air and has a non-solid
// block just outside the box gets a cobblestone (else cobbled deepslate, else dirt) placed into it from
// inside the box. Place only: nothing is dug, fluids are never touched, and protected areas, the supply
// chest, beds and stair steps (solid blocks, not air) are left alone. The world is the state, so a
// restarted job just scans again. The pure parts (scan, standSpot, refFace) are tested in test.js with
// a fake world; makeSeal() wires them to a bot like level.js does.
const {Vec3} = require('vec3');
const {insideAreas, normDim} = require('./world');

const MAX_SIDE = 24; // a 16 x 16 shaft plus a margin of 4
const MAX_HEIGHT = 160; // the shaft is 140 deep
const MAX_WALLS = 300; // placements per run; the rest is reported and a second run does it
const MAX_MS = 30 * 60 * 1000;
const TRIES = 2; // a cell is given up after this many failed attempts
const SKIP_MS = 20000;
const ROOF = 40; // rock this far above makes an opening a cave opening
const REACH = 4.2; // eye to the face placed against
const MATERIALS = ['cobblestone', 'cobbled_deepslate', 'dirt'];
const FLUID = /^(water|lava|bubble_column)$/;
const AIR = /^(air|cave_air|void_air)$/;
const NEIGHBOURS = [[0, -1, 0], [1, 0, 0], [-1, 0, 0], [0, 0, 1], [0, 0, -1], [0, 1, 0]]; // below first: the steadiest hold

// 'air' | 'fluid' | 'solid' | 'soft' (grass, torches ...: passable, not wallable) | null (not loaded).
const kindOf = (block) => (!block ? null : AIR.test(block.name) ? 'air' : FLUID.test(block.name) ? 'fluid' : block.boundingBox === 'block' ? 'solid' : 'soft');

const key = (c) => `${c.x},${c.y},${c.z}`;

// The outward neighbours of a cell on the side faces of the box ([] inside or on the top/bottom only).
const outward = (b, x, z) => [x === b.x1 && [x - 1, z], x === b.x2 && [x + 1, z], z === b.z1 && [x, z - 1], z === b.z2 && [x, z + 1]].filter(Boolean);

// The cells to wall, given kindAt(x,y,z) and skip(x,y,z) (protected area, chest, bed ...):
// {walls: [{x,y,z}], fluid, unloaded, skipped, sky}. fluid: boundary cells of water/lava (left as they are);
// sky: openings with no roof above them (the surface is the rim wall's business, not a cave opening).
function scan(box, kindAt, skip = () => false, roofed = () => true) {
  const out = {walls: [], fluid: 0, unloaded: 0, skipped: 0, sky: 0};
  for (let x = box.x1; x <= box.x2; x++) {
    for (let z = box.z1; z <= box.z2; z++) {
      if (x !== box.x1 && x !== box.x2 && z !== box.z1 && z !== box.z2) continue;
      for (let y = box.y1; y <= box.y2; y++) {
        const k = kindAt(x, y, z);
        if (k === null) out.unloaded++;
        else if (k === 'fluid') out.fluid++;
        else if (k === 'air') {
          const kinds = outward(box, x, z).map(([ox, oz]) => kindAt(ox, y, oz));
          if (kinds.some((o) => o === 'air' || o === 'fluid' || o === 'soft')) {
            if (!roofed(x, y, z)) out.sky++;
            else if (skip(x, y, z)) out.skipped++;
            else out.walls.push({x, y, z});
          } else if (kinds.includes(null)) out.unloaded++;
        }
      }
    }
  }
  return out;
}

// A solid neighbour of the cell to place against, nearest to `eye` and within reach: {pos, face} (face: from
// the reference block towards the cell) or null.
function refFace(cell, kindAt, eye) {
  let best = null;
  for (const [dx, dy, dz] of NEIGHBOURS) {
    const p = {x: cell.x + dx, y: cell.y + dy, z: cell.z + dz};
    if (kindAt(p.x, p.y, p.z) !== 'solid') continue;
    const d = Math.hypot(p.x + 0.5 - eye.x, p.y + 0.5 - eye.y, p.z + 0.5 - eye.z);
    if (d <= REACH + 0.9 && (!best || d < best.d)) best = {pos: p, face: {x: -dx, y: -dy, z: -dz}, d};
  }
  return best;
}

// Where to stand inside the box to reach a cell: a free cell with a floor and two blocks of headroom,
// within 3 blocks, nearest to the cell and off the boundary when possible. null: nowhere to stand.
function standSpot(cell, box, kindAt) {
  let best = null;
  for (let dx = -3; dx <= 3; dx++) for (let dz = -3; dz <= 3; dz++) for (let dy = -3; dy <= 2; dy++) {
    const s = {x: cell.x + dx, y: cell.y + dy, z: cell.z + dz};
    if (s.x < box.x1 || s.x > box.x2 || s.z < box.z1 || s.z > box.z2 || s.y < box.y1 || s.y > box.y2) continue;
    if (!dx && !dz && dy <= 0 || kindAt(s.x, s.y, s.z) !== 'air' || kindAt(s.x, s.y + 1, s.z) !== 'air' || kindAt(s.x, s.y - 1, s.z) !== 'solid') continue;
    const d = Math.hypot(dx, dy + 1.6 - 0.5, dz); // eye to the middle of the cell
    if (d > REACH) continue;
    const cost = d + (s.x === box.x1 || s.x === box.x2 || s.z === box.z1 || s.z === box.z2 ? 2 : 0);
    if (!best || cost < best.cost) best = {...s, cost};
  }
  return best;
}

// Box limits (VALIDATE.seal): normalised corners, a bounded volume.
function validateBox(p, q) {
  const box = {x1: Math.min(p.x, q.x), z1: Math.min(p.z, q.z), x2: Math.max(p.x, q.x), z2: Math.max(p.z, q.z), y1: Math.min(p.y, q.y), y2: Math.max(p.y, q.y)};
  if (box.x2 - box.x1 + 1 > MAX_SIDE || box.z2 - box.z1 + 1 > MAX_SIDE) throw new Error(`a seal box is at most ${MAX_SIDE} x ${MAX_SIDE} blocks wide`);
  if (box.y2 - box.y1 + 1 > MAX_HEIGHT) throw new Error(`a seal box is at most ${MAX_HEIGHT} blocks high`);
  if (box.x2 - box.x1 < 2 || box.z2 - box.z1 < 2) throw new Error('a seal box is at least 3 x 3 blocks wide');
  return box;
}

function makeSeal({goNear, guard, sleep, goals, withdraw, skipMs = SKIP_MS}) {
  return async function seal(r, job) {
    const {bot} = r;
    const box = job.args;
    const dim = normDim(bot.game?.dimension);
    const kindAt = (x, y, z) => kindOf(bot.blockAt(new Vec3(x, y, z)));
    const nearBed = (x, y, z) => {
      for (let dx = -1; dx <= 1; dx++) for (let dy = -1; dy <= 1; dy++) for (let dz = -1; dz <= 1; dz++) if (/_bed$/.test(bot.blockAt(new Vec3(x + dx, y + dy, z + dz))?.name || '')) return true;
      return false;
    };
    const chest = r.supplyChest;
    const skip = (x, y, z) => insideAreas(r.protectedAreas, x, z) || r.reserved?.(x, y, z)
      || (chest && Math.abs(x - chest.x) <= 1 && Math.abs(y - chest.y) <= 1 && Math.abs(z - chest.z) <= 1) || nearBed(x, y, z);
    // A cave opening has rock somewhere above it; open sky (the surface around the shaft) is not walled.
    const roofed = (x, y, z) => {
      for (let h = y + 1; h <= y + ROOF; h++) {
        const b = bot.blockAt(new Vec3(x, h, z));
        if (!b) return true; // above the loaded world: assume rock
        if (b.boundingBox === 'block' && !/_leaves$/.test(b.name)) return true; // a tree is no roof
      }
      return false;
    };
    const held = () => bot.inventory.items().filter((i) => MATERIALS.includes(i.name));
    const material = () => MATERIALS.map((n) => held().find((i) => i.name === n)).find(Boolean);

    // The pathfinder neither digs (natural ground stays) nor scaffolds (it would wall in the box itself).
    const mv = bot.pathfinder.movements;
    const scaffold = mv.scafoldingBlocks, digOnly = r.digOnly;
    mv.scafoldingBlocks = [];
    r.digOnly = /(?!)/;
    try {
      // Not loaded yet right after a login: walk to the middle of the box first.
      await goNear(r, job, (box.x1 + box.x2) >> 1, Math.floor(bot.entity.position.y), (box.z1 + box.z2) >> 1, 8, {doing: 'walking to the seal box'}).catch((e) => guard(job)); // too far still: scan what is loaded
      guard(job);
      const started = Date.now();
      const failed = new Map(), wait = new Map(), gaveUp = new Set();
      let placed = 0, total = 0, left = 0, note = '';
      for (let round = 0; round < 2 && !note; round++) {
        const found = scan(box, kindAt, skip, roofed);
        const todo = found.walls.filter((c) => !gaveUp.has(key(c)));
        if (!round) {
          total = found.walls.length;
          const extra = [found.fluid && `${found.fluid} fluid cells left untouched`, found.skipped && `${found.skipped} openings left (protected, chest or bed)`, found.sky && `${found.sky} open to the sky (rim wall, not walled)`, found.unloaded && `${found.unloaded} cells not loaded`].filter(Boolean);
          r.emit('info', `seal ${box.x1} ${box.z1} ${box.x2} ${box.z2} y ${box.y1}..${box.y2}: ${found.walls.length} openings${extra.length ? `, ${extra.join(', ')}` : ''}`);
        }
        if (!todo.length) break;
        job.t.total = total;
        while (!note) {
          guard(job);
          if (Date.now() - started > MAX_MS) note = `time limit (${MAX_MS / 60000} min)`;
          else if (placed >= MAX_WALLS) note = `capped at ${MAX_WALLS} walls this run, run it again for the rest`;
          if (note) break;
          const now = Date.now();
          const eye = bot.entity.position.offset(0, 1.6, 0);
          const open = todo.filter((c) => kindAt(c.x, c.y, c.z) === 'air' && !gaveUp.has(key(c)));
          left = open.length;
          if (!open.length) break;
          const ready = open.filter((c) => (wait.get(key(c)) || 0) <= now);
          // Nearest first; a cell with no solid block beside it has to wait until a neighbour is walled.
          const cand = ready.map((c) => ({c, d: Math.hypot(c.x - eye.x, c.y - eye.y, c.z - eye.z)})).sort((a, b) => a.d - b.d);
          let pick = null;
          for (const {c} of cand) {
            const stand = standSpot(c, box, kindAt);
            const ref = NEIGHBOURS.some(([dx, dy, dz]) => kindAt(c.x + dx, c.y + dy, c.z + dz) === 'solid');
            if (stand && ref) { pick = {c, stand}; break; }
          }
          if (!pick) {
            if (ready.length < open.length) { await sleep(1000); continue; } // some are only waiting out a failed try
            break; // nowhere to stand or nothing to hold on to
          }
          const {c, stand} = pick;
          const k = `${dim}:${key(c)}`;
          if (r.world && !(await r.world.claim(r.name, k))) { wait.set(key(c), now + 5000); continue; }
          try {
            if (!material() && !(await fetchBlocks(r, job, open.length))) throw Object.assign(new Error('out of wall blocks (cobblestone, cobbled_deepslate or dirt) and the supply chest has none'), {fatal: true});
            await goNear(r, job, stand.x, stand.y, stand.z, 0, {goal: new goals.GoalBlock(stand.x, stand.y, stand.z), doing: `walking to wall ${c.x} ${c.y} ${c.z}`});
            guard(job);
            if (kindAt(c.x, c.y, c.z) !== 'air') continue; // changed meanwhile
            const item = material();
            const ref = refFace(c, kindAt, bot.entity.position.offset(0, 1.6, 0));
            if (!ref || !item) throw new Error('nothing to place against');
            job.t.doing = `walling ${c.x} ${c.y} ${c.z} with ${item.name}`;
            await bot.equip(item, 'hand');
            guard(job); // a Stop during the equip must not place anything
            await bot.placeBlock(bot.blockAt(new Vec3(ref.pos.x, ref.pos.y, ref.pos.z)), new Vec3(ref.face.x, ref.face.y, ref.face.z)).catch(() => {}); // 26.x may not echo the update in time
            for (let i = 0; i < 20 && kindAt(c.x, c.y, c.z) !== 'solid'; i++) await sleep(100);
            if (kindAt(c.x, c.y, c.z) !== 'solid') throw new Error(`placing ${item.name} at ${c.x} ${c.y} ${c.z} did not take`);
            placed++;
            job.t.done = placed;
            job.progress = `sealed ${placed}/${total}`;
            await torch(r, job, c, box, kindAt);
          } catch (e) {
            guard(job);
            if (e.fatal) throw new Error(`${e.message} (${placed} walls placed this run, ${left} openings were left)`);
            const n = (failed.get(key(c)) || 0) + 1;
            failed.set(key(c), n);
            wait.set(key(c), Date.now() + skipMs);
            if (n >= TRIES) gaveUp.add(key(c));
            job.t.doing = `skipping ${c.x} ${c.y} ${c.z}: ${e.message.slice(0, 60)}`;
          } finally {
            r.world?.release(r.name, k);
          }
        }
      }
      left = scan(box, kindAt, skip, roofed).walls.length;
      if (note) r.emit('info', `seal: ${note}`);
      job.noop = !placed && !left;
      job.progress = `sealed ${placed}/${total}${left ? `, ${left} left` : ''}`;
      if (left && !note) throw new Error(`${placed} walls placed, ${left} openings left (unreachable, nothing to place against, or held by another bot)`);
    } finally {
      mv.scafoldingBlocks = scaffold;
      r.digOnly = digOnly;
    }
  };

  // Cobblestone from the supply chest: enough for the openings left, one fetch of at most 128.
  async function fetchBlocks(r, job, need) {
    if (!r.supplyChest) return false;
    try {
      await withdraw(r, job, 'cobblestone', Math.max(1, Math.min(need, 128)));
    } catch (e) {
      guard(job);
      if (!/^no .+ in the chest$/.test(e.message)) throw e;
    }
    return r.bot.inventory.items().some((i) => MATERIALS.includes(i.name));
  }

  // A torch on the inside face of a fresh wall when the bot carries one and none shines within 5 blocks.
  async function torch(r, job, c, box, kindAt) {
    const {bot} = r;
    const item = bot.inventory.items().find((i) => i.name === 'torch');
    if (!item || !(r.getSettings?.().torches ?? true)) return;
    const [ox, oz] = outward(box, c.x, c.z)[0] || [];
    if (ox === undefined) return;
    const inside = {x: c.x - (ox - c.x), y: c.y, z: c.z - (oz - c.z)};
    if (kindAt(inside.x, inside.y, inside.z) !== 'air') return;
    const ids = ['torch', 'wall_torch'].map((n) => bot.registry.blocksByName[n]?.id).filter((id) => id !== undefined);
    if (bot.findBlock({matching: ids, maxDistance: 5})) return;
    try {
      await bot.equip(item, 'hand');
      guard(job);
      await bot.placeBlock(bot.blockAt(new Vec3(c.x, c.y, c.z)), new Vec3(inside.x - c.x, 0, inside.z - c.z)).catch(() => {});
      await sleep(250);
    } catch (e) {
      guard(job); // a torch that does not stay never stops the walling
    }
  }
}

module.exports = {scan, standSpot, refFace, validateBox, makeSeal, kindOf, MAX_SIDE, MAX_HEIGHT, MAX_WALLS, MATERIALS};

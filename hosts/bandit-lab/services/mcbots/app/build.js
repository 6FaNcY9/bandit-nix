'use strict';
// Build job (BOTS.md "Schematic building"): place the blocks of a small
// blueprint, bottom layer first, through the same claim table as digging, so
// a dig and a placement never meet on one block and several bots can share
// one build. Pure parts (validate, step, materials) are tested in test.js with
// a fake world; makeBuild() wires them to a bot like crafting.js does.
const {Vec3} = require('vec3');
const {insideAreas, normDim} = require('./world');

const MAX_BLOCKS = 75;
const MAX_SIZE = {x: 5, y: 3, z: 5}; // height 3: every target is in reach from the ground, no scaffolding
const NAME_RE = /^[a-z_]{1,48}$/;
// Plain full blocks only: no containers, gravity blocks, fluids, doors, or
// blocks whose facing/state matters (stairs, slabs, redstone, ...).
const REFUSED = /chest|barrel|shulker|furnace|hopper|dispenser|dropper|door|gate|bed$|sign|banner|(^|_)sand$|gravel|concrete_powder|anvil|water|lava|torch|lantern|stairs|slab|wall$|fence|pane|rail|button|lever|pressure_plate|redstone|piston|observer|repeater|comparator|scaffolding|carpet|^air$/;
const REPLACEABLE = new Set(['air', 'cave_air', 'short_grass', 'tall_grass', 'grass', 'fern', 'large_fern',
  'dandelion', 'poppy', 'snow', 'dead_bush']);
// Faces to place against, preferred first: the block below, then the sides, then above.
const FACES = [[0, -1, 0], [1, 0, 0], [-1, 0, 0], [0, 0, 1], [0, 0, -1], [0, 1, 0]];

const int = (v, what) => {
  const n = Number(v);
  if (!Number.isInteger(n) || Math.abs(n) > 3e7) throw new Error(`${what} must be a whole number`);
  return n;
};

// Blueprint {origin: {x,y,z}, blocks: [{x,y,z,block}], remove?} with block
// positions relative to the origin -> {origin, blocks (absolute, build order), remove}.
function validate(bp, areas = []) {
  if (!bp || typeof bp !== 'object') throw new Error('blueprint must be an object');
  const o = {x: int(bp.origin?.x, 'origin x'), y: int(bp.origin?.y, 'origin y'), z: int(bp.origin?.z, 'origin z')};
  if (o.y < -64 || o.y > 316) throw new Error('origin y must be within -64..316');
  if (!Array.isArray(bp.blocks) || !bp.blocks.length) throw new Error('blueprint has no blocks');
  if (bp.blocks.length > MAX_BLOCKS) throw new Error(`at most ${MAX_BLOCKS} blocks`);
  const seen = new Set();
  const blocks = bp.blocks.map((b, i) => {
    const block = String(b?.block ?? '');
    if (!NAME_RE.test(block) || REFUSED.test(block)) throw new Error(`block ${i}: ${block || '?'} cannot be built (plain full blocks only)`);
    const p = {x: o.x + int(b.x, `block ${i} x`), y: o.y + int(b.y, `block ${i} y`), z: o.z + int(b.z, `block ${i} z`), block};
    const k = `${p.x},${p.y},${p.z}`;
    if (seen.has(k)) throw new Error(`block ${i}: two blocks at ${k}`);
    seen.add(k);
    if (insideAreas(areas, p.x, p.z)) throw new Error(`block ${i}: ${p.x} ${p.z} is inside a protected area`);
    return p;
  });
  for (const ax of ['x', 'y', 'z']) {
    const vs = blocks.map((b) => b[ax]);
    if (Math.max(...vs) - Math.min(...vs) + 1 > MAX_SIZE[ax]) throw new Error(`blueprint is larger than ${MAX_SIZE.x}x${MAX_SIZE.y}x${MAX_SIZE.z} (x by height by z)`);
  }
  // Bottom layer first, then z, then x: each block has a neighbour placed before it.
  blocks.sort((a, b) => a.y - b.y || a.z - b.z || a.x - b.x);
  return {origin: o, blocks, remove: bp.remove === true};
}

const keyOf = (p) => `${p.x},${p.y},${p.z}`;
const solid = (name) => name != null && !REPLACEABLE.has(name) && !/water|lava/.test(name);

// What to do next, given nameAt(x,y,z) -> block name (null = not loaded) and
// keys to leave alone (claimed by another bot, failed lately):
// {done} | {next, face, clear?} (face: offset from the target to the block placed
// against; clear: a plant there must be broken first, soft(name) says which) | {wait} | {stuck}.
function step(plan, nameAt, skip = new Set(), soft = () => false) {
  let open = 0;
  const stuck = [];
  for (const b of plan.blocks) {
    const here = nameAt(b.x, b.y, b.z);
    if (here === b.block) continue;
    open++;
    if (here == null || skip.has(keyOf(b))) continue;
    const clear = !REPLACEABLE.has(here) && soft(here);
    if (!REPLACEABLE.has(here) && !clear) {
      stuck.push(`${here} is in the way at ${b.x} ${b.y} ${b.z}`);
      continue;
    }
    const face = FACES.find(([dx, dy, dz]) => solid(nameAt(b.x + dx, b.y + dy, b.z + dz)));
    if (face) return {next: b, face, ...(clear ? {clear} : {})};
  }
  if (!open) return {done: true};
  return stuck.length ? {stuck: stuck[0]} : {wait: open};
}

// Remove mode: the placed blocks of the blueprint, top layer first.
function removeStep(plan, nameAt, skip = new Set()) {
  const left = [...plan.blocks].reverse().filter((b) => nameAt(b.x, b.y, b.z) === b.block);
  if (!left.length) return {done: true};
  const next = left.find((b) => !skip.has(keyOf(b)));
  return next ? {next} : {wait: left.length};
}

// Blocks still to place, {name: count}.
function materials(plan, nameAt = () => null) {
  const need = {};
  for (const b of plan.blocks) if (nameAt(b.x, b.y, b.z) !== b.block) need[b.block] = (need[b.block] || 0) + 1;
  return need;
}

// What is missing, {name: count}: need minus have, only where have is short.
function shortfall(need, have) {
  const out = {};
  for (const [n, c] of Object.entries(need)) if ((have[n] || 0) < c) out[n] = c - (have[n] || 0);
  return out;
}

const formatShortfall = (missing) => Object.entries(missing).map(([n, c]) => `${c} ${n}`);

// {name: count} of an inventory item list.
function countHave(items) {
  const have = {};
  for (const it of items) have[it.name] = (have[it.name] || 0) + it.count;
  return have;
}

const WAIT_MS = 60000; // blocks held by other bots: give up when nothing frees for this long

function makeBuild({goNear, guard, sleep, goals, digAt, withdraw}) {
  return async function build(r, job) {
    const {bot} = r;
    const plan = validate(job.args, r.protectedAreas);
    const dim = normDim(bot.game?.dimension); // same claim keys as digging (collect in bots.js)
    const ckey = (p) => `${dim}:${p.x},${p.y},${p.z}`;
    const nameAt = (x, y, z) => bot.blockAt(new Vec3(x, y, z))?.name ?? null;
    const xs = plan.blocks.map((b) => b.x);
    const zs = plan.blocks.map((b) => b.z);
    const box = [Math.min(...xs), Math.min(...zs), Math.max(...xs), Math.max(...zs)];
    // The pathfinder must neither dig through nor scaffold into the build.
    const veto = (blk) => (insideAreas([box], blk.position.x, blk.position.z) ? 100 : 0);
    const mv = bot.pathfinder.movements;
    mv.exclusionAreasBreak.push(veto);
    mv.exclusionAreasPlace.push(veto);
    // Nor spend the build's material on scaffolding (it ate 6 cobblestone on one walk, 2026-10-10).
    const scaffold = mv.scafoldingBlocks; // sic: mineflayer-pathfinder 2.4.5 spells it so
    const wanted = new Set(plan.blocks.map((b) => bot.registry.itemsByName[b.block]?.id));
    mv.scafoldingBlocks = scaffold.filter((id) => !wanted.has(id));
    // Flowers, grass and the like break instantly and are cleared, not refused.
    const soft = (n) => {
      const d = bot.registry.blocksByName[n];
      return !!d && d.boundingBox === 'empty' && d.hardness === 0 && !/water|lava|fire/.test(n);
    };
    const skip = new Map(); // key -> until
    const total = plan.blocks.length;
    let waitingSince = 0;
    try {
      if (!plan.remove) {
        const need = materials(plan, nameAt);
        const missing = shortfall(need, countHave(bot.inventory.items()));
        if (Object.keys(missing).length) {
          if (!r.supplyChest) throw new Error(`missing material: ${formatShortfall(missing).join(', ')}`);
          // Take exactly what is missing from the supply chest, item by item; an item the
          // chest does not hold is not an error yet, the recount below decides.
          for (const [item, count] of Object.entries(missing)) {
            guard(job);
            try {
              await withdraw(r, job, item, count);
            } catch (e) {
              guard(job);
              if (!/^no .+ in the chest$/.test(e.message)) throw e;
            }
          }
          guard(job);
          const left = shortfall(need, countHave(bot.inventory.items()));
          if (Object.keys(left).length) throw new Error(`missing material: ${formatShortfall(left).join(', ')} (not in the supply chest either)`);
        }
      }
      for (;;) {
        guard(job);
        const now = Date.now();
        for (const [k, until] of skip) if (until < now) skip.delete(k);
        const s = (plan.remove ? removeStep : step)(plan, nameAt, new Set(skip.keys()), soft);
        const left = plan.remove ? (s.done ? 0 : plan.blocks.filter((b) => nameAt(b.x, b.y, b.z) === b.block).length) : Object.values(materials(plan, nameAt)).reduce((a, c) => a + c, 0);
        job.t.total = total;
        job.t.done = total - left;
        job.progress = `${plan.remove ? 'removed' : 'placed'} ${total - left}/${total}`;
        if (s.done) return;
        if (s.stuck) throw new Error(s.stuck);
        if (s.wait) {
          waitingSince ||= now;
          if (now - waitingSince > WAIT_MS) throw new Error(`${s.wait} blocks left that this bot cannot place or reach`);
          job.t.doing = 'waiting for blocks other bots hold';
          await sleep(1000);
          continue;
        }
        waitingSince = 0;
        const b = s.next;
        const k = ckey(b);
        if (r.world && !(await r.world.claim(r.name, k))) {
          r.conflict?.();
          skip.set(keyOf(b), now + 5000);
          continue;
        }
        try {
          if (plan.remove) {
            await digAt(r, job, new Vec3(b.x, b.y, b.z));
            continue;
          }
          const at = new Vec3(b.x, b.y, b.z);
          if (s.clear) await digAt(r, job, at); // GoalPlaceBlock wants the cell empty
          await goNear(r, job, b.x, b.y, b.z, 3, {goal: new goals.GoalPlaceBlock(at, bot.world, {range: 4}), doing: `walking to place ${b.block} at ${b.x} ${b.y} ${b.z}`});
          const item = bot.inventory.items().find((i) => i.name === b.block);
          if (!item) throw new Error(`ran out of ${b.block}`);
          job.t.doing = `placing ${b.block} at ${b.x} ${b.y} ${b.z}`;
          await bot.equip(item, 'hand');
          const [dx, dy, dz] = s.face;
          const against = bot.blockAt(at.offset(dx, dy, dz));
          await bot.placeBlock(against, new Vec3(-dx, -dy, -dz)).catch(() => {}); // 26.x may not echo the update in time
          for (let i = 0; i < 20 && nameAt(b.x, b.y, b.z) !== b.block; i++) await sleep(100);
          if (nameAt(b.x, b.y, b.z) !== b.block) skip.set(keyOf(b), Date.now() + 30000); // try the others, then again
        } catch (e) {
          guard(job);
          if (!/could not reach/.test(e.message)) throw e;
          skip.set(keyOf(b), Date.now() + 30000);
        } finally {
          r.world?.release(r.name, k);
        }
      }
    } finally {
      mv.exclusionAreasBreak.splice(mv.exclusionAreasBreak.indexOf(veto), 1);
      mv.exclusionAreasPlace.splice(mv.exclusionAreasPlace.indexOf(veto), 1);
      mv.scafoldingBlocks = scaffold;
    }
  };
}

module.exports = {validate, step, removeStep, materials, shortfall, formatShortfall, countHave, makeBuild, MAX_BLOCKS};

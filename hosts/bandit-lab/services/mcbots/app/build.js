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
// Plants a build may break to free a target cell (an explicit list: torches and redstone wire
// also have hardness 0 and no collision box, and they are a player's, MC-3 review 2026-10-10).
const PLANTS = new Set(['short_grass', 'tall_grass', 'grass', 'fern', 'large_fern', 'dead_bush', 'bush',
  'short_dry_grass', 'tall_dry_grass', 'dandelion', 'poppy', 'blue_orchid', 'allium', 'azure_bluet',
  'red_tulip', 'orange_tulip', 'white_tulip', 'pink_tulip', 'oxeye_daisy', 'cornflower', 'lily_of_the_valley',
  'wildflowers', 'pink_petals', 'leaf_litter', 'firefly_bush', 'sunflower', 'lilac', 'rose_bush', 'peony']);
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

// Remove mode: blocks this build placed (`placed`, keys "x,y,z"), top layer first. A matching
// block that was there before the build is never in `placed`, so it stays.
function removeStep(plan, nameAt, skip = new Set(), placed = new Set()) {
  const left = [...plan.blocks].reverse().filter((b) => placed.has(keyOf(b)) && nameAt(b.x, b.y, b.z) === b.block);
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

// What a bot can gather for itself: item -> (n, ctx) -> [[jobType, args]]. ctx (what the bot has
// and what stands nearby): {furnace, wood, hasFuel(n)}. Logs and planks are left out on purpose:
// `chop` takes any log type, so plank types would not match the blueprint.
const GATHER = {
  cobblestone: (n) => [['mine', {block: 'stone', count: n}]],
  dirt: (n) => [['mine', {block: 'dirt', count: n}]],
  // Stone is smelted cobblestone; the furnace (8 cobblestone, and a table from 1 log) and the
  // fuel (coal from coal ore) are fetched only when the bot has neither.
  stone: (n, ctx) => {
    const jobs = [['mine', {block: 'stone', count: n + (ctx.furnace ? 0 : 8)}]];
    if (!ctx.furnace && !ctx.wood) jobs.push(['chop', {count: 2}]);
    if (!ctx.hasFuel?.(n)) jobs.push(['mine', {block: 'coal_ore', count: Math.ceil(n / 8)}]);
    for (let left = n; left > 0; left -= 64) jobs.push(['smelt', {item: 'cobblestone', count: Math.min(left, 64)}]); // one furnace load
    return jobs;
  },
};

// {jobs: [[type, args]] in run order, unknown: ['2 oak_planks'], total: items asked for}.
// Mining jobs for the same block are merged (cobblestone and stone both mine stone).
function gatherPlan(missing, ctx = {}) {
  const jobs = [];
  const unknown = [];
  let total = 0;
  for (const [item, n] of Object.entries(missing)) {
    if (!GATHER[item]) {
      unknown.push(`${n} ${item}`);
      continue;
    }
    total += n;
    for (const [type, args] of GATHER[item](n, ctx)) {
      const same = type === 'mine' && jobs.find((j) => j[0] === 'mine' && j[1].block === args.block);
      if (same) same[1].count += args.count;
      else jobs.push([type, {...args}]);
    }
  }
  return {jobs, unknown, total};
}

const WAIT_MS = 60000; // no progress (blocks held by other bots, unreachable) for this long: give up
const DIG_TRIES = 3; // remove mode: a block that will not come out is given up after this many digs

// What builds placed, per dimension + blueprint (absolute blocks): a Set of "x,y,z". Shared by
// the bots of this process; lost when the process restarts (then remove refuses).
const RECORDS = new Map();
const recordOf = (dim, plan) => {
  const k = `${dim}|${JSON.stringify(plan.blocks)}`;
  if (!RECORDS.has(k)) RECORDS.set(k, new Set());
  return RECORDS.get(k);
};

function makeBuild({goNear, guard, sleep, goals, digAt, withdraw, runJob, gatherContext = () => ({}), waitMs = WAIT_MS}) {
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
    const scaffold = mv.scafoldingBlocks; // sic: mineflayer-pathfinder 2.4.5 spells it so
    const soft = (n) => PLANTS.has(n); // flowers and grass are cleared, anything else is refused
    const placed = recordOf(dim, plan);
    if (plan.remove && !placed.size) throw new Error('no record of this build being placed (only blocks a build placed are removed; records are lost when the bot process restarts)');
    const skip = new Map(); // key -> until
    const digFails = new Map(); // key -> failed digs (remove mode)
    const total = plan.blocks.length;
    let lastProgress = Date.now();
    const stalled = (what) => {
      if (Date.now() - lastProgress > waitMs) throw new Error(`no progress for ${Math.round(waitMs / 1000)} s: ${what}`);
    };
    try {
      mv.exclusionAreasBreak.push(veto);
      mv.exclusionAreasPlace.push(veto);
      // Nor spend the build's material on scaffolding (it ate 6 cobblestone on one walk, 2026-10-10).
      const names = new Set(plan.blocks.map((b) => b.block));
      if (names.has('stone')) names.add('cobblestone'); // stone is smelted from it
      const wanted = new Set([...names].map((n) => bot.registry.itemsByName[n]?.id));
      mv.scafoldingBlocks = scaffold.filter((id) => !wanted.has(id));
      if (!plan.remove) {
        const need = materials(plan, nameAt);
        const lack = () => shortfall(need, countHave(bot.inventory.items()));
        let missing = lack();
        const hasMissing = () => Object.keys(missing).length > 0;
        if (hasMissing() && r.supplyChest) {
          // Take exactly what is missing from the supply chest, item by item; an item the
          // chest does not hold is not an error yet, the recount decides.
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
          missing = lack();
        }
        // Then gather the rest. A second round happens only if something got lost on the way
        // (scaffolding, a drop nobody picked up); never gather more than twice the blueprint's size.
        let gathered = 0;
        while (hasMissing()) {
          const g = gatherPlan(missing, gatherContext(r));
          if (g.unknown.length) throw new Error(`cannot gather ${g.unknown.join(', ')} yet`);
          if (!runJob || gathered + g.total > 2 * total) {
            const why = gathered ? ` (gathered ${gathered}, the limit is ${2 * total})` : r.supplyChest ? ' (not in the supply chest either)' : '';
            throw new Error(`missing material: ${formatShortfall(missing).join(', ')}${why}`);
          }
          gathered += g.total;
          for (const [type, args] of g.jobs) {
            guard(job);
            const what = `${type} ${args.block || args.item || ''} x${args.count}`.replace('  ', ' ');
            job.t.doing = `gathering for the build: ${what}`;
            r.emit?.('info', `build gathers: ${what}`);
            await runJob(r, job, type, args);
          }
          guard(job);
          missing = lack();
        }
      }
      for (;;) {
        guard(job);
        const now = Date.now();
        for (const [k, until] of skip) if (until < now) skip.delete(k);
        const s = plan.remove ? removeStep(plan, nameAt, new Set(skip.keys()), placed) : step(plan, nameAt, new Set(skip.keys()), soft);
        const left = plan.remove ? (s.done ? 0 : plan.blocks.filter((b) => placed.has(keyOf(b)) && nameAt(b.x, b.y, b.z) === b.block).length) : Object.values(materials(plan, nameAt)).reduce((a, c) => a + c, 0);
        job.t.total = total;
        job.t.done = total - left;
        job.progress = `${plan.remove ? 'removed' : 'placed'} ${total - left}/${total}`;
        if (s.done) return;
        if (s.stuck) throw new Error(s.stuck);
        if (s.wait) {
          stalled(`${s.wait} blocks left that this bot cannot place or reach`);
          job.t.doing = 'waiting for blocks other bots hold';
          await sleep(1000);
          continue;
        }
        const b = s.next;
        const k = ckey(b);
        if (r.world && !(await r.world.claim(r.name, k))) {
          r.conflict?.();
          skip.set(keyOf(b), now + 5000);
          stalled(`${b.block} at ${b.x} ${b.y} ${b.z} is held by another bot`);
          continue;
        }
        try {
          if (plan.remove) {
            guard(job);
            if (await digAt(r, job, new Vec3(b.x, b.y, b.z), (n) => n === b.block)) {
              placed.delete(keyOf(b));
              lastProgress = Date.now();
              continue;
            }
            // Not dug (no answer, or gone): skip it for a while, give up after DIG_TRIES.
            const n = (digFails.get(keyOf(b)) || 0) + 1;
            digFails.set(keyOf(b), n);
            if (n >= DIG_TRIES && nameAt(b.x, b.y, b.z) === b.block) throw new Error(`could not dig ${b.block} at ${b.x} ${b.y} ${b.z} (${n} tries)`);
            skip.set(keyOf(b), Date.now() + 30000);
            continue;
          }
          const at = new Vec3(b.x, b.y, b.z);
          if (s.clear) {
            guard(job);
            await digAt(r, job, at, soft); // GoalPlaceBlock wants the cell empty; only a plant is cleared
          }
          await goNear(r, job, b.x, b.y, b.z, 3, {goal: new goals.GoalPlaceBlock(at, bot.world, {range: 4}), doing: `walking to place ${b.block} at ${b.x} ${b.y} ${b.z}`});
          guard(job);
          const item = bot.inventory.items().find((i) => i.name === b.block);
          if (!item) throw new Error(`ran out of ${b.block}`);
          job.t.doing = `placing ${b.block} at ${b.x} ${b.y} ${b.z}`;
          await bot.equip(item, 'hand');
          guard(job); // a Stop during the walk or the equip must not place anything
          if (nameAt(b.x, b.y, b.z) === b.block) continue; // someone placed it meanwhile
          const [dx, dy, dz] = s.face;
          const against = bot.blockAt(at.offset(dx, dy, dz));
          await bot.placeBlock(against, new Vec3(-dx, -dy, -dz)).catch(() => {}); // 26.x may not echo the update in time
          for (let i = 0; i < 20 && nameAt(b.x, b.y, b.z) !== b.block; i++) await sleep(100);
          if (nameAt(b.x, b.y, b.z) === b.block) {
            placed.add(keyOf(b));
            lastProgress = Date.now();
          } else skip.set(keyOf(b), Date.now() + 30000); // try the others, then again
        } catch (e) {
          guard(job);
          if (!/could not reach/.test(e.message)) throw e;
          skip.set(keyOf(b), Date.now() + 30000);
          stalled(`could not reach ${b.x} ${b.y} ${b.z}`);
        } finally {
          r.world?.release(r.name, k);
        }
      }
    } finally {
      for (const list of [mv.exclusionAreasBreak, mv.exclusionAreasPlace]) {
        const i = list.indexOf(veto);
        if (i >= 0) list.splice(i, 1);
      }
      mv.scafoldingBlocks = scaffold;
    }
  };
}

module.exports = {validate, step, removeStep, materials, shortfall, formatShortfall, countHave, gatherPlan, GATHER, makeBuild, MAX_BLOCKS, PLANTS, RECORDS};

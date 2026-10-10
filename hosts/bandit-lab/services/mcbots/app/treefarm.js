'use strict';
// Tree farm: `treefarm` plants saplings on a 3-block grid inside an area (at most 24 x 24), chops the
// grown trees (every log inside the area, leaves stay), picks up the saplings and apples that fall,
// replants, and puts the logs into the supply chest when the inventory fills. It runs until stopped.
// The decisions (grid, which cell is free, which logs are one tree) are pure and tested in test.js with
// plain objects; makeTreeFarm() wires them to a bot like hunt.js does. Only logs are ever dug and only
// saplings are placed, and only inside the box and outside protected areas.
const {Vec3} = require('vec3');
const {insideAreas, normDim} = require('./world');

const MAX_SIDE = 24, STEP = 3;
// Oak and birch first. No dark_oak or pale_oak (they grow only from a 2x2 of saplings).
const SAPLINGS = ['oak_sapling', 'birch_sapling', 'spruce_sapling', 'acacia_sapling', 'cherry_sapling', 'jungle_sapling'];
const SOIL = /^(grass_block|dirt|podzol|coarse_dirt|rooted_dirt)$/;
const LOG = /^(oak|birch|spruce|jungle|acacia|dark_oak|cherry|mangrove|pale_oak)_log$/; // never stripped_ (a player did that)
const LEAVES = /_leaves$/;
const FREE = /^(air|cave_air|short_grass|fern)$/;
const FLUID = /water|lava/;
const WANTED_DROP = /_sapling$|^apple$|_log$/;
const RETRY_MS = 300000;
const BONE_MEAL_USES = 6;

// {x1, z1, x2, z2} (any corners) -> the box; 3 x 3 to 24 x 24.
function farmBox(a) {
  const [x1, z1, x2, z2] = [a.x1, a.z1, a.x2, a.z2].map((v) => (v === null || v === '' ? NaN : Number(v)));
  if (![x1, z1, x2, z2].every((v) => Number.isInteger(v) && Math.abs(v) <= 3e7)) throw new Error('x1, z1, x2 and z2 must be whole numbers');
  const box = {x1: Math.min(x1, x2), z1: Math.min(z1, z2), x2: Math.max(x1, x2), z2: Math.max(z1, z2)};
  const [w, l] = [box.x2 - box.x1 + 1, box.z2 - box.z1 + 1];
  if (w < 3 || l < 3 || w > MAX_SIDE || l > MAX_SIDE) throw new Error(`a tree farm is 3 x 3 to ${MAX_SIDE} x ${MAX_SIDE} blocks (this one is ${w} x ${l})`);
  return box;
}

// The grid of planting cells: every 3rd block, one block in from the edge.
function gridCells(box) {
  const out = [];
  for (let x = box.x1 + 1; x < box.x2; x += STEP) for (let z = box.z1 + 1; z < box.z2; z += STEP) out.push({x, z});
  return out;
}

const inBox = (box, x, z) => x >= box.x1 && x <= box.x2 && z >= box.z1 && z <= box.z2;

// blockAt(x, y, z) -> {name, boundingBox} | null. The ground of a column: the top solid block that
// is not part of a tree (so a log standing on dirt still gives the dirt), searched y0+20 .. y0-20.
function groundY(blockAt, x, z, y0) {
  for (let y = y0 + 20; y >= y0 - 20; y--) {
    const b = blockAt(x, y, z);
    if (b && b.boundingBox === 'block' && !/_(log|wood|leaves)$/.test(b.name)) return y;
  }
  return null;
}

// 'planted' (a sapling stands there), 'tree' (a log does), 'free' (plantable: soil, free cell, open
// sky for 4 blocks - leaves allowed) or 'blocked' (anything else, including not loaded).
function cellState(blockAt, {x, z}, gy) {
  const base = blockAt(x, gy, z), cell = blockAt(x, gy + 1, z);
  if (!base || !cell) return 'blocked';
  if (/_sapling$/.test(cell.name)) return 'planted';
  if (LOG.test(cell.name)) return 'tree';
  if (!SOIL.test(base.name) || !FREE.test(cell.name)) return 'blocked';
  for (let dy = 2; dy <= 5; dy++) {
    const b = blockAt(x, gy + dy, z);
    if (!b || FLUID.test(b.name) || (b.boundingBox === 'block' && !LEAVES.test(b.name))) return 'blocked';
  }
  return 'free';
}

const NEIGHBOURS = [];
for (let dx = -1; dx <= 1; dx++) for (let dy = -1; dy <= 1; dy++) for (let dz = -1; dz <= 1; dz++) if (dx || dy || dz) NEIGHBOURS.push([dx, dy, dz]);

// The natural logs connected to `start` that lie inside the box and outside protected areas, lowest first.
function treeLogs(blockAt, start, box, areas) {
  const key = (p) => `${p.x},${p.y},${p.z}`;
  const seen = new Set([key(start)]), todo = [start], logs = [];
  while (todo.length && logs.length < 400) {
    const p = todo.pop();
    logs.push(p);
    for (const [dx, dy, dz] of NEIGHBOURS) {
      const q = {x: p.x + dx, y: p.y + dy, z: p.z + dz};
      if (seen.has(key(q)) || !inBox(box, q.x, q.z) || insideAreas(areas, q.x, q.z)) continue;
      seen.add(key(q));
      if (LOG.test(blockAt(q.x, q.y, q.z)?.name || '')) todo.push(q);
    }
  }
  return logs.sort((a, b) => a.y - b.y);
}

// What stands in the box: {trees: [{base, logs}], free: [cell + gy], planted: [cell + gy]}. A tree is a
// group of natural logs whose lowest log stands on soil inside the box and that has leaves next to it
// (a bare pillar of logs is somebody's build). Cells in protected areas are never listed.
function scan(blockAt, box, y0, areas) {
  const out = {trees: [], free: [], planted: []};
  const done = new Set();
  const grid = new Set(gridCells(box).map((c) => `${c.x},${c.z}`));
  for (let x = box.x1; x <= box.x2; x++) {
    for (let z = box.z1; z <= box.z2; z++) {
      if (insideAreas(areas, x, z)) continue;
      const gy = groundY(blockAt, x, z, y0);
      if (gy === null) continue;
      const here = blockAt(x, gy + 1, z)?.name || '';
      if (grid.has(`${x},${z}`)) {
        const state = cellState(blockAt, {x, z}, gy);
        if (state === 'free') out.free.push({x, z, gy});
        else if (state === 'planted') out.planted.push({x, z, gy});
      }
      if (!LOG.test(here) || !SOIL.test(blockAt(x, gy, z).name) || done.has(`${x},${gy + 1},${z}`)) continue;
      const logs = treeLogs(blockAt, {x, y: gy + 1, z}, box, areas);
      for (const l of logs) done.add(`${l.x},${l.y},${l.z}`);
      const leafy = logs.some((l) => [[1, 0, 0], [-1, 0, 0], [0, 0, 1], [0, 0, -1], [0, 1, 0]].some(([dx, dy, dz]) => LEAVES.test(blockAt(l.x + dx, l.y + dy, l.z + dz)?.name || '')));
      if (leafy) out.trees.push({base: {x, y: gy + 1, z}, logs});
    }
  }
  return out;
}

// Dropped saplings, apples and logs that lie inside the box (entities with getDroppedItem()), nearest first.
function pickups(entities, box, areas, me) {
  return entities
    .filter((e) => e.name === 'item' && e.position && e.isValid !== false && WANTED_DROP.test(e.getDroppedItem?.()?.name || '')
      && inBox(box, Math.floor(e.position.x), Math.floor(e.position.z)) && !insideAreas(areas, Math.floor(e.position.x), Math.floor(e.position.z)))
    .sort((a, b) => a.position.distanceTo(me) - b.position.distanceTo(me));
}

// The sapling to plant (oak and birch first) among inventory items, or undefined.
const pickSapling = (items) => SAPLINGS.map((n) => items.find((i) => i.name === n)).find(Boolean);

function makeTreeFarm({goNear, guard, sleep, digAt, waitCalm, deposit, withdraw, at}) {
  const held = (bot, re) => bot.inventory.items().filter((i) => re.test(i.name)).reduce((n, i) => n + i.count, 0);

  // Use bone meal on a sapling until it is a tree (or the meal or the tries are gone).
  async function boneMeal(r, job, c) {
    const {bot} = r;
    for (let i = 0; i < BONE_MEAL_USES; i++) {
      const meal = bot.inventory.items().find((it) => it.name === 'bone_meal');
      const sapling = bot.blockAt(new Vec3(c.x, c.gy + 1, c.z));
      if (!meal || !/_sapling$/.test(sapling?.name || '')) return;
      if (bot.entity.position.distanceTo(sapling.position.offset(0.5, 0, 0.5)) > 4) await goNear(r, job, c.x, c.gy + 1, c.z, 2, {doing: `walking to the sapling at ${c.x} ${c.z}`});
      guard(job);
      await bot.equip(meal, 'hand').catch(() => {});
      guard(job);
      await bot.activateBlock(sapling).catch(() => {});
      guard(job);
      await sleep(300);
    }
  }

  async function plant(r, job, c) {
    const {bot} = r;
    const sapling = pickSapling(bot.inventory.items());
    if (!sapling) return false;
    if (bot.entity.position.distanceTo(new Vec3(c.x + 0.5, c.gy + 1, c.z + 0.5)) > 4) await goNear(r, job, c.x, c.gy + 1, c.z, 2, {doing: `walking to ${at({x: c.x, y: c.gy + 1, z: c.z})} to plant`});
    guard(job);
    job.t.doing = `planting ${sapling.name} at ${at({x: c.x, y: c.gy + 1, z: c.z})}`;
    await bot.equip(sapling, 'hand');
    guard(job); // a Stop during the equip must not plant
    await bot.placeBlock(bot.blockAt(new Vec3(c.x, c.gy, c.z)), new Vec3(0, 1, 0)).catch(() => {}); // 26.x may not echo the update in time
    for (let i = 0; i < 15 && !/_sapling$/.test(bot.blockAt(new Vec3(c.x, c.gy + 1, c.z))?.name || ''); i++) await sleep(100);
    guard(job);
    return /_sapling$/.test(bot.blockAt(new Vec3(c.x, c.gy + 1, c.z))?.name || '');
  }

  async function treefarm(r, job) {
    const {bot} = r;
    const box = job.args;
    if (!r.supplyChest) throw new Error('a tree farm needs the supply chest for its logs and saplings');
    const blockAt = (x, y, z) => bot.blockAt(new Vec3(x, y, z));
    const y0 = r.supplyChest.y;
    const skip = new Map(); // key -> time until which that log, cell or item is left alone
    const skipped = (k) => (skip.get(k) || 0) > Date.now();
    const later = (k) => skip.set(k, Date.now() + RETRY_MS);
    let cut = job.cut || 0, planted = job.planted || 0, chestTriedAt = 0, chestHadNone = false;
    job.t.open = true; // no end: the dashboard shows a count, not a bar
    job.t.area = {x: Math.round((box.x1 + box.x2) / 2), y: y0, z: Math.round((box.z1 + box.z2) / 2)}; // where a resumed job walks back to
    const report = () => {
      job.cut = cut;
      job.planted = planted;
      job.t.done = cut;
      job.progress = `${cut} logs cut, ${planted} saplings planted`;
    };
    for (;;) {
      guard(job);
      await waitCalm(r, job);
      if (r.world?.unreachable) throw new Error('hub unreachable: not chopping without block reservations');
      const dim = normDim(bot.game?.dimension);
      const s = scan(blockAt, box, y0, r.protectedAreas);
      const me = bot.entity.position;
      const near = (a, b) => Math.hypot(a.x - me.x, a.z - me.z) - Math.hypot(b.x - me.x, b.z - me.z);
      let acted = false;

      if (bot.inventory.emptySlotCount() < 4) {
        job.progress = `depositing (${cut} logs so far)`;
        await deposit(r, job);
        if (bot.inventory.emptySlotCount() < 4) throw new Error('inventory still full after depositing (chest full?)');
        continue;
      }

      // 1. The nearest grown tree: every log of it inside the box, lowest first.
      const trees = s.trees
        .map((t) => ({...t, logs: t.logs.filter((l) => !skipped(`log:${l.x},${l.y},${l.z}`))}))
        .filter((t) => t.logs.length)
        .sort((a, b) => near(a.base, b.base));
      if (trees[0]) {
        let failed = 0;
        for (const l of trees[0].logs) {
          guard(job);
          if (!LOG.test(blockAt(l.x, l.y, l.z)?.name || '')) continue;
          const claim = `${dim}:${l.x},${l.y},${l.z}`;
          if (r.world && !(await r.world.claim(r.name, claim))) { r.conflict?.(); continue; }
          try {
            job.t.doing = `chopping the tree at ${at(trees[0].base)}`;
            if (await digAt(r, job, new Vec3(l.x, l.y, l.z), (n) => LOG.test(n))) { cut++; report(); } else later(`log:${l.x},${l.y},${l.z}`);
          } catch (e) {
            guard(job);
            later(`log:${l.x},${l.y},${l.z}`);
            r.emit('info', `treefarm: left a log at ${at(l)} (${e.message.slice(0, 60)})`);
            if (++failed >= 3) break;
          } finally {
            r.world?.release(r.name, claim);
          }
        }
        acted = true;
      }

      // 2. Saplings and apples that fell inside the box.
      for (const e of pickups(Object.values(bot.entities), box, r.protectedAreas, me).filter((e) => !skipped(`item:${e.id}`)).slice(0, 8)) {
        guard(job);
        job.t.doing = `picking up ${e.getDroppedItem().name}`;
        later(`item:${e.id}`); // one try per item: an unreachable one is left alone
        await goNear(r, job, e.position.x, e.position.y, e.position.z, 0.8, {doing: job.t.doing}).catch(() => {});
        acted = true;
      }
      guard(job);

      // 3. Plant the free cells, fetching saplings from the chest when the bot has none.
      const free = s.free.filter((c) => !skipped(`cell:${c.x},${c.z}`)).sort(near);
      if (free.length && !trees[0]) {
        if (!pickSapling(bot.inventory.items()) && Date.now() - chestTriedAt > RETRY_MS) {
          chestTriedAt = Date.now();
          chestHadNone = true;
          for (const kind of SAPLINGS) {
            try {
              await withdraw(r, job, kind, Math.min(free.length, 16));
              chestHadNone = false;
              r.emit('info', `treefarm: took ${kind} from the supply chest`);
              break;
            } catch (e) {
              guard(job);
              if (!/no \S+ in the chest/.test(e.message)) throw e;
            }
          }
        }
        for (const c of free.slice(0, 6)) {
          guard(job);
          if (!pickSapling(bot.inventory.items())) break;
          if (await plant(r, job, c)) { planted++; report(); acted = true; } else later(`cell:${c.x},${c.z}`);
          await boneMeal(r, job, c);
        }
      }

      // 4. Bone meal on the saplings that stand, when the bot has some.
      if (held(bot, /^bone_meal$/) && s.planted.length) {
        for (const c of s.planted.sort(near).slice(0, 3)) {
          guard(job);
          await boneMeal(r, job, c);
          acted = true;
        }
      }
      report();
      if (acted) continue;

      // Nothing to do: hand the logs in, then wait for the trees to grow.
      if (held(bot, /_log$/)) {
        job.progress = `depositing (${cut} logs so far)`;
        await deposit(r, job);
        continue;
      }
      if (!s.trees.length && !s.planted.length && !s.free.length) throw new Error('nothing to farm: no tree, no sapling and no free soil cell in the area');
      if (!s.trees.length && !s.planted.length && !pickSapling(bot.inventory.items()) && free.length && chestHadNone) {
        throw new Error('no saplings: none carried, none in the supply chest, no tree or sapling in the area; put saplings in the chest');
      }
      job.t.doing = s.planted.length || s.trees.length ? 'waiting for the trees to grow' : 'nothing to plant or chop';
      for (let i = 0; i < 10; i++) {
        guard(job);
        await sleep(1000);
      }
    }
  }

  return {treefarm};
}

module.exports = {SAPLINGS, farmBox, gridCells, groundY, cellState, treeLogs, scan, pickups, pickSapling, makeTreeFarm};

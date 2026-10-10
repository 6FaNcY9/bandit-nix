'use strict';
// Wheat farm: `wheatfarm` keeps a wheat field going inside an area (at most 9 x 9): harvests the ripe
// wheat (age 7), picks the drops up, clears grass off the soil, tills it with a hoe, plants seeds,
// crafts bread from every 3 wheat and hands bread and surplus wheat in at the base chest. It never ends
// on its own: when the wheat is growing it waits. Water is somebody else's job: farmland stays wet only
// within 4 blocks of water, so the bot tills only cells that are wet; the one exception is a water_bucket
// in the inventory, used once when the field has no water at all.
// The decisions (box, ground, cell states, wetness, what to do in which order) are pure and tested in
// test.js with plain objects; makeWheatFarm() wires them to a bot like treefarm.js does. Only wheat, grass
// and soil cells are ever dug, only inside the box and outside protected areas. Walking does not trample
// farmland (only a landing fall does); the bot never jumps on purpose and reaches cells from up to 3 blocks.
const {Vec3} = require('vec3');
const {insideAreas, normDim} = require('./world');

const MAX_SIDE = 9, REACH = 4;
const SOIL = /^(dirt|grass_block|dirt_path)$/; // what a hoe turns into farmland (coarse_dirt only becomes dirt)
const GRASS = /^(short_grass|tall_grass|fern|large_fern)$/;
const FREE = /^(air|cave_air|short_grass|tall_grass|fern|large_fern)$/;
const HOE = /^(wooden|stone|iron|golden|diamond|netherite)_hoe$/;
const WANTED_DROP = /^(wheat|wheat_seeds|bread)$/;
const RETRY_MS = 300000, BOOTSTRAP_MS = 120000;
const BREAD_AT = 16;

// {x1, z1, x2, z2} (any corners) -> the box; 1 x 1 to 9 x 9.
function farmBox(a) {
  const [x1, z1, x2, z2] = [a.x1, a.z1, a.x2, a.z2].map((v) => (v === null || v === '' ? NaN : Number(v)));
  if (![x1, z1, x2, z2].every((v) => Number.isInteger(v) && Math.abs(v) <= 3e7)) throw new Error('x1, z1, x2 and z2 must be whole numbers');
  const box = {x1: Math.min(x1, x2), z1: Math.min(z1, z2), x2: Math.max(x1, x2), z2: Math.max(z1, z2)};
  const [w, l] = [box.x2 - box.x1 + 1, box.z2 - box.z1 + 1];
  if (w > MAX_SIDE || l > MAX_SIDE) throw new Error(`a wheat field is at most ${MAX_SIDE} x ${MAX_SIDE} blocks (this one is ${w} x ${l})`);
  return box;
}

const inBox = (box, x, z) => x >= box.x1 && x <= box.x2 && z >= box.z1 && z <= box.z2;
const centre = (box) => ({x: Math.floor((box.x1 + box.x2) / 2), z: Math.floor((box.z1 + box.z2) / 2)});

// The growth stage of a wheat block. mineflayer exposes the state as getProperties().age on flattened
// versions (1.13+, so 26.2); metadata is the same number there (age is wheat's only property).
function wheatAge(b) {
  const p = b?.getProperties?.()?.age ?? b?.properties?.age ?? b?.metadata;
  return p === undefined ? NaN : Number(p);
}

// The top block of a column that is ground: farmland, a solid block or water; wheat, grass and air above
// it are skipped. blockAt(x, y, z) -> {name, boundingBox} | null. Searched y0+20 .. y0-20.
function columnTop(blockAt, x, z, y0) {
  for (let y = y0 + 20; y >= y0 - 20; y--) {
    const b = blockAt(x, y, z);
    if (!b) continue;
    if (b.boundingBox === 'block' || b.name === 'farmland' || b.name === 'water') return {gy: y, base: b};
  }
  return null;
}

// Farmland at (x, gy, z) is wet when water stands within 4 blocks on its level or one above.
const hydrated = (isWater, x, gy, z) => {
  for (let dx = -4; dx <= 4; dx++) for (let dz = -4; dz <= 4; dz++) if (isWater(x + dx, gy, z + dz) || isWater(x + dx, gy + 1, z + dz)) return true;
  return false;
};

// Every column of the box: {x, z, gy, state, wet}. States: ripe (wheat age 7), growing (younger wheat),
// plant (empty farmland), clear (soil with grass on it), till (soil with air on it), water, blocked
// (anything else, also not loaded). `unloaded` counts the columns without a block. Protected columns are left out.
function scan(blockAt, box, y0, areas) {
  const isWater = (x, y, z) => blockAt(x, y, z)?.name === 'water';
  const cells = [];
  let unloaded = 0;
  for (let x = box.x1; x <= box.x2; x++) {
    for (let z = box.z1; z <= box.z2; z++) {
      if (insideAreas(areas, x, z)) continue;
      const top = columnTop(blockAt, x, z, y0);
      if (!top) { unloaded++; continue; }
      const {gy, base} = top, above = blockAt(x, gy + 1, z);
      let state = 'blocked';
      if (base.name === 'water') state = 'water';
      else if (!above) unloaded++;
      else if (base.name === 'farmland') {
        if (above.name === 'wheat') state = wheatAge(above) >= 7 ? 'ripe' : 'growing';
        else if (FREE.test(above.name)) state = 'plant';
      } else if (SOIL.test(base.name)) {
        if (above.name === 'air' || above.name === 'cave_air') state = 'till';
        else if (GRASS.test(above.name)) state = 'clear';
      }
      cells.push({x, z, gy, state, wet: state === 'blocked' ? false : hydrated(isWater, x, gy, z)});
    }
  }
  return {cells, unloaded, wet: cells.some((c) => c.wet), centre: cells.find((c) => c.x === centre(box).x && c.z === centre(box).z) || null};
}

// What to do now, in order: harvest the ripe wheat, plant the empty farmland (as many as there are
// seeds), clear the grass off wet soil, till wet soil (only with a hoe). Nearest first; `skip(cell)` leaves
// cells that failed lately alone. -> {harvest, plant, clear, till, needHoe, needSeeds} (lists capped at `limit`).
function chooseWork(cells, {me, seeds, hoe, skip = () => false, limit = 8}) {
  const near = (a, b) => Math.hypot(a.x - me.x, a.z - me.z) - Math.hypot(b.x - me.x, b.z - me.z);
  const pick = (f) => cells.filter((c) => !skip(c) && f(c)).sort(near);
  const harvest = pick((c) => c.state === 'ripe');
  const plantable = pick((c) => c.state === 'plant');
  const clear = pick((c) => c.state === 'clear' && c.wet);
  const tillable = pick((c) => c.state === 'till' && c.wet);
  return {
    harvest: harvest.slice(0, limit),
    plant: plantable.slice(0, Math.min(limit, seeds)),
    clear: clear.slice(0, limit),
    till: hoe ? tillable.slice(0, limit) : [],
    needHoe: !hoe && tillable.length > 0,
    needSeeds: seeds === 0 && (plantable.length > 0 || clear.length > 0 || tillable.length > 0),
  };
}

// Dropped wheat, seeds and bread within a block of the box (entities with getDroppedItem()), nearest first.
function pickups(entities, box, areas, me) {
  const wide = {x1: box.x1 - 1, z1: box.z1 - 1, x2: box.x2 + 1, z2: box.z2 + 1};
  return entities
    .filter((e) => e.name === 'item' && e.position && e.isValid !== false && WANTED_DROP.test(e.getDroppedItem?.()?.name || '')
      && inBox(wide, Math.floor(e.position.x), Math.floor(e.position.z)) && !insideAreas(areas, Math.floor(e.position.x), Math.floor(e.position.z)))
    .sort((a, b) => a.position.distanceTo(me) - b.position.distanceTo(me));
}

// Bread to craft from the wheat carried (3 each); 0 when there is not enough.
const breadFrom = (wheat) => Math.floor(wheat / 3);

// Hand in when the bread is worth a trip or the inventory is nearly full.
const shouldDeposit = ({bread, emptySlots}) => bread >= BREAD_AT || emptySlots < 4;

function makeWheatFarm({goNear, guard, sleep, digAt, waitCalm, deposit, crafting, craftTable, base, at}) {
  const held = (bot, re) => bot.inventory.items().filter((i) => re.test(i.name)).reduce((n, i) => n + i.count, 0);
  const look = (bot, x, y, z) => bot.blockAt(new Vec3(x, y, z));

  // Poll until the block at the position satisfies test (26.x may not echo a placement in time).
  async function settled(bot, sleep, x, y, z, test) {
    for (let i = 0; i < 15 && !test(look(bot, x, y, z)?.name || ''); i++) await sleep(100);
    return test(look(bot, x, y, z)?.name || '');
  }

  async function till(r, job, c, hoe) {
    const {bot} = r;
    if (bot.entity.position.distanceTo(new Vec3(c.x + 0.5, c.gy + 1, c.z + 0.5)) > 3.5) await goNear(r, job, c.x, c.gy + 1, c.z, 3, {doing: `walking to ${at({x: c.x, y: c.gy + 1, z: c.z})} to till`});
    guard(job);
    job.t.doing = `tilling ${at({x: c.x, y: c.gy, z: c.z})}`;
    await bot.equip(hoe, 'hand');
    guard(job); // a Stop during the equip must not till
    await bot.activateBlock(look(bot, c.x, c.gy, c.z)).catch(() => {}); // right click on the top face
    return settled(bot, sleep, c.x, c.gy, c.z, (n) => n === 'farmland').then((ok) => { guard(job); return ok; });
  }

  async function plant(r, job, c) {
    const {bot} = r;
    const seed = bot.inventory.items().find((i) => i.name === 'wheat_seeds');
    if (!seed) return false;
    if (bot.entity.position.distanceTo(new Vec3(c.x + 0.5, c.gy + 1, c.z + 0.5)) > 3.5) await goNear(r, job, c.x, c.gy + 1, c.z, 3, {doing: `walking to ${at({x: c.x, y: c.gy + 1, z: c.z})} to plant`});
    guard(job);
    job.t.doing = `planting wheat at ${at({x: c.x, y: c.gy + 1, z: c.z})}`;
    await bot.equip(seed, 'hand');
    guard(job);
    await bot.placeBlock(look(bot, c.x, c.gy, c.z), new Vec3(0, 1, 0)).catch(() => {});
    return settled(bot, sleep, c.x, c.gy + 1, c.z, (n) => n === 'wheat').then((ok) => { guard(job); return ok; });
  }

  // The field has no water at all: with a water_bucket, dig the centre cell and pour into the hole
  // (a source on the ground surface would flood the field); without one, say where to put water.
  async function addWater(r, job, s, box, y0) {
    const {bot} = r;
    const c = s.centre, bucket = bot.inventory.items().find((i) => i.name === 'water_bucket');
    if (!c) throw new Error(`no water in the field: place a water source at ${centre(box).x} ${y0} ${centre(box).z}`);
    if (!bucket) throw new Error(`no water in the field: place a water source at ${c.x} ${c.gy} ${c.z}`);
    if (!['till', 'clear', 'plant'].includes(c.state)) throw new Error(`no water in the field and the centre ${c.x} ${c.gy} ${c.z} is not soil: place a water source there`);
    if (c.state === 'clear') await digAt(r, job, new Vec3(c.x, c.gy + 1, c.z), (n) => GRASS.test(n));
    guard(job);
    await digAt(r, job, new Vec3(c.x, c.gy, c.z), (n) => n === 'farmland' || SOIL.test(n));
    guard(job);
    if (bot.entity.position.distanceTo(new Vec3(c.x + 0.5, c.gy, c.z + 0.5)) > 3.5) await goNear(r, job, c.x, c.gy + 1, c.z, 3, {doing: 'walking to the water spot'});
    guard(job);
    job.t.doing = `pouring water at ${c.x} ${c.gy} ${c.z}`;
    await bot.equip(bucket, 'hand');
    guard(job);
    await bot.lookAt(new Vec3(c.x + 0.5, c.gy, c.z + 0.5), true); // the floor of the hole: the bucket pours into the cell above the hit block
    guard(job);
    await bot.activateItem();
    if (!(await settled(bot, sleep, c.x, c.gy, c.z, (n) => n === 'water'))) throw new Error(`could not pour water at ${c.x} ${c.gy} ${c.z}: place a water source there`);
    guard(job);
    r.emit('info', `wheatfarm: poured water at ${c.x} ${c.gy} ${c.z}`);
  }

  async function wheatfarm(r, job) {
    const {bot} = r;
    const box = job.args;
    const blockAt = (x, y, z) => look(bot, x, y, z);
    const y0 = (r.supplyChest || base).y;
    const mid = centre(box);
    const skip = new Map(); // key -> time until which that cell, item or chore is left alone
    const skipped = (k) => (skip.get(k) || 0) > Date.now();
    const later = (k, ms = RETRY_MS) => skip.set(k, Date.now() + ms);
    let harvested = job.harvested || 0, planted = job.planted || 0, bread = job.bread || 0, unloadedTries = 0;
    job.t.open = true; // no end: the dashboard shows a count, not a bar
    job.t.area = {x: mid.x, y: y0, z: mid.z}; // where a resumed job walks back to
    const report = () => {
      job.harvested = harvested;
      job.planted = planted;
      job.bread = bread;
      job.t.done = harvested;
      job.progress = `${harvested} wheat harvested, ${planted} planted, ${bread} bread`;
    };
    const handIn = async () => {
      for (const what of ['bread', 'wheat']) {
        if (!held(bot, new RegExp(`^${what}$`))) continue;
        job.progress = `depositing ${what}`;
        await deposit(r, job, what);
      }
    };
    for (;;) {
      guard(job);
      await waitCalm(r, job);
      if (r.world?.unreachable) throw new Error('hub unreachable: not farming without block reservations');
      const dim = normDim(bot.game?.dimension);
      if (Math.hypot(bot.entity.position.x - mid.x, bot.entity.position.z - mid.z) > 10) await goNear(r, job, mid.x, y0, mid.z, 6, {doing: `walking to the wheat field at ${mid.x} ${mid.z}`});
      guard(job);
      const s = scan(blockAt, box, y0, r.protectedAreas);
      if (s.unloaded) { // not loaded yet: wait a moment before judging the field
        if (++unloadedTries > 20) throw new Error('the wheat field is not loaded');
        await sleep(1000);
        continue;
      }
      unloadedTries = 0;
      if (!s.cells.length) throw new Error('nothing to farm: the whole area is protected');
      if (!s.wet) { await addWater(r, job, s, box, y0); continue; }

      const me = bot.entity.position;
      const near = (a, b) => Math.hypot(a.x - me.x, a.z - me.z) - Math.hypot(b.x - me.x, b.z - me.z);
      const seeds = held(bot, /^wheat_seeds$/);
      const hoe = bot.inventory.items().find((i) => HOE.test(i.name));
      const work = chooseWork(s.cells, {me, seeds, hoe: !!hoe, skip: (c) => skipped(`cell:${c.x},${c.z}`)});
      let acted = false;

      if (shouldDeposit({bread: held(bot, /^bread$/), emptySlots: bot.inventory.emptySlotCount()})) {
        await handIn();
        if (bot.inventory.emptySlotCount() < 4) throw new Error('inventory still full after depositing (chest full?)');
        continue;
      }

      // 1. Bread from every 3 wheat, at a crafting table near the base chest (never one placed on the field).
      if (held(bot, /^wheat$/) >= 3 && !skipped('bread')) {
        try {
          if (!craftTable(r)) await goNear(r, job, base.x, base.y, base.z, 3, {doing: 'walking to the base to craft bread'});
          const want = held(bot, /^bread$/) + breadFrom(held(bot, /^wheat$/));
          const before = held(bot, /^bread$/);
          await crafting.ensureItem(r, job, 'bread', want);
          bread += held(bot, /^bread$/) - before;
          report();
          acted = true;
        } catch (e) {
          guard(job);
          later('bread');
          r.emit('info', `wheatfarm: no bread (${e.message.slice(0, 80)})`);
        }
      }

      // 2. Harvest the ripe wheat; the drops are picked up by digAt.
      for (const c of work.harvest) {
        guard(job);
        const pos = new Vec3(c.x, c.gy + 1, c.z), claim = `${dim}:${c.x},${c.gy + 1},${c.z}`;
        if (wheatAge(bot.blockAt(pos)) < 7) continue; // not ripe any more
        if (r.world && !(await r.world.claim(r.name, claim))) { r.conflict?.(); continue; }
        try {
          job.t.doing = `harvesting wheat at ${at(pos)}`;
          if (await digAt(r, job, pos, (n) => n === 'wheat')) { harvested++; report(); } else later(`cell:${c.x},${c.z}`);
        } catch (e) {
          guard(job);
          later(`cell:${c.x},${c.z}`);
          r.emit('info', `wheatfarm: left the wheat at ${at(pos)} (${e.message.slice(0, 60)})`);
        } finally {
          r.world?.release(r.name, claim);
        }
        acted = true;
      }

      // 3. Wheat and seeds lying around the field.
      for (const e of pickups(Object.values(bot.entities), box, r.protectedAreas, me).filter((e) => !skipped(`item:${e.id}`)).slice(0, 8)) {
        guard(job);
        job.t.doing = `picking up ${e.getDroppedItem().name}`;
        later(`item:${e.id}`); // one try per item
        await goNear(r, job, e.position.x, e.position.y, e.position.z, 0.8, {doing: job.t.doing}).catch(() => {});
        acted = true;
      }
      guard(job);

      // 4. Plant the empty farmland.
      for (const c of work.plant) {
        guard(job);
        if (!held(bot, /^wheat_seeds$/)) break;
        if (await plant(r, job, c)) { planted++; report(); } else later(`cell:${c.x},${c.z}`);
        acted = true;
      }

      // 5. Grass off wet soil (its seeds are welcome), then a hoe, then till.
      for (const c of work.clear) {
        guard(job);
        const pos = new Vec3(c.x, c.gy + 1, c.z);
        try {
          await digAt(r, job, pos, (n) => GRASS.test(n));
        } catch (e) {
          guard(job);
          later(`cell:${c.x},${c.z}`);
          r.emit('info', `wheatfarm: left the grass at ${at(pos)} (${e.message.slice(0, 60)})`);
        }
        acted = true;
      }
      if (work.needHoe && !skipped('hoe')) {
        try {
          await crafting.ensureItem(r, job, crafting.count(bot, 'cobblestone') >= 2 ? 'stone_hoe' : 'wooden_hoe', 1);
          acted = true;
        } catch (e) {
          guard(job);
          later('hoe');
          r.emit('info', `wheatfarm: no hoe (${e.message.slice(0, 80)})`);
        }
      }
      for (const c of work.till) {
        guard(job);
        if (!(await till(r, job, c, hoe))) later(`cell:${c.x},${c.z}`);
        acted = true;
      }

      // 6. No seeds: grass breaks into seeds now and then. Capped, then left alone for a while.
      if (work.needSeeds && !skipped('seeds')) {
        later('seeds');
        const grass = ['short_grass', 'tall_grass'].map((n) => bot.registry.blocksByName[n]?.id).filter((id) => id !== undefined);
        const until = Date.now() + BOOTSTRAP_MS;
        for (const p of bot.findBlocks({matching: grass, maxDistance: 24, count: 40})) {
          guard(job);
          if (Date.now() > until || held(bot, /^wheat_seeds$/) >= 4) break;
          if (insideAreas(r.protectedAreas, p.x, p.z)) continue;
          job.t.doing = 'looking for seeds in the grass';
          await digAt(r, job, p, (n) => GRASS.test(n)).catch((e) => { guard(job); });
          acted = true;
        }
      }
      report();
      if (acted) continue;

      if (!s.cells.some((c) => ['growing', 'ripe', 'plant', 'till', 'clear'].includes(c.state))) throw new Error('nothing to farm: no soil, farmland or wheat in the area');
      job.t.doing = work.needHoe ? 'no hoe to till with' : work.needSeeds ? 'waiting for seeds' : s.cells.some((c) => c.state === 'growing') ? 'waiting for the wheat to grow' : 'nothing to do';
      for (let i = 0; i < 10; i++) {
        guard(job);
        await sleep(1000);
      }
    }
  }

  return {wheatfarm};
}

module.exports = {farmBox, centre, wheatAge, columnTop, hydrated, scan, chooseWork, pickups, breadFrom, shouldDeposit, makeWheatFarm};

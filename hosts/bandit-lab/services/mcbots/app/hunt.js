'use strict';
// Animals and beds (R5): `hunt` kills (or shears) N animals of one kind around a point and picks the
// drops up; `bed` crafts a bed from the wool, places it and clicks it so the bot's spawn point is
// there. The decisions (which animal, where a bed goes, which wool) are pure and tested in test.js
// with plain objects; makeHunt() wires them to a bot like build.js does.
const {Vec3} = require('vec3');
const {insideAreas} = require('./world');
const {weaponScore} = require('./combat');

// What each animal drops (counted in the job's report). No mooshrooms, horses, wolves or cats.
const ANIMALS = {sheep: /_wool$|^mutton$/, cow: /^(beef|leather)$/, pig: /^porkchop$/, chicken: /^(chicken|feather)$/};
const FACING = {north: [0, -1], south: [0, 1], east: [1, 0], west: [-1, 0]};
const FLUID = /water|lava/;

// A custom name (name tag) is entity metadata 2; the baby flag of an animal is metadata 16.
const named = (e) => ![undefined, null, false, ''].includes(e.metadata?.[2]);
const baby = (e) => e.metadata?.[16] === true;

// The animals of the kind that are inside the radius around x,z, outside protected areas, not named, not
// a baby and not already handled, nearest first. `entities` is a plain list.
function huntTargets(entities, {animal, x, y, z, radius, areas, done, me}) {
  return entities
    .filter((e) => e.name === animal && e.type !== 'player' && e.isValid !== false && e.position && !done.has(e.id) && !named(e) && !baby(e)
      && Math.hypot(e.position.x - x, e.position.z - z) <= radius && Math.abs(e.position.y - y) <= 16
      && !insideAreas(areas, Math.floor(e.position.x), Math.floor(e.position.z)))
    .sort((a, b) => Math.hypot(a.position.x - me.x, a.position.z - me.z) - Math.hypot(b.position.x - me.x, b.position.z - me.z));
}
const huntTarget = (entities, o) => huntTargets(entities, o)[0];

// A bed at x,y,z (the foot); the head lies one block towards `facing`. The bot stands behind the
// foot looking along `facing` (the server turns the bed the way the player looks).
function bedCells({x, y, z}, facing) {
  const [dx, dz] = FACING[facing];
  return {foot: {x, y, z}, head: {x: x + dx, y, z: z + dz}, back: (n) => ({x: x - dx * n, y, z: z - dz * n})};
}

const empty = (b) => !!b && b.boundingBox === 'empty' && !FLUID.test(b.name);
const solid = (b) => !!b && b.boundingBox === 'block';

// blockAt(x, y, z) -> {name, boundingBox} | null. -> {present: true} when a bed already lies on both cells,
// {present: true, click: cell} when only one of them holds a bed (any colour, any facing: the other half
// lies elsewhere or its update is late; the one that is there is clicked), {problem: text}, or {} when a
// bed can be placed.
function bedCheck(blockAt, {foot, head}, areas) {
  for (const c of [foot, head]) if (insideAreas(areas, c.x, c.z)) return {problem: `${c.x} ${c.z} is inside a protected area`};
  const isBed = (c) => /_bed$/.test(blockAt(c.x, c.y, c.z)?.name || '');
  if (isBed(foot) && isBed(head)) return {present: true};
  const click = [foot, head].find(isBed);
  if (click) return {present: true, click};
  for (const c of [foot, head]) {
    const here = blockAt(c.x, c.y, c.z);
    if (!here) return {problem: `${c.x} ${c.y} ${c.z} is not loaded`};
    if (!empty(here)) return {problem: `${here.name} is in the way at ${c.x} ${c.y} ${c.z}`};
    if (!solid(blockAt(c.x, c.y - 1, c.z))) return {problem: `nothing solid under ${c.x} ${c.y} ${c.z}`};
  }
  return {};
}

// A cell the bot can stand on: free feet and head room, solid ground.
const standable = (blockAt, c) => empty(blockAt(c.x, c.y, c.z)) && empty(blockAt(c.x, c.y + 1, c.z)) && solid(blockAt(c.x, c.y - 1, c.z));

// The colour of wool the bot holds at least 3 of (the most of it), or null; items = [{name, count}].
function woolColour(items) {
  const have = {};
  for (const i of items) {
    const m = /^(\w+)_wool$/.exec(i.name);
    if (m) have[m[1]] = (have[m[1]] || 0) + i.count;
  }
  return Object.keys(have).filter((c) => have[c] >= 3).sort((a, b) => have[b] - have[a])[0] || null;
}

function makeHunt({goNear, guard, sleep, goals, waitCalm, crafting, at}) {
  const held = (bot, re) => bot.inventory.items().filter((i) => re.test(i.name)).reduce((n, i) => n + i.count, 0);

  // Close in on one animal and kill it, or shear it. 'done' | 'lost' (30 s, left the area, or no wool).
  async function engage(r, job, e, shears) {
    const {bot} = r;
    const end = Date.now() + 30000;
    const weapon = shears || bot.inventory.items().filter((i) => weaponScore(i.name)).sort((a, b) => weaponScore(b.name) - weaponScore(a.name))[0];
    // The live animal may have been named, moved into a protected area or gone since it was picked, and
    // every await below lets that happen: check again before any blow or shearing (Codex R4-1).
    const off = () => named(e) || baby(e) || insideAreas(r.protectedAreas, Math.floor(e.position.x), Math.floor(e.position.z));
    let following = false, epoch = r.combat.epoch, lastHit = 0;
    const wool = held(bot, /_wool$/);
    try {
      for (;;) {
        guard(job);
        if (e.isValid === false || !bot.entities[e.id]) return shears ? 'lost' : 'done';
        if (Date.now() > end || off()) return 'lost';
        await waitCalm(r, job);
        if (off()) return 'lost';
        if (epoch !== r.combat.epoch) { epoch = r.combat.epoch; following = false; } // combat replaced our goal
        if (weapon && bot.heldItem?.type !== weapon.type && !r.inventoryBusy) {
          await bot.equip(weapon, 'hand').catch(() => {});
          guard(job);
          if (off()) return 'lost';
        }
        if (e.position.distanceTo(bot.entity.position) > 3) {
          if (!following || !bot.pathfinder.isMoving()) { bot.pathfinder.setGoal(new goals.GoalFollow(e, 2), true); following = true; }
          await sleep(250);
          continue;
        }
        if (following) { bot.pathfinder.setGoal(null); following = false; }
        await bot.lookAt(e.position.offset(0, e.height * 0.8, 0), true).catch(() => {});
        guard(job);
        if (off()) return 'lost';
        if (shears) {
          await bot.activateEntity(e);
          guard(job);
          await sleep(800);
          return held(bot, /_wool$/) > wool ? 'done' : 'lost'; // none: already sheared, or a lamb
        }
        if (Date.now() - lastHit >= 650) { lastHit = Date.now(); bot.attack(e); }
        await sleep(100);
      }
    } finally {
      if (following) bot.pathfinder.setGoal(null);
    }
  }

  async function hunt(r, job) {
    const {bot} = r;
    const {animal, count, x, y, z, radius} = job.args;
    const done = new Set(), seen = new Set();
    const before = held(bot, ANIMALS[animal]);
    job.t.total = count;
    job.t.done = job.collected || 0;
    while ((job.collected || 0) < count) {
      guard(job);
      await waitCalm(r, job);
      const around = huntTargets(Object.values(bot.entities), {animal, x, y, z, radius, areas: r.protectedAreas, done, me: bot.entity.position});
      for (const o of around) seen.add(o.id);
      const e = around[0];
      if (!e) throw new Error(`${job.collected || 0} of ${count} ${animal} hunted: no more within ${radius} blocks of ${x} ${y} ${z}`);
      done.add(e.id);
      const shears = animal === 'sheep' ? bot.inventory.items().find((i) => i.name === 'shears') : null;
      job.t.doing = `${shears ? 'shearing' : 'hunting'} a ${animal} at ${at(e.position)}`;
      const outcome = await engage(r, job, e, shears);
      if (outcome === 'done') {
        job.collected = (job.collected || 0) + 1;
        job.t.done = job.collected;
      }
      // A sword sweep kills the animals next to the target too: they count (the drops lie there as well).
      for (const id of seen) if (!done.has(id) && !bot.entities[id]) { done.add(id); job.collected = (job.collected || 0) + 1; }
      job.t.done = job.collected || 0;
      job.progress = `${job.collected || 0}/${count} ${animal}`;
      await sleep(500); // the drops fly a little
      const spot = e.position;
      for (const d of Object.values(bot.entities).filter((en) => en.name === 'item' && en.position.distanceTo(spot) <= 6).slice(0, 8)) {
        guard(job);
        await goNear(r, job, d.position.x, d.position.y, d.position.z, 0.8, {doing: 'picking up the drops'}).catch(() => {});
      }
      guard(job);
    }
    r.emit('info', `hunted ${job.collected} ${animal}: +${held(bot, ANIMALS[animal]) - before} ${animal === 'sheep' ? 'wool and mutton' : 'drops'}`);
  }

  async function bed(r, job) {
    const {bot} = r;
    const {x, y, z, facing} = job.args;
    const cells = bedCells(job.args, facing);
    const blockAt = (a, b, c) => bot.blockAt(new Vec3(a, b, c));
    const check = bedCheck(blockAt, cells, r.protectedAreas);
    if (check.problem) throw new Error(check.problem);
    if (!check.present) {
      let item = bot.inventory.items().find((i) => /_bed$/.test(i.name))?.name;
      if (!item) {
        const colour = woolColour(bot.inventory.items());
        if (!colour) throw new Error(`need 3 wool of one colour for a bed (have ${held(bot, /_wool$/)} wool); hunt sheep first`);
        item = `${colour}_bed`;
        // The planks first: with none in hand ensureItem prefers the "any bed + dye" recipe and fails.
        await crafting.ensurePlanks(r, job, 3);
        await crafting.ensureItem(r, job, item, 1);
      }
      const stand = [2, 1].map(cells.back).find((c) => standable(blockAt, c));
      if (!stand) throw new Error(`no free place to stand behind the bed at ${x} ${y} ${z}`);
      await goNear(r, job, stand.x, stand.y, stand.z, 0, {goal: new goals.GoalBlock(stand.x, stand.y, stand.z), doing: `walking to ${at(stand)} to place a bed`});
      job.t.doing = `placing ${item} at ${x} ${y} ${z}`;
      await bot.equip(bot.inventory.items().find((i) => i.name === item), 'hand');
      guard(job); // a Stop during the equip must not place anything
      await bot.placeBlock(bot.blockAt(new Vec3(x, y - 1, z)), new Vec3(0, 1, 0)).catch(() => {}); // 26.x may not echo the update in time
      const lies = (c) => /_bed$/.test(blockAt(c.x, c.y, c.z)?.name || '');
      for (let i = 0; i < 20 && !(lies(cells.foot) && lies(cells.head)); i++) await sleep(100); // the head's update follows the foot's
      if (!lies(cells.foot)) throw new Error(`placing ${item} did not take`);
      r.emit('info', `placed ${item} at ${x} ${y} ${z}`);
      if (!lies(cells.head)) r.emit('info', `the bed at ${x} ${y} ${z} does not face ${facing}`);
    }
    // Right-click it: that sets the spawn point (day or night); at night sleep in it for a moment.
    const target = check.click || cells.foot;
    const bedBlock = bot.blockAt(new Vec3(target.x, target.y, target.z));
    await goNear(r, job, target.x, target.y, target.z, 2, {doing: `walking to the bed at ${at(target)}`});
    guard(job); // a Stop on arrival must not click (Codex R4-2)
    let confirmed = false;
    const onMessage = (m) => { if (/respawn point set/i.test(m)) confirmed = true; };
    bot.on('messagestr', onMessage);
    try {
      const night = bot.time?.timeOfDay >= 12541 && bot.time.timeOfDay <= 23458; // mineflayer's own limits for sleeping
      // sleep() refuses before it clicks (monsters near, too far); the click alone sets the spawn point.
      if (night) await bot.sleep(bedBlock).catch(async (e) => { guard(job); r.emit('info', `could not sleep (${e.message}); clicking the bed`); await bot.activateBlock(bedBlock).catch(() => {}); });
      else await bot.activateBlock(bedBlock);
      guard(job);
      await sleep(1200);
    } finally {
      bot.off('messagestr', onMessage);
      if (bot.isSleeping) await bot.wake().catch(() => {});
    }
    guard(job);
    r.emit('info', `spawn set at ${at(cells.foot)}${confirmed ? '' : ' (no server confirmation seen: it may have been set already)'}`);
  }

  return {hunt, bed};
}

module.exports = {ANIMALS, FACING, huntTarget, huntTargets, bedCells, bedCheck, standable, woolColour, makeHunt};

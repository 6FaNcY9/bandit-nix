'use strict';
// tidy: pick up the dropped items lying within `radius` of a point (default the supply chest), then put
// them into the supply chest with the deposit job. Items inside protected areas (player bases) and items
// lying in lava, fire or a cactus are left alone. The choice of targets is pure and tested in test.js.
const {Vec3} = require('vec3');
const {insideAreas} = require('./world');

const MAX_VISITS = 60; // items walked to in one job (stacks merge, so this is plenty)
const MAX_MS = 180000;
const TRIES = 2; // walks to one item before it is given up (behind a wall, in a pit)
const HARM = /^(lava|fire|soul_fire|cactus|magma_block|sweet_berry_bush|cobweb)$/;

// The dropped items to walk to, nearest to `me` first. `entities` is a plain list; `skip` the ids given up on;
// `blockAt(x, y, z)` -> name | null tells what an item lies in.
function tidyTargets(entities, {x, y, z, radius, areas, skip = new Set(), me, blockAt = () => null}) {
  return entities
    .filter((e) => e.name === 'item' && e.position && e.isValid !== false && !skip.has(e.id)
      && Math.hypot(e.position.x - x, e.position.z - z) <= radius && Math.abs(e.position.y - y) <= 16
      && !insideAreas(areas, e.position.x, e.position.z) && !HARM.test(blockAt(Math.floor(e.position.x), Math.floor(e.position.y), Math.floor(e.position.z)) || '') && !HARM.test(blockAt(Math.floor(e.position.x), Math.floor(e.position.y) - 1, Math.floor(e.position.z)) || ''))
    .sort((a, b) => a.position.distanceTo(me) - b.position.distanceTo(me));
}

function makeTidy({goNear, guard, sleep, waitCalm, deposit, at}) {
  const held = (bot) => bot.inventory.items().reduce((n, i) => n + i.count, 0);

  return async function tidy(r, job) {
    const {bot} = r;
    const spot = job.args.x !== undefined ? job.args : r.supplyChest;
    if (!spot) throw new Error('tidy needs x, y, z or a supply chest');
    const {x, y, z} = spot;
    const radius = job.args.radius;
    const blockAt = (a, b, c) => bot.blockAt(new Vec3(a, b, c))?.name;
    const before = held(bot);
    const skip = new Set();
    const tries = new Map();
    const t0 = Date.now();
    let visits = 0, deposits = 0;
    while (visits < MAX_VISITS && Date.now() - t0 < MAX_MS) {
      guard(job);
      await waitCalm(r, job);
      const [e] = tidyTargets(Object.values(bot.entities), {x, y, z, radius, areas: r.protectedAreas, skip, me: bot.entity.position, blockAt});
      if (!e) break;
      if (bot.inventory.emptySlotCount() < 2) {
        if (!r.supplyChest || ++deposits > 3) { r.emit('info', 'tidy stopped: inventory full'); break; }
        await deposit(r, job);
        continue;
      }
      visits++;
      job.progress = `${held(bot) - before} picked up, ${visits} visits`;
      const n = (tries.get(e.id) || 0) + 1;
      tries.set(e.id, n);
      if (n >= TRIES) skip.add(e.id);
      await goNear(r, job, e.position.x, e.position.y, e.position.z, 0.8, {doing: `picking up a dropped item at ${at(e.position)}`}).catch(() => {
        guard(job); // a Stop is not a failed walk
        skip.add(e.id);
      });
      await sleep(300); // the pickup happens a moment after arriving
    }
    guard(job);
    const got = held(bot) - before;
    job.collected = got;
    if (r.supplyChest && got > 0) await deposit(r, job);
    r.emit('info', `tidied ${got} items within ${radius} of ${at(spot)}${r.supplyChest ? '' : ' (no supply chest: kept them)'}`);
  };
}

module.exports = {tidyTargets, makeTidy};

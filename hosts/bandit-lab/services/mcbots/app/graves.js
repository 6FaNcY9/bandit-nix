'use strict';
// Graves (AxGraves): a dead bot's items wait in a packet-based grave entity for 24 h; only the owner can
// take them, by sneaking and right-clicking it. `grave` walks there, does that and puts the loot into the
// supply chest. The decisions (which entity is the grave, whether to go after a death, which armour to
// wear) are pure and tested in test.js with plain objects; makeGraves() wires them to a bot like hunt.js.
const {Vec3} = require('vec3');
const {insideAreas, normDim} = require('./world');

const REACH = 3; // the grave entity lies within this many blocks of the death position
const FAR = 1500; // a death further than this from the base is not worth the walk
const NOT_GRAVE = new Set(['item', 'experience_orb', 'arrow', 'trident', 'falling_block']);

// Entities that may be the grave (an armor stand with a head, a display entity, ...), nearest first.
// `entities` is a plain list; players and dropped items never are.
function graveCandidates(entities, {x, y, z}) {
  const d = (e) => Math.hypot(e.position.x - x, e.position.y - y, e.position.z - z);
  return entities
    .filter((e) => e.position && e.type !== 'player' && e.isValid !== false && !NOT_GRAVE.has(e.name) && d(e) <= REACH)
    .sort((a, b) => d(a) - d(b));
}

// Where to look for the grave after a death, or null when the bot should not go: not its own overworld
// death position, too far from the base chest, in a protected area, a grave job already queued for it, or
// the death happened on the way to a grave (a deadly spot would otherwise be visited again and again).
function graveAfterDeath({pos, dim, chest, areas, jobType, queued}) {
  if (!pos || !chest || jobType === 'grave' || normDim(dim) !== 'overworld') return null;
  const [x, y, z] = [pos.x, pos.y, pos.z].map(Math.floor);
  if (![x, y, z].every(Number.isFinite) || y < -64 || y > 320 || insideAreas(areas, x, z)) return null;
  if (Math.hypot(x - chest.x, z - chest.z) > FAR || queued.some((j) => j.type === 'grave' && j.args.x === x && j.args.y === y && j.args.z === z)) return null;
  return {x, y, z};
}

const TIER = ['leather', 'golden', 'chainmail', 'iron', 'diamond', 'netherite'];
const SLOTS = {head: /_helmet$/, torso: /_chestplate$/, legs: /_leggings$/, feet: /_boots$/};
const tier = (n) => TIER.findIndex((t) => n.startsWith(t));

// The armour pieces to put on: per slot the best one in the inventory, if the worn piece (name or null) is worse.
function armourPicks(items, worn) {
  const picks = [];
  for (const [slot, re] of Object.entries(SLOTS)) {
    const best = items.filter((i) => re.test(i.name)).sort((a, b) => tier(b.name) - tier(a.name))[0];
    if (best && (!worn[slot] || tier(best.name) > tier(worn[slot]))) picks.push({slot, item: best});
  }
  return picks;
}

// mineflayer's activateEntity always sends sneaking: false, so write the packets ourselves: first
// "interact at" (where on the entity), then "interact", as the vanilla client does.
async function click(bot, e, sneaking) {
  await bot.lookAt(e.position.offset(0, (e.height || 1) / 2, 0), false);
  for (const mouse of [2, 0]) bot._client.write('use_entity', {target: e.id, mouse, sneaking, hand: 0, x: 0, y: 0, z: 0, location: new Vec3(0, 0, 0)});
}

const countAll = (bot) => (bot.inventory.slots || bot.inventory.items()).reduce((n, i) => n + (i ? i.count : 0), 0);

function makeGraves({goNear, guard, sleep, deposit}) {
  async function grave(r, job) {
    const {bot} = r;
    const {x, y, z} = job.args;
    if (insideAreas(r.protectedAreas, x, z)) throw new Error(`${x} ${z} is inside a protected area`);
    const where = `${x} ${y} ${z}`;
    await goNear(r, job, x, y, z, 2, {doing: `walking to the grave at ${where}`});
    // The packet-based entity is sent when the bot is near; give it a moment.
    let found = [];
    for (let i = 0; i < 20 && !found.length; i++) {
      found = graveCandidates(Object.values(bot.entities), job.args);
      if (!found.length) await sleep(250);
      guard(job);
    }
    const seen = Object.values(bot.entities).filter((e) => e.position && e.type !== 'player' && e.position.distanceTo(bot.entity.position) <= 8).map((e) => `${e.name}/${e.type}`);
    r.emit('info', `grave at ${where}: ${found.length} candidates (${found.map((e) => e.name).join(', ')}); nearby: ${[...new Set(seen)].join(', ') || 'nothing'}`);
    if (!found.length) throw new Error(`no grave entity within ${REACH} blocks of ${where} (gone, or already taken)`);
    const before = countAll(bot);
    job.t.doing = `taking the grave at ${where}`;
    bot.setControlState('sneak', true);
    try {
      await sleep(400); // the server must see the sneak before the click
      for (const e of found.slice(0, 4)) {
        guard(job);
        if (e.position.distanceTo(bot.entity.position) > 4) await goNear(r, job, e.position.x, e.position.y, e.position.z, 2, {doing: 'closing in on the grave'});
        await click(bot, e, true).catch((err) => r.emit('info', `grave click on ${e.name} failed: ${err.message}`));
        for (let i = 0; i < 12 && countAll(bot) === before; i++) await sleep(250);
        guard(job);
        if (countAll(bot) > before) break;
      }
    } finally {
      bot.setControlState('sneak', false);
    }
    const got = countAll(bot) - before;
    if (got <= 0) throw new Error(`the grave at ${where} gave nothing (not ours, empty, or the click did not take)`);
    job.collected = got;
    job.t.done = got;
    for (const {slot, item} of armourPicks(bot.inventory.items(), Object.fromEntries(Object.keys(SLOTS).map((s) => [s, bot.inventory.slots?.[bot.getEquipmentDestSlot(s)]?.name || null])))) {
      guard(job);
      await bot.equip(item, slot).catch(() => {});
    }
    guard(job);
    if (r.supplyChest) await deposit(r, job);
    r.emit('info', `grave at ${where}: ${got} items back${r.supplyChest ? '' : ' (no supply chest to deposit into)'}`);
  }

  return {grave};
}

module.exports = {click, REACH, FAR, graveCandidates, graveAfterDeath, armourPicks, makeGraves};

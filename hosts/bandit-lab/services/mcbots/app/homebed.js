'use strict';
// A home bed for every bot (R5b): `homebed` takes the bot's own slot in the storage rooms (foot on the
// south wall row, head towards the north), gets 3 wool (the base chest, else sheep around the base) and
// planks, crafts the bed, places it from the head cell and lets the `bed` job click it (spawn set).
// A slot that already holds a bed (any colour or facing) is only clicked; a natural block in the slot or
// where the bot stands is dug first, anything placed (planks, chests) is refused. The decisions (which slot, where the bot stands, what
// is missing) are pure and tested in test.js with plain objects; makeHomebed() wires them to a bot.
const {Vec3} = require('vec3');
const {insideAreas} = require('./world');
const {bedCells, bedCheck, standable, woolColour} = require('./hunt');

// Storage room 1: x -272..-266, beds' feet on z -213 (floor y 58); room 2 lies 8 blocks further south
// (z -205) the same way. One slot per x, seven per room.
const ROOM = {x: -272, y: 58, z: -213, width: 7, step: 8};
const SLOTS = ROOM.width * 2;
// Who sleeps where when a job names no slot (the lab crew; bot10 sits in the Nether).
const CREW = ['bot1', 'bot2', 'bot3', 'bot4', 'bot16', 'bot17', 'bot18'];
// Look direction (mineflayer yaw: 0 faces -z) that makes the server turn the bed that way.
const YAW = {north: 0, west: Math.PI / 2, south: Math.PI, east: -Math.PI / 2};

// Stops of the sheep search: a ring around the base, 70 and 140 blocks out (animals are sent ~48 blocks far).
const searchRing = (c) => [70, 140].flatMap((d) => [[d, 0], [0, d], [-d, 0], [0, -d]].map(([dx, dz]) => ({x: Math.floor(c.x) + dx, z: Math.floor(c.z) + dz})));

const slotSpot = (slot) => ({x: ROOM.x + (slot % ROOM.width), y: ROOM.y, z: ROOM.z + ROOM.step * Math.floor(slot / ROOM.width), facing: 'north'});

// The bed spot for a job: explicit x,y,z(,facing), else its slot, else the bot's place in the crew.
function homeSpot(name, a) {
  if (a.x !== undefined) return {x: a.x, y: a.y, z: a.z, facing: a.facing || 'north'};
  const slot = a.slot ?? CREW.indexOf(name);
  if (!Number.isInteger(slot) || slot < 0 || slot >= SLOTS) throw new Error(`${name} has no bed slot (pass slot 0..${SLOTS - 1} or x, y, z)`);
  return slotSpot(slot);
}

// What the bot still has to get for a bed: items = [{name, count}].
function bedNeeds(items) {
  const sum = (re) => items.filter((i) => re.test(i.name)).reduce((n, i) => n + i.count, 0);
  if (sum(/_bed$/)) return {wool: false, planks: false};
  return {wool: !woolColour(items), planks: sum(/_planks$/) < 3 && sum(/_log$/) < 1};
}

function makeHomebed({goNear, guard, sleep, goals, crafting, run, at, digAt, NATURAL}) {
  const items = (bot) => bot.inventory.items();

  // 3 wool of one colour: the base chest first, then sheep around the base (one at a time, the drops mix colours).
  async function getWool(r, job) {
    const {bot} = r;
    const c = r.supplyChest;
    if (c) {
      const have = items(bot).filter((i) => /_wool$/.test(i.name)).reduce((n, i) => n + i.count, 0);
      try {
        await run(r, job, 'withdraw', {item: 'wool', count: Math.max(1, 3 - have), ...c});
      } catch (e) {
        guard(job);
        r.emit('info', `no wool from the base chest: ${e.message.slice(0, 80)}`);
      }
    }
    // Animals are only sent within ~48 blocks of the bot: look here, then walk a ring around the base.
    const home = c || bot.entity.position;
    for (const [i, spot] of [null, ...searchRing(home)].entries()) {
      for (let tries = 0; tries < 6 && !woolColour(items(bot)); tries++) {
        guard(job);
        job.t.doing = 'looking for sheep for wool';
        if (spot && tries === 0) {
          try {
            await goNear(r, job, spot.x, bot.entity.position.y, spot.z, 8, {goal: new goals.GoalNearXZ(spot.x, spot.z, 8), doing: `searching for sheep at ${spot.x} ${spot.z}`});
          } catch (e) {
            guard(job);
            r.emit('info', `sheep search stop ${i} unreachable: ${e.message.slice(0, 60)}`);
            break;
          }
          guard(job);
        }
        const here = bot.entity.position;
        try {
          await run(r, job, 'hunt', {animal: 'sheep', count: 1, x: Math.floor(here.x), y: Math.floor(here.y), z: Math.floor(here.z), radius: 48});
        } catch (e) {
          guard(job);
          break; // none in sight from here: next stop
        }
      }
      if (woolColour(items(bot))) return;
    }
    throw new Error('need 3 wool of one colour: no sheep found around the base; put wool in the base chest');
  }

  async function getWood(r, job) {
    const {bot} = r;
    if (r.supplyChest) {
      try {
        await run(r, job, 'withdraw', {item: 'logs', count: 1, ...r.supplyChest});
      } catch (e) {
        guard(job);
        r.emit('info', `no logs from the base chest: ${e.message.slice(0, 80)}`);
      }
    }
    if (!bedNeeds(items(bot)).planks) return;
    await run(r, job, 'chop', {count: 1});
  }

  // What the bed cells really hold, for the log: the part and facing of the foot, and any bed next to it.
  function describe(blockAt, cells) {
    const one = (c) => {
      const b = blockAt(c.x, c.y, c.z);
      let props = {};
      try { props = b?.getProperties?.() || {}; } catch (e) { /* no properties */ }
      return `${b?.name || 'unloaded'}${props.facing ? ` ${props.part} facing ${props.facing}` : ''}`;
    };
    const near = [[1, 0], [-1, 0], [0, 1], [0, -1]].map(([dx, dz]) => ({x: cells.foot.x + dx, y: cells.foot.y, z: cells.foot.z + dz}))
      .filter((c) => /_bed$/.test(blockAt(c.x, c.y, c.z)?.name || '')).map((c) => at(c));
    return `foot ${one(cells.foot)}, head cell ${one(cells.head)}, beds next to the foot: ${near.join(', ') || 'none'}`;
  }

  // Natural blocks in the slot, the cell the bot stands in (the head) and its head room are dug; the rest stays for bedCheck to refuse.
  async function clearNatural(r, job, cells) {
    const {bot} = r;
    if ([cells.foot, cells.head].some((c) => /_bed$/.test(bot.blockAt(new Vec3(c.x, c.y, c.z))?.name || ''))) return; // a bed is there: it is only clicked
    for (const c of [cells.foot, cells.head, {...cells.head, y: cells.head.y + 1}]) {
      const b = bot.blockAt(new Vec3(c.x, c.y, c.z));
      if (!b || b.boundingBox === 'empty' || !NATURAL.test(b.name)) continue;
      r.emit('info', `digging ${b.name} out of the bed slot at ${at(c)}`);
      await digAt(r, job, new Vec3(c.x, c.y, c.z), (n) => NATURAL.test(n));
      guard(job);
    }
  }

  async function place(r, job, spot, cells, item) {
    const {bot} = r;
    const blockAt = (a, b, c) => bot.blockAt(new Vec3(a, b, c));
    // The server turns the bed the way the player looks; the head cell is free of other beds, the room's
    // walls are behind the foot, so the bot stands where the head will be.
    const stand = cells.head;
    if (!standable(blockAt, stand)) throw new Error(`no free place to stand at ${at(stand)}`);
    await goNear(r, job, stand.x, stand.y, stand.z, 0, {goal: new goals.GoalBlock(stand.x, stand.y, stand.z), doing: `walking to ${at(stand)} to place a bed`});
    job.t.doing = `placing ${item} at ${at(cells.foot)}`;
    await bot.equip(items(bot).find((i) => i.name === item), 'hand');
    guard(job); // a Stop during the equip must not place anything
    await bot.look(YAW[spot.facing], 0, true);
    await sleep(100); // the look packet leaves with the next physics tick; the server turns the bed by the last one it got
    guard(job);
    const ground = bot.blockAt(new Vec3(spot.x, spot.y - 1, spot.z));
    // forceLook 'ignore': placeBlock would turn the bot towards the block and the bed with it.
    await bot._placeBlockWithOptions(ground, new Vec3(0, 1, 0), {swingArm: 'right', forceLook: 'ignore'}).catch(() => {}); // 26.x may not echo the update in time
    const lies = (c) => /_bed$/.test(blockAt(c.x, c.y, c.z)?.name || '');
    for (let i = 0; i < 20 && !(lies(cells.foot) && lies(cells.head)); i++) await sleep(100);
    guard(job);
    if (!lies(cells.foot)) throw new Error(`placing ${item} did not take`);
    r.emit('info', `placed ${item} at ${at(cells.foot)}`);
    if (!lies(cells.head)) r.emit('info', `the bed did not land facing ${spot.facing}: ${describe(blockAt, cells)} (bot yaw ${bot.entity.yaw})`);
  }

  async function homebed(r, job) {
    const {bot} = r;
    const spot = homeSpot(r.name, job.args);
    const cells = bedCells(spot, spot.facing);
    const blockAt = (a, b, c) => bot.blockAt(new Vec3(a, b, c));
    for (const c of [cells.foot, cells.head]) if (insideAreas(r.protectedAreas, c.x, c.z)) throw new Error(`${c.x} ${c.z} is inside a protected area`);
    // The chunks of the room must be loaded before the bed cells can be read.
    await goNear(r, job, spot.x, spot.y, spot.z, 4, {doing: `walking to the bed slot at ${at(cells.foot)}`});
    guard(job);
    await clearNatural(r, job, cells);
    let check = bedCheck(blockAt, cells, r.protectedAreas);
    if (check.problem) throw new Error(check.problem);
    if (!check.present) {
      const need = bedNeeds(items(bot));
      if (need.wool) await getWool(r, job);
      if (need.planks) await getWood(r, job);
      guard(job);
      let item = items(bot).find((i) => /_bed$/.test(i.name))?.name;
      if (!item) {
        item = `${woolColour(items(bot))}_bed`;
        await crafting.ensurePlanks(r, job, 3); // with no planks in hand ensureItem prefers "any bed + dye" and fails
        await crafting.ensureItem(r, job, item, 1);
      }
      guard(job);
      check = bedCheck(blockAt, cells, r.protectedAreas); // someone may have taken the slot meanwhile
      if (check.problem) throw new Error(check.problem);
      if (!check.present) await place(r, job, spot, cells, item);
    }
    await run(r, job, 'bed', {x: spot.x, y: spot.y, z: spot.z, facing: spot.facing});
  }

  return {homebed};
}

module.exports = {ROOM, SLOTS, CREW, YAW, searchRing, slotSpot, homeSpot, bedNeeds, makeHomebed};

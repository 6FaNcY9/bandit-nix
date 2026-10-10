'use strict';
// Mining levels: at one height of the shaft (see the shaft job) dig a 2-high tunnel straight out from the
// middle of each of the four walls, with 1 x 2 side branches every 3rd block (branch mining: two blocks
// of rock between neighbours show every ore of the layer), and mine every ore that touches what was
// dug, with its vein. The geometry (armPlan, armOrder) is pure and tested in test.js; makeLevel() wires it
// to a bot like hunt.js. Claims, protected areas, torches and deposits go through the same helpers as the
// excavate job.
const {Vec3} = require('vec3');
const {insideAreas, normDim} = require('./world');

const DIRS = [[-1, 0], [1, 0], [0, -1], [0, 1]]; // west, east, north, south
const NAMES = ['west', 'east', 'north', 'south'];
const GAP = 3; // a branch every GAP blocks of tunnel
const ORE = /_ore$/;
const FLUID = /^(water|lava|bubble_column)$/;
const VEIN_MAX = 24; // blocks of one vein, so a lava-side vein cannot lead the bot on for ever
// Why a block could not be dug that is no reason to end the job: the arm just stops there.
const SKIPPABLE = /^unsafe: |could not reach|Digging aborted|got no answer/;

// The columns (x, z; each is dug at y and y + 1) of the tunnel that leaves the shaft box through the
// middle of its `dir` wall (0 west, 1 east, 2 north, 3 south): `main` from the wall outwards, and the
// branches (one per side at every GAP-th column, farthest first so the walk back ends at the shaft),
// each {k, cells}: k is the main column it leaves from.
function armPlan(box, dir, length = 32, branch = 8) {
  const [dx, dz] = DIRS[dir];
  const sx = dx < 0 ? box.x1 : dx > 0 ? box.x2 : (box.x1 + box.x2) >> 1;
  const sz = dz < 0 ? box.z1 : dz > 0 ? box.z2 : (box.z1 + box.z2) >> 1;
  const col = (k, j = 0) => ({x: sx + dx * k - dz * j, z: sz + dz * k + dx * j}); // j: sideways
  const main = Array.from({length}, (_, i) => col(i + 1));
  const branches = [];
  for (let k = Math.floor(length / GAP) * GAP; k >= GAP; k -= GAP) {
    for (const side of [-1, 1]) branches.push({k, cells: Array.from({length: branch}, (_, j) => col(k, side * (j + 1)))});
  }
  return {main, branches: branches.filter((b) => b.cells.length)};
}

// The order a bot works the four arms in: its own first (bots of a level start apart, like the shaft's corners).
function armOrder(name) {
  const h = [...name].reduce((n, c) => n + c.charCodeAt(0), 0) % 4;
  return [0, 1, 2, 3].map((i) => (h + i) % 4);
}

const NEIGHBOURS = [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]];

function makeLevel({goNear, waitCalm, guard, sleep, digAt, upkeep, NATURAL, stairRing, at}) {
  const keyOf = (r, p) => `${normDim(r.bot.game?.dimension)}:${p.x},${p.y},${p.z}`;

  // Claim a block for this bot (the hub decides across machines). null: another bot has it.
  const claim = async (r, p) => {
    const k = keyOf(r, p);
    return !r.world || (await r.world.claim(r.name, k)) ? k : null;
  };

  // Dig the ores that touch `from`, and the vein they belong to.
  async function mineOres(r, job, from) {
    const {bot} = r;
    const queue = NEIGHBOURS.map((d) => from.offset(...d));
    const seen = new Set();
    let n = 0;
    while (queue.length && n < VEIN_MAX) {
      const p = queue.shift();
      const s = `${p.x},${p.y},${p.z}`;
      if (seen.has(s) || p.distanceTo(from) > 8) continue;
      seen.add(s);
      const b = bot.blockAt(p);
      if (!b || !ORE.test(b.name) || insideAreas(r.protectedAreas, p.x, p.z) || r.reserved?.(p.x, p.y, p.z)) continue;
      const k = await claim(r, p);
      if (!k) continue;
      try {
        guard(job);
        if (await digAt(r, job, p, (name) => ORE.test(name))) {
          n++;
          job.ores = (job.ores || 0) + 1;
          queue.push(...NEIGHBOURS.map((d) => p.offset(...d)));
        }
      } catch (e) {
        guard(job);
        if (!SKIPPABLE.test(e.message)) throw e;
        r.emit('info', `left an ore at ${at(p)}: ${e.message.slice(0, 60)}`);
      } finally {
        r.world?.release(r.name, k);
      }
    }
  }

  // Dig the two blocks of one column. 'ok' | 'blocked' (something that must stay, unsafe, unreachable,
  // not loaded) | 'busy' (another bot holds a block of it).
  async function digColumn(r, job, c, y) {
    const {bot} = r;
    for (const dy of [0, 1]) {
      const p = new Vec3(c.x, y + dy, c.z);
      for (let tries = 0; ; tries++) {
        guard(job);
        const b = bot.blockAt(p);
        if (!b) return 'blocked';
        if (b.boundingBox === 'empty' && !FLUID.test(b.name)) break;
        if (FLUID.test(b.name) || !NATURAL.test(b.name) || insideAreas(r.protectedAreas, p.x, p.z) || r.reserved?.(p.x, p.y, p.z) || tries >= 4) return 'blocked';
        const k = await claim(r, p);
        if (!k) return 'busy';
        try {
          await upkeep(r, job, [b.type]);
          job.t.doing = `mining the ${job.dirName} tunnel at ${at(p)}`;
          if (!(await digAt(r, job, p, (name) => name === b.name))) return 'blocked';
        } catch (e) {
          guard(job);
          if (!SKIPPABLE.test(e.message)) throw e;
          r.emit('info', `level ${y}: stopped at ${at(p)}: ${e.message.slice(0, 80)}`);
          return 'blocked';
        } finally {
          r.world?.release(r.name, k);
        }
        await mineOres(r, job, p);
        await sleep(250); // gravel above falls into the hole: the next round digs it again
      }
    }
    return 'ok';
  }

  // A walk that waits for a fight to end first and tries again when combat took the pathfinder over
  // ("The goal was changed": a creeper backing the bot off), instead of failing the whole level.
  async function walk(r, job, x, y, z, dist, opts) {
    for (let tries = 0; ; tries++) {
      await waitCalm(r, job);
      try {
        return await goNear(r, job, x, y, z, dist, opts);
      } catch (e) {
        guard(job);
        if (tries >= 3) throw e;
        await sleep(3000);
      }
    }
  }

  // One arm: the main tunnel, then its branches. Returns 'done' | 'busy' | 'blocked'.
  async function runArm(r, job, dir, y) {
    const {main, branches} = armPlan(job.args, dir, job.args.length, job.args.branch);
    job.dirName = NAMES[dir];
    let status = 'done';
    // A branch that stops early is normal (a cave, a fluid); only a stopped main tunnel or a busy block is reported.
    const step = (s, main) => {
      job.t.done++;
      if (s === 'busy' || (s === 'blocked' && main)) status = s;
      return s === 'ok';
    };
    try {
      await walk(r, job, main[0].x, y, main[0].z, 2, {doing: `walking to the ${job.dirName} tunnel`});
    } catch (e) {
      guard(job);
      r.emit('info', `level ${y}: cannot reach the ${job.dirName} tunnel: ${e.message.slice(0, 80)}`);
      return 'busy'; // the next pass tries again
    }
    let reached = 0;
    for (const c of main) {
      job.t.area = {x: c.x, y, z: c.z}; // where a resumed job walks back to
      if (!step(await digColumn(r, job, c, y), true)) break;
      reached++;
    }
    for (const b of branches) {
      if (b.k > reached) continue;
      for (const c of b.cells) {
        job.t.area = {x: c.x, y, z: c.z};
        if (!step(await digColumn(r, job, c, y))) break;
      }
    }
    return status;
  }

  // Walk down (or up) the shaft's own staircase, 16 layers at a time: a walk straight to a spot far
  // below would dig a stair of its own beside the shaft.
  async function toLevel(r, job, y) {
    const {x1, z1, x2, z2, top} = job.args;
    const ring = stairRing(x1, z1, x2, z2);
    await walk(r, job, (x1 + x2) >> 1, Math.floor(r.bot.entity.position.y), z1 - 2, 4, {doing: 'walking to the shaft'});
    for (let leg = 0; leg < 12; leg++) {
      const cur = Math.floor(r.bot.entity.position.y);
      if (cur === y) return;
      const layer = cur > y ? Math.max(y - 1, cur - 17) : Math.min(y - 1, cur + 15); // the layer whose step the bot stands on
      const s = ring[(((top - layer) % ring.length) + ring.length) % ring.length];
      await walk(r, job, s.x, layer + 1, s.z, 1, {doing: `going down the shaft to y ${y} (now y ${cur})`});
    }
  }

  async function level(r, job) {
    const {y} = job.args;
    const cols = (p) => p.main.length + p.branches.reduce((n, b) => n + b.cells.length, 0);
    job.t.total = [0, 1, 2, 3].reduce((n, d) => n + cols(armPlan(job.args, d, job.args.length, job.args.branch)), 0);
    job.t.done = 0;
    await toLevel(r, job, y);
    const report = {};
    for (let pass = 1; pass <= 3; pass++) {
      let busy = 0;
      job.t.done = 0;
      for (const d of armOrder(r.name)) {
        guard(job);
        if (report[d] === 'done' || report[d] === 'blocked') continue;
        report[d] = await runArm(r, job, d, y);
        busy += report[d] === 'busy';
        job.progress = `level y ${y}: ${NAMES.filter((_, i) => report[i] === 'done').join(', ') || 'no'} tunnel(s) done, ${job.ores || 0} ores`;
      }
      if (!busy) break;
      await sleep(3000); // another bot is still digging there
    }
    const stopped = NAMES.filter((_, i) => report[i] === 'blocked'), waiting = NAMES.filter((_, i) => report[i] === 'busy');
    r.emit('info', `level y ${y} finished: ${job.ores || 0} ores${stopped.length ? `; the ${stopped.join(', ')} tunnel(s) ended early (rock that must stay, fluids or caves)` : ''}${waiting.length ? `; the ${waiting.join(', ')} tunnel(s) were left (another bot's blocks or unreachable): run the level again` : ''}`);
  }

  return {level};
}

module.exports = {DIRS, NAMES, GAP, armPlan, armOrder, makeLevel};

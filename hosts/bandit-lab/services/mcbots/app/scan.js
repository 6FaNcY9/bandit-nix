'use strict';
// scanAround(bot, r): a small text map of what is around a bot, for the Andy agents (GET /api/scan/:bot).
// Everything is relative to the bot: dx east, dy up, dz south. Pure over `bot.blockAt`, `bot.entities` and
// `bot.entity.position` (tests pass plain objects); the text stays under MAX_TEXT characters.
const {Vec3} = require('vec3');
const {isHostile} = require('./world');

const MAX_TEXT = 300;
const FLUID_R = 4; // lava and water matter within this many blocks
const MOB_R = 16;
const FALL = 3; // a drop of more than this next to the bot hurts
const DIRS = [['N', 0, -1], ['E', 1, 0], ['S', 0, 1], ['W', -1, 0]];
const ORE = /_ore$|^ancient_debris$/;
const STATION = /^(chest|trapped_chest|barrel|crafting_table|furnace|blast_furnace|smoker)$|_bed$/;
const FLUID = /^(water|lava)$/;

// Free to stand in: no collision box and no fluid. A null block (unloaded chunk) counts as not free.
const free = (b) => !!b && b.boundingBox === 'empty' && !FLUID.test(b.name);
const short = (name) => name.replace(/^deepslate_/, '').replace(/_ore$/, '');
const off = (d) => `${d[0]},${d[1]},${d[2]}`;

function scanAround(bot, r = 10) {
  const p = bot.entity.position;
  const [bx, by, bz] = [Math.floor(p.x), Math.floor(p.y), Math.floor(p.z)];
  const at = (dx, dy, dz) => bot.blockAt(new Vec3(bx + dx, by + dy, bz + dz));
  const dist = (d) => Math.hypot(d[0], d[1], d[2]);
  const ores = [], stations = [], fluids = {};
  for (let dx = -r; dx <= r; dx++) {
    for (let dy = -r; dy <= r; dy++) {
      for (let dz = -r; dz <= r; dz++) {
        const b = at(dx, dy, dz);
        const n = b?.name;
        if (!n || n === 'air' || n === 'cave_air') continue;
        const d = [dx, dy, dz];
        if (ORE.test(n)) ores.push({name: n, d});
        else if (STATION.test(n)) stations.push({name: n, d});
        else if (FLUID.test(n) && dist(d) <= FLUID_R) {
          const f = (fluids[n] ||= {name: n, d, n: 0});
          f.n++;
          if (dist(d) < dist(f.d)) f.d = d;
        }
      }
    }
  }
  const nearest = (list, max) => list.sort((a, b) => dist(a.d) - dist(b.d)).slice(0, max);
  const kinds = []; // a bed or a double chest is two blocks: keep one
  for (const s of nearest(stations, 40)) if (!kinds.some((k) => k.name === s.name && Math.abs(k.d[0] - s.d[0]) + Math.abs(k.d[1] - s.d[1]) + Math.abs(k.d[2] - s.d[2]) <= 1)) kinds.push(s);
  // A drop next to the bot: the neighbour is open at feet and head height and the first solid block below it is further down than FALL.
  const drops = [];
  for (const [name, dx, dz] of DIRS) {
    if (!free(at(dx, 0, dz)) || !free(at(dx, 1, dz))) continue;
    let fall = 0;
    while (fall <= r && free(at(dx, -1 - fall, dz))) fall++;
    if (fall > FALL) drops.push({dir: name, fall: fall > r ? r : fall});
  }
  let up = 0;
  while (up < r && free(at(0, 2 + up, 0))) up++;
  const exits = DIRS.filter(([, dx, dz]) => free(at(dx, 0, dz)) && free(at(dx, 1, dz))).map(([name]) => name);
  const items = Object.values(bot.entities).filter((e) => e.name === 'item' && e.position && e.position.distanceTo(p) <= r);
  const near = items.sort((a, b) => a.position.distanceTo(p) - b.position.distanceTo(p))[0];
  let itemName = '';
  try {
    itemName = near?.getDroppedItem?.()?.name || '';
  } catch {}
  const mobs = Object.values(bot.entities)
    .filter((e) => e !== bot.entity && e.position && isHostile(e) && e.position.distanceTo(p) <= MOB_R)
    .map((e) => ({name: e.name, dist: Math.round(e.position.distanceTo(p))}))
    .sort((a, b) => a.dist - b.dist).slice(0, 4);
  const lava = fluids.lava, water = fluids.water;
  const data = {
    ores: nearest(ores, 6).map((o) => ({name: o.name, d: o.d})),
    fluids: [lava, water].filter(Boolean).map((f) => ({name: f.name, d: f.d, n: f.n})),
    drops,
    up,
    exits,
    stations: kinds.slice(0, 4),
    items: {n: items.length, nearest: near ? {d: [Math.round(near.position.x - p.x), Math.round(near.position.y - p.y), Math.round(near.position.z - p.z)], name: itemName} : null},
    mobs,
  };
  return {text: render(data), data};
}

// Segments in order of importance (danger first); tokens are dropped from the end until it fits.
function render(data) {
  const seg = [
    ['', data.fluids.map((f) => `${f.name}(${off(f.d)})${f.n > 1 ? `x${f.n}` : ''}`)],
    ['drop ', data.drops.map((d) => `${d.dir}${d.fall}`)],
    ['mobs ', data.mobs.map((m) => `${m.name} ${m.dist}m`)],
    ['', [`up ${data.up}${data.up >= 10 ? '+' : ''}`, `exits ${data.exits.join(',') || 'none'}`]],
    ['items ', data.items.n ? [`${data.items.n}${data.items.nearest ? ` near(${off(data.items.nearest.d)})${data.items.nearest.name ? ` ${data.items.nearest.name}` : ''}` : ''}`] : []],
    ['', data.stations.map((s) => `${s.name}(${off(s.d)})`)],
    ['ores ', data.ores.map((o) => `${short(o.name)}(${off(o.d)})`)],
  ];
  const text = () => seg.filter(([, t]) => t.length).map(([label, t]) => label + t.join(' ')).join('; ');
  for (let i = seg.length - 1; text().length > MAX_TEXT && i >= 0; ) {
    if (seg[i][1].length > (i === 3 ? 2 : 0)) seg[i][1].pop();
    else i--;
  }
  return text();
}

module.exports = {scanAround, MAX_TEXT};

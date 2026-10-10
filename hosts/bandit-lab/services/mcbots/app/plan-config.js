'use strict';
// The base plan (R7): geometry and the ordered objectives for plan.js. Data only; plan.js decides.
//
// An objective is either keeper-driven (`keeper: [[item, want]]`: the Keeper works the quotas in
// the base chest) or direct (`roles`: each role is a job chain given to idle bots, `count` of them,
// or `each: true` for one per roster bot; `split: 'x'|'z'` cuts the role's box into one disjoint
// strip per bot). Job args may be a function `({bot, i, n, roster}) => args`. A role chain that ends
// without an error closes its slot; an objective is done when all its slots are closed, or when
// `done(ctx)` says so earlier. ctx = {world, stock, places, keeper, snaps, results, roster, blockAt}.
const {CREW} = require('./homebed');

const BASE = {
  box: {x1: -272, z1: -219, x2: -266, z2: -213},
  chest: {x: -271, y: 66, z: -214}, // the base chest: every withdraw/deposit of the plan uses it, not SUPPLY_CHEST
  shaft: {x1: -291, z1: -222, x2: -276, z2: -207},
  farm: {x1: -262, z1: -238, x2: -248, z2: -224},
  room: {x1: -272, y1: 58, z1: -219, x2: -266, y2: 60, z2: -213}, // under the base box; floor y 57
  roomChests: [{x: -272, y: 58, z: -219}, {x: -270, y: 58, z: -219}],
};
const C = BASE.chest;
const SHAFT_BOTTOM = -54;
const AIR = new Set(['air', 'cave_air']);

// Beds: a CREW name keeps its slot, others take room 2 (slots 7-13) in roster order.
const bedSlot = (bot, roster) => (CREW.includes(bot) ? CREW.indexOf(bot) : Math.min(13, 7 + roster.indexOf(bot)));
const carries = (ctx, prefix) => [...ctx.snaps.values()].some((s) => s?.inventory?.some((i) => i.startsWith(`${prefix} x`)));
const running = (ctx, type, s) => [...ctx.snaps.values()].some((x) => x?.job?.type === type && x.job.runningS >= s);

const OBJECTIVES = [
  {id: 'home-beds', label: 'a home bed for every bot', needs: [], onBlocked: 'park',
    roles: [{each: true, jobs: [['homebed', ({bot, roster}) => ({slot: bedSlot(bot, roster)})]]}]},
  {id: 'stock-basics', label: 'stock the base chest: logs, cobblestone, coal, torches', needs: [], onBlocked: 'park',
    keeper: [['logs', 64], ['cobblestone', 128], ['coal', 32], ['torch', 64]]},
  {id: 'shaft-to-ore', label: `dig the shaft down to y ${SHAFT_BOTTOM}`, needs: ['stock-basics', 'home-beds'], onBlocked: 'park',
    roles: [{count: 3, split: 'x', jobs: [['shaft', {...BASE.shaft, top: 66, bottom: SHAFT_BOTTOM}]]}],
    done: (ctx) => {
      const s = BASE.shaft;
      return AIR.has(ctx.blockAt?.(Math.floor((s.x1 + s.x2) / 2), SHAFT_BOTTOM, Math.floor((s.z1 + s.z2) / 2)));
    }},
  {id: 'storage-room', label: 'dig the storage room at y 58 and place its chests', needs: ['stock-basics'], onBlocked: 'park',
    roles: [{count: 1, jobs: [
      ['excavate', BASE.room],
      ['withdraw', {item: 'logs', count: 4, ...C}],
      ['craft', {item: 'chest', count: BASE.roomChests.length}],
      ...BASE.roomChests.map((c) => ['place', {item: 'chest', ...c}]),
    ]}],
    done: (ctx) => BASE.roomChests.every((c) => ctx.blockAt?.(c.x, c.y, c.z) === 'chest')},
  {id: 'tree-farm', label: 'start the tree farm', needs: ['stock-basics'], onBlocked: 'skip',
    roles: [{count: 1, jobs: [['treefarm', BASE.farm]]}],
    done: (ctx) => running(ctx, 'treefarm', 120)}, // the job never ends: planting for two minutes counts
  {id: 'iron-quota', label: 'raw iron for a full kit in the chest', needs: ['shaft-to-ore'], onBlocked: 'park',
    keeper: [['raw_iron', 32]]},
  {id: 'iron-tools', label: 'smelt and craft an iron pickaxe, sword and armour', needs: ['iron-quota', 'stock-basics'], onBlocked: 'skip',
    roles: [{count: 1, jobs: [
      ['withdraw', {item: 'raw_iron', count: 29, ...C}],
      ['withdraw', {item: 'coal', count: 4, ...C}],
      ['withdraw', {item: 'cobblestone', count: 8, ...C}],
      ['withdraw', {item: 'logs', count: 4, ...C}],
      ['smelt', {item: 'raw_iron', count: 29}],
      ...['pickaxe', 'sword', 'chestplate', 'leggings', 'helmet', 'boots'].map((t) => ['craft', {item: `iron_${t}`, count: 1}]),
    ]}],
    done: (ctx) => carries(ctx, 'iron_pickaxe')},
];

module.exports = {BASE, OBJECTIVES, bedSlot};

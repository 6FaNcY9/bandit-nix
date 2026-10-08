'use strict';
// Shared situational picture, one per process: players (BlueMap, global),
// hostile mobs and notable blocks reported by any bot. Pure logic + a poller.

const MAPS = {world: 'overworld', world_the_nether: 'the_nether', world_the_end: 'the_end'};
const MOB_TTL_MS = 30000;
const BLOCK_TTL_MS = 600000;
const PLAYER_TTL_MS = 10000; // BlueMap polled every 2 s; older = stale, drop
const MAX_MOBS = 200;
const MAX_BLOCKS = 100;
const NOTABLE_BLOCKS = ['chest', 'trapped_chest', 'barrel', 'diamond_ore', 'deepslate_diamond_ore', 'ancient_debris', 'emerald_ore', 'deepslate_emerald_ore'];

// Hostile for the shared picture: mineflayer/minecraft-data classify mobs.
const isHostile = (e) => !!e && e.type !== 'player' && (e.type === 'hostile' || e.category === 'Hostile mobs');
// Hostile but never attacked: neutral unless provoked (enderman, piglins), or
// far too strong for a bot (warden, wither, dragon, elder guardian).
const NO_FIGHT = new Set(['enderman', 'zombified_piglin', 'piglin', 'piglin_brute', 'warden', 'wither', 'ender_dragon', 'elder_guardian', 'ghast', 'breeze']);
const shouldFight = (e) => isHostile(e) && !NO_FIGHT.has(e.name);

// 'minecraft:the_nether' / 'the_nether' / 'overworld' -> canonical name.
const normDim = (d) => String(d || '').replace(/^minecraft:/, '');

// Walking time budget: 90 s, plus 1 s per block of distance, capped at 10 min.
const deadlineMs = (dist) => Math.min(600000, 90000 + Math.max(0, Math.floor(dist || 0)) * 1000);

// BlueMap /maps/<map>/live/players.json -> [{name, uuid, x, y, z, dim}].
function parsePlayers(json, dim) {
  const out = [];
  for (const p of Array.isArray(json?.players) ? json.players : []) {
    if (p.foreign || typeof p.name !== 'string' || !/^\w{1,16}$/.test(p.name)) continue;
    const {x, y, z} = p.position || {};
    if (![x, y, z].every(Number.isFinite)) continue;
    out.push({name: p.name, uuid: String(p.uuid || ''), x, y, z, dim});
  }
  return out;
}

const CLAIM_TTL_MS = 120000;

class WorldModel {
  constructor({now = Date.now} = {}) {
    this.now = now;
    this.players = new Map(); // name -> {..., t}
    this.mobs = new Map(); // `${dim}:${id}` -> {id, type, x, y, z, dim, by, t}
    this.blocks = new Map(); // `${dim}:${x},${y},${z}` -> {type, x, y, z, dim, by, t}
    this.bluemap = {enabled: false, ok: false, error: '', t: 0};
    this.claims = new Map(); // `${dim}:${x},${y},${z}` -> {by, t}: blocks a bot is working on
  }

  // Bots share one process, so claims are exact: a bot only takes a block no
  // other bot holds. Claims expire after CLAIM_TTL_MS in case a bot dies.
  claim(by, key) {
    const c = this.claims.get(key);
    if (c && c.by !== by && this.now() - c.t < CLAIM_TTL_MS) return false;
    this.claims.set(key, {by, t: this.now()});
    return true;
  }

  release(by, key) {
    if (this.claims.get(key)?.by === by) this.claims.delete(key);
  }

  // A disconnected bot (or worker) must not keep blocks reserved.
  releaseAll(by) {
    for (const [k, c] of this.claims) if (c.by === by) this.claims.delete(k);
  }

  // True when claims cannot be checked against the shared table (a worker that
  // lost the hub): jobs that dig refuse to start instead of risking a block
  // another bot holds.
  get unreachable() {
    return false;
  }

  claimedByOther(by, key) {
    const c = this.claims.get(key);
    return !!c && c.by !== by && this.now() - c.t < CLAIM_TTL_MS;
  }

  setPlayers(list) {
    const t = this.now();
    this.players = new Map(list.map((p) => [p.name, {...p, t}]));
    this.bluemap.t = t;
  }

  player(name) {
    const p = this.players.get(name);
    return p && this.now() - p.t <= PLAYER_TTL_MS ? p : undefined;
  }

  noteMob(by, e, dim) {
    const {x, y, z} = e.position;
    this.mobs.set(`${dim}:${e.id}`, {id: e.id, type: e.name, x, y, z, dim, by, t: this.now()});
    this.trim(this.mobs, MAX_MOBS);
  }

  forgetMob(id) {
    for (const k of this.mobs.keys()) if (k.endsWith(`:${id}`)) this.mobs.delete(k);
  }

  noteBlock(by, type, pos, dim) {
    this.blocks.set(`${dim}:${pos.x},${pos.y},${pos.z}`, {type, x: pos.x, y: pos.y, z: pos.z, dim, by, t: this.now()});
    this.trim(this.blocks, MAX_BLOCKS);
  }

  // Drop the oldest entries beyond the cap (Map keeps insertion order; a
  // re-set of an existing key keeps its slot, so sort by last-seen).
  trim(map, max) {
    if (map.size <= max) return;
    const oldest = [...map.entries()].sort((a, b) => a[1].t - b[1].t).slice(0, map.size - max);
    for (const [k] of oldest) map.delete(k);
  }

  prune() {
    const t = this.now();
    for (const [k, m] of this.mobs) if (t - m.t > MOB_TTL_MS) this.mobs.delete(k);
    for (const [k, b] of this.blocks) if (t - b.t > BLOCK_TTL_MS) this.blocks.delete(k);
    for (const [k, p] of this.players) if (t - p.t > PLAYER_TTL_MS) this.players.delete(k);
  }

  hostilesNear(x, z, dim, r) {
    this.prune();
    return [...this.mobs.values()].filter((m) => m.dim === dim && Math.hypot(m.x - x, m.z - z) <= r);
  }

  snapshot() {
    this.prune();
    const t = this.now();
    const age = (o) => ({...o, age: Math.round((t - o.t) / 1000)});
    return {
      bluemap: {...this.bluemap, age: this.bluemap.t ? Math.round((t - this.bluemap.t) / 1000) : null},
      players: [...this.players.values()].map(age),
      mobs: [...this.mobs.values()].map(age),
      blocks: [...this.blocks.values()].map(age),
      claims: [...this.claims].map(([key, c]) => ({key, by: c.by})),
    };
  }
}

// Poll BlueMap every 2 s. Failures only mark the model degraded: bots keep
// working from entity tracking.
function startBlueMap(world, baseUrl, log, fetchFn = fetch) {
  if (!baseUrl) return () => {};
  world.bluemap.enabled = true;
  let busy = false;
  const poll = async () => {
    if (busy) return;
    busy = true;
    try {
      const lists = await Promise.all(Object.entries(MAPS).map(async ([map, dim]) => {
        const res = await fetchFn(`${baseUrl.replace(/\/+$/, '')}/maps/${map}/live/players.json`, {signal: AbortSignal.timeout(1500)});
        if (!res.ok) throw new Error(`${map}: HTTP ${res.status}`);
        return parsePlayers(await res.json(), dim);
      }));
      world.setPlayers(lists.flat());
      if (!world.bluemap.ok) log('bluemap', 'player positions available');
      Object.assign(world.bluemap, {ok: true, error: ''});
    } catch (e) {
      const err = String(e.cause?.code || e.message || e);
      if (world.bluemap.ok || world.bluemap.error !== err) log('bluemap', `unavailable: ${err}`);
      Object.assign(world.bluemap, {ok: false, error: err});
    } finally {
      busy = false;
    }
  };
  poll();
  const timer = setInterval(poll, 2000);
  return () => clearInterval(timer);
}

module.exports = {WorldModel, startBlueMap, parsePlayers, isHostile, shouldFight, normDim, deadlineMs, NOTABLE_BLOCKS, MAPS, MOB_TTL_MS, MAX_MOBS, MAX_BLOCKS, NO_FIGHT};

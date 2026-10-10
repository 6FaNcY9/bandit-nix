'use strict';
// The pathfinder asks for the same block dozens of times per search (every move type looks at the
// same neighbours) and each ask builds a new Block (prismarine-block fromStateId, Biome, block entity):
// 40 % of all CPU with four working bots (profile 2026-10-10). Within one window the answer is the
// same object. The window is short so a changed block is seen by the next search tick, and any block
// update (version() changes) empties it at once: the pathfinder digs by itself and reads fluid safety from
// here, so air that just became water must never come from the cache (Codex review, 2026-10-10).
const WINDOW_MS = 100;

function cacheGetBlock(mv, now = Date.now, version = () => 0) {
  const orig = mv.getBlock.bind(mv);
  let cache = new Map();
  let since = 0;
  let seen = version();
  mv.getBlock = (pos, dx, dy, dz) => {
    if (!pos) return orig(pos, dx, dy, dz);
    const t = now();
    const v = version();
    if (t - since > WINDOW_MS || v !== seen) {
      cache = new Map();
      since = t;
      seen = v;
    }
    // A number key (20 bits x, 20 bits z, 12 bits y): a template string per call cost as much as it saved.
    // A search is local, so coordinates a million blocks apart never share a window.
    const k = (((pos.x + dx) & 0xfffff) * 1048576 + ((pos.z + dz) & 0xfffff)) * 4096 + ((pos.y + dy + 2048) & 0xfff);
    let b = cache.get(k);
    if (!b) {
      b = orig(pos, dx, dy, dz);
      cache.set(k, b);
    }
    return b;
  };
  return mv;
}

module.exports = {cacheGetBlock, WINDOW_MS};

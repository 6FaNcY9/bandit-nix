'use strict';
// Paper 26.2 rejects a movement packet whose bounding box touches a block face
// exactly (gap 0.0): the client walks flush into a wall, the server pulls it
// back (~20 corrections/s) and the pathfinder never gets past the block. A gap
// of 1e-6 is already accepted, so every horizontal collision stops GAP short.
// Found 2026-10-08 with raw position packets against a one-block step.
// Note: widening the player box instead lets prismarine-physics walk straight
// through any wall the bot is already touching, so the clip itself is changed.
const AABB = require('prismarine-physics/lib/aabb');

const GAP = 1e-4;

function keepGap(name) {
  const orig = AABB.prototype[name];
  if (orig.keepsGap) return;
  const patched = function (other, offset) {
    const r = orig.call(this, other, offset);
    if (r === offset) return r; // not blocked
    const m = Math.abs(r) - GAP;
    return m > 0 ? Math.sign(r) * m : 0;
  };
  patched.keepsGap = true;
  AABB.prototype[name] = patched;
}

keepGap('computeOffsetX');
keepGap('computeOffsetZ');

module.exports = {GAP};

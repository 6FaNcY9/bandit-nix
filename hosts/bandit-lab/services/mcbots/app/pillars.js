'use strict';
// Bookkeeping for the pillars a bot builds to climb to the logs of a tall tree (the pathfinder places dirt or
// cobblestone under its feet; the tree farm was full of the leftovers, 2026-10-10). The placement wrapper in
// bots.js records each such block (cells: Map "x,y,z" -> {x, y, z, name}); once the bot is done with the tree
// it digs them back down. Pure and tested in test.js with plain objects.
const key = (x, y, z) => `${x},${y},${z}`;

// A block placed straight up onto the block under the bot's own column is a pillar step; bridges and walls are not.
const isPillarStep = (face, ref, feet) => !!face && face.x === 0 && face.y === 1 && face.z === 0 && !!ref && ref.x === Math.floor(feet.x) && ref.z === Math.floor(feet.z) && ref.y < feet.y;

const record = (cells, x, y, z, name) => cells.set(key(x, y, z), {x, y, z, name});

// A block update at a recorded cell that changes it away from what we recorded ends our claim (a player's
// same-type replacement after a removal is then not ours). Our own placement (air -> recorded name) keeps it.
function changed(cells, x, y, z, oldName, newName) {
  const c = cells.get(key(x, y, z));
  if (c && (oldName === c.name || newName !== c.name)) cells.delete(key(x, y, z));
}

// The cells to dig now, tallest first. Only a cell this bot placed and that is still the same block (a player's
// replacement stays), never in a protected area; stale entries are forgotten. With `target` ({x, z}: the next log),
// a pillar within `near` blocks of it is kept: the bot may still need it for the rest of the tree.
function due(cells, {blockAt, protectedAt = () => false, target = null, near = 4}) {
  const out = [];
  for (const [k, c] of cells) {
    if (blockAt(c.x, c.y, c.z)?.name !== c.name) { cells.delete(k); continue; }
    if (protectedAt(c.x, c.z)) { cells.delete(k); continue; }
    if (target && Math.hypot(c.x - target.x, c.z - target.z) <= near) continue;
    out.push(c);
  }
  return out.sort((a, b) => b.y - a.y);
}

module.exports = {record, changed, due, isPillarStep, key};

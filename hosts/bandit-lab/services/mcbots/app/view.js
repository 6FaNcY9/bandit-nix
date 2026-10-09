'use strict';
// First-person view of a bot as a small PNG: one ray per pixel through the
// blocks the bot has loaded, coloured by block name, shaded by face and
// distance. No textures and no entities other than players/mobs as boxes;
// it answers "what is it looking at", not "what does the game look like".
// ponytail: CPU raycast (~15k rays), fine for one viewer at 1 fps; a WebGL client would scale further.
const zlib = require('node:zlib');
const {Vec3} = require('vec3');

const SKY = [135, 175, 235];
const FOG = 48; // blocks
const COLORS = [
  [/water/, [48, 90, 200]], [/lava/, [230, 100, 20]], [/grass_block|moss|azalea/, [92, 150, 60]],
  [/leaves/, [55, 110, 40]], [/_log|_wood|stem|hyphae/, [110, 80, 45]], [/planks|crafting_table|chest|barrel|bookshelf|_door|_fence|_slab|_stairs/, [165, 130, 80]],
  [/diamond_ore/, [95, 210, 200]], [/iron_ore/, [205, 160, 130]], [/coal_ore/, [45, 45, 45]], [/gold_ore/, [230, 200, 60]],
  [/redstone_ore/, [190, 30, 30]], [/lapis_ore/, [40, 70, 180]], [/copper_ore/, [190, 110, 70]], [/emerald_ore/, [40, 190, 90]],
  [/deepslate/, [75, 75, 80]], [/sand/, [220, 205, 150]], [/gravel/, [135, 125, 120]], [/dirt|mud|farmland|path/, [125, 90, 60]],
  [/snow|ice|quartz|white/, [235, 240, 245]], [/torch|glowstone|lantern|shroomlight/, [255, 220, 120]], [/netherrack|crimson/, [120, 40, 40]],
  [/obsidian/, [30, 20, 45]], [/glass/, [200, 225, 235]], [/flower|tulip|poppy|dandelion/, [210, 70, 120]],
  [/stone|cobble|andesite|tuff|ore|furnace|bricks/, [128, 128, 128]], [/granite/, [150, 105, 90]], [/diorite|calcite/, [200, 200, 200]],
];
const cache = new Map();
function color(name) {
  let c = cache.get(name);
  if (!c) {
    c = COLORS.find(([re]) => re.test(name))?.[1];
    if (!c) { let h = 0; for (const ch of name) h = (h * 31 + ch.charCodeAt(0)) >>> 0; c = [90 + (h & 63), 90 + ((h >> 6) & 63), 90 + ((h >> 12) & 63)]; }
    cache.set(name, c);
  }
  return c;
}
const SEE_THROUGH = /^(air|cave_air|void_air|short_grass|tall_grass|fern|large_fern|dead_bush|vine|light|structure_void|snow)$|torch|flower|sapling|tulip|poppy|dandelion|button|rail|carpet|sign|_plant$/;

// Fast voxel traversal (Amanatides & Woo) from (ox,oy,oz) along unit (dx,dy,dz).
function cast(blockAt, ox, oy, oz, dx, dy, dz) {
  let x = Math.floor(ox), y = Math.floor(oy), z = Math.floor(oz);
  const sx = Math.sign(dx), sy = Math.sign(dy), sz = Math.sign(dz);
  const tdx = Math.abs(1 / dx), tdy = Math.abs(1 / dy), tdz = Math.abs(1 / dz);
  let tx = (sx > 0 ? x + 1 - ox : ox - x) * tdx, ty = (sy > 0 ? y + 1 - oy : oy - y) * tdy, tz = (sz > 0 ? z + 1 - oz : oz - z) * tdz;
  let face = 1, t = 0;
  while (t < FOG) {
    if (tx < ty && tx < tz) { x += sx; t = tx; tx += tdx; face = 0; } else if (ty < tz) { y += sy; t = ty; ty += tdy; face = 1; } else { z += sz; t = tz; tz += tdz; face = 2; }
    const name = blockAt(x, y, z);
    if (name === null) return null; // unloaded chunk
    if (!SEE_THROUGH.test(name)) return {name, t, face, top: face === 1 && sy < 0};
  }
  return null;
}

function png(w, h, rgb) {
  const raw = Buffer.alloc((w * 3 + 1) * h);
  for (let y = 0; y < h; y++) rgb.copy(raw, y * (w * 3 + 1) + 1, y * w * 3, (y + 1) * w * 3);
  const chunk = (type, data) => {
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
    const td = Buffer.concat([Buffer.from(type), data]), crc = Buffer.alloc(4); crc.writeUInt32BE(zlib.crc32(td));
    return Buffer.concat([len, td, crc]);
  };
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
}

// blockAt(x,y,z) -> block name, or null when not loaded. Yaw/pitch as in mineflayer
// (yaw 0 looks to -z, increasing counter-clockwise; pitch > 0 looks up).
function render({blockAt, eye, yaw, pitch, w = 160, h = 90, fov = 70, boxes = []}) {
  const rgb = Buffer.alloc(w * h * 3);
  const f = Math.tan((fov * Math.PI) / 360), aspect = w / h;
  // camera basis
  const fx = -Math.sin(yaw) * Math.cos(pitch), fy = Math.sin(pitch), fz = -Math.cos(yaw) * Math.cos(pitch);
  const rx = Math.cos(yaw), rz = -Math.sin(yaw); // right, horizontal
  const ux = Math.sin(yaw) * Math.sin(pitch), uy = Math.cos(pitch), uz = Math.cos(yaw) * Math.sin(pitch); // up = right x forward
  for (let py = 0; py < h; py++) {
    const v = (1 - (2 * (py + 0.5)) / h) * f;
    for (let px = 0; px < w; px++) {
      const u = ((2 * (px + 0.5)) / w - 1) * f * aspect;
      let dx = fx + u * rx + v * ux, dy = fy + v * uy, dz = fz + u * rz + v * uz;
      const n = Math.hypot(dx, dy, dz); dx /= n; dy /= n; dz /= n;
      const hit = cast(blockAt, eye.x, eye.y, eye.z, dx, dy, dz);
      let c = SKY, t = FOG;
      if (hit) {
        const shade = hit.face === 1 ? (hit.top ? 1 : 0.55) : hit.face === 0 ? 0.8 : 0.68;
        c = color(hit.name).map((k) => k * shade);
        t = hit.t;
      } else if (dy < 0) c = [40, 40, 45]; // looking down into unloaded/void
      for (const b of boxes) { // players / mobs as solid boxes (slab test)
        const bt = slab(eye, dx, dy, dz, b);
        if (bt !== null && bt < t) { t = bt; c = b.color; }
      }
      const fog = Math.min(1, t / FOG) ** 2, i = (py * w + px) * 3;
      rgb[i] = c[0] + (SKY[0] - c[0]) * fog; rgb[i + 1] = c[1] + (SKY[1] - c[1]) * fog; rgb[i + 2] = c[2] + (SKY[2] - c[2]) * fog;
    }
  }
  return png(w, h, rgb);
}

function slab(o, dx, dy, dz, b) {
  let t0 = 0, t1 = FOG;
  for (const [oo, d, lo, hi] of [[o.x, dx, b.x - b.r, b.x + b.r], [o.y, dy, b.y, b.y + b.h], [o.z, dz, b.z - b.r, b.z + b.r]]) {
    if (Math.abs(d) < 1e-9) { if (oo < lo || oo > hi) return null; continue; }
    let a = (lo - oo) / d, c = (hi - oo) / d;
    if (a > c) [a, c] = [c, a];
    t0 = Math.max(t0, a); t1 = Math.min(t1, c);
    if (t0 > t1) return null;
  }
  return t0;
}

// View of a live mineflayer bot.
function botView(bot, opts = {}) {
  const e = bot.entity;
  const p = new Vec3(0, 0, 0);
  const blockAt = (x, y, z) => {
    p.x = x; p.y = y; p.z = z;
    const b = bot.blockAt(p, false); // false: no sign/extra data
    return b ? b.name : null;
  };
  const boxes = Object.values(bot.entities)
    .filter((o) => o !== e && o.position && o.position.distanceTo(e.position) < FOG && (o.type === 'player' || o.type === 'hostile' || o.type === 'mob'))
    .map((o) => ({x: o.position.x, y: o.position.y, z: o.position.z, r: (o.width || 0.6) / 2, h: o.height || 1.8, color: o.type === 'player' ? [40, 90, 230] : o.type === 'hostile' ? [210, 40, 40] : [230, 200, 160]}));
  return render({blockAt, eye: {x: e.position.x, y: e.position.y + (e.eyeHeight || 1.62), z: e.position.z}, yaw: e.yaw, pitch: e.pitch, boxes, ...opts});
}

module.exports = {render, botView, cast, png};

'use strict';
// Adapter between our runner and the vendored Mindcraft skill library
// (vendor/mindcraft, ESM, MIT). Everything bot-specific lives here so the
// vendored files stay close to upstream:
//  - skills expect a mineflayer bot with a few Mindcraft fields (output log,
//    interrupt_code, modes, restrict_to_inventory); attach() provides them as
//    inert stand-ins (no LLM agent exists here);
//  - skills create their own `new pf.Movements(bot)` in many places; we swap
//    pf.Movements for a subclass that always applies our movement constraints
//    and protected-area veto, so no skill can walk or dig outside the rules.
const pf = require('mineflayer-pathfinder');
const {plugin: collectBlock} = require('mineflayer-collectblock');
const {plugin: pvp} = require('mineflayer-pvp');
const {plugin: autoEat} = require('mineflayer-auto-eat');
const armorManager = require('mineflayer-armor-manager');

const areasByBot = new WeakMap(); // bot -> [[x1,z1,x2,z2], ...]

// Bots speak 26.1 to a 26.2 server through ViaBackwards; sprinting, parkour
// jumps and diagonal corner-cutting make the server reject the move and pull
// the bot back (277 corrections in 15 s vs 0 without them, 2026-10-08).
// Inside protected areas (player bases) a bot neither digs nor places. A
// custom unbreakable-block list made the pathfinder plan routes it then
// refused to walk (2026-10-08), so protection is by area only.
function constrain(mv, areas) {
  mv.allowSprinting = false;
  mv.allowParkour = false;
  mv.getMoveDiagonal = () => {};
  // findBlocks hands predicates blocks without a position: nothing to veto yet.
  const veto = (blk) => (blk.position && inArea(areas, blk.position.x, blk.position.z) ? 100 : 0);
  mv.exclusionAreasBreak = [veto];
  mv.exclusionAreasPlace = [veto];
  return mv;
}

const inArea = (areas, x, z) => areas.some(([x1, z1, x2, z2]) => x >= x1 && x <= x2 && z >= z1 && z <= z2);

class SafeMovements extends pf.Movements {
  constructor(bot, ...rest) {
    super(bot, ...rest);
    constrain(this, areasByBot.get(bot) || []);
  }
}
pf.Movements = SafeMovements; // seen by skills.js and mineflayer-pvp (property lookup at call time)

const safeMovements = (bot) => new SafeMovements(bot);

// Load plugins and the Mindcraft stand-ins on a fresh bot.
function attach(bot, areas) {
  areasByBot.set(bot, areas);
  bot.output = '';
  bot.interrupt_code = false;
  bot.restrict_to_inventory = false;
  bot.modes = {isOn: () => false, pause() {}, unpause() {}};
  bot.loadPlugin(pf.pathfinder);
  bot.loadPlugin(collectBlock);
  bot.loadPlugin(pvp);
  bot.loadPlugin(armorManager);
  bot.loadPlugin(autoEat);
  // Plugins are injected by spawn. The off-hand holds the
  // totem: never eat from it.
  bot.once('spawn', () => {
    bot.autoEat.options.offhand = false;
    bot.autoEat.options.bannedFood.push('enchanted_golden_apple');
  });
}

let lib = null;
// Load the ESM skill library once. `version` (the bot's protocol version)
// initialises Mindcraft's minecraft-data helpers.
async function load(version) {
  if (!lib) {
    const base = './vendor/mindcraft/src/';
    const [skills, world, mc] = await Promise.all([
      import(base + 'agent/library/skills.js'),
      import(base + 'agent/library/world.js'),
      import(base + 'utils/mcdata.js'),
    ]);
    lib = {skills, world, mc};
  }
  if (version) lib.mc.init(version);
  return lib;
}

module.exports = {attach, load, safeMovements, inArea};

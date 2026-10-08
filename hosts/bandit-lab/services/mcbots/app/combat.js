'use strict';
// Self-defence, one per BotRunner, ticking every 500 ms. Targets are hostile
// mobs only (never players, tamed or neutral animals). It may take over the
// pathfinder (retreat / creeper back-off); `epoch` then changes so the running
// job knows to re-issue its goal, and `busy` makes jobs wait until calm.
const {goals} = require('mineflayer-pathfinder');
const {isHostile, shouldFight, normDim, NOTABLE_BLOCKS} = require('./world');

const TICK_MS = 500;
const FIGHT_RANGE = 4;
const SEE_RANGE = 24;
const LOW_HEALTH = 8;
const RECOVERED_HEALTH = 12;
const EAT_BELOW = 15;
const SCAN_EVERY = 20; // ticks between notable-block scans (10 s)
const MATERIALS = ['wooden', 'golden', 'stone', 'iron', 'diamond', 'netherite'];
const AVOID_FOOD = new Set(['pufferfish', 'spider_eye', 'poisonous_potato', 'rotten_flesh', 'chicken', 'golden_apple', 'enchanted_golden_apple', 'chorus_fruit', 'suspicious_stew']);

// Swords beat axes (axes hit harder but cool down much slower); higher tier wins.
function weaponScore(name) {
  const m = /^(\w+?)_(sword|axe)$/.exec(name);
  if (!m) return 0;
  const tier = Math.max(0, MATERIALS.indexOf(m[1]));
  return (m[2] === 'sword' ? 100 : 50) + tier;
}

class Combat {
  constructor(runner) {
    this.r = runner;
    this.epoch = 0;
    this.busy = false; // retreating or backing off a creeper
    this.mode = null; // 'retreat' | 'creeper'
    this.eating = false;
    this.lastAttack = 0;
    this.ticks = 0;
    this.timer = setInterval(() => this.tick().catch(() => {}), TICK_MS);
  }

  stop() {
    clearInterval(this.timer);
  }

  takeover(mode, target, dist) {
    if (this.mode === mode) return;
    this.mode = mode;
    this.busy = true;
    this.epoch++;
    this.r.log(this.r.name, `${mode}: away from ${target.name}`);
    this.r.bot.pathfinder.setGoal(new goals.GoalInvert(new goals.GoalFollow(target, dist)), true);
  }

  release() {
    if (!this.mode) return;
    this.mode = null;
    this.busy = false;
    this.epoch++;
    this.r.bot.pathfinder.setGoal(null);
  }

  async tick() {
    const {r} = this;
    const bot = r.bot;
    if (!r.online || !bot?.entity) return;
    this.ticks++;
    const dim = normDim(bot.game?.dimension);
    const me = bot.entity.position;

    const seen = Object.values(bot.entities).filter((e) => e !== bot.entity && isHostile(e) && e.position.distanceTo(me) <= SEE_RANGE);
    for (const e of seen) r.world.noteMob(r.name, e, dim);
    if (this.ticks % SCAN_EVERY === 0) this.scanBlocks(dim);
    // Only mobs that actually threaten the bot drive retreat/back-off/attack;
    // endermen, piglins and the like are seen and shared but left alone.
    const near = seen.filter(shouldFight).sort((a, b) => a.position.distanceTo(me) - b.position.distanceTo(me))[0];
    const dist = near ? near.position.distanceTo(me) : Infinity;

    // Retreat until healthy again or nothing hostile is close.
    if (this.mode === 'retreat') {
      if (bot.health >= RECOVERED_HEALTH || dist > 16) this.release();
      return;
    }
    if (near && bot.health < LOW_HEALTH && dist <= 16) return this.takeover('retreat', near, 20);
    if (this.mode === 'creeper' && (!near || near.name !== 'creeper' || dist > 8)) this.release();

    if (near && near.name === 'creeper' && dist < 6) return this.takeover('creeper', near, 8);
    if (near && shouldFight(near) && dist <= FIGHT_RANGE && !this.busy) return this.fight(near);
    if (!this.busy && !near) await this.eat();
  }

  async fight(target) {
    const bot = this.r.bot;
    const weapon = bot.inventory.items().sort((a, b) => weaponScore(b.name) - weaponScore(a.name))[0];
    if (weapon && weaponScore(weapon.name) && bot.heldItem?.type !== weapon.type) await bot.equip(weapon, 'hand').catch(() => {});
    await bot.lookAt(target.position.offset(0, target.height * 0.8, 0), true).catch(() => {});
    const cooldown = bot.heldItem?.name.endsWith('_axe') ? 1100 : 650;
    if (Date.now() - this.lastAttack >= cooldown && target.isValid !== false) {
      this.lastAttack = Date.now();
      bot.attack(target);
    }
  }

  async eat() {
    const bot = this.r.bot;
    if (this.eating || bot.food >= EAT_BELOW) return;
    const food = bot.inventory.items()
      .filter((i) => bot.registry.foodsByName[i.name] && !AVOID_FOOD.has(i.name))
      .sort((a, b) => bot.registry.foodsByName[b.name].foodPoints - bot.registry.foodsByName[a.name].foodPoints)[0];
    if (!food) return;
    this.eating = true;
    try {
      await bot.equip(food, 'hand');
      await bot.consume();
    } catch {} finally {
      this.eating = false;
    }
  }

  scanBlocks(dim) {
    const bot = this.r.bot;
    const ids = NOTABLE_BLOCKS.map((n) => bot.registry.blocksByName[n]?.id).filter((i) => i !== undefined);
    for (const pos of bot.findBlocks({matching: ids, maxDistance: 32, count: 16})) {
      const b = bot.blockAt(pos);
      if (b) this.r.world.noteBlock(this.r.name, b.name, pos, dim);
    }
  }
}

module.exports = {Combat, weaponScore};

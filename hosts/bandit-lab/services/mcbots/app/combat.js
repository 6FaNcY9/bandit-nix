'use strict';
// Self-defence, one per BotRunner, ticking every 500 ms. Targets are hostile
// mobs only (never players, tamed or neutral animals). It may take over the
// pathfinder (retreat / creeper back-off); `epoch` then changes so the running
// job knows to re-issue its goal, and `busy` makes jobs wait until calm.
const {goals} = require('mineflayer-pathfinder');
const {isHostile, shouldFight, normDim, NOTABLE_BLOCKS} = require('./world');
const {DEFAULTS} = require('./settings');

const TICK_MS = 500;

// Health only regenerates at food 18+, so a hurt bot must eat earlier than a healthy one.
const wantsToEat = (food, health, eatBelow) => food < eatBelow || (health < 20 && food < 18);

// A bot with a sword or axe, two armour pieces and more than 12 health fights a mob near its target
// instead of waiting for it to leave (5 of 8 lab bots stood still at night, 2026-10-10).
const fightReady = (names, armour, health) => health > 12 && armour >= 2 && names.some((n) => /_(sword|axe)$/.test(n));

const DEATH_PHRASE = /^(was slain by|was shot by|fell|hit the ground|drowned|burned|went up in flames|tried to swim in lava|blew up|was blown up|suffocated|starved|froze|was killed|withered|was pricked|experienced kinetic energy)/;
// "bot1 fell from a high place" -> "fell from a high place"; null for chat and other players.
const deathCause = (name, msg) => {
  if (!msg.startsWith(`${name} `)) return null;
  const rest = msg.slice(name.length + 1);
  return DEATH_PHRASE.test(rest) ? rest : null;
};
const FIGHT_RANGE = 4;
const SEE_RANGE = 24;
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

  // True when this bot should clear a nearby hostile itself rather than wait for it (see fightReady).
  fit() {
    const bot = this.r.bot;
    const armour = ['head', 'torso', 'legs', 'feet'].filter((s) => bot.inventory.slots[bot.getEquipmentDestSlot(s)]).length;
    return (this.r.getSettings?.() || DEFAULTS).defend && fightReady(bot.inventory.items().map((i) => i.name), armour, bot.health);
  }

  takeover(mode, target, dist) {
    if (this.mode === mode) return;
    this.mode = mode;
    this.busy = true;
    this.epoch++;
    this.r.log(this.r.name, `${mode}: away from ${target.name}`);
    this.r.bot.pathfinder.setGoal(new goals.GoalInvert(new goals.GoalFollow(target, dist)), true);
  }

  // Lava or fire within 3 blocks of a mob: do not chase it there (a bot burned
  // to death hunting a zombie, 2026-10-10); it is still fought if it comes close.
  hazardNear(pos) {
    const bot = this.r.bot;
    const ids = ['lava', 'fire', 'soul_fire', 'magma_block'].map((n) => bot.registry.blocksByName[n]?.id).filter((i) => i !== undefined);
    return !!bot.findBlock({matching: ids, point: pos, maxDistance: 3});
  }

  hunt(target) {
    this.mode = 'hunt';
    this.target = target;
    this.busy = true;
    this.epoch++;
    this.r.bot.pathfinder.setGoal(new goals.GoalFollow(target, 2), true);
  }

  release() {
    if (!this.mode) return;
    this.mode = null;
    this.target = null;
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
    const s = this.r.getSettings?.() || DEFAULTS;
    const near = seen.filter(shouldFight).sort((a, b) => a.position.distanceTo(me) - b.position.distanceTo(me))[0];
    const dist = near ? near.position.distanceTo(me) : Infinity;

    // Retreat until healthy again or nothing hostile is close.
    if (this.mode === 'retreat') {
      if (bot.health >= Math.min(20, s.retreatHealth + 4) || dist > 16) this.release();
      return;
    }
    if (near && bot.health < s.retreatHealth && dist <= 16) return this.takeover('retreat', near, 20);
    // Hunt: walk up to a hostile within the fight range (skeletons shoot from afar).
    if (this.mode === 'hunt' && (!near || !s.defend || dist > s.fightRange + 4 || near !== this.target)) this.release();
    if (this.mode === 'creeper' && (!near || near.name !== 'creeper' || dist > 8)) this.release();

    if (near && near.name === 'creeper' && dist < 6) return this.takeover('creeper', near, 8);
    if (near && s.defend && dist <= FIGHT_RANGE && (!this.busy || this.mode === 'hunt')) return this.fight(near);
    if (near && s.defend && dist <= s.fightRange && !this.busy && !this.r.inventoryBusy && !bot.currentWindow && !this.hazardNear(near.position)) return this.hunt(near);
    if (!this.busy && !near && !this.r.inventoryBusy && !bot.currentWindow) await this.eat();
  }

  async fight(target) {
    const bot = this.r.bot;
    // Swapping to a weapon (or striking) mid-dig leaves the dig running with the
    // wrong item: the server counts its slower break time and refuses the block, and
    // the bot waits for an answer that never comes. End the dig first; digAt() digs
    // again once the fight is over (2026-10-10).
    this.lastFight = Date.now();
    if (bot.targetDigBlock) bot.stopDigging();
    const weapon = bot.inventory.items().sort((a, b) => weaponScore(b.name) - weaponScore(a.name))[0];
    // Keep an axe or sword already in hand (a bot chopping with an axe fights
    // with it instead of swapping to the sword and then chopping with that).
    const armed = /_(axe|sword)$/.test(bot.heldItem?.name || '');
    if (!armed && !this.r.inventoryBusy && !bot.currentWindow && weapon && weaponScore(weapon.name) && bot.heldItem?.type !== weapon.type) await bot.equip(weapon, 'hand').catch(() => {});
    // Precision a player cannot match: swing exactly when the weapon is fully
    // charged (full damage, and a sword sweeps every mob around), and make it a
    // critical hit (x1.5, the sparkles) by jumping and striking on the way down.
    const cooldown = (bot.heldItem?.name.endsWith('_axe') ? 1000 : 625) + 30; // attack speed 1.0 / 1.6 per s, plus a tick of slack
    const wait = cooldown - (Date.now() - this.lastAttack);
    if (this.striking || target.isValid === false) return;
    const aim = () => bot.lookAt(target.position.offset(0, target.height * 0.8, 0), true).catch(() => {});
    await aim();
    if (wait > 450) return; // the next tick comes in 500 ms
    this.striking = true;
    try {
      if (wait > 0) await new Promise((res) => setTimeout(res, wait));
      // A sword sweep (ground hit) beats a crit when two or more hostiles stand together.
      const bunch = Object.values(bot.entities).filter((e) => e !== target && shouldFight(e) && e.position.distanceTo(target.position) <= 2).length;
      const sweep = bunch > 0 && bot.heldItem?.name.endsWith('_sword');
      const crit = !sweep && bot.entity.onGround && !bot.entity.isInWater && !bot.entity.isInLava && target.position.distanceTo(bot.entity.position) <= 3.2;
      if (crit) {
        bot.setControlState('jump', true);
        await bot.waitForTicks(1);
        bot.setControlState('jump', false);
        for (let i = 0; i < 12 && !(bot.entity.velocity.y < 0); i++) await bot.waitForTicks(1); // apex of the jump
      }
      if (target.isValid === false || target.position.distanceTo(bot.entity.position) > 3.6) return;
      await aim();
      this.lastAttack = Date.now();
      bot.attack(target);
      this.hits = (this.hits || 0) + 1;
      if (crit) this.crits = (this.crits || 0) + 1;
    } finally {
      bot.setControlState('jump', false);
      this.striking = false;
    }
  }

  async eat() {
    const bot = this.r.bot;
    if (this.eating || !wantsToEat(bot.food, bot.health, (this.r.getSettings?.() || DEFAULTS).eatBelow)) return;
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

module.exports = {Combat, weaponScore, AVOID_FOOD, wantsToEat, deathCause, fightReady};

'use strict';
// minecraft-data 26.1 gives every block that needs a better-than-wooden
// pickaxe (ores, metal and copper blocks, obsidian: 108 blocks) the material
// incorrect_for_wooden_tool, and that table lists the wooden shovel, pickaxe,
// axe and hoe at speed 2 instead of the pickaxe tiers. prismarine-block's
// digTime therefore found no speed bonus for a stone/iron/diamond pickaxe
// (iron_ore with an iron pickaxe took 4.5 s instead of 0.75 s) and rated a
// wooden axe as a good ore tool (2026-10-10). All those blocks are pickaxe
// blocks, so their table becomes mineable/pickaxe's. Harvest rules
// (harvestTools) are separate data and stay as they are. This runs only while
// the table lacks the iron pickaxe, so it switches itself off once upstream
// fixes the data.
const mcData = require('minecraft-data');

function fix(version) {
  const md = mcData(version);
  const bad = md?.materials?.incorrect_for_wooden_tool;
  const pick = md?.materials?.['mineable/pickaxe'];
  const iron = md?.itemsByName?.iron_pickaxe?.id;
  if (!bad || !pick || iron == null || bad[iron] != null) return false;
  for (const k of Object.keys(bad)) delete bad[k];
  Object.assign(bad, pick);
  return true;
}

fix('26.1'); // the protocol version bots.js connects with
module.exports = {fix};

'use strict';
// Minecraft 26.x sends an item's enchantments as a component object
// ({enchantments: [{id, level}]}), and prismarine-item 1.18 returns that
// object from Item#enchants. mineflayer's dig-time code expects an array and
// throws "enchantments.concat is not a function" whenever an enchanted tool
// is held, so bots could not dig with any enchanted kit tool (2026-10-08).
// This wraps the prismarine-item loader once, before mineflayer loads it, so
// every Item class returns [{name, lvl}]. Drop it when upstream handles the
// component form.
const id = require.resolve('prismarine-item');
const loader = require(id);

function normalize(value, registry) {
  if (Array.isArray(value)) return value;
  const list = value && Array.isArray(value.enchantments) ? value.enchantments : [];
  return list.map((e) => ({name: e.name ?? registry.enchantments?.[e.id]?.name ?? null, lvl: e.lvl ?? e.level ?? 0}));
}

function patched(registryOrVersion) {
  const Item = loader(registryOrVersion);
  const desc = Object.getOwnPropertyDescriptor(Item.prototype, 'enchants');
  if (desc?.get && !Item.prototype.__componentEnchants) {
    const registry = typeof registryOrVersion === 'string' ? require('prismarine-registry')(registryOrVersion) : registryOrVersion;
    Object.defineProperty(Item.prototype, 'enchants', {
      configurable: true,
      get() {
        return normalize(desc.get.call(this), registry);
      },
      set: desc.set,
    });
    Object.defineProperty(Item.prototype, '__componentEnchants', {value: true});
  }
  return Item;
}

require.cache[id].exports = patched;
module.exports = {normalize};

// The three memory stores (services/memory): the header switcher and [[store:path]] links between them.
// Links only point at the other store's page; no store ever fetches another (no CORS). Plain functions so node --test can check them.
(function (root) {
  const STORES = {
    vino: 'https://memory.tail7facc9.ts.net',
    albert: 'https://memory-albert.tail7facc9.ts.net',
    firma: 'https://memory-firma.tail7facc9.ts.net',
  };
  const storeOf = (host) => Object.keys(STORES).find((s) => STORES[s] === 'https://' + host);

  // Takes already escaped text: [[firma:projects/aiia]] becomes a link to that note on the firma store.
  const storeLinks = (escaped) => escaped.replace(/\[\[(vino|albert|firma):([^\]]+)\]\]/g, (_, s, p) =>
    `<a href="${STORES[s]}/notes/${p.replace(/^\/+/, '')}${p.endsWith('.md') ? '' : '.md'}">${s}:${p}</a>`);

  // Plain [[note]] links, run after storeLinks. No `"` in the match: it must never swallow the href of a link storeLinks made.
  const wikiLinks = (html) => html.replace(/\[\[([^\]"]+)\]\]/g, (_, t) => `<button class="link" data-open="${t}">${t}</button>`);

  function switcherHtml(host) {
    const cur = storeOf(host);
    return Object.keys(STORES).map((s) => `<a href="${STORES[s]}"${s === cur ? ' aria-current="page"' : ''}>${s}</a>`).join(' ');
  }

  if (typeof module !== 'undefined') module.exports = {STORES, storeLinks, wikiLinks, switcherHtml};
  else Object.assign(root, {storeLinks, wikiLinks, switcherHtml});
})(typeof window !== 'undefined' ? window : globalThis);

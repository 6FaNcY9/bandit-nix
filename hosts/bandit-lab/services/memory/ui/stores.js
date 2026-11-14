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

  // Task classification, the same rule as index.sh: a step with a who part not starting with "claude" is a human's,
  // every other one Claude's; "[/]" before "[ ]", file order otherwise. Tasks are {state, who, ...} as the page parses them.
  const isHuman = (who) => !!who && !/^claude/i.test(who);
  const isLate = (due, state, today) => !!due && due < today && state !== 'done';
  function nextSteps(tasks) {
    const todo = [...tasks.filter((t) => t.state === 'doing'), ...tasks.filter((t) => t.state === 'open')];
    return {human: todo.find((t) => isHuman(t.who)), claude: todo.find((t) => !isHuman(t.who))};
  }

  // The generated lagebild note (index.sh): project rows, plus which projects' waiting step is LATE.
  // Its cells are data from other stores: callers must esc() them.
  const COLS = ['project', 'store', 'status', 'open', 'doing', 'late', 'human', 'claude', 'repo', 'changed'];
  function parseLagebild(text) {
    const part = (h) => (text.split('\n## ' + h + '\n')[1] || '').split('\n## ')[0];
    const lateSteps = new Set([...part('Waiting for a human').matchAll(/^\d+\. (\S+) \((\S+)\): .* LATE \S+$/gm)].map((m) => m[2] + '/' + m[1]));
    const rows = part('Projects').split('\n').filter((l) => l.startsWith('| ') && !l.startsWith('| project |')).map((l) => {
      const cells = l.slice(1, -1).split('|').map((c) => c.trim());
      const r = Object.fromEntries(COLS.map((k, i) => [k, cells[i] === '-' ? '' : cells[i] || '']));
      for (const k of ['open', 'doing', 'late']) r[k] = +r[k] || 0;
      r.humanLate = lateSteps.has(r.store + '/' + r.project);
      return r;
    }).filter((r) => r.project && Object.hasOwn(STORES, r.store));
    return rows;
  }

  if (typeof module !== 'undefined') module.exports = {STORES, storeOf, storeLinks, wikiLinks, switcherHtml, isHuman, isLate, nextSteps, parseLagebild};
  else Object.assign(root, {STORES, storeOf, storeLinks, wikiLinks, switcherHtml, isHuman, isLate, nextSteps, parseLagebild});
})(typeof window !== 'undefined' ? window : globalThis);

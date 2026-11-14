// "Geräte" view of the memory page: the bandit-net device list from /bnet/devices (memory-web adds the
// router token server-side, the browser never sees it). Plain function so node --test can check it.
(function (root) {
  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'}[c]));
  // Pong Retro stripe colours, one per state.
  const STATES = {
    idle: ['frei', '#61bb46'], light: ['leicht genutzt', '#009ddc'], heavy: ['voll genutzt', '#e03a3e'],
    media: ['Film/Musik', '#963d97'], unavailable: ['niemand angemeldet', '#848488'],
  };
  const when = (iso) => (iso ? iso.slice(0, 16).replace('T', ' ') : 'nie');

  function devicesHtml(list) {
    if (!Array.isArray(list)) return '<p class="bad">bandit-net ist gerade nicht erreichbar.</p>';
    if (!list.length) return '<p>Keine Geräte eingetragen.</p>';
    const rows = list.map((d) => {
      const [label, col] = d.online ? (STATES[d.state] || ['online', '#61bb46']) : ['offline', '#848488'];
      return `<tr class="dev"><td><b>${esc(d.host)}</b><br><span class="dim">${esc(d.kind)}</span></td>` +
        `<td><span class="pill" style="border-color:${col};color:${col}">${esc(label)}</span></td>` +
        `<td>${d.job ? esc(d.job) : '<span class="dim">–</span>'}</td><td class="dim">${esc(when(d.last_seen))}</td></tr>`;
    }).join('');
    return '<div class="card"><h2>Geräte</h2><table><tr><th>Gerät</th><th>Zustand</th><th>Lab-Job</th><th>Zuletzt gesehen</th></tr>' +
      rows + '</table>' + (typeof location !== 'undefined'
        ? '<p class="dim">Hardware-Werte: <a href="https://beszel.' + esc(location.host.replace(/^memory\./, '')) + '">Beszel</a></p>' : '') + '</div>';
  }

  if (typeof module !== 'undefined') module.exports = {devicesHtml};
  else root.devicesHtml = devicesHtml;
})(typeof window !== 'undefined' ? window : globalThis);

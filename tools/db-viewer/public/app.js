// WatchLogs DB viewer — frontend. Vanilla JS, no build step: fetch the API,
// render a table, poll it while "Live" is on. Per-table column order/lock/
// sort/page-size preferences persist in localStorage; filters are session-only.

const state = {
  tables: [],
  currentTable: null,
  columns: [], // [{name, type, pk}]
  columnOrder: [], // column names, user-orderable
  lockedColumns: [], // column names pinned to the left, in lock order
  sort: { by: 'rowid', dir: 'desc' },
  filters: {}, // { [column]: string }
  globalFilter: '',
  page: 0,
  pageSize: 100,
  total: 0,
  knownRowIds: new Set(), // for new-row flash highlighting
  live: true,
  pollHandle: null,
  showingLint: false,
  showingReplay: false,
};

const el = (id) => document.getElementById(id);

function prefsKey(table) {
  return `watchlogs-db-viewer:${table}`;
}

function loadPrefs(table) {
  try {
    const raw = localStorage.getItem(prefsKey(table));
    return raw ? JSON.parse(raw) : {};
  } catch {
    return {};
  }
}

function savePrefs(table) {
  const prefs = {
    columnOrder: state.columnOrder,
    lockedColumns: state.lockedColumns,
    sort: state.sort,
    pageSize: state.pageSize,
  };
  localStorage.setItem(prefsKey(table), JSON.stringify(prefs));
}

// --- Networking -------------------------------------------------------------

async function fetchJson(url) {
  const res = await fetch(url);
  if (!res.ok) {
    const body = await res.json().catch(() => ({ error: res.statusText }));
    throw new Error(body.error || `HTTP ${res.status}`);
  }
  return res.json();
}

async function refreshTableList() {
  const { tables } = await fetchJson('/api/tables');
  state.tables = tables;
  renderTableList();
  setStatus(true);
}

async function loadTable(name) {
  hideLint();
  hideReplay();
  hideDayBoundary();
  state.currentTable = name;
  state.page = 0;
  state.filters = {};
  state.globalFilter = '';
  state.knownRowIds = new Set();

  const { columns } = await fetchJson(`/api/tables/${encodeURIComponent(name)}/columns`);
  state.columns = columns;

  const prefs = loadPrefs(name);
  const allNames = columns.map((c) => c.name);
  state.columnOrder = (prefs.columnOrder || allNames).filter((n) => allNames.includes(n));
  for (const n of allNames) if (!state.columnOrder.includes(n)) state.columnOrder.push(n);
  state.lockedColumns = (prefs.lockedColumns || []).filter((n) => allNames.includes(n));
  state.sort = prefs.sort && allNames.includes(prefs.sort.by) ? prefs.sort : { by: 'rowid', dir: 'desc' };
  state.pageSize = prefs.pageSize || 100;

  el('page-size').value = String(state.pageSize);
  el('global-filter').disabled = false;
  el('global-filter').value = '';
  el('table-title').textContent = name;
  el('empty-state').style.display = 'none';

  renderHeader();
  await refreshRows();
}

async function refreshRows() {
  if (!state.currentTable) return;
  const params = new URLSearchParams({
    limit: String(state.pageSize),
    offset: String(state.page * state.pageSize),
    sortBy: state.sort.by,
    sortDir: state.sort.dir,
  });
  const filters = { ...state.filters };
  if (state.globalFilter) filters.__any__ = state.globalFilter;
  if (Object.keys(filters).length) params.set('filters', JSON.stringify(filters));

  const data = await fetchJson(`/api/tables/${encodeURIComponent(state.currentTable)}/rows?${params}`);
  state.total = data.total;
  renderRows(data.rows);
  renderPager();
}

// --- Sidebar ------------------------------------------------------------

function renderTableList() {
  const list = el('table-list');
  list.innerHTML = '';
  for (const t of state.tables) {
    const li = document.createElement('li');
    li.className = 'table-item' + (t.name === state.currentTable ? ' active' : '');
    li.innerHTML = `<span class="table-name">${t.name}</span><span class="badge">${formatCount(t.count)}</span>`;
    li.addEventListener('click', () => {
      if (state.currentTable !== t.name) loadTable(t.name).catch(showError);
    });
    list.appendChild(li);
  }
}

function formatCount(n) {
  return n > 999 ? `${Math.floor(n / 1000)}k+` : String(n);
}

function setStatus(ok) {
  const dot = document.querySelector('#db-status .dot');
  dot.classList.toggle('ok', ok);
  dot.classList.toggle('bad', !ok);
  el('status-text').textContent = ok ? `live · ${new Date().toLocaleTimeString()}` : 'connection lost';
}

// --- Table header: reorder, lock, sort, filter ------------------------------

let dragColumn = null;

function renderHeader() {
  const headerRow = el('header-row');
  const filterRow = el('filter-row');
  headerRow.innerHTML = '';
  filterRow.innerHTML = '';

  const ordered = orderedColumns();

  for (const col of ordered) {
    const th = document.createElement('th');
    th.draggable = true;
    th.dataset.col = col.name;
    th.className = state.lockedColumns.includes(col.name) ? 'locked' : '';

    const lockBtn = document.createElement('button');
    lockBtn.className = 'lock-btn';
    lockBtn.title = state.lockedColumns.includes(col.name) ? 'Unlock column' : 'Lock column (pin to left)';
    lockBtn.textContent = state.lockedColumns.includes(col.name) ? '📌' : '📍';
    lockBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      toggleLock(col.name);
    });

    const label = document.createElement('span');
    label.className = 'col-label';
    label.textContent = col.name + (col.pk ? ' 🔑' : '');

    const sortIndicator = document.createElement('span');
    sortIndicator.className = 'sort-indicator';
    if (state.sort.by === col.name) sortIndicator.textContent = state.sort.dir === 'asc' ? ' ▲' : ' ▼';

    label.appendChild(sortIndicator);
    th.appendChild(lockBtn);
    th.appendChild(label);
    th.addEventListener('click', () => cycleSort(col.name));

    th.addEventListener('dragstart', () => { dragColumn = col.name; th.classList.add('dragging'); });
    th.addEventListener('dragend', () => th.classList.remove('dragging'));
    th.addEventListener('dragover', (e) => e.preventDefault());
    th.addEventListener('drop', (e) => {
      e.preventDefault();
      if (dragColumn && dragColumn !== col.name) reorderColumn(dragColumn, col.name);
    });

    headerRow.appendChild(th);

    const filterTh = document.createElement('th');
    const input = document.createElement('input');
    input.type = 'text';
    input.placeholder = 'filter…';
    input.value = state.filters[col.name] || '';
    input.addEventListener('input', debounce(() => {
      state.filters[col.name] = input.value;
      state.page = 0;
      refreshRows().catch(showError);
    }, 300));
    filterTh.appendChild(input);
    filterRow.appendChild(filterTh);
  }

  applyLockOffsets();
}

function orderedColumns() {
  const byName = new Map(state.columns.map((c) => [c.name, c]));
  const locked = state.lockedColumns.map((n) => byName.get(n)).filter(Boolean);
  const rest = state.columnOrder.filter((n) => !state.lockedColumns.includes(n)).map((n) => byName.get(n)).filter(Boolean);
  return [...locked, ...rest];
}

function toggleLock(name) {
  if (state.lockedColumns.includes(name)) {
    state.lockedColumns = state.lockedColumns.filter((n) => n !== name);
  } else {
    state.lockedColumns = [...state.lockedColumns, name];
  }
  savePrefs(state.currentTable);
  renderHeader();
  refreshRows().catch(showError);
}

function reorderColumn(dragged, target) {
  const withoutDragged = state.columnOrder.filter((n) => n !== dragged);
  const targetIndex = withoutDragged.indexOf(target);
  withoutDragged.splice(targetIndex, 0, dragged);
  state.columnOrder = withoutDragged;
  savePrefs(state.currentTable);
  renderHeader();
  refreshRows().catch(showError);
}

function cycleSort(name) {
  if (state.sort.by !== name) {
    state.sort = { by: name, dir: 'asc' };
  } else if (state.sort.dir === 'asc') {
    state.sort = { by: name, dir: 'desc' };
  } else {
    state.sort = { by: 'rowid', dir: 'desc' };
  }
  state.page = 0;
  savePrefs(state.currentTable);
  renderHeader();
  refreshRows().catch(showError);
}

// Sticky-position locked columns left-to-right, each offset by the running
// width of the locked columns before it.
function applyLockOffsets() {
  const headerCells = [...el('header-row').children];
  let offset = 0;
  for (const th of headerCells) {
    if (!th.classList.contains('locked')) continue;
    th.style.left = `${offset}px`;
    offset += th.getBoundingClientRect().width || 120;
  }
}

// --- Rows --------------------------------------------------------------

function renderRows(rows) {
  const body = el('data-body');
  const scroller = el('table-scroll');
  const savedScrollTop = scroller.scrollTop;

  body.innerHTML = '';
  const ordered = orderedColumns();
  const newIds = new Set();

  for (const row of rows) {
    newIds.add(row.__rowid__);
    const tr = document.createElement('tr');
    if (!state.knownRowIds.has(row.__rowid__) && state.knownRowIds.size > 0) {
      tr.className = 'flash';
    }
    let lockOffset = 0;
    for (const col of ordered) {
      const td = document.createElement('td');
      const value = row[col.name];
      td.textContent = value === null || value === undefined ? '' : String(value);
      if (value === null) td.classList.add('null-value');
      // Every table that carries a view_id is one click from the story behind
      // it. Following an id by hand — views, then raw_events, then segments,
      // pasting a UUID into three filter boxes — is how a lineage question
      // turns into ten minutes of clerical work.
      if (col.name === 'view_id' && value) {
        td.classList.add('linked');
        td.title = 'Replay this View';
        td.addEventListener('click', () => showReplay(String(value)));
      }
      if (state.lockedColumns.includes(col.name)) {
        td.classList.add('locked');
        td.style.left = `${lockOffset}px`;
        lockOffset += 120;
      }
      tr.appendChild(td);
    }
    body.appendChild(tr);
  }

  state.knownRowIds = newIds;
  el('empty-state').style.display = rows.length === 0 ? 'flex' : 'none';
  scroller.scrollTop = savedScrollTop;
  requestAnimationFrame(applyLockOffsets);
}

function renderPager() {
  const start = state.total === 0 ? 0 : state.page * state.pageSize + 1;
  const end = Math.min(state.total, (state.page + 1) * state.pageSize);
  el('pager-summary').textContent = `${start}–${end} of ${state.total}`;
  el('prev-page').disabled = state.page === 0;
  el('next-page').disabled = end >= state.total;
}

// --- Utilities -----------------------------------------------------------

function debounce(fn, ms) {
  let timer;
  return (...args) => {
    clearTimeout(timer);
    timer = setTimeout(() => fn(...args), ms);
  };
}

function showError(err) {
  console.error(err);
  el('status-text').textContent = err.message;
  setStatus(false);
}

// --- Lint -------------------------------------------------------------------
// The same checks the `tools/lint` CLI runs, rendered here so a Flush landing
// badly is visible in the same place you were already watching it land.

const SEVERITY_ORDER = { high: 0, medium: 1, low: 2 };

async function refreshLint() {
  const report = await fetchJson('/api/lint');
  const total = report.results.reduce((n, r) => n + r.findings.length, 0);
  el('lint-badge').textContent = formatCount(total);
  el('lint-badge').classList.toggle(
    'bad',
    report.results.some((r) => r.severity === 'high' && r.findings.length),
  );
  if (state.showingLint) renderLint(report);
  setStatus(true);
}

function renderLint(report) {
  const panel = el('lint-panel');
  const found = report.results
    .filter((result) => result.findings.length || result.error)
    .sort((a, b) => SEVERITY_ORDER[a.severity] - SEVERITY_ORDER[b.severity]);

  if (!found.length) {
    panel.innerHTML = '<p class="lint-clean">Nothing to report — every check passed.</p>';
    return;
  }

  const share = report.totalMs
    ? `${Math.round(report.implicatedMs / 60000)} min of ${Math.round(report.totalMs / 60000)} min recorded ` +
      `(${Math.round((report.implicatedMs / report.totalMs) * 100)}%) sits in a Segment some check flags`
    : '';

  panel.innerHTML =
    `<p class="lint-summary">${share}</p>` +
    found
      .map((result) => {
        const cost = result.costMs ? ` · ${(result.costMs / 60000).toFixed(1)} min in doubt` : '';
        const body = result.error
          ? `<p class="lint-error">could not run: ${escapeHtml(result.error)}</p>`
          : `<ul class="lint-findings">${result.findings
              .slice(0, 50)
              .map((finding) => `<li>${escapeHtml(finding.summary)}</li>`)
              .join('')}${
              result.findings.length > 50
                ? `<li class="lint-more">… and ${result.findings.length - 50} more</li>`
                : ''
            }</ul>`;
        return (
          `<section class="lint-check ${result.severity}">` +
          `<h3><span class="lint-sev">${result.severity}</span> ${escapeHtml(result.title)}` +
          `<span class="lint-count">${result.findings.length} found${cost}</span></h3>` +
          `<p class="lint-why">${escapeHtml(result.why)}</p>${body}</section>`
        );
      })
      .join('');
}

function escapeHtml(text) {
  return String(text).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
}

async function showLint() {
  hideReplay();
  hideDayBoundary();
  state.showingLint = true;
  state.currentTable = null;
  el('table-title').textContent = 'Lint — what the data must never say';
  el('data-table').hidden = true;
  el('pager').hidden = true;
  el('empty-state').style.display = 'none';
  el('lint-panel').hidden = false;
  el('global-filter').disabled = true;
  el('lint-item').classList.add('active');
  renderTableList();
  await refreshLint();
}

/** Leaving the lint panel for an ordinary table view. */
function hideLint() {
  state.showingLint = false;
  el('data-table').hidden = false;
  el('pager').hidden = false;
  el('lint-panel').hidden = true;
  el('lint-item').classList.remove('active');
}

// --- Replay -----------------------------------------------------------------
// One View, all the way down the pipeline. The report comes from the wl-replay
// binary, which calls the shipped SegmentComputer and read model — so what is
// rendered here is what the app itself would compute, not a second opinion.
//
// Results and report are two panes, not one. Rendering both into the same
// element meant picking a match threw the other matches away: three Views share
// the title "MoErgo Go60 — long term review", and choosing the wrong one first
// left nothing to go back to.

const replay = { query: '', views: [], selected: null };

async function showReplay(viewId = null) {
  hideDayBoundary();
  state.showingReplay = true;
  state.showingLint = false;
  state.currentTable = null;
  el('table-title').textContent = 'Replay — one View, all the way down';
  el('data-table').hidden = true;
  el('pager').hidden = true;
  el('empty-state').style.display = 'none';
  el('lint-panel').hidden = true;
  el('lint-item').classList.remove('active');
  el('replay-panel').hidden = false;
  el('global-filter').disabled = true;
  el('replay-item').classList.add('active');
  renderTableList();

  try {
    // Arriving with a View in hand — a view_id clicked in some table — the
    // query is not the user's and must not be overwritten with a UUID they
    // then have to clear before they can search again.
    if (!replay.views.length) await runSearch(replay.query);
    if (viewId) await openReport(viewId);
    setStatus(true);
  } catch (err) {
    el('replay-body').innerHTML = `<p class="replay-error">${escapeHtml(err.message)}</p>`;
  }
}

async function runSearch(query) {
  replay.query = query;
  const { views } = await fetchJson(`/api/replay?find=${encodeURIComponent(query)}`);
  replay.views = views ?? [];
  renderResults();
}

function renderResults() {
  const results = el('replay-results');
  const count = el('replay-count');

  if (!replay.views.length) {
    count.textContent = '';
    results.innerHTML = replay.query
      ? `<p class="replay-loading">Nothing matches “${escapeHtml(replay.query)}”. ` +
        'Every word has to appear somewhere in the title, author, id or video id — ' +
        'matching is literal, so a misspelling finds nothing. Try fewer words.</p>'
      : '<p class="replay-loading">No Views recorded yet.</p>';
    return;
  }

  count.textContent = replay.query
    ? `${replay.views.length} View${replay.views.length === 1 ? '' : 's'} match`
    : `${replay.views.length} most recent Views`;

  results.innerHTML =
    '<table class="replay-list"><tbody>' +
    replay.views
      .map(
        (view) =>
          `<tr data-view="${escapeHtml(view.viewId)}"` +
          `${view.viewId === replay.selected ? ' class="selected"' : ''}>` +
          `<td class="mono">${escapeHtml(view.viewId.slice(0, 8))}</td>` +
          `<td>${escapeHtml(clockTime(view.startedAtMs))}</td>` +
          `<td class="dim">tab ${view.tabId}</td>` +
          `<td>${escapeHtml(view.title ?? view.videoId)}</td>` +
          `<td class="dim">${view.open ? 'open' : ''}</td></tr>`
      )
      .join('') +
    '</tbody></table>';
}

/** Show one View's report, leaving the matches you chose it from on screen. */
async function openReport(viewId) {
  replay.selected = viewId;
  renderResults();
  el('replay-body').innerHTML = '<p class="replay-loading">…</p>';
  try {
    renderReplay(await fetchJson(`/api/replay?view=${encodeURIComponent(viewId)}`));
    setStatus(true);
  } catch (err) {
    el('replay-body').innerHTML = `<p class="replay-error">${escapeHtml(err.message)}</p>`;
  }
}

function clockTime(ms) {
  return new Date(ms).toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
    second: '2-digit',
  });
}

/** Milliseconds the way wl-replay prints them, so the two agree on screen. */
function ms(value) {
  if (value === null || value === undefined) return '—';
  const seconds = value / 1000;
  if (Math.abs(seconds) < 60) return `${seconds.toFixed(1)}s`;
  const whole = Math.trunc(seconds);
  return `${Math.trunc(whole / 60)}m${String(Math.abs(whole % 60)).padStart(2, '0')}s`;
}

function pos(value) {
  return value === null || value === undefined ? '—' : value.toFixed(1);
}


function renderReplay(report) {
  const view = report.view;
  const parts = [view.author, view.service, view.contentFormat].filter(Boolean);
  if (view.embedded) parts.push('embedded');

  const header =
    `<section class="replay-section"><h3>View <span class="mono dim">${escapeHtml(view.viewId)}</span></h3>` +
    `<p class="replay-title">${escapeHtml(view.title ?? 'Untitled')}</p>` +
    `<p class="dim">${escapeHtml(parts.join(' · '))}</p>` +
    `<p class="dim">tab ${view.tabId} · started ${escapeHtml(clockTime(view.startedAtMs))} · ` +
    `${view.open ? '<span class="flag">open</span>' : 'closed'}</p>` +
    `<p class="dim mono">video ${escapeHtml(view.videoId)} · duration ` +
    `${view.durationSec ? `${view.durationSec.toFixed(1)}s` : '—'} · metadata ` +
    `${escapeHtml(view.metadataSource ?? '—')}/${escapeHtml(view.adapterId ?? 'no adapter')}</p>` +
    (view.identityIsHash
      ? '<p class="flag">identity is a page-address hash — the page named no video when this View opened</p>'
      : '') +
    '</section>';

  const events =
    `<section class="replay-section"><h3>Events <span class="dim">${report.events.length} recorded</span></h3>` +
    '<table class="replay-table"><thead><tr><th>seq</th><th>time</th><th class="num">Δwall</th>' +
    '<th class="num">Δmedia</th><th>type</th><th class="num">pos</th><th></th></tr></thead><tbody>' +
    report.events
      .map(
        (event) =>
          `<tr${event.warning ? ' class="warn-row"' : ''}>` +
          `<td class="num dim">${event.seq}</td>` +
          `<td>${escapeHtml(clockTime(event.tMs))}</td>` +
          `<td class="num">${ms(event.deltaWallMs)}</td>` +
          `<td class="num">${ms(event.deltaMediaMs == null ? null : Math.max(0, event.deltaMediaMs))}</td>` +
          `<td class="mono">${escapeHtml(event.type)}</td>` +
          `<td class="num">${pos(event.pos)}</td>` +
          `<td class="dim">${escapeHtml(event.detail ?? '')}` +
          (event.warning ? ` <span class="flag">⚠ ${escapeHtml(event.warning)}</span>` : '') +
          '</td></tr>'
      )
      .join('') +
    '</tbody></table></section>';

  const segmentTable = (rows) =>
    '<table class="replay-table"><tbody>' +
    (rows.length
      ? rows
          .map(
            (segment) =>
              `<tr${segment.warning ? ' class="warn-row"' : ''}><td class="mono">${segment.kind}</td>` +
              `<td>${escapeHtml(clockTime(segment.wallStartMs))} → ${escapeHtml(clockTime(segment.wallEndMs))}</td>` +
              `<td class="num">${ms(segment.durationMs)}</td>` +
              `<td class="dim">pos ${pos(segment.posStart)} → ${pos(segment.posEnd)}</td>` +
              `<td class="dim">media ${ms(segment.mediaMs == null ? null : Math.max(0, segment.mediaMs))}</td>` +
              `<td class="dim">${segment.provisional ? 'provisional' : ''}` +
              (segment.warning ? ` <span class="flag">⚠ ${escapeHtml(segment.warning)}</span>` : '') +
              '</td></tr>'
          )
          .join('')
      : '<tr><td class="dim">none</td></tr>') +
    '</tbody></table>';

  const segments =
    '<section class="replay-section"><h3>Segments ' +
    `<span class="dim">${report.storedSegments.length} stored · ` +
    `${report.recomputedSegments.length} recomputed by this build</span></h3>` +
    segmentTable(report.storedSegments) +
    (report.recomputeDiffers
      ? '<p class="flag">this build would derive something different from the same Events:</p>' +
        segmentTable(report.recomputedSegments) +
        `<p class="flag">Watched: ${ms(report.storedWatchedMs)} stored → ${ms(report.recomputedWatchedMs)} ` +
        'recomputed — the stored Segments were written by an older build</p>'
      : '') +
    '</section>';

  const history = report.history;
  let historyHtml = '<section class="replay-section"><h3>History <span class="dim">what the popover renders</span></h3>';
  if (!history) {
    historyHtml += '<p class="dim">no History row — this View contributed no Watched time to its Day</p>';
  } else {
    const badges = [];
    if (history.contentFormat === 'live') badges.push('live');
    if (history.embedded) badges.push('embedded');
    const progress =
      history.coverage === null || history.coverage === undefined
        ? history.statusLabel
        : `bar ${(history.coverage * 100).toFixed(0)}%`;
    historyHtml +=
      `<p class="replay-title">${escapeHtml(history.title ?? 'Untitled')}</p>` +
      `<p>${ms(history.watchedMs)} · ${escapeHtml(progress)}` +
      (badges.length ? ` · ${escapeHtml(badges.join(' · '))}` : '') +
      ` · <span class="dim">day ${escapeHtml(history.dayLabel)}</span></p>`;

    if (history.fold.length > 1) {
      historyHtml +=
        `<p class="dim">folded from ${history.fold.length} Views:</p>` +
        '<table class="replay-table"><tbody>' +
        history.fold
          .map(
            (member) =>
              `<tr data-view="${escapeHtml(member.viewId)}" class="linked-row">` +
              `<td>${member.isSubject ? '→' : ''}</td>` +
              `<td class="mono">${escapeHtml(member.viewId.slice(0, 8))}</td>` +
              `<td class="num">${member.durationSec ? `${member.durationSec.toFixed(1)}s` : '—'}</td>` +
              `<td>${escapeHtml(member.title ?? member.videoId)}</td>` +
              `<td>${member.sameVideo ? '' : '<span class="flag">← a different video</span>'}</td></tr>`
          )
          .join('') +
        '</tbody></table>' +
        (history.knownDurationSec
          ? `<p class="dim">the bar is measured against ${history.knownDurationSec.toFixed(1)}s — ` +
            'the longest duration in the fold</p>'
          : '');
    }
  }
  historyHtml += '</section>';

  const body = el('replay-body');
  body.innerHTML = header + events + segments + historyHtml;
  for (const row of body.querySelectorAll('tr[data-view]')) {
    row.addEventListener('click', () => openReport(row.dataset.view));
  }
}

/** Leaving Replay for an ordinary table view. */
function hideReplay() {
  state.showingReplay = false;
  el('replay-panel').hidden = true;
  el('replay-item').classList.remove('active');
}

// --- Day Boundary Diagnostics ----------------------------------------------

const dayBoundaryState = {
  date: new Date().toISOString().slice(0, 10),
  targetHour: 4,
  windowMinutes: 90,
};

async function showDayBoundary() {
  hideLint();
  hideReplay();
  hideDayBoundary();

  state.currentTable = null;
  el('table-title').textContent = '📅 Day Boundary Diagnostics';
  el('global-filter').disabled = true;
  el('empty-state').style.display = 'none';
  el('data-table').style.display = 'none';
  el('pager').style.display = 'none';
  el('day-boundary-panel').hidden = false;
  el('day-boundary-item').classList.add('active');

  await refreshDayBoundary();
}

async function refreshDayBoundary() {
  renderDayBoundaryLoading();
  const params = new URLSearchParams({
    date: dayBoundaryState.date,
    targetHour: String(dayBoundaryState.targetHour),
    windowMinutes: String(dayBoundaryState.windowMinutes),
  });

  try {
    const data = await fetchJson(`/api/day-boundary?${params}`);
    renderDayBoundary(data);
    setStatus(true);
  } catch (err) {
    el('day-boundary-panel').innerHTML = `<p class="replay-error">${escapeHtml(err.message)}</p>`;
  }
}

function renderDayBoundaryLoading() {
  el('day-boundary-panel').innerHTML =
    `<div class="day-boundary-content">` +
    dayBoundaryControlsHtml() +
    '<p class="replay-loading">Analyzing…</p></div>';
  wireDayBoundaryControls();
}

function hideDayBoundary() {
  el('day-boundary-panel').hidden = true;
  el('day-boundary-item').classList.remove('active');
  el('data-table').style.display = '';
  el('pager').style.display = '';
}

function renderDayBoundary(data) {
  const {
    config,
    summary,
    timeline,
    crossingSegment,
    newestActivity,
    fixAnalysis,
    actualResult,
    expectedResult,
    segmentsAtCriticalMoment,
  } = data;

  let html = '<div class="day-boundary-content">';
  html += dayBoundaryControlsHtml();

  html += '<section class="replay-section">';
  html += '<h2>Boundary analysis</h2>';
  html += `<p>${escapeHtml(summary)}</p>`;
  html += '<table class="replay-table"><tbody>';
  html += `<tr><td>Date</td><td class="mono">${escapeHtml(config.date)}</td></tr>`;
  html += `<tr><td>Target hour</td><td class="mono">${escapeHtml(config.target)}</td></tr>`;
  html += `<tr><td>Boundary window</td><td>${config.boundaryWindowMinutes} min</td></tr>`;
  html += `<tr><td>Expected logical date</td><td class="mono">${escapeHtml(config.logicalDateExpected)}</td></tr>`;
  html += '</tbody></table>';
  html += '</section>';

  html += '<section class="replay-section">';
  html += '<h3>Timeline</h3>';
  html += '<table class="replay-table"><thead><tr><th>Time</th><th>Event</th></tr></thead><tbody>';
  for (const event of timeline) {
    const rowClass = event.event.toLowerCase().includes('race') ? ' class="warn-row"' : '';
    html += `<tr${rowClass}><td class="mono">${escapeHtml(event.time)}</td><td>${escapeHtml(event.event)}</td></tr>`;
  }
  html += '</tbody></table></section>';

  if (crossingSegment) {
    html += '<section class="replay-section">';
    html += '<h3>Crossing segment</h3><table class="replay-table"><tbody>';
    html += `<tr><td>View</td><td class="mono">${escapeHtml(crossingSegment.viewId)}</td></tr>`;
    html += `<tr><td>Start</td><td class="mono">${escapeHtml(crossingSegment.start)}</td></tr>`;
    html += `<tr><td>End</td><td class="mono">${escapeHtml(crossingSegment.end)}</td></tr>`;
    html += `<tr><td>First flush for this view</td><td class="mono">${escapeHtml(crossingSegment.firstFlush ?? '—')}</td></tr>`;
    html += `<tr><td>Arrived before first post-target flush?</td><td>${crossingSegment.arrivedBeforeFirstPostTargetFlush ? '✅ Yes' : '❌ No'}</td></tr>`;
    html += '</tbody></table></section>';
  }

  if (newestActivity) {
    html += '<section class="replay-section">';
    html += '<h3>Newest activity before critical flush</h3><table class="replay-table"><tbody>';
    html += `<tr><td>Timestamp</td><td class="mono">${escapeHtml(newestActivity.timestamp)}</td></tr>`;
    html += `<tr><td>Minutes from target</td><td>${newestActivity.minutesFromTarget}</td></tr>`;
    html += `<tr><td>Within boundary window?</td><td>${newestActivity.withinBoundaryWindow ? '✅ Yes' : 'No'}</td></tr>`;
    html += '</tbody></table></section>';
  }

  if (fixAnalysis) {
    html += '<section class="replay-section">';
    html += '<h3>Fix behavior</h3><table class="replay-table"><tbody>';
    html += `<tr><td>Activity within window?</td><td>${fixAnalysis.activityWithinWindow ? '✅ Yes' : 'No'}</td></tr>`;
    html += `<tr><td>Wait until</td><td class="mono">${escapeHtml(fixAnalysis.windowEnd)}</td></tr>`;
    html += '</tbody></table>';
    html += `<p>${escapeHtml(fixAnalysis.fixBehavior)}</p>`;
    html += '</section>';
  }

  html += '<section class="replay-section"><h3>Actual vs expected</h3><div style="display:grid;grid-template-columns:1fr 1fr;gap:1rem;">';
  html += '<div><h4>Actual frozen day</h4>';
  html += actualResult
    ? `<table class="replay-table"><tbody>
        <tr><td>Date</td><td class="mono">${escapeHtml(actualResult.date)}</td></tr>
        <tr><td>Start</td><td class="mono">${escapeHtml(actualResult.start)}</td></tr>
        <tr><td>End</td><td class="mono">${escapeHtml(actualResult.end)}</td></tr>
      </tbody></table>`
    : '<p class="dim">No rolled_day row found for that logical date.</p>';
  html += '</div>';
  html += '<div><h4>Expected if activity slides boundary</h4>';
  html += expectedResult
    ? `<table class="replay-table"><tbody>
        <tr><td>Last activity</td><td class="mono">${escapeHtml(expectedResult.lastActivity)}</td></tr>
        <tr><td>Should end</td><td class="mono">${escapeHtml(expectedResult.shouldEndAt)}</td></tr>
        <tr><td>Slide</td><td>+${expectedResult.slidMinutes} min</td></tr>
      </tbody></table>`
    : '<p class="dim">No watched activity found near this boundary.</p>';
  html += '</div></div></section>';

  if (segmentsAtCriticalMoment?.length) {
    html += '<section class="replay-section"><h3>Watched segments before first post-target flush</h3>';
    html += '<table class="replay-table"><thead><tr><th>Start</th><th>End</th><th>Crosses boundary?</th></tr></thead><tbody>';
    for (const seg of segmentsAtCriticalMoment.slice(0, 20)) {
      html += `<tr${seg.crossesBoundary ? ' class="warn-row"' : ''}><td class="mono">${escapeHtml(seg.start)}</td><td class="mono">${escapeHtml(seg.end)}</td><td>${seg.crossesBoundary ? '✅ Yes' : ''}</td></tr>`;
    }
    html += '</tbody></table></section>';
  }

  html += '</div>';
  el('day-boundary-panel').innerHTML = html;
  wireDayBoundaryControls();
}

function dayBoundaryControlsHtml() {
  return (
    '<section class="replay-section">' +
    '<h3>Analyze boundary</h3>' +
    '<div style="display:flex;gap:8px;align-items:end;flex-wrap:wrap;">' +
    `<label>Date<br><input id="db-day-date" type="date" value="${escapeHtml(dayBoundaryState.date)}"></label>` +
    `<label>Target hour<br><input id="db-day-hour" type="number" min="0" max="23" value="${dayBoundaryState.targetHour}" style="width:80px"></label>` +
    `<label>Window min<br><input id="db-day-window" type="number" min="1" max="240" value="${dayBoundaryState.windowMinutes}" style="width:90px"></label>` +
    '<button id="db-day-run">Run</button>' +
    '</div></section>'
  );
}

function wireDayBoundaryControls() {
  const run = el('db-day-run');
  if (!run) return;

  run.onclick = () => {
    const date = el('db-day-date').value;
    const hour = Number(el('db-day-hour').value);
    const windowMinutes = Number(el('db-day-window').value);
    if (date) dayBoundaryState.date = date;
    dayBoundaryState.targetHour = Number.isFinite(hour) ? Math.max(0, Math.min(23, hour)) : 4;
    dayBoundaryState.windowMinutes = Number.isFinite(windowMinutes) ? Math.max(1, Math.min(240, windowMinutes)) : 90;
    refreshDayBoundary().catch(showError);
  };
}

// --- Polling ---------------------------------------------------------------

function startPolling() {
  stopPolling();
  state.pollHandle = setInterval(async () => {
    try {
      await refreshTableList();
      await refreshLint();
      // Replay is a report about one moment, not a feed. Re-fetching it under
      // the reader would move the rows they are reading.
      if (state.currentTable) await refreshRows();
    } catch (err) {
      showError(err);
    }
  }, 2000);
}

function stopPolling() {
  if (state.pollHandle) clearInterval(state.pollHandle);
  state.pollHandle = null;
}

// --- Wiring ------------------------------------------------------------

el('live-toggle').addEventListener('change', (e) => {
  state.live = e.target.checked;
  if (state.live) startPolling();
  else stopPolling();
});

el('lint-item').addEventListener('click', () => {
  if (!state.showingLint) showLint().catch(showError);
});

el('replay-item').addEventListener('click', () => {
  if (!state.showingReplay) showReplay().catch(showError);
});

el('day-boundary-item').addEventListener('click', () => {
  showDayBoundary().catch(showError);
});

el('replay-results').addEventListener('click', (e) => {
  const row = e.target.closest('tr[data-view]');
  if (row) openReport(row.dataset.view);
});

el('replay-find').addEventListener('input', debounce((e) => {
  // A new search is a new question: the report below belongs to the old one.
  replay.selected = null;
  el('replay-body').innerHTML = '';
  runSearch(e.target.value.trim()).catch((err) => {
    el('replay-results').innerHTML = `<p class="replay-error">${escapeHtml(err.message)}</p>`;
  });
}, 350));

el('refresh-btn').addEventListener('click', () => {
  refreshTableList().catch(showError);
  refreshLint().catch(showError);
  if (state.currentTable) refreshRows().catch(showError);
});

el('global-filter').addEventListener('input', debounce((e) => {
  state.globalFilter = e.target.value;
  state.page = 0;
  refreshRows().catch(showError);
}, 300));

el('page-size').addEventListener('change', (e) => {
  state.pageSize = Number(e.target.value);
  state.page = 0;
  savePrefs(state.currentTable);
  refreshRows().catch(showError);
});

el('prev-page').addEventListener('click', () => {
  if (state.page > 0) {
    state.page -= 1;
    refreshRows().catch(showError);
  }
});

el('next-page').addEventListener('click', () => {
  state.page += 1;
  refreshRows().catch(showError);
});

// --- Boot ------------------------------------------------------------------

refreshTableList()
  .then(() => refreshLint())
  .then(() => startPolling())
  .catch(showError);

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

// --- Polling ---------------------------------------------------------------

function startPolling() {
  stopPolling();
  state.pollHandle = setInterval(async () => {
    try {
      await refreshTableList();
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

el('refresh-btn').addEventListener('click', () => {
  refreshTableList().catch(showError);
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
  .then(() => startPolling())
  .catch(showError);

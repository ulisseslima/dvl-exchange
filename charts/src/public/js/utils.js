// Shared utilities for charts pages
async function apiPost(path, body){
  const res = await fetch(path, { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(body) })
  if (!res.ok) throw new Error(await res.text())
  return res.json()
}

function exportCSV(cols, rows, filename='export.csv'){
  const csv = [cols.join(',')].concat(rows.map(r => r.map(c => '"'+String(c).replace(/"/g,'""')+'"').join(','))).join('\n')
  const blob = new Blob([csv], { type: 'text/csv' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a'); a.href = url; a.download = filename; document.body.appendChild(a); a.click(); a.remove(); URL.revokeObjectURL(url)
}

function renderTable(container, cols, rows){
  const wrap = typeof container === 'string' ? document.getElementById(container) : container
  wrap.innerHTML = ''
  const table = document.createElement('table'); table.className='striped responsive-table'
  const thead = document.createElement('thead'); const thr = document.createElement('tr')
  cols.forEach(c=>{const th=document.createElement('th'); th.textContent=c; thr.appendChild(th)})
  thead.appendChild(thr); table.appendChild(thead)
  const tb = document.createElement('tbody')
  rows.forEach(r=>{ const tr=document.createElement('tr'); r.forEach(cell=>{ const td=document.createElement('td'); td.textContent = cell==null ? '' : cell; tr.appendChild(td)}); tb.appendChild(tr) })
  table.appendChild(tb)
  wrap.appendChild(table)
}

function drawChart(canvasId, cols, rows, labelColIndex, valueColIndex, type='bar', options={}){
  const ctx = document.getElementById(canvasId).getContext('2d')
  if (window._currentChart){ window._currentChart.destroy(); window._currentChart=null }
  const labels = rows.map(r=> r[labelColIndex])
  const data = rows.map(r=> { const v = r[valueColIndex]; if (typeof v==='number') return v; const s=String(v||'').replace(/[^0-9.-]+/g,''); return s===''?0:parseFloat(s) })
  window._currentChart = new Chart(ctx, { type, data:{ labels, datasets:[{ label: cols[valueColIndex]||'value', data, backgroundColor:'rgba(54,162,235,0.6)'}]}, options: Object.assign({ responsive:true }, options) })
  return window._currentChart
}

function populateSelect(selectId, items, includeEmpty=false){
  const sel = document.getElementById(selectId)
  sel.innerHTML=''
  if (includeEmpty){ const o = document.createElement('option'); o.value=''; o.textContent=''; sel.appendChild(o) }
  items.forEach(it=>{ const o = document.createElement('option'); o.value = it.value ?? it; o.textContent = it.label ?? it; sel.appendChild(o) })
}

// --- Filter persistence & named presets ---

// Collect all [data-filter] elements into a plain object
function collectFilters() {
  const f = {}
  document.querySelectorAll('[data-filter]').forEach(el => {
    const k = el.dataset.filter
    f[k] = el.type === 'checkbox' ? el.checked : el.value
  })
  return f
}

// Restore [data-filter] elements from a plain object
function applyFilters(f) {
  if (!f) return
  const selects = []
  document.querySelectorAll('[data-filter]').forEach(el => {
    const k = el.dataset.filter
    if (!(k in f)) return
    if (el.type === 'checkbox') el.checked = !!f[k]
    else { el.value = f[k]; if (el.tagName === 'SELECT') selects.push(el) }
  })
  if (selects.length && window.M) M.FormSelect.init(selects)
}

function _escHtml(s) {
  return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;')
}

// pageKey   : unique key per page, e.g. 'cheapest', 'position'
// extraHooks: { getExtra?: () => object, onRestore?: (data) => void }
//   getExtra  – returns extra fields (e.g. excludeTickerIds) to merge when saving
//   onRestore – called with the full saved object so pages can restore extras (e.g. chips)
// Returns saveCurrentFilters() — call it after each Run to persist last-used state.
function initFilterPersistence(pageKey, extraHooks = {}) {
  const LS_LAST    = `dvl:last:${pageKey}`
  const LS_PRESETS = `dvl:presets:${pageKey}`

  function getPresetsMap() {
    try { return JSON.parse(localStorage.getItem(LS_PRESETS) || '{}') } catch { return {} }
  }
  function savePresetsMap(map) {
    localStorage.setItem(LS_PRESETS, JSON.stringify(map))
  }
  function getCurrentData() {
    const f = collectFilters()
    if (extraHooks.getExtra) Object.assign(f, extraHooks.getExtra())
    return f
  }
  function restoreData(data) {
    applyFilters(data)
    if (extraHooks.onRestore) extraHooks.onRestore(data)
  }

  // Restore last-used filters immediately (called after M.FormSelect.init)
  const lastData = (() => { try { return JSON.parse(localStorage.getItem(LS_LAST) || 'null') } catch { return null } })()
  if (lastData) restoreData(lastData)

  // Render presets panel if the placeholder exists
  const panel = document.getElementById('presets-panel')
  if (panel) _renderPresetsUI(panel)

  function _renderPresetsUI(container) {
    const presets = getPresetsMap()
    const names = Object.keys(presets)
    container.innerHTML = `
      <div style="display:flex;align-items:center;gap:6px;flex-wrap:wrap;padding:4px 0">
        <span class="grey-text text-darken-1" style="font-size:13px;white-space:nowrap">Presets:</span>
        <select id="_ps_select" style="display:inline-block;height:32px;padding:0 6px;border:1px solid #bbb;border-radius:4px;background:#fff;min-width:150px;font-size:13px">
          <option value="">— load preset —</option>
          ${names.map(n => `<option value="${_escHtml(n)}">${_escHtml(n)}</option>`).join('')}
        </select>
        <button class="btn-small btn waves-effect waves-light" id="_ps_load" style="height:32px;line-height:32px">Load</button>
        <button class="btn-small btn red lighten-1 waves-effect waves-light" id="_ps_del" style="height:32px;line-height:32px">Delete</button>
        <span style="flex:1;min-width:12px"></span>
        <input id="_ps_name" placeholder="Preset name…" style="margin:0;height:32px;width:140px;font-size:13px;border-bottom:1px solid #bbb;padding:0 4px">
        <button class="btn-small btn green darken-1 waves-effect waves-light" id="_ps_save" style="height:32px;line-height:32px">Save preset</button>
      </div>`

    container.querySelector('#_ps_load').addEventListener('click', () => {
      const name = container.querySelector('#_ps_select').value
      if (!name) return
      const data = getPresetsMap()[name]
      if (data) restoreData(data)
    })
    container.querySelector('#_ps_del').addEventListener('click', () => {
      const name = container.querySelector('#_ps_select').value
      if (!name) return
      const map = getPresetsMap(); delete map[name]; savePresetsMap(map)
      _renderPresetsUI(container)
    })
    container.querySelector('#_ps_save').addEventListener('click', () => {
      const name = container.querySelector('#_ps_name').value.trim()
      if (!name) return
      const map = getPresetsMap(); map[name] = getCurrentData(); savePresetsMap(map)
      container.querySelector('#_ps_name').value = ''
      _renderPresetsUI(container)
    })
  }

  return function saveCurrentFilters() {
    localStorage.setItem(LS_LAST, JSON.stringify(getCurrentData()))
  }
}

// Ticker exclusion chip component
// containerId: ID of the div to render into
// Returns { getExcluded, setExcluded }
async function initTickerExclude(containerId) {
  const container = document.getElementById(containerId)
  if (!container) return { getExcluded: () => [], setExcluded: () => {} }

  container.innerHTML = `
    <div class="input-field" style="display:flex;gap:8px;align-items:flex-end;flex-wrap:wrap">
      <div style="flex:1;min-width:200px">
        <input type="text" id="_te_input" class="autocomplete" placeholder="Type ticker name to exclude...">
        <label for="_te_input">Exclude Tickers</label>
      </div>
      <div id="_te_chips" style="display:flex;gap:4px;flex-wrap:wrap"></div>
    </div>`

  let tickers = []
  try {
    const res = await fetch('/api/tickers')
    tickers = await res.json()
  } catch (e) { console.error('Failed to load tickers', e) }

  const excluded = new Map() // id -> name
  const chipsEl = document.getElementById('_te_chips')
  const inputEl = document.getElementById('_te_input')

  function renderChips() {
    chipsEl.innerHTML = ''
    excluded.forEach((name, id) => {
      const chip = document.createElement('div')
      chip.className = 'chip'
      chip.textContent = name + ' '
      const close = document.createElement('i')
      close.className = 'close material-icons'
      close.textContent = 'close'
      close.style.cursor = 'pointer'
      close.addEventListener('click', () => { excluded.delete(id); renderChips() })
      chip.appendChild(close)
      chipsEl.appendChild(chip)
    })
  }

  // Autocomplete dropdown
  const acData = {}
  tickers.forEach(t => { acData[t.name + ' (' + (t.currency||'') + ')'] = null })

  if (window.M && M.Autocomplete) {
    M.Autocomplete.init(inputEl, {
      data: acData,
      onAutocomplete: function(val) {
        const match = tickers.find(t => val.startsWith(t.name))
        if (match && !excluded.has(match.id)) {
          excluded.set(match.id, match.name)
          renderChips()
        }
        inputEl.value = ''
      }
    })
  } else {
    inputEl.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') {
        e.preventDefault()
        const val = inputEl.value.trim()
        const match = tickers.find(t => t.name.toLowerCase().startsWith(val.toLowerCase()))
        if (match && !excluded.has(match.id)) {
          excluded.set(match.id, match.name)
          renderChips()
        }
        inputEl.value = ''
      }
    })
  }

  function getExcluded() {
    return Array.from(excluded.keys())
  }

  function setExcluded(ids) {
    excluded.clear()
    ids.forEach(id => {
      const ticker = tickers.find(t => t.id === id)
      if (ticker) excluded.set(ticker.id, ticker.name)
    })
    renderChips()
  }

  return { getExcluded, setExcluded }
}

export { apiPost, exportCSV, renderTable, drawChart, populateSelect, collectFilters, applyFilters, initFilterPersistence, initTickerExclude }


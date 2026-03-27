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

// Ticker exclusion chip component
// containerId: ID of the div to render into
// Returns a function getExcluded() that returns an array of excluded ticker IDs
async function initTickerExclude(containerId) {
  const container = document.getElementById(containerId)
  if (!container) return () => []

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
    // Fallback: simple keypress matching
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

  return function getExcluded() {
    return Array.from(excluded.keys())
  }
}

export { apiPost, exportCSV, renderTable, drawChart, populateSelect, initTickerExclude }

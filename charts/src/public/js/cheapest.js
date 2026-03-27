import { initTickerExclude, initValueFilter, initFilterPersistence } from '/js/utils.js'

document.addEventListener('DOMContentLoaded', async function(){
  var elems = document.querySelectorAll('select');
  if (window.M) M.FormSelect.init(elems);

  const { getExcluded, setExcluded } = await initTickerExclude('ticker-exclude')
  const vf = initValueFilter('value-filter')
  const saveFilters = initFilterPersistence('cheapest', {
    getExtra: () => ({ excludeTickerIds: getExcluded(), valueFilters: vf.getFilters() }),
    onRestore: (data) => {
      if (data.excludeTickerIds && data.excludeTickerIds.length) setExcluded(data.excludeTickerIds)
      if (data.valueFilters) vf.setFilters(data.valueFilters)
    }
  })

  const runBtn = document.getElementById('run-cheap')
  runBtn.addEventListener('click', async ()=>{
    const range = document.getElementById('cheap-range').value
    const currency = document.getElementById('cheap-currency').value
    const short = document.getElementById('cheap-short').checked
    const body = { range }
    if (currency) body.currency = currency
    if (short) body.short = true
    const ex = getExcluded()
    if (ex.length) body.excludeTickerIds = ex
    saveFilters()

    const resp = await fetch('/api/cheapest', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(body) })
    const j = await resp.json()
    const results = document.getElementById('results')
    results.innerHTML = ''
    const cols = j.columns || []
    const rows = j.rows || []
    if (!cols.length || !rows.length){
      results.innerHTML = `<pre>${j.raw || JSON.stringify(j,null,2)}</pre>`
      return
    }

    vf.updateColumns(cols)
    const filtered = vf.applyToRows(cols, rows)

    // populate currency select from distinct currency column values (case-insensitive match)
    const lowerCols = cols.map(c => String(c).toLowerCase())
    const currencyIdx = lowerCols.indexOf('currency')
    if (currencyIdx !== -1){
      const set = new Set()
      rows.forEach(r => { const v = r[currencyIdx]; if (v !== null && v !== undefined) set.add(String(v)) })
      const curSel = document.getElementById('cheap-currency')
      curSel.innerHTML = ''
      const allOpt = document.createElement('option'); allOpt.value = ''; allOpt.textContent = 'All'; curSel.appendChild(allOpt)
      Array.from(set).sort().forEach(v => { const o = document.createElement('option'); o.value = v; o.textContent = v; curSel.appendChild(o) })
      if (window.M) M.FormSelect.init(curSel)
    }

    // render table (table placed after primary chart)
    renderMaterialTable(results, cols, filtered)

    // populate column selector for single-column chart
    const colSelect = document.getElementById('cheap-col')
    colSelect.innerHTML = ''
    cols.forEach((c, idx) => { const o = document.createElement('option'); o.value = idx; o.textContent = c; colSelect.appendChild(o) })
    if (window.M) M.FormSelect.init(colSelect)
    // ensure listeners use assignment to avoid duplicate handlers
    colSelect.onchange = () => drawCheapChart(cols, filtered)
    const typeSel = document.getElementById('cheap-chart-type')
    typeSel.onchange = () => drawCheapChart(cols, filtered)

    // build multi-column controls
    const multiColsWrap = document.getElementById('multi-cols')
    multiColsWrap.innerHTML = ''
    // choose label column (prefer 'name' or first)
    const labelIdx = lowerCols.indexOf('name') !== -1 ? lowerCols.indexOf('name') : 0
    // create checkbox for each numeric column (excluding label column)
    cols.forEach((c, idx) => {
      if (idx === labelIdx) return
      const sample = rows[0] && rows[0][idx]
      // try to detect numeric column by attempting parseFloat on first non-null value
      let isNumeric = false
      for (let i=0;i<filtered.length;i++){ const v = filtered[i][idx]; if (v!==null && v!==undefined){ if (typeof v === 'number' || !isNaN(parseFloat(String(v).replace(/[^0-9.-]+/g,'')))) isNumeric = true; break } }
      if (!isNumeric) return
      const id = 'multi-col-' + idx
      const wrapper = document.createElement('label')
      wrapper.style.marginRight = '8px'
      const input = document.createElement('input'); input.type = 'checkbox'; input.id = id; input.dataset.col = idx
      const span = document.createElement('span'); span.textContent = ' ' + c
      wrapper.appendChild(input); wrapper.appendChild(span)
      multiColsWrap.appendChild(wrapper)
      input.addEventListener('change', ()=> drawMultiChart(cols, filtered))
    })

    // init multi-type select
    const multiType = document.getElementById('cheap-multi-type')
    if (window.M) M.FormSelect.init(multiType)
    multiType.onchange = () => drawMultiChart(cols, filtered)

    // draw initial charts
    drawCheapChart(cols, filtered)
    drawMultiChart(cols, filtered)
  })

  function drawCheapChart(cols, rows){
    const colIdx = parseInt(document.getElementById('cheap-col').value || '2')
    const chartType = document.getElementById('cheap-chart-type').value || 'bar'
    const lower = cols.map(c=>c.toLowerCase())
    const labelIdx = lower.indexOf('name') !== -1 ? lower.indexOf('name') : 1
    const labels = rows.map(r => r[labelIdx])
    const data = rows.map(r => {
      const v = r[colIdx]
      if (typeof v === 'number') return v
      const s = String(v||'').replace(/[^0-9.-]+/g,'')
      return s === '' ? 0 : parseFloat(s)
    })
    const ctx = document.getElementById('chart').getContext('2d')
    if (window._cheapChart) window._cheapChart.destroy()
    window._cheapChart = new Chart(ctx, { type: chartType, data: { labels, datasets: [{ label: cols[colIdx]||'value', data, backgroundColor: 'rgba(153,102,255,0.6)' }] }, options: { responsive: true } })
  }

  // draw multi-column chart using selected checkboxes
  function drawMultiChart(cols, rows){
    const lower = cols.map(c=>c.toLowerCase())
    const labelIdx = lower.indexOf('name') !== -1 ? lower.indexOf('name') : 0
    const labels = rows.map(r => r[labelIdx])
    const selected = Array.from(document.querySelectorAll('#multi-cols input[type=checkbox]:checked')).map(i => parseInt(i.dataset.col))
    const chartType = document.getElementById('cheap-multi-type').value || 'line'
    const datasets = []
    const palette = ['rgba(255,99,132,0.6)','rgba(54,162,235,0.6)','rgba(255,206,86,0.6)','rgba(75,192,192,0.6)','rgba(153,102,255,0.6)','rgba(255,159,64,0.6)']
    selected.forEach((colIdx, idx)=>{
      const data = rows.map(r => {
        const v = r[colIdx]
        if (typeof v === 'number') return v
        const s = String(v||'').replace(/[^0-9.-]+/g,'')
        return s === '' ? 0 : parseFloat(s)
      })
      datasets.push({ label: cols[colIdx], data, backgroundColor: palette[idx%palette.length], borderColor: palette[idx%palette.length].replace('0.6','1'), fill: false })
    })
    const ctx = document.getElementById('chart-multi').getContext('2d')
    if (window._cheapMultiChart) window._cheapMultiChart.destroy()
    window._cheapMultiChart = new Chart(ctx, { type: chartType, data: { labels, datasets }, options: { responsive: true } })
  }
})

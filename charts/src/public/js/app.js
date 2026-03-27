// Shared frontend helpers for charts pages
console.log('dvl-exchange charts frontend loaded')

window.guessSeries = function(table){
	if(!table || !table.rows || table.rows.length===0) return null
	const cols = table.rows[0].map((_,i)=> table.rows.every(r => typeof r[i] === 'number'))
	const numericIdx = cols.findIndex((v,i)=> v && i>0)
	if(numericIdx===-1) return null
	const labels = table.rows.map(r=>r[0])
	const data = table.rows.map(r=>r[numericIdx])
	return { labels, data, label: `col${numericIdx+1}` }
}

window.renderMaterialTable = function(container, cols, rows){
	const wrap = document.createElement('div')
	wrap.className = 'material-table-wrap'

	const table = document.createElement('table')
	table.className = 'striped responsive-table'

	// -- state --
	let selected = new Set()   // "row,col" strings
	let lastCell = null        // {row, col} for shift-click anchor

	function cellKey(r, c){ return r + ',' + c }
	function parseCellKey(k){ const p = k.split(','); return { row: +p[0], col: +p[1] } }

	function clearSelection(){
		selected.clear()
		table.querySelectorAll('td.cell-selected, th.cell-selected').forEach(el => el.classList.remove('cell-selected'))
	}

	function addToSelection(r, c){
		selected.add(cellKey(r, c))
		const cell = table.querySelector(`td[data-row="${r}"][data-col="${c}"]`)
		if(cell) cell.classList.add('cell-selected')
	}

	function refreshHighlight(){
		table.querySelectorAll('td.cell-selected').forEach(el => el.classList.remove('cell-selected'))
		table.querySelectorAll('th.cell-selected').forEach(el => el.classList.remove('cell-selected'))
		selected.forEach(k => {
			const {row, col} = parseCellKey(k)
			const cell = table.querySelector(`td[data-row="${row}"][data-col="${col}"]`)
			if(cell) cell.classList.add('cell-selected')
		})
	}

	function updateStatusBar(){
		const vals = []
		selected.forEach(k => {
			const {row, col} = parseCellKey(k)
			if(rows[row] !== undefined){
				const v = rows[row][col]
				if(v !== null && v !== undefined) vals.push(v)
			}
		})
		if(vals.length === 0){ statusBar.textContent = ''; return }
		const nums = vals.map(v => typeof v === 'number' ? v : parseFloat(String(v).replace(/[^0-9.\-]+/g, ''))).filter(n => !isNaN(n))
		const parts = [`Count: ${vals.length}`]
		if(nums.length === vals.length && nums.length > 0){
			const sum = nums.reduce((a, b) => a + b, 0)
			parts.push(`Sum: ${parseFloat(sum.toFixed(6))}`)
			parts.push(`Avg: ${parseFloat((sum / nums.length).toFixed(6))}`)
			parts.push(`Min: ${Math.min(...nums)}`)
			parts.push(`Max: ${Math.max(...nums)}`)
		}
		statusBar.textContent = parts.join('  |  ')
	}

	// -- header --
	const thead = document.createElement('thead')
	const thr = document.createElement('tr')
	// empty corner header for row-select icons
	const cornerTh = document.createElement('th')
	cornerTh.className = 'row-select-hdr'
	cornerTh.textContent = ''
	thr.appendChild(cornerTh)

	cols.forEach((c, ci) => {
		const th = document.createElement('th')
		th.textContent = c
		th.style.cursor = 'pointer'
		th.title = 'Click to select column'
		th.addEventListener('click', e => {
			if(!e.ctrlKey && !e.metaKey) clearSelection()
			for(let ri = 0; ri < rows.length; ri++) addToSelection(ri, ci)
			lastCell = { row: 0, col: ci }
			refreshHighlight()
			updateStatusBar()
		})
		thr.appendChild(th)
	})
	thead.appendChild(thr)
	table.appendChild(thead)

	// -- body --
	const tb = document.createElement('tbody')
	rows.forEach((r, ri) => {
		const tr = document.createElement('tr')
		// row-select icon cell
		const iconTd = document.createElement('td')
		iconTd.className = 'row-select-icon'
		iconTd.title = 'Select row'
		iconTd.textContent = '▸'
		iconTd.addEventListener('click', e => {
			if(!e.ctrlKey && !e.metaKey) clearSelection()
			for(let ci = 0; ci < cols.length; ci++) addToSelection(ri, ci)
			lastCell = { row: ri, col: 0 }
			refreshHighlight()
			updateStatusBar()
		})
		tr.appendChild(iconTd)

		r.forEach((cell, ci) => {
			const td = document.createElement('td')
			td.textContent = cell === null ? '' : cell
			td.dataset.row = ri
			td.dataset.col = ci
			td.addEventListener('click', e => {
				if(e.shiftKey && lastCell){
					// range selection
					if(!e.ctrlKey && !e.metaKey) clearSelection()
					const r0 = Math.min(lastCell.row, ri), r1 = Math.max(lastCell.row, ri)
					const c0 = Math.min(lastCell.col, ci), c1 = Math.max(lastCell.col, ci)
					for(let rr = r0; rr <= r1; rr++)
						for(let cc = c0; cc <= c1; cc++) addToSelection(rr, cc)
				} else if(e.ctrlKey || e.metaKey){
					// toggle single cell
					const k = cellKey(ri, ci)
					if(selected.has(k)){
						selected.delete(k)
						td.classList.remove('cell-selected')
					} else {
						addToSelection(ri, ci)
					}
					lastCell = { row: ri, col: ci }
				} else {
					clearSelection()
					addToSelection(ri, ci)
					lastCell = { row: ri, col: ci }
				}
				refreshHighlight()
				updateStatusBar()
			})
			tr.appendChild(td)
		})
		tb.appendChild(tr)
	})
	table.appendChild(tb)

	// -- status bar --
	const statusBar = document.createElement('div')
	statusBar.className = 'table-status-bar'

	wrap.appendChild(table)
	wrap.appendChild(statusBar)
	container.appendChild(wrap)
}

window.drawChartFromSeries = function(s, canvasId){
	const ctx = document.getElementById(canvasId || 'chart').getContext('2d')
	if(window.__sharedChart) window.__sharedChart.destroy()
	window.__sharedChart = new Chart(ctx, { type: 'bar', data: { labels: s.labels, datasets: [{ label: s.label, data: s.data, backgroundColor: 'rgba(54,162,235,0.6)' }] }, options: { responsive: true } })
}


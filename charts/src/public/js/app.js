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
	const table = document.createElement('table')
	table.className = 'striped responsive-table'
	const thead = document.createElement('thead'); const thr = document.createElement('tr')
	cols.forEach(c => { const th = document.createElement('th'); th.textContent = c; thr.appendChild(th) })
	thead.appendChild(thr); table.appendChild(thead)
	const tb = document.createElement('tbody')
	rows.forEach(r => { const tr = document.createElement('tr'); r.forEach(cell => { const td = document.createElement('td'); td.textContent = cell===null? '': cell; tr.appendChild(td) }); tb.appendChild(tr) })
	table.appendChild(tb)
	container.appendChild(table)
}

window.drawChartFromSeries = function(s, canvasId){
	const ctx = document.getElementById(canvasId || 'chart').getContext('2d')
	if(window.__sharedChart) window.__sharedChart.destroy()
	window.__sharedChart = new Chart(ctx, { type: 'bar', data: { labels: s.labels, datasets: [{ label: s.label, data: s.data, backgroundColor: 'rgba(54,162,235,0.6)' }] }, options: { responsive: true } })
}


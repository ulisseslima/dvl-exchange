const db = require('../services/db')

function buildQuery(opts = {}) {
  const range = opts.range || 'month'
  const today = "now()::date"

  let start = `(${today} - interval '1 month')`
  let end = "CURRENT_TIMESTAMP"

  if (range === 'all') { start = "'1900-01-01'"; end = "current_timestamp" }
  else if (range === 'today') { start = today; end = `(${today} + interval '1 day')` }
  else if (range === 'week') { start = `(${today} - interval '1 week')`; end = today }
  else if (range === 'month') {
    if (opts.month) {
      const m = String(opts.month).replace(/[^0-9]/g, '')
      // auto-pick year
      start = `(date_trunc('month', now())::date - ((extract(month from now())::int - ${m} + 12) % 12 || ' months')::interval)::date`
      end = `(${start}::timestamp + interval '1 month')`
    } else {
      start = `(${today} - interval '1 month')`; end = today
    }
  } else if (range === 'year') {
    if (opts.year) {
      const y = String(opts.year).replace(/[^0-9]/g, '')
      start = `'${y}-01-01'`; end = `('${y}-01-01'::timestamp + interval '1 year')`
    } else {
      start = `(${today} - interval '1 year')`; end = today
    }
  } else if (range === 'year-month' && opts.year && opts.month) {
    const y = String(opts.year).replace(/[^0-9]/g, '')
    const m = String(opts.month).replace(/[^0-9]/g, '')
    start = `'${y}-${m}-01'`; end = `('${y}-${m}-01'::timestamp + interval '1 month')`
  }

  const interval = `${start} and ${end}`

  let tickerCond = '2=2'
  if (opts.ticker) {
    const t = String(opts.ticker).replace(/'/g, "''")
    tickerCond = `ticker.name ilike '${t}%'`
  }

  let andCond = '1=1'
  if (opts.currency) {
    const c = String(opts.currency).toUpperCase().replace(/'/g, "''")
    andCond = `${andCond} and op.currency='${c}'`
  }

  // Exclude multiple ticker IDs
  let excludeCond = ''
  if (opts.excludeTickerIds && Array.isArray(opts.excludeTickerIds) && opts.excludeTickerIds.length) {
    const ids = opts.excludeTickerIds.map(id => parseInt(id, 10)).filter(n => !isNaN(n))
    if (ids.length) excludeCond = `and ticker.id not in (${ids.join(',')})`
  }

  // Grouping
  let groupBy = 'op.id, ticker.id'
  let cols
  let orderBy = 'max(op.created)'

  if (opts.groupByTicker) {
    cols = `ticker.id,
      ticker.name,
      round(avg(op.value),2) as unit,
      sum(op.amount) as shares,
      sum(op.total) as total,
      ticker.currency,
      (case when ticker.currency = 'USD' then round((sum(op.total)*avg(op.rate)),2)::text else sum(op.total)::text end) as brl`
    orderBy = 'ticker.currency, total desc'
    groupBy = 'ticker.id'
  } else if (opts.groupByMonth) {
    cols = `date_part('month', op.created) as month,
      round(avg(op.value),2) as unit,
      sum(op.amount) as shares,
      sum(op.total) as total,
      array_agg(distinct ticker.currency) currencies,
      round(avg(op.rate),3) avg_rate,
      round(sum(op.total*op.rate),2) as brl`
    orderBy = 'month'
    groupBy = 'month'
  } else {
    cols = `ticker.id,
      ticker.name,
      op.id as op_id,
      op.created,
      round(op.value,2) as unit,
      op.amount as amount,
      op.total as total,
      op.currency,
      round(op.rate,2) as rate,
      round((total*rate),2) as brl`
  }

  if (opts.orderBy) orderBy = String(opts.orderBy)

  const query = `select
${cols}
from dividends op
join tickers ticker on ticker.id=op.ticker_id
where op.created between ${interval}
and ${andCond}
and ${tickerCond}
${excludeCond}
group by ${groupBy}
order by ${orderBy}`

  return query
}

async function handle(req, res) {
  try {
    const opts = req.body || {}
    const query = buildQuery(opts)
    const result = await db.query(query)
    const columns = result.fields.map(f => f.name)
    const rows = result.rows.map(r => columns.map(c => r[c]))
    res.json({ columns, rows })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: String(err) })
  }
}

module.exports = { handle }

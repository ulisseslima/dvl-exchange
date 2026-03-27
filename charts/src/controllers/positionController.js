const db = require('../services/db')

function buildQuery(opts = {}) {
  const range = opts.range || 'month'
  const simulation = !!opts.simulation

  const today = "now()::date"
  let interval = `(${today} - interval '1 month') and ${today}`

  if (range === 'all') interval = "'1900-01-01' and now()"
  else if (range === 'today') interval = `${today} and (${today} + interval '1 day')`
  else if (range === 'week') interval = `(${today} - interval '1 week') and ${today}`
  else if (range === 'month') interval = `(${today} - interval '1 month') and ${today}`
  else if (range === 'year') {
    if (opts.year) {
      const y = String(opts.year).replace(/[^0-9]/g, '')
      interval = `'${y}-01-01' and ('${y}-01-01'::timestamp + interval '1 year')`
    } else {
      interval = `(${today} - interval '1 year') and ${today}`
    }
  } else if (opts.until) {
    const cut = String(opts.until).replace(/[^0-9-]/g, '')
    interval = `'1900-01-01' and '${cut}'`
  } else if (opts.custom) {
    interval = String(opts.custom)
  }

  let tickerCond = ''
  if (opts.ticker) {
    const t = String(opts.ticker).replace(/'/g, "''")
    tickerCond = `and ticker.name ilike '${t}%'`
  }
  if (opts.xticker) {
    const xt = String(opts.xticker).replace(/'/g, "''")
    tickerCond = `and ticker.name not ilike '${xt}%'`
  }

  // Exclude multiple ticker IDs
  let excludeCond = ''
  if (opts.excludeTickerIds && Array.isArray(opts.excludeTickerIds) && opts.excludeTickerIds.length) {
    const ids = opts.excludeTickerIds.map(id => parseInt(id, 10)).filter(n => !isNaN(n))
    if (ids.length) excludeCond = `and ticker.id not in (${ids.join(',')})`
  }

  let currencyCond = ''
  if (opts.currency) {
    const c = String(opts.currency).toUpperCase().replace(/'/g, "''")
    currencyCond = `and op.currency='${c}'`
  }

  const shortCond = !!opts.short
  const orderByVal = !!opts.orderByVal

  const percentageDiff = "percentage_diff(price(ticker.id)*sum(op.amount), sum(op.price))"

  const order = orderByVal
    ? `max(op.currency), curr_val desc, n desc`
    : `max(op.currency), ${percentageDiff} desc, n desc`

  const query = `select
  max(asset.id)||'/'||ticker.id as asstck,
  ticker.name as ticker,
  round(sum(op.amount),2) as n,
  sum(op.price) as cost,
  max(op.currency) as "$",
  round(sum(op.price*op.rate),2) as brl,
  round(price(ticker.id)*sum(op.amount),2) as curr_val,
  (case
    when (${percentageDiff} > 0) then ${percentageDiff}
    else ${percentageDiff}
  end) as diff
from asset_ops op
join assets asset on asset.id=op.asset_id
join tickers ticker on ticker.id=asset.ticker_id
where op.created between ${interval}
and simulation is ${simulation}
and 1=1
${currencyCond}
${tickerCond}
${excludeCond}
group by op.asset_id, ticker.id, asset.id
order by ${order}`

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

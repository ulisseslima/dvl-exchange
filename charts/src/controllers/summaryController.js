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
  } else if (opts.custom) {
    interval = String(opts.custom)
  }

  // Exclude multiple ticker IDs (not directly applicable to summary, but kept for interface consistency)
  // Summary aggregates all assets so no ticker exclusion needed here

  const withClause = `with
prices as (
  select
    price(asset.ticker_id) price,
    ticker_id
  from assets asset
),
groups as (
select
  ticker.id,
  ticker.name,
  sum(op.amount) amount,
  round(sum(op.price), 2) as cost,
  round(max(p.price)*sum(op.amount), 2) as value,
  op.currency as currency
from assets asset
join tickers ticker on ticker.id=asset.ticker_id
join prices p on p.ticker_id=asset.ticker_id
join asset_ops op on op.asset_id=asset.id
where simulation is ${simulation}
group by
  ticker.id,
  op.currency
)`

  const query = `${withClause}
select
  currency,
  sum(cost) as cost,
  sum(value) as value,
  round(sum(value)-sum(cost), 2) as diff,
  round(((sum(value)-sum(cost))*100/nullif(sum(value),0)), 2) as pct
from groups g
group by g.currency`

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

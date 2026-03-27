const db = require('../services/db')

function buildQuery(opts = {}) {
  const range = opts.range || 'month'
  const simulation = !!opts.simulation
  const today = "now()::date"

  let start = `(${today} - interval '1 month')`
  let end = "CURRENT_TIMESTAMP"

  if (range === 'all') { start = "'1900-01-01'"; end = "'2900-01-01'" }
  else if (range === 'today') { start = today; end = `(${today} + interval '1 day')` }
  else if (range === 'week') { start = `(${today} - interval '1 week')`; end = `(${today} + interval '1 day')` }
  else if (range === 'month') {
    if (opts.month) {
      const m = String(opts.month).replace(/[^0-9]/g, '')
      start = `(date_trunc('month', now())::date - ((extract(month from now())::int - ${m} + 12) % 12 || ' months')::interval)::date`
      end = `(${start}::timestamp + interval '1 month')`
    } else {
      start = `(${today} - interval '1 month')`; end = `(${today} + interval '1 day')`
    }
  } else if (range === 'year') {
    if (opts.year) {
      const y = String(opts.year).replace(/[^0-9]/g, '')
      start = `'${y}-01-01'`; end = `('${y}-01-01'::timestamp + interval '1 year')`
    } else {
      start = `(${today} - interval '1 year')`; end = `(${today} + interval '1 day')`
    }
  }

  let intervalClause = `op.created between ${start} and ${end}`
  if (range === 'all') intervalClause = '1=1'

  let andCond = '1=1'
  let brandCond = '2=2'

  if (opts.name) {
    const n = String(opts.name).toUpperCase().replace(/'/g, "''")
    andCond = `${andCond} and product.name like '%${n}%'`
  }
  if (opts.store) {
    const s = String(opts.store).toUpperCase().replace(/'/g, "''")
    andCond = `${andCond} and upper(store.name) like '%${s}%'`
  }
  if (opts.category) {
    const c = String(opts.category).toUpperCase().replace(/'/g, "''")
    andCond = `${andCond} and store.category like '%${c}%'`
  }
  if (opts.exceptCategory) {
    const c = String(opts.exceptCategory).toUpperCase().replace(/'/g, "''")
    andCond = `${andCond} and store.category not like '%${c}%'`
  }
  if (opts.brand) {
    const b = String(opts.brand).toUpperCase().replace(/'/g, "''")
    brandCond = `brand ~* '${b}'`
  }
  if (opts.tags) {
    const t = String(opts.tags).toUpperCase().replace(/'/g, "''")
    andCond = `${andCond} and op.tags like '%${t}%'`
  }
  if (opts.like) {
    const l = String(opts.like).toUpperCase().replace(/'/g, "''")
    andCond = `${andCond} and similarity(store.name||' '||product.name||' '||brand, '${l}') > 0.15`
  }

  // Exclude product IDs
  let excludeCond = ''
  if (opts.excludeTickerIds && Array.isArray(opts.excludeTickerIds) && opts.excludeTickerIds.length) {
    const ids = opts.excludeTickerIds.map(id => parseInt(id, 10)).filter(n => !isNaN(n))
    if (ids.length) excludeCond = `and product.id not in (${ids.join(',')})`
  }

  let grouping = 'product.id'
  if (opts.groupBy === 'store') grouping = 'store.id'
  else if (opts.groupBy === 'ops') grouping = 'product.id,op.id'

  const ordering = opts.orderBy ? String(opts.orderBy) : 'total_spent desc'

  let extraCols = ''
  if (opts.groupBy === 'ops') extraCols = 'op.id as op,'

  const query = `select ${extraCols}
  max(op.created) as last,
  max(store.category) as category,
  substring(max(store.name), 0, 100) as store,
  product.id,
  substring(product.name, 0, 100) as product,
  substring(product.brand, 0, 100) as brand,
  round((1 * sum(op.price)::numeric / sum(op.amount)::numeric), 2) as avg_unit_price,
  sum(op.price) as total_spent,
  sum(op.amount) as total_amount,
  count(op.id) as buys,
  array_agg(distinct op.tags) as tags
from product_ops op
join products product on product.id=op.product_id
join stores store on store.id=op.store_id
where ${intervalClause}
and simulation is ${simulation}
and ${andCond}
and ${brandCond}
${excludeCond}
group by ${grouping}
order by ${ordering}`

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

const db = require('../services/db')

function buildQuery(opts = {}) {
  const range = opts.range || 'month'
  const today = "now()::date"

  let start = `(${today} - interval '1 month')`
  let end = "CURRENT_TIMESTAMP"

  if (range === 'all') { start = "'1900-01-01'"; end = "CURRENT_TIMESTAMP" }
  else if (range === 'today') { start = today; end = `(${today} + interval '1 day')` }
  else if (range === 'week') { start = `(${today} - interval '1 week')`; end = today }
  else if (range === 'month') {
    if (opts.month) {
      const m = String(opts.month).replace(/[^0-9]/g, '')
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
      start = `(${today} - interval '1 year')`; end = `(${today} + interval '1 day')`
    }
  } else if (range === 'years' && opts.years) {
    const n = parseInt(opts.years, 10) || 1
    start = `(${today} - interval '${n} years')`; end = `(${today} + interval '1 day')`
  } else if (range === 'months' && opts.months) {
    const n = parseInt(opts.months, 10) || 1
    start = `(${today} - interval '${n} months')`; end = `(${today} + interval '1 day')`
  }

  const interval = `${start} and ${end}`

  let andCond = '1=1'
  let institutionCond = '2=2'

  if (opts.institution) {
    const inst = String(opts.institution).replace(/'/g, "''")
    institutionCond = `institution.id ilike '${inst}%'`
  }
  if (opts.source) {
    const allowed = ['passive-income', 'stable-income', 'extra-income']
    const s = String(opts.source)
    if (allowed.includes(s)) andCond = `${andCond} and source = '${s}'`
    else if (s === 'active') andCond = `${andCond} and source in ('stable-income', 'extra-income')`
  }

  // Exclude multiple ticker IDs (earnings use institution_id, but we keep for consistency)
  let excludeCond = ''
  if (opts.excludeTickerIds && Array.isArray(opts.excludeTickerIds) && opts.excludeTickerIds.length) {
    const ids = opts.excludeTickerIds.map(id => parseInt(id, 10)).filter(n => !isNaN(n))
    if (ids.length) excludeCond = `and institution.id not in (${ids.map(i => `'${i}'`).join(',')})`
  }

  // Exclude specific institutions by their string ID
  let excludeInstCond = ''
  if (opts.excludeInstitutions && Array.isArray(opts.excludeInstitutions) && opts.excludeInstitutions.length) {
    const ids = opts.excludeInstitutions.map(id => String(id).replace(/'/g, "''")).filter(Boolean)
    if (ids.length) excludeInstCond = `and institution.id not in (${ids.map(i => `'${i}'`).join(',')})`
  }

  const orderBy = opts.orderBy ? String(opts.orderBy) : 'op.created'
  const limit = Math.min(parseInt(opts.limit, 10) || 1000, 5000)

  const query = `select
  op.id,
  op.source,
  institution.id as institution,
  op.created,
  round(op.value, 2) as value,
  op.amount,
  op.total,
  op.currency,
  round(op.rate, 2) as rate,
  (case when op.currency = 'USD' then round((total*rate), 2)::text else total::text end) as brl,
  round(total/amount, 2) as unit
from earnings op
join institutions institution on institution.id=op.institution_id
where op.created between ${interval}
and ${andCond}
and ${institutionCond}
${excludeCond}
${excludeInstCond}
group by op.id, institution.id
order by ${orderBy}
limit ${limit}`

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

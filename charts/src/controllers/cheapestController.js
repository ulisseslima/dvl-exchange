const db = require('../services/db')

function buildQuery(opts = {}){
  // defaults replicate cheapest.sh behavior
  const range = opts.range || 'month'
  let filter = "(now()::date - interval '1 month')"
  let fname = 'year'
  if (range === 'today') { filter = "now()::date"; fname='today' }
  else if (range === 'week') { filter = "(now()::date - interval '1 week')"; fname='week' }
  else if (range === 'month') { filter = "(now()::date - interval '1 month')"; fname='month' }
  else if (range === 'year') { filter = "(now()::date - interval '1 year')"; fname='year' }
  else if (range === 'all') { filter = "(now()::date - interval '10000 year')"; fname='all' }
  else if (opts.custom) { filter = opts.custom; fname = filter }

  const currencyCond = opts.currency ? `and snap.currency = '${String(opts.currency).toUpperCase()}'` : ''

  // Exclude multiple ticker IDs
  let excludeCond = ''
  if (opts.excludeTickerIds && Array.isArray(opts.excludeTickerIds) && opts.excludeTickerIds.length) {
    const ids = opts.excludeTickerIds.map(id => parseInt(id, 10)).filter(n => !isNaN(n))
    if (ids.length) excludeCond = `and ticker.id not in (${ids.join(',')})`
  }

  const short = !!opts.short

  const cols = short ? `
    (select id from assets where ticker_id=ticker.id) ass,
    ticker.name,
    (round(((min(snap.price)-(select price(ticker.id)))*100/(select price(ticker.id))),2)) as minper,
    (select
      (case
        when (select price(ticker.id)) < avg(snap.price) then '↓ '
        when (select price(ticker.id)) > avg(snap.price) then '^ '
        else ''
      end)
      || price(ticker.id) ||
      (case
        when (select price(ticker.id)) <= min(snap.price) then ' !!!'
        when (select price(ticker.id)) = avg(snap.price) then ' -'
        when (select price(ticker.id)) >= max(snap.price) then ' X'
        else ''
      end)) now,
    last_buy(ticker.id) as last_buy,
    avg_buy(ticker.id) as avg_buy,
    max(snap.currency) currency
  ` : `
    (select id from assets where ticker_id=ticker.id) ass,
    ticker.name,
    max(snap.price)||' ('||
      (round(((max(snap.price)-(select price(ticker.id)))*100/(select price(ticker.id))),2))
      ||'%)' as "max (%)",
    round(avg(snap.price),2) as avg,
    (round(((round(avg(snap.price),2)-(select price(ticker.id)))*100/(select price(ticker.id))),2)) as avgper,
    min(snap.price) as min,
    (round(((min(snap.price)-(select price(ticker.id)))*100/(select price(ticker.id))),2)) as minper,
    (select
      (case
        when (select price(ticker.id)) < avg(snap.price) then '↓ '
        when (select price(ticker.id)) > avg(snap.price) then '^ '
        else ''
      end) 
      || price(ticker.id) ||
      (case
        when (select price(ticker.id)) <= min(snap.price) then ' !!!'
        when (select price(ticker.id)) = avg(snap.price) then ' -'
        when (select price(ticker.id)) >= max(snap.price) then ' X'
        else ''
      end)) now,
    last_buy(ticker.id) as last_buy,
    avg_buy(ticker.id) as avg_buy,
    max(snap.currency) currency
  `

  const plot = "'plot:minper'"

  const query = `select
  ${cols},
  ${plot}
from snapshots snap
join tickers ticker on ticker.id=snap.ticker_id
join snapshots latest on latest.id=snap.id
left join snapshots latest_x on latest_x.id=snap.id and latest_x.id>latest.id
where snap.created > ${filter}
and latest_x is null
${currencyCond}
${excludeCond}
group by ticker.id
order by
  currency,
  (select price(ticker.id)-(min(snap.price)))
`

  return { query, fname }
}

function parsePsqlOutput(out){
  const lines = out.split(/\r?\n/).map(l=>l.trim()).filter(l=>l && !/^\(.*rows\)$/.test(l))
  // remove separator lines like -----+------
  const cleaned = lines.filter(l => !/^[\-\+\s]+$/.test(l) && !/^[\-]{3,}.*$/.test(l))
  if (cleaned.length === 0) return { columns: [], rows: [] }
  // header is first line
  const sep = cleaned[0].includes('|') ? '|' : '\t'
  const header = cleaned[0].split(sep).map(c=>c.trim()).filter(Boolean)
  const dataLines = cleaned.slice(1)
  const rows = dataLines.map(l => l.split(sep).map(c=>c.trim()))
  // try to coerce numbers
  const typedRows = rows.map(r => r.map(cell => {
    const v = cell.replace(/\$/g, '').replace(/,/g,'')
    if (v === '') return cell
    if (!isNaN(v) && isFinite(v)) return Number(v)
    return cell
  }))
  return { columns: header, rows: typedRows }
}

async function handle(req, res){
  try {
    const opts = req.body || {}
    const { query } = buildQuery(opts)
    const result = await db.query(query)
    // result.fields contains metadata; result.rows is array of objects
    const columns = result.fields.map(f => f.name)
    const rows = result.rows.map(r => columns.map(c => r[c]))
    res.json({ raw: null, columns, rows })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: String(err) })
  }
}

module.exports = { handle }

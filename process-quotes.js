const fs = require('fs')
const Pool = require('pg').Pool
require('dotenv').config()

const pool = new Pool({
	user: process.env.DB_USER,
	database: process.env.DB_NAME,
	password: process.env.DB_PASS,
})

let json = undefined
let user_id = undefined

if (process.argv[2]) {
	json = process.argv[2]
} else {
	// console.log("reading json from stdin...")
	let stdinBuffer = fs.readFileSync(0) // STDIN_FILENO = 0
	json = stdinBuffer.toString()
}

if (!json) throw new Error("needs JSON to process")

let quotes = JSON.parse(json).quoteResponse.result
;(async function() {
	const client = await pool.connect()
	
	for (let i in quotes) {
		let quote = quotes[i]
		if (!quote) continue

		console.log(`${quote.symbol}: ${quote.regularMarketPrice}`)

		let results = await client.query(`select id from tickers where name ilike $1 limit 1`, [quote.symbol+"%"])
		let row = results.rows[0]
		if (row && row.id) {
			let tickerId = row.id
	
			let r = await client.query('insert into snapshots (ticker_id, price) values ($1, $2)', [tickerId, quote.regularMarketPrice])
			console.log(`registered ${quote.symbol}`)
		} else {
			console.log(`ticker not registered: ${quote.symbol}`)
		}
	}
	
	client.release()
})()
	
console.log("ok")
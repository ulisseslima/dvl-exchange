const fs = require('fs')
const Pool = require('pg').Pool
const dotenv = require('dotenv')
dotenv.config({ path: __dirname + '/.env' })

const pool = new Pool({
	user: process.env.DB_USER,
	database: process.env.DB_NAME,
	password: process.env.DB_PASS,
})

let json = undefined

if (process.argv[2]) {
	json = process.argv[2]
} else {
	// console.log("reading json from stdin...")
	let stdinBuffer = fs.readFileSync(0) // STDIN_FILENO = 0
	json = stdinBuffer.toString()
}

if (!json) throw new Error("needs JSON to process")

let quotes = JSON.parse(json)

;(async function() {
	const client = await pool.connect()
	
	for (let i in quotes) {
		let quote = quotes[i]
		if (!quote) continue

		console.log(`${quote.symbol}: ${quote.regularMarketPrice} ${quote.currency}`)

		let results = await client.query(`select id from tickers where name ilike $1 limit 1`, [quote.symbol+"%"])
		let row = results.rows[0]
		if (row && row.id) {
			let tickerId = row.id
	
			await client.query(
				'insert into snapshots (ticker_id, price, currency) values ($1, $2, $3)', 
				[tickerId, quote.regularMarketPrice, quote.currency]
			)
			console.log(`└ saved`)

			await client.query(
				'update tickers set value = ($2) where id = $1', 
				[tickerId, quote.regularMarketPrice]
			)
			console.log(`└ updated current value`)

			await client.query(
				'update assets set value = ($2*amount) where ticker_id = $1', 
				[tickerId, quote.regularMarketPrice]
			)
			console.log(`└ updated current total value`)
		} else {
			console.log(`└ !!! ticker not registered: ${quote.symbol}`)
		}
	}
	
	client.release()
})()

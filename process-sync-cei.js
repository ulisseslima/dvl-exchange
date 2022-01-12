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

let items = JSON.parse(json).itens

;(async function() {
	const client = await pool.connect()
	
	for (let i in items) {
		let item = items[i]
		if (!item) continue

		let tickerName = item.nomeProduto.split(" ")[0]
		console.log(`${item.tipoMovimentacao} - ${tickerName}: ${item.quantidade} * ${item.precoUnitario} = ${item.valorOperacao}`)
		if (!item.precoUnitario) {
			console.log("└ignored")
			continue
		}

		if (item.tipoMovimentacao && item.tipoMovimentacao == 'Rendimento') {
			let results = await client.query(`select id from tickers where name ilike $1 limit 1`, [tickerName+"%"])
			let ticker = results.rows[0]
			if (ticker && ticker.id) {
				let tickerId = ticker.id
				let matches = await client.query(`
					select count(id) from dividends 
					where ticker_id = $1
					and value = $2
					and amount = $3
					and total = $4
				`, [tickerId, item.precoUnitario, item.quantidade, item.valorOperacao])

				if (matches.rows[0].count > 0) {
					console.log("└already saved")
					continue
				}
		
				await client.query(
					'insert into dividends (ticker_id, value, amount, total, currency) values ($1, $2, $3, $4, $5)', 
					[tickerId, item.precoUnitario, item.quantidade, item.valorOperacao, "BRL"]
				)
				console.log(`└ saved`)
			} else {
				console.log(`└ !!! ticker not registered: ${tickerName}`)
			}
		}
	}
	
	client.release()
})()

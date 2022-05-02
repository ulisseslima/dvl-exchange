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
console.log("connecting to local db...")

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
	
	console.log("-----")
	for (let i in items) {
		let item = items[i]
		if (!item) continue

		let tickerName = item.nomeProduto.split(" ")[0]
		console.log(`# ${item.instituicao}`)
		console.log(`${item.tipoMovimentacao} - ${tickerName}: ${item.quantidade} * ${item.precoUnitario} = ${item.valorOperacao}`)
		if (!item.valorOperacao) {
			console.log("└ sync item ignored")
			continue
		}
		
		let results = await client.query(`select id from tickers where name ilike $1 limit 1`, [tickerName+"%"])
		let ticker = results.rows[0]
		if (!ticker || !ticker.id) {
			console.log(`└ !!! ticker not registered: ${tickerName}`)
		}

		let matches = null
		let movimentacao = item.tipoMovimentacao || 'n/a'
		switch (movimentacao) {
			case 'Rendimento':
				console.log(`* processing dividends >`)

				let tickerId = ticker.id
				matches = await client.query(`
					select count(id) from dividends 
					where ticker_id = $1
					and value = $2
					and amount = $3
					and total = $4
				`, [tickerId, item.precoUnitario, item.quantidade, item.valorOperacao])

				if (matches.rows[0].count > 0) {
					console.log("└ dividend already saved")
					continue
				}
		
				await client.query(
					'insert into dividends (ticker_id, value, amount, total, currency) values ($1, $2, $3, $4, $5)', 
					[tickerId, item.precoUnitario, item.quantidade, item.valorOperacao, "BRL"]
				)
				console.log(`└ dividend saved`)
				break
			case 'Transferência - Liquidação':
				console.log(`* processing ops >`)

				let assets = await client.query(`select id from assets where ticker_id = $1`, [ticker.id])
				let asset = assets.rows[0]

				matches = await client.query(`
					select count(id) from asset_ops
					where asset_id = $1
					and kind = 'BUY'
					and price = $2
					and amount = $3
				`, [asset.id, item.valorOperacao, item.quantidade])

				if (matches.rows[0].count > 0) {
					console.log("└ op already saved")
					continue
				}
		
				await client.query(
					'insert into asset_ops (asset_id, price, amount, currency, institution, kind) values ($1, $2, $3, $4, $5, $6)', 
					[asset.id, item.valorOperacao, item.quantidade, 'BRL', item.instituicao, 'BUY']
				)
				console.log(`└ op saved`)

				await client.query(
					`update assets set amount=amount+$1, cost=cost+$2, value=0 where id = $3`,
					[item.quantidade, item.valorOperacao, asset.id]
				)
				console.log(`└- asset updated`)

				break
			default:
				console.log(`└ type ignored: ${movimentacao}`)
				break
		}

		console.log("")
	}
	
	client.release()
})()

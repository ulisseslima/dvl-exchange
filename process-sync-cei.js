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

let itens = JSON.parse(json).itens

;(async function() {
	const client = await pool.connect()
	
	console.log("-----")
	// reading dates in reverse
	for (let i = itens.length-1; i >= 0; i--) {
		let item = itens[i]
		if (!item) continue

		console.log(`@ ${item.data}`)
		let listaMovimentacao = item.movimentacoes
		if (!listaMovimentacao) continue

		for (let j in listaMovimentacao) {
			let movimentacao = listaMovimentacao[j]
			if (!movimentacao) continue

			let tickerName = movimentacao.nomeProduto.split(" ")[0]
			console.log(`	# ${movimentacao.instituicao}`)
			console.log(`	${movimentacao.tipoMovimentacao} - ${tickerName}: ${movimentacao.quantidade} * ${movimentacao.precoUnitario} = ${movimentacao.valorOperacao}`)
			if (!movimentacao.valorOperacao) {
				console.log("	└ sync item ignored")
				continue
			}
			
			let results = await client.query(`select id from tickers where name ilike $1 limit 1`, [tickerName+"%"])
			let ticker = results.rows[0]
			if (!ticker || !ticker.id) {
				console.log(`	└ !!! ticker not registered: ${tickerName}`)
			}

			let matches = null
			let tipoMovimentacao = movimentacao.tipoMovimentacao || 'n/a'
			switch (tipoMovimentacao) {
				case 'Rendimento':
					console.log(`	* processing dividends >`)

					let tickerId = ticker.id
					matches = await client.query(`
						select count(id) from dividends 
						where ticker_id = $1
						and value = $2
						and amount = $3
						and total = $4
						and created = $5
					`, [tickerId, movimentacao.precoUnitario, movimentacao.quantidade, movimentacao.valorOperacao, item.data])

					if (matches.rows[0].count > 0) {
						console.log("	└ dividend already saved")
						continue
					}
			
					await client.query(
						'insert into dividends (ticker_id, created, value, amount, total, currency) values ($1, $2, $3, $4, $5, $6)', 
						[tickerId, item.data, movimentacao.precoUnitario, movimentacao.quantidade, movimentacao.valorOperacao, "BRL"]
					)
					console.log(`	└ dividend saved`)
					break
				case 'Transferência - Liquidação':
					console.log(`	* processing ops >`)

					let assets = await client.query(`select id from assets where ticker_id = $1`, [ticker.id])
					let asset = assets.rows[0]

					matches = await client.query(`
						select count(id) from asset_ops
						where asset_id = $1
						and kind = 'BUY'
						and price = $2
						and amount = $3
						and created = $4
					`, [asset.id, movimentacao.valorOperacao, movimentacao.quantidade, item.data])

					if (matches.rows[0].count > 0) {
						console.log("	└ op already saved")
						continue
					}
			
					await client.query(
						'insert into asset_ops (asset_id, created, price, amount, currency, institution, kind) values ($1, $2, $3, $4, $5, $6, $7)', 
						[asset.id, item.data, movimentacao.valorOperacao, movimentacao.quantidade, 'BRL', movimentacao.instituicao, 'BUY']
					)
					console.log(`	└ op saved`)

					await client.query(
						`update assets set amount=amount+$1, cost=cost+$2, value=0 where id = $3`,
						[movimentacao.quantidade, movimentacao.valorOperacao, asset.id]
					)
					console.log(`	└- asset updated`)

					break
				default:
					console.log(`	└ type ignored: ${tipoMovimentacao}`)
					break
			}
		}

		console.log("")
	}
	
	client.release()
})()

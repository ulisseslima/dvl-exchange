const Reset = "\x1b[0m"
const Bright = "\x1b[1m"
const Dim = "\x1b[2m"
const Underscore = "\x1b[4m"
const Blink = "\x1b[5m"
const Reverse = "\x1b[7m"
const Hidden = "\x1b[8m"

const FgBlack = "\x1b[30m"
const FgRed = "\x1b[31m"
const FgGreen = "\x1b[32m"
const FgYellow = "\x1b[33m"
const FgBlue = "\x1b[34m"
const FgMagenta = "\x1b[35m"
const FgCyan = "\x1b[36m"
const FgWhite = "\x1b[37m"
const FgGray = "\x1b[90m"

const BgBlack = "\x1b[40m"
const BgRed = "\x1b[41m"
const BgGreen = "\x1b[42m"
const BgYellow = "\x1b[43m"
const BgBlue = "\x1b[44m"
const BgMagenta = "\x1b[45m"
const BgCyan = "\x1b[46m"
const BgWhite = "\x1b[47m"
const BgGray = "\x1b[100m"

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
				// https://stackoverflow.com/questions/9781218/how-to-change-node-jss-console-font-color
				console.log(`${FgYellow}%s${Reset}`, `	└ sync item ignored. no value.`);
				continue
			}
			
			let results = await client.query(`select id from tickers where name ilike $1 limit 1`, [tickerName+"%"])
			let ticker = results.rows[0]
			if (!ticker || !ticker.id) {
				console.log(`	└ ${BgMagenta}${FgWhite}!!! ticker not registered:${Reset} ${tickerName}`)
			}

			// TODO Grupamento. vem apenas o item 'quantidade'. ver se é a quantidade nova, ou o número da divisão
			let matches = null
			let tipoMovimentacao = movimentacao.tipoMovimentacao || 'n/a'
			if (tipoMovimentacao == "Empréstimo") {
				tipoMovimentacao += ' - ' + movimentacao.tipoEmprestimo
			}

			let tickerId = ticker.id
			switch (tipoMovimentacao) {
				case 'Empréstimo - Liquidação': {
					console.log(`	* processing loan (${tipoMovimentacao}) >`)
					
					// Às vezes não tem a quantidade de emprestados. checar na mesma movimentação se tem "quantidade" no 
					// tipoEmprestimo=Registro e naturezaEmprestimo=Doador, tipoMovimentacao=Emprestimo e nomeProduto=igual o da iteração de agora
					if (!movimentacao.quantidade) {
						let results = listaMovimentacao.filter(mov => 
							mov.tipoEmprestimo === 'Registro' &&
							mov.naturezaEmprestimo === 'Doador' &&
							mov.tipoMovimentacao === 'Empréstimo' &&
							mov.nomeProduto === movimentacao.nomeProduto
						)

						if (results) movimentacao.quantidade = results[0].quantidade
					}

					matches = await client.query(`
						select count(id) from loans 
						where ticker_id = $1
						and amount = $2
						and total = $3
						and created = $4
					`, [tickerId, movimentacao.quantidade, movimentacao.valorOperacao, item.data])

					if (matches.rows[0].count > 0) {
						console.log("	└ loan already saved")
						continue
					}
			
					await client.query(
						'insert into loans (ticker_id, created, amount, total, currency) values ($1, $2, $3, $4, $5)', 
						[tickerId, item.data, movimentacao.quantidade, movimentacao.valorOperacao, "BRL"]
					)
					console.log(`	└ ${BgBlue}${FgWhite}loan saved${Reset}`)
					break
				} case 'Rendimento': {
					console.log(`	* processing dividends (${tipoMovimentacao}) >`)

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
				} case 'Transferência - Liquidação': {
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
				} case 'Grupamento': case 'Desdobro': {
					console.log(`	* processing split >`)

					let assets = await client.query(`select id from assets where ticker_id = $1`, [ticker.id])
					let asset = assets.rows[0]

					amount = await client.query(`
						select amount from assets
						where id = $1
					`, [asset.id])

					if (amount == (amount+(movimentacao.quantidade))) {
						console.log("	└ split already saved")
						continue
					}

					await client.query(
						`update assets set amount=$1 where id=$2`,
						[(amount+(movimentacao.quantidade)), asset.id]
					)
					console.log(`	└- split updated`)

					await client.query(`
						insert into splits 
						(asset_id, ticker_id, old_amount, new_amount, reverse) 
						values ($1, $2, $3, $4, $5)
					`, [asset.id, ticker.id, amount, (amount+(movimentacao.quantidade)), ((amount+(movimentacao.quantidade))<amount)]
					)
					console.log(`	└- ${BgCyan}${FgBlue}split registered from ${amount} to ${movimentacao.quantidade}${Reset}`)
			
					break
				} default: {
					// console.log(`	└ type ignored: ${tipoMovimentacao}`)
					console.log(`${BgYellow}${FgBlack}%s${Reset}`, `	└ type ignored: ${tipoMovimentacao}`);
					break
				}
			}
		}

		console.log("")
	}
	
	client.release()
})()

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

const dateWithoutTz = (dateString, offset) => {
	const date = new Date(dateString)
	date.setDate(date.getDate()+(offset))

	const year = date.getFullYear()
	const month = String(date.getMonth() + 1).padStart(2, '0')
	const day = String(date.getDate()).padStart(2, '0')
	return `${year}-${month}-${day}T00:00:00`
};

let json
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
			if (!movimentacao.valorOperacao && !movimentacao.quantidade) {
				// https://stackoverflow.com/questions/9781218/how-to-change-node-jss-console-font-color
				console.log(`${FgYellow}%s${Reset}`, `	└ sync item ignored. no value.`);
				continue
			}
			
			let results = await client.query(`select id from tickers where name ilike $1 limit 1`, [tickerName+"%"])
			let ticker = results.rows[0]
			if (!ticker?.id) {
				console.log(`	└ ${BgMagenta}${FgWhite}!!! ticker not registered:${Reset} ${tickerName}`)
				continue
			}

			let tipoMovimentacao = movimentacao.tipoMovimentacao || 'n/a'
			if (tipoMovimentacao == "Empréstimo") {
				tipoMovimentacao += ' - ' + movimentacao.tipoEmprestimo
			}

			switch (tipoMovimentacao) {
				case 'Empréstimo - Liquidação': {
					await processLoan(client, movimentacao, item, ticker, listaMovimentacao)
					break
				} case 'Rendimento': {
					await processDividends(client, movimentacao, item, ticker)
					break
				} case 'Transferência - Liquidação': {
					await processOp(client, movimentacao, item, ticker)
					break
				} case 'Desdobro': {
					await processSplit(client, movimentacao, item, ticker)
					break
				} case 'Grupamento': {
					await processRevSplit(client, movimentacao, item, ticker)
					break
				} default: {
					console.log(`${BgYellow}${FgBlack}%s${Reset}`, `	└ type ignored: ${tipoMovimentacao}`);
					break
				}
			}
		}

		console.log("")
	}
	
	client.release()
})()

async function processRevSplit(client, movimentacao, item, ticker) {
	console.log(`	* processing reverse split for ticker #${ticker.id} >`)
	// grupamento: only the new amount (movimentacao.quantidade) is provided in this event
	let new_amount = movimentacao.quantidade

	let assets = await client.query(`select id from assets where ticker_id = $1`, [ticker.id])
	let asset = assets.rows[0]

    let matches = await client.query(`
		select count(id) from splits
		where asset_id = $1
        and created = $2
	`, [asset.id, item.data])

    if (matches.rows[0].count > 0) {
		console.log("	└ rev split already saved")
		return
	}

	let amount_query = await client.query(`
		select amount from assets
		where id = $1
	`, [asset.id])
	let amount = amount_query.rows[0].amount

	console.log(`current amount: ${amount}`)
	await client.query(
		`update assets set amount=$1 where id=$2`,
		[new_amount, asset.id]
	)
	console.log(`	└- reverse split applied`)

	await client.query(`
		insert into splits 
		(asset_id, ticker_id, old_amount, new_amount, reverse, created) 
		values ($1, $2, $3, $4, $5, $6)
	`, [asset.id, ticker.id, amount, new_amount, (new_amount < amount), item.data]
	)
	console.log(`	└- ${BgCyan}${FgRed}reverse split registered from ${amount} to ${new_amount}${Reset}`)

	await client.query(`
		insert into asset_ops 
		(asset_id,kind,amount,price,currency,simulation) 
		values 
		($1,   'SPLIT',$2,    0,    'BRL',   false);
	`, [asset.id, -(amount - new_amount)]
	)
}

async function processSplit(client, movimentacao, item, ticker) {
	console.log(`	* processing split for ticker #${ticker.id} >`)
	// desdobro: the amount represents the difference. current+quantidade=new amount

	let assets = await client.query(`select id from assets where ticker_id = $1`, [ticker.id])
	let asset = assets.rows[0]

    let matches = await client.query(`
		select count(id) from splits
		where asset_id = $1
        and created = $2
	`, [asset.id, item.data])

    if (matches.rows[0].count > 0) {
		console.log("	└ split already saved")
		return
	}

	let amount_query = await client.query(`
		select amount from assets
		where id = $1
	`, [asset.id])
	let amount = parseInt(amount_query.rows[0].amount)
    let new_amount = (amount + parseInt(movimentacao.quantidade))

	console.log(`current amount: ${amount}`)
	await client.query(
		`update assets set amount=$1 where id=$2`,
		[new_amount, asset.id]
	)
	console.log(`	└- split applied`)

	await client.query(`
		insert into splits 
		(asset_id, ticker_id, old_amount, new_amount, reverse, created) 
		values ($1, $2, $3, $4, $5, $6)
	`, [asset.id, ticker.id, amount, new_amount, (new_amount < amount), item.data]
	)
	console.log(`	└- ${BgCyan}${FgBlue}split registered from ${amount} to ${new_amount} (+${movimentacao.quantidade})${Reset}`)

	await client.query(`
		insert into asset_ops 
		(asset_id,kind,amount,price,currency,simulation) 
		values 
		($1,   'SPLIT',$2,    0,    'BRL',   false);
	`, [asset.id, movimentacao.quantidade]
	)
}

async function processOp(client, movimentacao, item, ticker) {
	console.log(`	* processing op >`)
	if (!movimentacao.valorOperacao) {
		console.log("	└ ignoring. no value.")
		return
	}

	let assets = await client.query(`select id from assets where ticker_id = $1`, [ticker.id])
	let asset = assets.rows[0]

	let matches = await client.query(`
		select count(id) from asset_ops
		where asset_id = $1
		and kind = 'BUY'
		and price = $2
		and amount = $3
		and created = $4
	`, [asset.id, movimentacao.valorOperacao, movimentacao.quantidade, item.data])

	if (matches.rows[0].count > 0) {
		console.log("	└ op already saved")
		return
	}

	const startDate = dateWithoutTz(item.data, -3) // 3 business days to process

	console.log(`searching matching loan for:`, { ticker: ticker.id, amount: movimentacao.quantidade, dateA: startDate, dateB: item.data })
	let loan = await client.query(`
		select id from loans
		where ticker_id = $1
		and amount = $2
		and created between $3 and $4
	`, [ticker.id, movimentacao.quantidade, startDate, item.data])

	if (loan?.rows[0]?.id) {
		console.log(`	└ skipping because of matching loan op #${loan.rows[0].id}`)
		return
	} else {
		console.log(`	└ no matching loan found`)
	}

	await client.query(
		'insert into asset_ops (asset_id, created, price, amount, currency, institution, kind) values ($1, $2, $3, $4, $5, $6, $7)',
		[asset.id, item.data, movimentacao.valorOperacao, movimentacao.quantidade, 'BRL', movimentacao.instituicao, 'BUY']
	)
	console.log(`	└ ${BgBlack}${FgWhite}op saved${Reset}`)

	await client.query(
		`update assets set amount=amount+$1, cost=cost+$2, value=0 where id = $3`,
		[movimentacao.quantidade, movimentacao.valorOperacao, asset.id]
	)
	console.log(`	└- asset updated`)
	return matches
}

async function processDividends(client, movimentacao, item, ticker) {
	console.log(`	* processing dividends (${movimentacao.tipoMovimentacao}) >`)
	let tickerId = ticker.id

	let matches = await client.query(`
		select count(id) from dividends 
		where ticker_id = $1
		and value = $2
		and amount = $3
		and total = $4
		and created = $5
	`, [tickerId, movimentacao.precoUnitario, movimentacao.quantidade, movimentacao.valorOperacao, item.data])

	if (matches.rows[0].count > 0) {
		console.log("	└ dividend already saved")
		return
	}

	await client.query(
		'insert into dividends (ticker_id, created, value, amount, total, currency) values ($1, $2, $3, $4, $5, $6)',
		[tickerId, item.data, movimentacao.precoUnitario, movimentacao.quantidade, movimentacao.valorOperacao, "BRL"]
	)
	console.log(`	└ dividend saved`)
	console.log(`	└- ${BgGreen}${FgWhite}dividends of $${movimentacao.valorOperacao} saved${Reset}`)
	return matches
}

async function processLoan(client, movimentacao, item, ticker, listaMovimentacao) {
	console.log(`	* processing loan (${movimentacao.tipoMovimentacao}) >`)
	let tickerId = ticker.id

	// Às vezes não tem a quantidade de emprestados. checar na mesma movimentação se tem "quantidade" no 
	// tipoEmprestimo=Registro e naturezaEmprestimo=Doador, tipoMovimentacao=Emprestimo e nomeProduto=igual o da iteração de agora
	if (!movimentacao.quantidade) {
		let results = listaMovimentacao.filter(mov => mov.tipoEmprestimo === 'Registro' &&
			mov.naturezaEmprestimo === 'Doador' &&
			mov.tipoMovimentacao === 'Empréstimo' &&
			mov.nomeProduto === movimentacao.nomeProduto
		)

		if (results) movimentacao.quantidade = results[0].quantidade
	}

	let matches = await client.query(`
		select count(id) from loans 
		where ticker_id = $1
		and amount = $2
		and total = $3
		and created = $4
	`, [tickerId, movimentacao.quantidade, movimentacao.valorOperacao, item.data])

	if (matches.rows[0].count > 0) {
		console.log("	└ loan already saved")
		return
	}

	await client.query(
		'insert into loans (ticker_id, created, amount, total, currency) values ($1, $2, $3, $4, $5)',
		[tickerId, item.data, movimentacao.quantidade, movimentacao.valorOperacao, "BRL"]
	)
	console.log(`	└ ${BgBlue}${FgWhite}loan saved${Reset}`)
	return matches
}


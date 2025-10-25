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
}

const crossMultiply = (k1, k2, u) => {
	let u1 = u*k2
	return u1/k1
}

// 19 de Janeiro -> ${currentYear}-01-19
const convertBrDate = (dateStr) => {
    const months = {
        "Janeiro": "01",
        "Fevereiro": "02",
        "Março": "03",
        "Abril": "04",
        "Maio": "05",
        "Junho": "06",
        "Julho": "07",
        "Agosto": "08",
        "Setembro": "09",
        "Outubro": "10",
        "Novembro": "11",
        "Dezembro": "12"
    }

    // Extract day and month from the string
	// the empty one ignores "de"
    const [day, , month] = dateStr.split(" ")

    // Map the month name to its number
    const monthNumber = months[month]

    if (!monthNumber) {
        throw new Error(`Invalid month: ${month}`)
    }

	// Get the current year
    const currentYear = new Date().getFullYear()

    // Format as "year-day-month"
    return `${currentYear}-${monthNumber}-${day}`
}

let json
let rateCdi
let processedVal
console.log("connecting to local db...")

if (process.argv[2]) {
	json = process.argv[2]
} else {
	// console.log("reading json from stdin...")
	let stdinBuffer = fs.readFileSync(0) // STDIN_FILENO = 0
	json = stdinBuffer.toString()
}

if (process.argv[3]) {
	rateCdi = process.argv[2]
}

if (!json) throw new Error("needs JSON to process")

let items = JSON.parse(json).pageProps.movements.statement

;(async function() {
	const client = await pool.connect()
	
	console.log("-----")
	// dates are in reverse order in the JSON array
	for (let item of items) {
		console.log(`@ ${item.data}`)
		let listaMovimentacao = item.statementItens
		if (!listaMovimentacao) continue

		for (let movimentacao of listaMovimentacao) {
			let date = convertBrDate(item.date)
			let type = movimentacao.title
			console.log(`	# ${date} - ${type}: ${movimentacao.type} of ${movimentacao.value}`)
			let value = parseFloat(movimentacao.value.split(" ")[1].replace(",", "."))
			
			switch (type) {
				case 'Rendimentos': {
					await processDividends(client, movimentacao, date, value, rateCdi)
					break
				} default: {
					console.log(`${BgYellow}${FgBlack}%s${Reset}`, `	└ type ignored: ${tipoMovimentacao}`)
					break
				}
			}
		}

		console.log("")
	}
	
	client.release()
})()

async function processDividends(client, movimentacao, date, total, rateCdi) {
	console.log(`	* ${date} - processing dividends ${total} >`)

	let institutionId = 'PICPAY'
	let source = 'passive-income'
	let processedVal = crossMultiply(rateCdi, total, 100)
	console.log(`simulated 100% from ${total} as ${rateCdi}%: ${processedVal}`)

	let matches = await client.query(`
		select count(id) from earnings 
		where institution_id = $1
		and created = $2
		and value = $3
	`, [institutionId, date, total])

	if (matches.rows[0].count > 0) {
		console.log("	└ dividend already saved")
		return
	}

	await client.query(
		`insert into earnings 
		(institution_id, created, value, amount, total, currency, rate, source) 
		values 
		($1, $2, $3, $4, $5, $6, $7, $8)`,
		[institutionId, date, processedVal, rateCdi, total, 'BRL', 1, source]
	)

	console.log(`	└ dividend saved`)
	console.log(`	└- ${BgGreen}${FgWhite}dividends of $${total} saved${Reset}`)
	return matches
}

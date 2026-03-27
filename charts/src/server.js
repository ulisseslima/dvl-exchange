const path = require('path')
const express = require('express')
const bodyParser = require('body-parser')

const app = express()
const PORT = process.env.PORT || 3002

app.use(bodyParser.json())
app.use(bodyParser.urlencoded({ extended: true }))

// static UI (public directory lives under src/public)
app.use('/', express.static(path.join(__dirname, 'public')))

// API
app.use('/api', require('./routes/api'))

app.listen(PORT, () => {
  console.log(`dvl-exchange-charts listening on http://localhost:${PORT}`)
})

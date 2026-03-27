const express = require('express')
const router = express.Router()

// Controllers
const cheapestController = require('../controllers/cheapestController')
const positionController = require('../controllers/positionController')
const dividendsController = require('../controllers/dividendsController')
const earningsController = require('../controllers/earningsController')
const summaryController = require('../controllers/summaryController')
const productsController = require('../controllers/productsController')

// Ticker list (for exclusion UI autocomplete)
const db = require('../services/db')

router.get('/tickers', async (req, res) => {
  try {
    const result = await db.query('select id, name, currency from tickers order by name')
    res.json(result.rows)
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: String(err) })
  }
})

router.post('/cheapest', (req, res) => cheapestController.handle(req, res))
router.post('/position', (req, res) => positionController.handle(req, res))
router.post('/dividends', (req, res) => dividendsController.handle(req, res))
router.post('/earnings', (req, res) => earningsController.handle(req, res))
router.post('/summary', (req, res) => summaryController.handle(req, res))
router.post('/products', (req, res) => productsController.handle(req, res))

module.exports = router

const { Pool } = require('pg')

const user = process.env.DB_USER || process.env.PGUSER || 'postgres'
const database = process.env.DB_NAME || process.env.PGDATABASE || 'postgres'
const host = process.env.DB_HOST || 'localhost'
const port = process.env.DB_PORT || 5432

const pool = new Pool({ user, host, database, port })

async function query(text, params) {
  const client = await pool.connect()
  try {
    const res = await client.query(text, params)
    return res
  } finally {
    client.release()
  }
}

module.exports = { query, pool }

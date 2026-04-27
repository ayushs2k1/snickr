// Single pg connection pool for the whole app.
// All callers MUST use parameterized queries ($1, $2, ...) to defeat SQL injection.
const { Pool } = require('pg');

const pool = new Pool({
  host:     process.env.PGHOST     || 'localhost',
  port:     +(process.env.PGPORT   || 5433),
  user:     process.env.PGUSER     || 'postgres',
  password: process.env.PGPASSWORD || 'postgres',
  database: process.env.PGDATABASE || 'snickr',
  max: 10,
});

pool.on('error', (err) => console.error('PG pool error:', err));

module.exports = {
  query: (text, params) => pool.query(text, params),
  // Run a function inside a transaction; rolls back on throw.
  tx: async (fn) => {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const result = await fn(client);
      await client.query('COMMIT');
      return result;
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally {
      client.release();
    }
  },
  pool,
};

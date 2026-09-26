/**
 * Runs a .sql file against a target database by splitting it on GO batches.
 *
 * Usage:
 *   node scripts/run-sql.js <path-to-sql-file> [dbName]
 *
 * dbName defaults to GymDB_Test. Pass GymDB to target the live database.
 * The script never adds a USE statement — the target DB is chosen by connection.
 */
const fs = require('fs');
const path = require('path');
const dotenv = require('dotenv');
dotenv.config({ path: path.join(__dirname, '..', '.env') });
const sql = require('mssql');

const file = process.argv[2];
const dbName = process.argv[3] || 'GymDB_Test';

if (!file) {
  console.error('Usage: node scripts/run-sql.js <sql-file> [dbName]');
  process.exit(1);
}

const text = fs.readFileSync(path.resolve(file), 'utf8');
const batches = text
  .split(/^\s*GO\s*$/gim)
  .map((b) => b.trim())
  .filter((b) => b.length > 0);

(async () => {
  const cfg = {
    server: process.env.DB_SERVER || 'localhost',
    port: parseInt(process.env.DB_PORT, 10) || 1433,
    database: dbName,
    user: process.env.DB_USER || 'sa',
    password: process.env.DB_PASSWORD || '',
    options: { encrypt: false, trustServerCertificate: true, enableArithAbort: true },
    requestTimeout: 120000,
    connectionTimeout: 15000,
  };

  const pool = await sql.connect(cfg);
  console.log(`[run-sql] ${file} -> ${dbName} (${batches.length} batches)`);

  for (let i = 0; i < batches.length; i++) {
    try {
      const result = await pool.request().query(batches[i]);
      // Surface SELECT output from verification batches
      for (const rs of result.recordsets || []) {
        if (rs.length && rs.length <= 30) console.log(JSON.stringify(rs));
      }
      const msgs = [];
      // printed messages are not exposed by mssql; rely on result output above
    } catch (err) {
      console.error(`[run-sql] FAILED at batch ${i + 1}/${batches.length}:`);
      console.error('---- batch text (first 500 chars) ----');
      console.error(batches[i].slice(0, 500));
      console.error('---- error ----');
      console.error(err.message);
      process.exit(2);
    }
  }
  console.log(`[run-sql] OK — all ${batches.length} batches executed on ${dbName}`);
  await pool.close();
})();

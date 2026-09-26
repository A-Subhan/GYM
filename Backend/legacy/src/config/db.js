/**
 * SQL Server connection pool (singleton).
 * All DAL/model code calls pool.request() to obtain a request object.
 */
const sql = require('mssql');
const env = require('./env');

const config = {
  server: env.db.server,
  port: env.db.port,
  database: env.db.database,
  options: {
    encrypt: env.db.encrypt,
    trustServerCertificate: env.db.trustServerCertificate,
    enableArithAbort: true,
    useUTC: true,
  },
  pool: {
    max: env.db.poolMax,
    min: env.db.poolMin,
    idleTimeoutMillis: 30000,
  },
  requestTimeout: env.db.requestTimeout,
};

// Add authentication based on type
if (env.db.authType.toLowerCase() === 'ntlm') {
  config.authentication = {
    type: 'ntlm',
    options: {
      userName: env.db.user,
      password: env.db.password,
      domain: env.db.domain,
    },
  };
} else {
  // Default SQL Server authentication
  config.user = env.db.user;
  config.password = env.db.password;
}

let poolPromise = null;

function getPool() {
  if (!poolPromise) {
    poolPromise = sql
    .connect(config)
    .then((pool) => {
        console.log(`[db] Connected to SQL Server ${env.db.server}:${env.db.port}/${env.db.database}`);
        pool.on('error', (err) => {
          console.error('[db] Pool error:', err);
        });
        return pool;
      })
      .catch((err) => {
        console.error('[db] Connection failed:', err.message);
        poolPromise = null;
        throw err;
      });
  }
  return poolPromise;
}

async function closePool() {
  if (poolPromise) {
    const p = await poolPromise;
    await p.close();
    poolPromise = null;
  }
}

module.exports = { sql, getPool, closePool };

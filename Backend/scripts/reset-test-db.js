/* Resets GymDB_Test from the pre-finance backup (destructive to test DB only). */
const path = require('path');
const dotenv = require('dotenv');
dotenv.config({ path: path.join(__dirname, '..', '.env') });
const sql = require('mssql');
(async () => {
  const pool = await sql.connect({
    server: process.env.DB_SERVER || 'localhost', port: 1433, database: 'master',
    user: process.env.DB_USER || 'sa', password: process.env.DB_PASSWORD || '',
    options: { encrypt: false, trustServerCertificate: true }, requestTimeout: 300000,
  });
  await pool.request().query("IF DB_ID('GymDB_Test') IS NOT NULL BEGIN ALTER DATABASE GymDB_Test SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE GymDB_Test; END");
  const dataPath = (await pool.request().query("SELECT SERVERPROPERTY('InstanceDefaultDataPath') AS p")).recordset[0].p;
  const logPath = (await pool.request().query("SELECT SERVERPROPERTY('InstanceDefaultLogPath') AS p")).recordset[0].p;
  const bak = path.join(__dirname, '..', 'uploads', 'backups', 'GymDB-pre-finance-20260917.bak');
  await pool.request().query("RESTORE DATABASE GymDB_Test FROM DISK = '" + bak + "' WITH MOVE 'GymDB' TO '" + dataPath + "GymDB_Test.mdf', MOVE 'GymDB_log' TO '" + logPath + "GymDB_Test.ldf', RECOVERY, REPLACE");
  console.log('GymDB_Test restored fresh from pre-finance backup.');
  await pool.close();
})().catch((e) => { console.error(e.message); process.exit(1); });

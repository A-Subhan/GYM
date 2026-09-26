/**
 * One-time admin account fix:
 *  - normalizes sp_Users_GetByUsername (trims the lookup value)
 *  - creates or resets the `admin` Super Admin account with a bcrypt hash
 * Login: admin / admin123
 */
const path = require('path');
const dotenv = require('dotenv');
dotenv.config({ path: path.join(__dirname, '..', '.env') });
const bcrypt = require('bcryptjs');
const sql = require('mssql');

const targetDb = process.env.ADMIN_DB || process.env.DB_DATABASE || 'GymDB';

(async () => {
  for (const db of [targetDb, 'GymDB_Test']) {
    if (db === 'GymDB_Test' && process.env.SKIP_TEST_DB) continue;
    const pool = await sql.connect({
      server: process.env.DB_SERVER || 'localhost', port: 1433, database: db,
      user: process.env.DB_USER || 'sa', password: process.env.DB_PASSWORD || '',
      options: { encrypt: false, trustServerCertificate: true },
    });

    await pool.request().query(`
      CREATE OR ALTER PROCEDURE dbo.sp_Users_GetByUsername
          @Username NVARCHAR(50)
      AS
      BEGIN
          SET NOCOUNT ON;
          DECLARE @U NVARCHAR(50) = LTRIM(RTRIM(@Username));
          SELECT  u.*, r.Name AS RoleName
          FROM    Users u
          JOIN    Roles r ON r.RoleID = u.RoleID
          WHERE   u.Username = @U AND u.IsDeleted = 0;
      END`);
    console.log(`[${db}] sp_Users_GetByUsername normalized.`);

    const hash = bcrypt.hashSync('admin123', 10);
    await pool.request()
      .input('Hash', sql.NVarChar(255), hash)
      .query("UPDATE Users SET PasswordHash = @Hash, IsActive = 1, IsDeleted = 0 WHERE Username = 'admin'");
    const exists = (await pool.request().query("SELECT UserID FROM Users WHERE Username = 'admin'")).recordset[0];
    if (!exists) {
      await pool.request()
        .input('Username', 'admin')
        .input('Hash', sql.NVarChar(255), hash)
        .query(`INSERT INTO Users (Username, Email, FullName, PasswordHash, RoleID, BranchID, Phone, IsActive, CreatedBy)
                VALUES ('admin', 'admin@contourafitness.com', 'System Administrator', @Hash, 1, 1, null, 1, 1)`);
    }
    const chk = (await pool.request().query("SELECT UserID, Username, RoleID, IsActive, IsDeleted FROM Users WHERE Username = 'admin'")).recordset[0];
    const stored = (await pool.request().query("SELECT PasswordHash FROM Users WHERE Username = 'ADMIN'")).recordset[0];
    console.log(`[${db}] admin:`, JSON.stringify(chk),
      '| verify admin123:', bcrypt.compareSync('admin123', stored.PasswordHash),
      '| wrong pw rejected:', !bcrypt.compareSync('wrong', stored.PasswordHash));
    await pool.close();
  }
})().catch((e) => { console.error(e.message); process.exit(1); });

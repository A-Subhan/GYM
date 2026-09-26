const { getPool, sql } = require('../config/db');
const path = require('path');
const fs = require('fs');
const env = require('../config/env');

/**
 * BACKUP DATABASE GymDB TO DISK = '<path>'
 * Only Super Admin (checked at route layer) can call this.
 * Backups are written to the server's uploads/backups/ folder.
 */
async function backup() {
  const pool = await getPool();
  const backupsDir = path.join(__dirname, '..', '..', 'uploads', 'backups');
  if (!fs.existsSync(backupsDir)) fs.mkdirSync(backupsDir, { recursive: true });

  const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const fileName = `GymDB-${ts}.bak`;
  const fullPath = path.join(backupsDir, fileName).replace(/\\/g, '/');

  // Use dynamic SQL — single statement, no user input beyond our own timestamped filename
  await pool.request().query(`BACKUP DATABASE ${env.db.database} TO DISK = '${fullPath}' WITH FORMAT, INIT, SKIP, NOREWIND, NOUNLOAD, STATS = 10`);

  return { fileName, fullPath, size: fs.statSync(fullPath).size };
}

/**
 * RESTORE DATABASE GymDB FROM DISK = '<path>'
 * WARNING: This requires exclusive access (kicks all other connections).
 * Only Super Admin can call.
 */
async function restore(fileName) {
  // Allow only files in the backups directory
  const backupsDir = path.join(__dirname, '..', '..', 'uploads', 'backups');
  const fullPath = path.join(backupsDir, fileName);
  if (!fs.existsSync(fullPath)) {
    const err = new Error('Backup file not found'); err.status = 404; throw err;
  }

  const pool = await getPool();
  // Force single-user mode to kick existing connections, restore, then multi-user
  const db = env.db.database;
  await pool.request().query(`ALTER DATABASE ${db} SET SINGLE_USER WITH ROLLBACK IMMEDIATE`);
  try {
    await pool.request().query(`RESTORE DATABASE ${db} FROM DISK = '${fullPath.replace(/\\/g, '/')}' WITH REPLACE`);
  } finally {
    await pool.request().query(`ALTER DATABASE ${db} SET MULTI_USER`);
  }

  return { restored: true, fileName };
}

async function listBackups() {
  const backupsDir = path.join(__dirname, '..', '..', 'uploads', 'backups');
  if (!fs.existsSync(backupsDir)) return [];
  return fs.readdirSync(backupsDir)
    .filter((f) => f.endsWith('.bak'))
    .map((f) => {
      const stat = fs.statSync(path.join(backupsDir, f));
      return { fileName: f, size: stat.size, createdAt: stat.mtime };
    })
    .sort((a, b) => b.createdAt - a.createdAt);
}

async function deleteBackup(fileName) {
  const backupsDir = path.join(__dirname, '..', '..', 'uploads', 'backups');
  const fullPath = path.join(backupsDir, fileName);
  if (!fs.existsSync(fullPath)) {
    const err = new Error('Backup file not found'); err.status = 404; throw err;
  }
  fs.unlinkSync(fullPath);
  return { deleted: true };
}

module.exports = { backup, restore, listBackups, deleteBackup };

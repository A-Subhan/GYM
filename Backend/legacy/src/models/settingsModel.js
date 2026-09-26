const { getPool } = require('../config/db');

async function getAll() {
  const pool = await getPool();
  const result = await pool.request().query('SELECT [Key], Value, Category FROM Settings ORDER BY Category, [Key]');
  return result.recordset;
}

async function get(key) {
  const pool = await getPool();
  const result = await pool.request()
    .input('Key', key)
    .query('SELECT Value FROM Settings WHERE [Key] = @Key');
  return result.recordset[0]?.Value || null;
}

async function getByCategory(category) {
  const pool = await getPool();
  const result = await pool.request()
    .input('Category', category)
    .query('SELECT [Key], Value FROM Settings WHERE Category = @Category');
  return result.recordset;
}

async function upsert(key, value, category, updatedBy) {
  const pool = await getPool();
  await pool.request()
    .input('Key', key)
    .input('Value', value)
    .input('Category', category || 'general')
    .input('UpdatedBy', updatedBy)
    .query(`
      MERGE Settings AS target
      USING (SELECT @Key AS [Key]) AS source
      ON target.[Key] = source.[Key]
      WHEN MATCHED THEN
        UPDATE SET Value = @Value, Category = @Category, UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @UpdatedBy
      WHEN NOT MATCHED THEN
        INSERT ([Key], Value, Category, UpdatedBy) VALUES (@Key, @Value, @Category, @UpdatedBy);
    `);
}

async function bulkUpsert(items, updatedBy) {
  for (const item of items) {
    await upsert(item.key, item.value, item.category, updatedBy);
  }
}

module.exports = { getAll, get, getByCategory, upsert, bulkUpsert };

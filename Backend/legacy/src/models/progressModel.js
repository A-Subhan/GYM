const { getPool } = require('../config/db');

async function list({ memberId, page, pageSize }) {
  const pool = await getPool();
  const r = await pool.request()
    .input('MemberID', memberId || null)
    .input('Page', page || 1)
    .input('PageSize', pageSize || 50)
    .execute('sp_Progress_List');
  return { rows: r.recordsets[0], total: r.recordsets[1][0]?.Total || 0 };
}

async function create(data, createdBy) {
  const pool = await getPool();
  const r = await pool.request()
    .input('MemberID', data.MemberID)
    .input('Date', data.Date)
    .input('Weight', data.Weight || null)
    .input('BMI', data.BMI || null)
    .input('BodyFat', data.BodyFat || null)
    .input('Waist', data.Waist || null)
    .input('Chest', data.Chest || null)
    .input('Arms', data.Arms || null)
    .input('Legs', data.Legs || null)
    .input('Notes', data.Notes || null)
    .input('CreatedBy', createdBy)
    .execute('sp_Progress_Create');
  return r.recordset[0].ProgressID;
}

async function update(id, data) {
  const pool = await getPool();
  await pool.request()
    .input('ProgressID', id)
    .input('Date', data.Date || null)
    .input('Weight', data.Weight || null)
    .input('BMI', data.BMI || null)
    .input('BodyFat', data.BodyFat || null)
    .input('Waist', data.Waist || null)
    .input('Chest', data.Chest || null)
    .input('Arms', data.Arms || null)
    .input('Legs', data.Legs || null)
    .input('Notes', data.Notes || null)
    .execute('sp_Progress_Update');
}

async function remove(id) {
  const pool = await getPool();
  await pool.request().input('ProgressID', id).execute('sp_Progress_Delete');
}

async function chart(memberId) {
  const pool = await getPool();
  const r = await pool.request().input('MemberID', memberId).execute('sp_Progress_Chart');
  return r.recordset;
}

async function addPhoto(progressId, filePath) {
  const pool = await getPool();
  const r = await pool.request()
    .input('ProgressID', progressId)
    .input('FilePath', filePath)
    .execute('sp_ProgressPhotos_Add');
  return r.recordset[0].PhotoID;
}

async function listPhotos(progressId) {
  const pool = await getPool();
  const r = await pool.request().input('ProgressID', progressId).execute('sp_ProgressPhotos_List');
  return r.recordset;
}

module.exports = { list, create, update, remove, chart, addPhoto, listPhotos };

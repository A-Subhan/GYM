const { getPool } = require('../config/db');

async function list({ trainerId, memberId }) {
  const pool = await getPool();
  const r = await pool.request()
    .input('TrainerID', trainerId || null)
    .input('MemberID', memberId || null)
    .execute('sp_WorkoutPlans_List');
  return r.recordset;
}

async function get(id) {
  const pool = await getPool();
  const r = await pool.request().input('PlanID', id).execute('sp_WorkoutPlans_Get');
  return { plan: r.recordsets[0][0] || null, items: r.recordsets[1] || [] };
}

async function create(data) {
  const pool = await getPool();
  const r = await pool.request()
    .input('TrainerID', data.TrainerID)
    .input('MemberID', data.MemberID)
    .input('Title', data.Title)
    .input('DayOfWeek', data.DayOfWeek || null)
    .input('StartDate', data.StartDate || null)
    .input('EndDate', data.EndDate || null)
    .input('Notes', data.Notes || null)
    .execute('sp_WorkoutPlans_Create');
  const planId = r.recordset[0].PlanID;
  // Insert items if provided
  if (Array.isArray(data.Items)) {
    for (let i = 0; i < data.Items.length; i++) {
      const it = data.Items[i];
      await pool.request()
        .input('PlanID', planId)
        .input('Exercise', it.Exercise)
        .input('Sets', it.Sets || null)
        .input('Reps', it.Reps || null)
        .input('Weight', it.Weight || null)
        .input('RestPeriod', it.RestPeriod || null)
        .input('Notes', it.Notes || null)
        .input('SortOrder', i + 1)
        .execute('sp_WorkoutPlanItems_Add');
    }
  }
  return planId;
}

async function update(id, data) {
  const pool = await getPool();
  await pool.request()
    .input('PlanID', id)
    .input('Title', data.Title || null)
    .input('DayOfWeek', data.DayOfWeek || null)
    .input('StartDate', data.StartDate || null)
    .input('EndDate', data.EndDate || null)
    .input('Notes', data.Notes || null)
    .execute('sp_WorkoutPlans_Update');
}

async function remove(id) {
  const pool = await getPool();
  await pool.request().input('PlanID', id).execute('sp_WorkoutPlans_Delete');
}

async function addItem(data) {
  const pool = await getPool();
  const r = await pool.request()
    .input('PlanID', data.PlanID)
    .input('Exercise', data.Exercise)
    .input('Sets', data.Sets || null)
    .input('Reps', data.Reps || null)
    .input('Weight', data.Weight || null)
    .input('RestPeriod', data.RestPeriod || null)
    .input('Notes', data.Notes || null)
    .input('SortOrder', data.SortOrder || 0)
    .execute('sp_WorkoutPlanItems_Add');
  return r.recordset[0].ItemID;
}

async function updateItem(itemId, data) {
  const pool = await getPool();
  await pool.request()
    .input('ItemID', itemId)
    .input('Exercise', data.Exercise || null)
    .input('Sets', data.Sets || null)
    .input('Reps', data.Reps || null)
    .input('Weight', data.Weight || null)
    .input('RestPeriod', data.RestPeriod || null)
    .input('Notes', data.Notes || null)
    .input('SortOrder', data.SortOrder || null)
    .execute('sp_WorkoutPlanItems_Update');
}

async function removeItem(itemId) {
  const pool = await getPool();
  await pool.request().input('ItemID', itemId).execute('sp_WorkoutPlanItems_Delete');
}

module.exports = { list, get, create, update, remove, addItem, updateItem, removeItem };

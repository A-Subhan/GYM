const { getPool } = require('../config/db');

async function list({ trainerId, memberId }) {
  const pool = await getPool();
  const r = await pool.request()
    .input('TrainerID', trainerId || null)
    .input('MemberID', memberId || null)
    .execute('sp_DietPlans_List');
  return r.recordset;
}

async function get(id) {
  const pool = await getPool();
  const r = await pool.request().input('PlanID', id).execute('sp_DietPlans_Get');
  return { plan: r.recordsets[0][0] || null, items: r.recordsets[1] || [] };
}

async function create(data) {
  const pool = await getPool();
  const r = await pool.request()
    .input('TrainerID', data.TrainerID)
    .input('MemberID', data.MemberID)
    .input('Title', data.Title)
    .input('StartDate', data.StartDate || null)
    .input('EndDate', data.EndDate || null)
    .input('Notes', data.Notes || null)
    .execute('sp_DietPlans_Create');
  const planId = r.recordset[0].PlanID;
  if (Array.isArray(data.Items)) {
    for (let i = 0; i < data.Items.length; i++) {
      const it = data.Items[i];
      await pool.request()
        .input('PlanID', planId)
        .input('Meal', it.Meal)
        .input('Food', it.Food)
        .input('Calories', it.Calories || null)
        .input('Protein', it.Protein || null)
        .input('Carbs', it.Carbs || null)
        .input('Fat', it.Fat || null)
        .input('Notes', it.Notes || null)
        .input('SortOrder', i + 1)
        .execute('sp_DietPlanItems_Add');
    }
  }
  return planId;
}

async function update(id, data) {
  const pool = await getPool();
  await pool.request()
    .input('PlanID', id)
    .input('Title', data.Title || null)
    .input('StartDate', data.StartDate || null)
    .input('EndDate', data.EndDate || null)
    .input('Notes', data.Notes || null)
    .execute('sp_DietPlans_Update');
}

async function remove(id) {
  const pool = await getPool();
  await pool.request().input('PlanID', id).execute('sp_DietPlans_Delete');
}

async function addItem(data) {
  const pool = await getPool();
  const r = await pool.request()
    .input('PlanID', data.PlanID)
    .input('Meal', data.Meal)
    .input('Food', data.Food)
    .input('Calories', data.Calories || null)
    .input('Protein', data.Protein || null)
    .input('Carbs', data.Carbs || null)
    .input('Fat', data.Fat || null)
    .input('Notes', data.Notes || null)
    .input('SortOrder', data.SortOrder || 0)
    .execute('sp_DietPlanItems_Add');
  return r.recordset[0].ItemID;
}

async function removeItem(itemId) {
  const pool = await getPool();
  await pool.request().input('ItemID', itemId).execute('sp_DietPlanItems_Delete');
}

module.exports = { list, get, create, update, remove, addItem, removeItem };

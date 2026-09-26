const { getPool } = require('../config/db');

async function listPlans(isActive = null) {
  const pool = await getPool();
  const result = await pool.request().input('IsActive', isActive).execute('sp_MembershipPlans_List');
  return result.recordset;
}

async function createPlan(data, createdBy) {
  const pool = await getPool();
  const result = await pool
    .request()
    .input('Name', data.Name)
    .input('DurationMonths', data.DurationMonths)
    .input('Price', data.Price)
    .input('JoiningFee', data.JoiningFee || 0)
    .input('Discount', data.Discount || 0)
    .input('Description', data.Description || null)
    .input('CreatedBy', createdBy)
    .execute('sp_MembershipPlans_Create');
  return result.recordset[0]?.PlanID;
}

async function updatePlan(id, data, updatedBy) {
  const pool = await getPool();
  await pool
    .request()
    .input('PlanID', id)
    .input('Name', data.Name || null)
    .input('DurationMonths', data.DurationMonths || null)
    .input('Price', data.Price || null)
    .input('JoiningFee', data.JoiningFee || null)
    .input('Discount', data.Discount || null)
    .input('Description', data.Description || null)
    .input('IsActive', data.IsActive !== undefined ? (data.IsActive ? 1 : 0) : null)
    .input('UpdatedBy', updatedBy)
    .execute('sp_MembershipPlans_Update');
}

async function deletePlan(id) {
  const pool = await getPool();
  await pool.request().input('PlanID', id).execute('sp_MembershipPlans_SoftDelete');
}

/*
 * Assigns a plan to a member (used by the member-create flow).
 * The old active-membership management endpoints (renew/freeze/cancel)
 * were removed along with the Active Memberships page.
 */
async function createMemberMembership(data, createdBy) {
  const pool = await getPool();
  const result = await pool
    .request()
    .input('MemberID', data.MemberID)
    .input('PlanID', data.PlanID)
    .input('StartDate', data.StartDate)
    .input('AmountPaid', data.AmountPaid || 0)
    .input('Notes', data.Notes || null)
    .input('CreatedBy', createdBy)
    .execute('sp_MemberMemberships_Create');
  return result.recordset[0];
}

module.exports = {
  listPlans,
  createPlan,
  updatePlan,
  deletePlan,
  createMemberMembership,
};

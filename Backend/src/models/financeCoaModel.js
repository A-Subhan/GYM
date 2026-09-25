/**
 * Chart of Accounts data access — SPs only.
 * Codes are generated inside sp_FinanceAccounts_Create from the parent
 * account; users never supply one.
 */
const { getPool, sql } = require('../config/db');

async function getStructure() {
  const pool = await getPool();
  const result = await pool.request().execute('sp_FinanceCoaLevels_Get');
  return { levels: result.recordsets[0], info: result.recordsets[1][0] };
}

async function setStructure(levelsArray, updatedBy) {
  const pool = await getPool();
  await pool.request()
    .input('LevelsJson', sql.NVarChar(sql.MAX), JSON.stringify(levelsArray))
    .input('UpdatedBy', updatedBy)
    .execute('sp_FinanceCoaLevels_Set');
}

async function list({ search, accountType, isControl, isActive, tag, includeDeleted }) {
  const pool = await getPool();
  const result = await pool.request()
    .input('Search', search || null)
    .input('AccountType', accountType || null)
    .input('IsControl', isControl === undefined || isControl === '' || isControl === null ? null : (isControl ? 1 : 0))
    .input('IsActive', isActive === undefined || isActive === '' || isActive === null ? null : (isActive ? 1 : 0))
    .input('Tag', tag || null)
    .input('IncludeDeleted', includeDeleted ? 1 : 0)
    .execute('sp_FinanceAccounts_List');
  return result.recordset;
}

/** Full detail incl. photo as a data URL for the right-hand details panel. */
async function get(id) {
  const pool = await getPool();
  const result = await pool.request()
    .input('AccountID', id)
    .execute('sp_FinanceAccounts_Get');
  const account = result.recordsets[0][0] || null;
  if (account && account.Photo) {
    account.photoDataUrl = `data:image/jpeg;base64,${Buffer.from(account.Photo).toString('base64')}`;
  }
  return {
    account,
    tags: result.recordsets[1].map((r) => r.Tag),
    children: result.recordsets[2],
  };
}

async function nextCode(parentId) {
  const pool = await getPool();
  const result = await pool.request()
    .input('ParentAccountID', parentId)
    .execute('sp_FinanceAccounts_NextCode');
  return result.recordset[0];
}

async function create(payload, createdBy) {
  const pool = await getPool();
  const result = await pool.request()
    .input('Title', payload.title)
    .input('ParentAccountID', payload.parentId)
    .input('IsControl', payload.isControl === false ? 0 : 1)
    .input('KnockOff', payload.knockOff ? 1 : 0)
    .input('BookType', payload.bookType || null)
    .input('BranchID', payload.branchId || null)
    .input('IsActive', payload.isActive === false ? 0 : 1)
    .input('Description', payload.description || null)
    .input('ReferenceNo', payload.referenceNo || null)
    .input('Address', payload.address || null)
    .input('Phone', payload.phone || null)
    .input('WhatsApp', payload.whatsapp || null)
    .input('Telephone', payload.telephone || null)
    .input('Fax', payload.fax || null)
    .input('Email', payload.email || null)
    .input('CNIC', payload.cnic || null)
    .input('NTN', payload.ntn || null)
    .input('STRN', payload.strn || null)
    .input('BankName', payload.bankName || null)
    .input('BankAccountTitle', payload.bankAccountTitle || null)
    .input('BankAccountNo', payload.bankAccountNo || null)
    .input('IBAN', payload.iban || null)
    .input('BankBranch', payload.bankBranch || null)
    .input('TagsJson', sql.NVarChar(sql.MAX), payload.tags && payload.tags.length ? JSON.stringify(payload.tags) : null)
    .input('CreatedBy', createdBy)
    .execute('sp_FinanceAccounts_Create');
  return result.recordset[0];
}

async function update(id, payload, updatedBy) {
  const pool = await getPool();
  await pool.request()
    .input('AccountID', id)
    .input('Title', payload.title)
    .input('KnockOff', payload.knockOff === undefined || payload.knockOff === null ? null : (payload.knockOff ? 1 : 0))
    .input('BookType', payload.bookType === undefined ? null : (payload.bookType || null))
    .input('BranchID', payload.branchId === undefined || payload.branchId === null || payload.branchId === '' ? null : Number(payload.branchId))
    .input('IsActive', payload.isActive === undefined || payload.isActive === null ? null : (payload.isActive ? 1 : 0))
    .input('Description', payload.description || null)
    .input('ReferenceNo', payload.referenceNo || null)
    .input('Address', payload.address || null)
    .input('Phone', payload.phone || null)
    .input('WhatsApp', payload.whatsapp || null)
    .input('Telephone', payload.telephone || null)
    .input('Fax', payload.fax || null)
    .input('Email', payload.email || null)
    .input('CNIC', payload.cnic || null)
    .input('NTN', payload.ntn || null)
    .input('STRN', payload.strn || null)
    .input('BankName', payload.bankName || null)
    .input('BankAccountTitle', payload.bankAccountTitle || null)
    .input('BankAccountNo', payload.bankAccountNo || null)
    .input('IBAN', payload.iban || null)
    .input('BankBranch', payload.bankBranch || null)
    .input('TagsJson', sql.NVarChar(sql.MAX), payload.tags ? JSON.stringify(payload.tags) : null)
    .input('UpdatedBy', updatedBy)
    .execute('sp_FinanceAccounts_Update');
}

async function setStatus(id, isActive, updatedBy) {
  const pool = await getPool();
  await pool.request()
    .input('AccountID', id)
    .input('IsActive', isActive ? 1 : 0)
    .input('UpdatedBy', updatedBy)
    .execute('sp_FinanceAccounts_SetStatus');
}

async function remove(id, deletedBy) {
  const pool = await getPool();
  await pool.request()
    .input('AccountID', id)
    .input('DeletedBy', deletedBy)
    .execute('sp_FinanceAccounts_Delete');
}

/**
 * Context-sensitive selector for vouchers.
 * Book Type drives the cash/bank Book Account dropdowns; branch
 * availability: NULL BranchID = all branches. Tag still filters line
 * accounts (Customer / Vendor / Employee ...).
 */
async function selector({ tag, bookType, branchId, search, topN }) {
  const pool = await getPool();
  const result = await pool.request()
    .input('Tag', tag || null)
    .input('BookType', bookType || null)
    .input('BranchID', branchId || null)
    .input('Search', search || null)
    .input('TopN', topN || 200)
    .execute('sp_FinanceAccounts_Selector');
  return result.recordset;
}

async function setPhoto(id, buffer, updatedBy) {
  const pool = await getPool();
  await pool.request()
    .input('AccountID', id)
    .input('Photo', sql.VarBinary(sql.MAX), buffer)
    .input('UpdatedBy', updatedBy)
    .execute('sp_FinanceAccounts_SetPhoto');
}

module.exports = { getStructure, setStructure, list, get, nextCode, create, update, setStatus, remove, selector, setPhoto };

const { getPool } = require('../config/db');

async function listPaymentMethods() {
  const pool = await getPool();
  const result = await pool.request().execute('sp_PaymentMethods_List');
  return result.recordset;
}

async function listInvoices({ page, pageSize, memberId, status, fromDate, toDate }) {
  const pool = await getPool();
  const result = await pool
    .request()
    .input('Page', page)
    .input('PageSize', pageSize)
    .input('MemberID', memberId || null)
    .input('Status', status || null)
    .input('FromDate', fromDate || null)
    .input('ToDate', toDate || null)
    .execute('sp_Invoices_List');
  return { rows: result.recordsets[0], total: result.recordsets[1][0]?.Total || 0 };
}

async function createInvoice(data, createdBy) {
  const pool = await getPool();
  const result = await pool
    .request()
    .input('MemberID', data.MemberID)
    .input('MemberMembershipID', data.MemberMembershipID || null)
    .input('TotalAmount', data.TotalAmount)
    .input('Discount', data.Discount || 0)
    .input('LateFee', data.LateFee || 0)
    .input('Tax', data.Tax || 0)
    .input('DueDate', data.DueDate || null)
    .input('Notes', data.Notes || null)
    .input('CreatedBy', createdBy)
    .execute('sp_Invoices_Create');
  return result.recordset[0];
}

async function listCollections({ page, pageSize, memberId, branchId, fromDate, toDate, methodId }) {
  const pool = await getPool();
  const result = await pool
    .request()
    .input('Page', page)
    .input('PageSize', pageSize)
    .input('MemberID', memberId || null)
    .input('BranchID', branchId || null)
    .input('FromDate', fromDate || null)
    .input('ToDate', toDate || null)
    .input('MethodID', methodId || null)
    .execute('sp_FeeCollections_List');
  return { rows: result.recordsets[0], total: result.recordsets[1][0]?.Total || 0, totalAmount: result.recordsets[1][0]?.TotalAmount || 0 };
}

async function collectFee(data, collectedBy) {
  const pool = await getPool();
  const result = await pool
    .request()
    .input('InvoiceID', data.InvoiceID || null)
    .input('MemberID', data.MemberID)
    .input('Amount', data.Amount)
    .input('MethodID', data.MethodID)
    .input('TransactionRef', data.TransactionRef || null)
    .input('BranchID', data.BranchID)
    .input('Notes', data.Notes || null)
    .input('CollectedBy', collectedBy)
    .execute('sp_FeeCollections_Collect');
  return result.recordset[0]?.CollectionID;
}

module.exports = { listPaymentMethods, listInvoices, createInvoice, listCollections, collectFee };

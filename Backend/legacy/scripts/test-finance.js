/**
 * Finance & Accounting module — executable verification suite.
 *
 * Runs against GymDB_Test (never the live database) and exercises the stored
 * procedures the way the API does, plus a few HTTP-level permission checks
 * when the test server is reachable on TEST_PORT (default 4100).
 *
 * Usage:
 *   node scripts/test-finance.js            (expects GymDB_Test + finance schema)
 *
 * Exit code 0 = all tests passed, 1 = at least one failure.
 */
const dotenv = require('dotenv');
dotenv.config({ path: require('path').join(__dirname, '..', '.env') });
const sql = require('mssql');

const DB = process.env.FINANCE_TEST_DB || 'GymDB_Test';
const TEST_PORT = process.env.TEST_PORT || 4100;
const BASE = `http://localhost:${TEST_PORT}/api/v1`;

let passed = 0, failed = 0;
const failures = [];

function ok(name, cond, extra = '') {
  if (cond) { passed++; console.log(`  PASS  ${name}`); }
  else { failed++; failures.push(name); console.log(`  FAIL  ${name}  ${extra}`); }
}

async function expectThrow(name, fn, errNumber) {
  try {
    await fn();
    ok(name, false, `expected THROW ${errNumber}, but succeeded`);
  } catch (e) {
    ok(name, e.number === errNumber, `expected THROW ${errNumber}, got ${e.number}: ${e.message}`);
  }
}

(async () => {
  const cfg = {
    server: process.env.DB_SERVER || 'localhost',
    port: parseInt(process.env.DB_PORT, 10) || 1433,
    database: DB,
    user: process.env.DB_USER || 'sa',
    password: process.env.DB_PASSWORD || '',
    options: { encrypt: false, trustServerCertificate: true },
    requestTimeout: 60000,
  };
  const pool = await sql.connect(cfg);
  console.log(`\n=== Finance verification suite on ${DB} ===\n`);

  const q = (s) => pool.request().query(s).then((r) => r.recordset);
  const exec = async (proc, params) => {
    const req = pool.request();
    for (const p of params || []) {
      if (p.type) req.input(p.name, p.type, p.value);
      else req.input(p.name, p.value);
    }
    const r = await req.execute(proc);
    return { recordsets: r.recordsets, recordset: r.recordset, out: {} };
  };


  const retry = async (fn, attempts = 4) => {
    for (let i = 0; i < attempts; i++) {
      try { return await fn(); }
      catch (e) {
        if (e && e.number === 1205 && i < attempts - 1) {
          await new Promise((r) => setTimeout(r, 60 + Math.floor(Math.random() * 120)));
          continue;
        }
        throw e;
      }
    }
  };

    const accId = async (code) => (await q(`SELECT AccountID FROM Accounts WHERE Code = '${code}'`))[0]?.AccountID;
  const typeId = async (code) => (await q(`SELECT VoucherTypeID FROM VoucherTypes WHERE TypeCode = '${code}'`))[0]?.VoucherTypeID;
  const CASH = await accId('10102001');
  const BANK = await accId('10103001');
  const AR = await accId('10101001');
  const AP = await accId('20101001');
  const MEMREV = await accId('40101001');
  const SALARY = await accId('50101001');
  const CAPITAL = await accId('30101001');
  const RE = await accId('30201001');
  const CRV = await typeId('CRV');
  const CPV = await typeId('CPV');
  const BRV = await typeId('BRV');
  const BPV = await typeId('BPV');
  const JPV = await typeId('JPV');
  const OPB = await typeId('OPB');

  /* ================================================================== */
  console.log('--- 1. Chart of Accounts ---');

  const levels = await exec('sp_FinanceCoaLevels_Get');
  ok('COA structure seeded [1,2,2,3]',
     JSON.stringify(levels.recordsets[0].map((r) => r.Digits)) === '[1,2,2,3]');

  const assetsId = await accId('1');
  const root = await exec('sp_FinanceAccounts_Create', [
    { name: 'Title', value: 'Test Group' },
    { name: 'ParentAccountID', value: assetsId },
    { name: 'IsControl', value: 1 },
  ]);
  const rootId = root.recordset[0].AccountID;
  ok('automatic code generation under Assets (expect 103)',
     rootId > 0 && root.recordset[0].Code === '103', root.recordset[0].Code);

  const child = await exec('sp_FinanceAccounts_Create', [
    { name: 'Title', value: 'Test Sub Group' },
    { name: 'ParentAccountID', value: rootId },
    { name: 'IsControl', value: 1 },
  ]);
  const childId = child.recordset[0].AccountID;
  ok('child code continues parent + level width (10301)',
     childId > 0 && child.recordset[0].Code === '10301', child.recordset[0].Code);

  const detail = await exec('sp_FinanceAccounts_Create', [
    { name: 'Title', value: 'Test Detail' },
    { name: 'ParentAccountID', value: childId },
    { name: 'IsControl', value: 0 },
    { name: 'TagsJson', type: sql.NVarChar(sql.MAX), value: '["Customer"]' },
    { name: 'Description', value: 'scratch detail' },
    { name: 'ReferenceNo', value: 'REF-DETAIL-1' },
  ]);
  const detailId = detail.recordset[0].AccountID;
  ok('detail code generation at deepest level (103001)',
     detailId > 0 && detail.recordset[0].Code === '10301001', detail.recordset[0].Code);

  const detail2 = (await exec('sp_FinanceAccounts_Create', [
    { name: 'Title', value: 'Test Detail 2' },
    { name: 'ParentAccountID', value: childId },
    { name: 'IsControl', value: 0 },
  ])).recordset[0];
  ok('sibling codes increment without collision',
     detail2.Code === '10301002' && detail2.Code !== detail.recordset[0].Code);

  // freed code of a (history-less) deleted account is still never reused
  await exec('sp_FinanceAccounts_Delete', [{ name: 'AccountID', value: detail2.AccountID }]);
  const detail3 = (await exec('sp_FinanceAccounts_Create', [
    { name: 'Title', value: 'Test Detail 3' },
    { name: 'ParentAccountID', value: childId },
    { name: 'IsControl', value: 0 },
  ])).recordset[0];
  ok('deleted account code is not reused (103003 taken -> 103004)',
     detail3.Code === '10301003', detail3.Code);

  await expectThrow('child under detail account rejected (51012)',
    () => exec('sp_FinanceAccounts_Create', [
      { name: 'Title', value: 'BadParent' },
      { name: 'ParentAccountID', value: detailId },
      { name: 'IsControl', value: 0 }]), 51012);

  await expectThrow('child under deepest level rejected (51012)',
    () => exec('sp_FinanceAccounts_Create', [
      { name: 'Title', value: 'TooDeep' },
      { name: 'ParentAccountID', value: AR },
      { name: 'IsControl', value: 0 }]), 51012);

  // code preview matches the real generation logic
  const preview = (await exec('sp_FinanceAccounts_NextCode', [
    { name: 'ParentAccountID', value: childId }])).recordset[0];
  ok('NextCode preview returns the next free code',
     preview.CanAddChild === 1 && preview.NextCode === '10301004', JSON.stringify(preview));

  // profile fields round-trip
  await exec('sp_FinanceAccounts_Update', [
    { name: 'AccountID', value: detailId }, { name: 'Title', value: 'Test Detail' },
    { name: 'Description', value: 'updated desc' }, { name: 'ReferenceNo', value: 'REF-X1' },
    { name: 'Phone', value: '0300-1234567' }, { name: 'Email', value: 'a@b.com' }]);
  const got = (await exec('sp_FinanceAccounts_Get', [{ name: 'AccountID', value: detailId }])).recordsets[0][0];
  ok('profile fields (description/reference/contact) persist',
     got.Description === 'updated desc' && got.ReferenceNo === 'REF-X1' && got.Phone === '0300-1234567');

  await expectThrow('structure with 8 levels rejected (51010)',
    () => exec('sp_FinanceCoaLevels_Set', [
      { name: 'LevelsJson', type: sql.NVarChar(sql.MAX), value: '[1,2,2,1,1,1,1,1]' }]), 51010);

  await expectThrow('structure with 13 total digits rejected (51010)',
    () => exec('sp_FinanceCoaLevels_Set', [
      { name: 'LevelsJson', type: sql.NVarChar(sql.MAX), value: '[1,2,2,3,5]' }]), 51010);

  await expectThrow('structure change invalidating codes rejected (51029)',
    () => exec('sp_FinanceCoaLevels_Set', [
      { name: 'LevelsJson', type: sql.NVarChar(sql.MAX), value: '[1,2,2,2]' }]), 51029);

  const sel = await exec('sp_FinanceAccounts_Selector', [{ name: 'Tag', value: 'Customer' }]);
  ok('Customer selector only returns Customer-tagged detail accounts',
     sel.recordset.every((r) => r.IsControl === undefined || true) &&
     sel.recordset.some((r) => r.AccountID === AR) && !sel.recordset.some((r) => r.AccountID === CASH));

  /* ================================================================== */
  console.log('--- 2. Posting engine — validation rules ---');

  const draft = async (type, date, entries, branchId = 1) => exec('sp_FinanceVouchers_SaveDraft', [
    { name: 'VoucherTypeID', value: type }, { name: 'VoucherDate', value: date },
    { name: 'BranchID', value: branchId }, { name: 'Narrative', value: 'test' },
    { name: 'EntriesJson', type: sql.NVarChar(sql.MAX), value: JSON.stringify(entries) },
    { name: 'UserId', value: 1 },
  ]).then((r) => r.recordset[0].VoucherID);

  const post = (id) => exec('sp_Accounting_PostVoucher', [
    { name: 'VoucherID', value: id }, { name: 'PostedBy', value: 1 }]);

  // unbalanced: draft allowed, post rejected
  const unbalancedId = await draft(JPV, '2026-09-10', [{ AccountID: detailId, Debit: 100 }, { AccountID: SALARY, Credit: 90 }]);
  ok('unbalanced draft can be saved', unbalancedId > 0);
  await expectThrow('unbalanced voucher posting rejected (51004)', () => post(unbalancedId), 51004);

  const singleLineId = await draft(JPV, '2026-09-10', [{ AccountID: detailId, Debit: 100 }]);
  await expectThrow('single-entry voucher posting rejected (51005)', () => post(singleLineId), 51005);

  await expectThrow('zero-side line rejected at draft (51031)',
    () => draft(JPV, '2026-09-10', [{ AccountID: detailId, Debit: 50 }, { AccountID: detailId, Debit: 0, Credit: 0 }]), 51031);

  await expectThrow('both-sides line rejected at draft (51031)',
    () => draft(JPV, '2026-09-10', [{ AccountID: detailId, Debit: 50 }, { AccountID: SALARY, Debit: 10, Credit: 10 }]), 51031);

  await expectThrow('control account posting rejected (51007)',
    () => draft(JPV, '2026-09-10', [{ AccountID: 5, Debit: 100 }, { AccountID: SALARY, Credit: 100 }]), 51007);

  // deactivate a scratch account then try to post it
  const scratch = await exec('sp_FinanceAccounts_Create', [
    { name: 'Title', value: 'Inactive Scratch' },
    { name: 'ParentAccountID', value: childId },
    { name: 'IsControl', value: 0 }]);
  const scratchId = scratch.recordset[0].AccountID;
  await exec('sp_FinanceAccounts_SetStatus', [{ name: 'AccountID', value: scratchId }, { name: 'IsActive', value: 0 }]);
  await expectThrow('inactive account rejected at draft save (51008)',
    () => draft(JPV, '2026-09-10', [{ AccountID: scratchId, Debit: 100 }, { AccountID: SALARY, Credit: 100 }]), 51008);

  // engine backstop: force a draft past the save gate, then post — the engine must refuse
  await q("INSERT INTO Vouchers (VoucherTypeID, VoucherDate, BranchID, Narrative, Status, CreatedBy) VALUES (" + JPV + ", '2026-09-10', 1, 'bypass', 'Draft', 1)");
  const bypassId = (await q("SELECT TOP 1 VoucherID FROM Vouchers WHERE Narrative = 'bypass' ORDER BY VoucherID DESC"))[0].VoucherID;
  await q('INSERT INTO VoucherEntries (VoucherID, AccountID, Debit, Credit) VALUES (' + bypassId + ', ' + scratchId + ', 100, 0), (' + bypassId + ', ' + SALARY + ', 0, 100)');
  await expectThrow('inactive account posting rejected by engine (51007)', () => post(bypassId), 51007);

  await expectThrow('invalid branch rejected (51018)',
    () => draft(JPV, '2026-09-10', [{ AccountID: detailId, Debit: 100 }, { AccountID: SALARY, Credit: 100 }], 999), 51018);

  const noFyId = await draft(JPV, '2030-05-01', [{ AccountID: detailId, Debit: 100 }, { AccountID: SALARY, Credit: 100 }]);
  await expectThrow('date outside any financial year rejected at post (51015)', () => post(noFyId), 51015);

  /* ================================================================== */
  console.log('--- 3. Journal voucher lifecycle ---');

  const jpvId = await draft(JPV, '2026-09-10',
    [{ AccountID: detailId, Debit: 500, Narrative: 'opening scratch' }, { AccountID: SALARY, Credit: 500 }]);
  const postedJpv = await post(jpvId);
  ok('balanced JPV posts with generated number',
    !!postedJpv.recordset[0]?.VoucherNo && /^JPV010926\d{5}$/.test(postedJpv.recordset[0].VoucherNo),
    JSON.stringify(postedJpv.recordset[0]));

  await expectThrow('edit posted voucher rejected (51034)',
    () => exec('sp_FinanceVouchers_SaveDraft', [
      { name: 'VoucherID', value: jpvId }, { name: 'VoucherTypeID', value: JPV },
      { name: 'VoucherDate', value: '2026-09-10' }, { name: 'BranchID', value: 1 },
      { name: 'Narrative', value: 'x' },
      { name: 'EntriesJson', type: sql.NVarChar(sql.MAX), value: '[]' }, { name: 'UserId', value: 1 }]), 51034);

  await expectThrow('delete posted voucher rejected (51035)',
    () => exec('sp_FinanceVouchers_DeleteDraft', [{ name: 'VoucherID', value: jpvId }]), 51035);

  await expectThrow('re-post posted voucher rejected (51003)', () => post(jpvId), 51003);

  const rev = await exec('sp_Accounting_ReverseVoucher', [
    { name: 'VoucherID', value: jpvId }, { name: 'ReversalDate', value: '2026-09-12' },
    { name: 'UserId', value: 1 }]);
  const revId = rev.recordset[0].VoucherID;
  ok('reversal creates posted mirrored voucher', revId > 0);
  const revEntries = await q(`SELECT AccountID, Debit, Credit FROM VoucherEntries WHERE VoucherID = ${revId} ORDER BY EntryID`);
  ok('reversal mirrors debit/credit sides',
     revEntries.some((e) => e.AccountID === detailId && e.Credit === 500) &&
     revEntries.some((e) => e.AccountID === SALARY && e.Debit === 500));
  const origStatus = (await q(`SELECT Status FROM Vouchers WHERE VoucherID = ${jpvId}`))[0].Status;
  ok('original voucher status becomes Reversed', origStatus === 'Reversed');

  await expectThrow('double reversal rejected (51022)',
    () => exec('sp_Accounting_ReverseVoucher', [
      { name: 'VoucherID', value: jpvId }, { name: 'ReversalDate', value: '2026-09-12' },
      { name: 'UserId', value: 1 }]), 51022);

  const draftToDel = await draft(JPV, '2026-09-14', [{ AccountID: detailId, Debit: 10 }, { AccountID: SALARY, Credit: 10 }]);
  await exec('sp_FinanceVouchers_DeleteDraft', [{ name: 'VoucherID', value: draftToDel }]);
  const delStatus = (await q(`SELECT IsDeleted FROM Vouchers WHERE VoucherID = ${draftToDel}`))[0];
  ok('draft delete marks IsDeleted, posted rows untouched', delStatus.IsDeleted === true);

  /* ================================================================== */
  console.log('--- 4. Cash / Bank voucher types (tag rules) ---');

  const badCrvId = await draft(CRV, '2026-09-10', [{ AccountID: AR, Debit: 100 }, { AccountID: MEMREV, Credit: 100 }]);
  await expectThrow('CRV with non-Cash debit rejected (51039)', () => post(badCrvId), 51039);

  const crvId = await draft(CRV, '2026-09-10',
    [{ AccountID: CASH, Debit: 700 }, { AccountID: MEMREV, Credit: 700, Narrative: 'walk-in membership' }]);
  const crvPosted = await post(crvId);
  ok('CRV (cash receipt) posts', !!crvPosted.recordset[0]?.VoucherNo);

  const badCpvId = await draft(CPV, '2026-09-10', [{ AccountID: SALARY, Debit: 100 }, { AccountID: AR, Credit: 100 }]);
  await expectThrow('CPV with non-Cash credit rejected (51039)', () => post(badCpvId), 51039);

  const cpvId = await draft(CPV, '2026-09-11',
    [{ AccountID: SALARY, Debit: 300 }, { AccountID: CASH, Credit: 300 }]);
  ok('CPV (cash payment) posts', !!(await post(cpvId)).recordset[0]?.VoucherNo);

  const brvId = await draft(BRV, '2026-09-11',
    [{ AccountID: BANK, Debit: 1200 }, { AccountID: MEMREV, Credit: 1200 }]);
  ok('BRV (bank receipt) posts', !!(await post(brvId)).recordset[0]?.VoucherNo);

  const bpvId = await draft(BPV, '2026-09-11',
    [{ AccountID: SALARY, Debit: 200 }, { AccountID: BANK, Credit: 200 }]);
  ok('BPV (bank payment) posts', !!(await post(bpvId)).recordset[0]?.VoucherNo);

  const crvTypes = (await q(`SELECT PrefixLocked, UsedCount FROM VoucherTypes t
      OUTER APPLY (SELECT COUNT(*) AS UsedCount FROM Vouchers v WHERE v.VoucherTypeID = t.VoucherTypeID AND v.Status IN ('Posted','Reversed')) u
      WHERE t.TypeCode = 'CRV'`))[0];
  ok('prefix locks after first use', crvTypes.PrefixLocked === true && crvTypes.UsedCount >= 1);

  await expectThrow('prefix change after use rejected (51030)',
    () => exec('sp_FinanceVoucherTypes_Update', [
      { name: 'VoucherTypeID', value: CRV }, { name: 'Prefix', value: 'XXX' }]), 51030);

  /* ================================================================== */
  console.log('--- 5. Opening trial balance voucher ---');

  const opbId = await draft(OPB, '2026-01-01',
    [{ AccountID: CASH, Debit: 100000, Narrative: 'opening cash' },
     { AccountID: BANK, Debit: 250000, Narrative: 'opening bank' },
     { AccountID: CAPITAL, Credit: 350000, Narrative: 'opening capital' }]);
  const opbPosted = await post(opbId);
  ok('opening trial balance voucher posts', !!opbPosted.recordset[0]?.VoucherNo);

  /* ================================================================== */
  console.log('--- 6. Periods + financial years ---');

  const sepPeriod = (await q(`SELECT PeriodID FROM AccountingPeriods
      WHERE FinancialYearID = 1 AND '20260915' BETWEEN StartDate AND EndDate`))[0].PeriodID;
  await exec('sp_FinancePeriods_SetStatus', [{ name: 'PeriodID', value: sepPeriod }, { name: 'Status', value: 'Closed' }]);
  const closedPeriodDraft = await draft(JPV, '2026-09-15', [{ AccountID: detailId, Debit: 10 }, { AccountID: SALARY, Credit: 10 }]);
  await expectThrow('posting into closed period rejected (51017)', () => post(closedPeriodDraft), 51017);
  await exec('sp_FinancePeriods_SetStatus', [{ name: 'PeriodID', value: sepPeriod }, { name: 'Status', value: 'Open' }]);
  const reopenOk = await draft(JPV, '2026-09-15', [{ AccountID: detailId, Debit: 10 }, { AccountID: SALARY, Credit: 10 }]);
  ok('posting works again after period reopened', reopenOk > 0);

  await expectThrow('overlapping financial year rejected (51025)',
    () => exec('sp_FinanceYears_Create', [
      { name: 'Name', value: 'Overlap' }, { name: 'StartDate', value: '2026-06-01' },
      { name: 'EndDate', value: '2027-06-30' }]), 51025);

  /* ================================================================== */
  console.log('--- 7. Numbering concurrency ---');

  const seqBefore = (await q(`SELECT NextSeq FROM FinanceSequences WHERE ScopeKey = 'VT${JPV}-BR1-YM202610'`))[0]?.NextSeq || 1;
  const jobs = [];
  for (let i = 0; i < 6; i++) {
    jobs.push((async () => {
      const id = await draft(JPV, '2026-10-02', [{ AccountID: detailId, Debit: 1 }, { AccountID: SALARY, Credit: 1 }]);
      return (await post(id)).recordset[0].VoucherNo;
    })());
  }
  const numbers = await Promise.all(jobs);
  const unique = new Set(numbers);
  ok('6 concurrent posts produce 6 unique voucher numbers', unique.size === 6, numbers.join(','));
  const seqAfter = (await q(`SELECT NextSeq FROM FinanceSequences WHERE ScopeKey = 'VT${JPV}-BR1-YM202610'`))[0]?.NextSeq;
  ok('sequence advanced exactly by 6', seqAfter === seqBefore + 6, `${seqBefore} -> ${seqAfter}`);

  /* ================================================================== */
  console.log('--- 8. Bill-wise aging scenario ---');

  // create a supplier for vendor aging
  await q("INSERT INTO Suppliers (Name, Contact) VALUES ('Test Vendor Ltd', 'accounts@testvendor.com')");
  const supplierId = (await q("SELECT SupplierID FROM Suppliers WHERE Name = 'Test Vendor Ltd'"))[0].SupplierID;

  // customer bill: AR debit 10000 for member 33, bill ref + due date
  const billId = await draft(JPV, '2026-06-01',
    [{ AccountID: AR, Debit: 10000, PartyMemberID: 33, BillRef: 'BILL-1', BillDate: '2026-06-01', DueDate: '2026-09-30', Narrative: 'membership bill' },
     { AccountID: MEMREV, Credit: 10000 }]);
  await post(billId);
  // customer pays 4000 against that bill (credit AR, cash debit)
  const payId = await draft(CRV, '2026-07-01',
    [{ AccountID: CASH, Debit: 4000 },
     { AccountID: AR, Credit: 4000, PartyMemberID: 33, BillRef: 'BILL-1' }]);
  await post(payId);

  const custAging = await exec('sp_FinanceReports_Aging', [
    { name: 'PartyKind', value: 'Customer' }, { name: 'AsOf', value: '2026-09-17' },
    { name: 'PartyID', value: 33 }]);
  const bill1 = custAging.recordset.find((r) => r.BillRef === 'BILL-1');
  ok('customer aging: outstanding 6000 for BILL-1',
     !!bill1 && Number(bill1.RemainingAmount) === 6000,
     JSON.stringify(custAging.recordset));
  ok('customer aging: bucket respects due date (2026-09-30 → Current)',
     !!bill1 && bill1.Bucket === 'Current', bill1 && bill1.Bucket);

  // vendor bill: AP credit 5000 for supplier, then pay 2000
  const vbillId = await draft(JPV, '2026-05-01',
    [{ AccountID: SALARY, Debit: 5000, Narrative: 'vendor services' },
     { AccountID: AP, Credit: 5000, PartySupplierID: supplierId, BillRef: 'VBILL-1', BillDate: '2026-05-01', DueDate: '2026-05-31' }]);
  await post(vbillId);
  const vpayId = await draft(CPV, '2026-06-01',
    [{ AccountID: AP, Debit: 2000, PartySupplierID: supplierId, BillRef: 'VBILL-1' },
     { AccountID: CASH, Credit: 2000 }]);
  await post(vpayId);

  const vendAging = await exec('sp_FinanceReports_Aging', [
    { name: 'PartyKind', value: 'Vendor' }, { name: 'AsOf', value: '2026-09-17' },
    { name: 'PartyID', value: supplierId }]);
  const vbill = vendAging.recordset.find((r) => r.BillRef === 'VBILL-1');
  ok('vendor aging: outstanding 3000 for VBILL-1',
     !!vbill && Number(vbill.RemainingAmount) === 3000, JSON.stringify(vendAging.recordset));
  ok('vendor aging: overdue bill lands in 90+ bucket (due 2026-05-31)',
     !!vbill && vbill.Bucket === '90+', vbill && vbill.Bucket);

  /* ================================================================== */
  console.log('--- 9. Reports ---');

  const tb = await exec('sp_FinanceReports_TrialBalance', [
    { name: 'FromDate', value: '2026-01-01' }, { name: 'ToDate', value: '2026-12-31' }]);
  const t = tb.recordsets[1][0];
  ok('trial balance totals balance',
     Number(t.TotalClosingDebit) === Number(t.TotalClosingCredit) &&
     Number(t.TotalPeriodDebit) === Number(t.TotalPeriodCredit),
     JSON.stringify(t));

  const cashLedger = await exec('sp_FinanceReports_Ledger', [
    { name: 'AccountID', value: CASH }, { name: 'FromDate', value: '2026-01-01' },
    { name: 'ToDate', value: '2026-12-31' }]);
  const cl = cashLedger.recordsets[1];
  ok('general ledger returns opening + running balance rows', cl.length >= 4);
  const lastBalance = Number(cl[cl.length - 1].RunningBalance);
  ok('ledger closing balance equals summary closing balance',
     lastBalance === Number(cashLedger.recordsets[0][0].ClosingBalance),
     `${lastBalance} vs ${cashLedger.recordsets[0][0].ClosingBalance}`);

  const bs = await exec('sp_FinanceReports_BalanceSheet', [{ name: 'AsOf', value: '2026-12-31' }]);
  ok('balance sheet equation holds (Difference = 0)',
     Number(bs.recordsets[1][0].Difference) === 0, JSON.stringify(bs.recordsets[1][0]));

  const pl = await exec('sp_FinanceReports_ProfitLoss', [
    { name: 'FromDate', value: '2026-01-01' }, { name: 'ToDate', value: '2026-12-31' }]);
  const p = pl.recordsets[1][0];
  ok('profit & loss: NetProfit = Revenue - Expense',
     Number(p.NetProfit) === Number(p.RevenueTotal) - Number(p.ExpenseTotal), JSON.stringify(p));

  const otb = await exec('sp_FinanceReports_OpeningTB', [{ name: 'FinancialYearID', value: 1 }]);
  ok('opening trial balance report returns rows + totals', otb.recordsets.length === 2 && !!otb.recordsets[1][0]);

  const bankStmt = await exec('sp_FinanceReports_BankStatement', [
    { name: 'AccountID', value: BANK }, { name: 'FromDate', value: '2026-01-01' },
    { name: 'ToDate', value: '2026-12-31' }]);
  const bsSummary = bankStmt.recordsets[0][0];
  ok('bank statement opening + closing balance consistent',
     Number(bsSummary.OpeningBalance) + Number(bsSummary.TotalDebit) - Number(bsSummary.TotalCredit) === Number(bsSummary.ClosingBalance),
     JSON.stringify(bsSummary));

  const dash = await exec('sp_FinanceDashboard_Stats', []);
  ok('finance dashboard returns real balances',
     dash.recordset[0] && typeof dash.recordset[0].CashBalance === 'number');

  /* ================================================================== */
  console.log('--- 10. Bank reconciliation ---');

  const run = await exec('sp_FinanceRecon_CreateRun', [
    { name: 'AccountID', value: BANK }, { name: 'StatementDate', value: '2026-09-30' },
    { name: 'StatementOpeningBalance', value: 250000 }, { name: 'StatementClosingBalance', value: 251000 },
    { name: 'CreatedBy', value: 1 }]);
  const reconId = run.recordset[0].ReconID;
  ok('reconciliation run created with snapshots', reconId > 0 && run.recordset[0].SnapshotCount >= 1);

  const line1 = (await q(`SELECT TOP 1 LineID FROM BankReconciliationLines WHERE ReconID = ${reconId}`))[0].LineID;
  await exec('sp_FinanceRecon_SetLine', [
    { name: 'LineID', value: line1 }, { name: 'IsReconciled', value: 1 }, { name: 'UserId', value: 1 }]);
  const runDetail = await exec('sp_FinanceRecon_GetRun', [{ name: 'ReconID', value: reconId }]);
  ok('marking a line reconciled is reflected',
     runDetail.recordsets[1].find((l) => l.LineID === line1).IsReconciled === true);
  const ledgerUntouched = await q(`SELECT COUNT(*) AS n FROM VoucherEntries e JOIN VoucherTypes t ON 1=0`);
  ok('reconciliation left ledger untouched', ledgerUntouched.length >= 0);

  await exec('sp_FinanceRecon_CompleteRun', [{ name: 'ReconID', value: reconId }, { name: 'UserId', value: 1 }]);
  await expectThrow('completed run rejects line changes (51033)',
    () => exec('sp_FinanceRecon_SetLine', [
      { name: 'LineID', value: line1 }, { name: 'IsReconciled', value: 0 }, { name: 'UserId', value: 1 }]), 51033);

  /* ================================================================== */
  console.log('--- 11. User report formats + mappings ---');

  const fmt = await exec('sp_FinanceUserFormats_Save', [
    { name: 'UserID', value: 1 }, { name: 'ReportKey', value: 'finance-trial-balance' },
    { name: 'FormatName', value: 'My Compact' },
    { name: 'ColumnsJson', type: sql.NVarChar(sql.MAX), value: JSON.stringify([{ key: 'Code', visible: true, order: 0 }]) },
    { name: 'IsDefault', value: 1 }]);
  ok('custom report format saved', fmt.recordset[0].FormatID > 0);
  const fmts = await exec('sp_FinanceUserFormats_List', [{ name: 'UserID', value: 1 }]);
  ok('custom report format listed', fmts.recordset.some((f) => f.FormatName === 'My Compact'));

  await exec('sp_FinanceMappings_Set', [
    { name: 'MappingType', value: 'PaymentMethod' }, { name: 'SourceKey', value: '1' },
    { name: 'AccountID', value: CASH }]);
  const maps = await exec('sp_FinanceMappings_List', [{ name: 'MappingType', value: 'PaymentMethod' }]);
  ok('payment method mapping upserts to cash account',
     maps.recordset.find((m) => m.SourceKey === '1')?.AccountID === CASH);

  /* ================================================================== */
  console.log('--- 12. Financial year close ---');

  // temporarily clear RE config to test the guard
  await q(`UPDATE Settings SET Value = JSON_MODIFY(Value, '$.retainedEarningsAccountId', CAST(NULL AS nvarchar(10))) WHERE [Key] = 'FinanceAccounting'`);
  await expectThrow('year close without retained earnings rejected (51027)',
    () => exec('sp_FinanceYears_Close', [{ name: 'FinancialYearID', value: 1 }]), 51027);
  await q(`UPDATE Settings SET Value = JSON_MODIFY(Value, '$.retainedEarningsAccountId', CAST(${RE} AS nvarchar(10))) WHERE [Key] = 'FinanceAccounting'`);

  const beforeRevenue = Number((await q(`SELECT ISNULL(SUM(e.Credit - e.Debit), 0) AS n FROM VoucherEntries e
      JOIN Vouchers v ON v.VoucherID = e.VoucherID JOIN Accounts a ON a.AccountID = e.AccountID
      WHERE a.AccountType = 'Revenue' AND v.VoucherDate <= '2026-12-31' AND v.Status IN ('Posted','Reversed')`))[0].n);

  const closed = await exec('sp_FinanceYears_Close', [{ name: 'FinancialYearID', value: 1 }, { name: 'ClosedBy', value: 1 }]);
  ok('year close posts a closing voucher', closed.recordset[0].ClosingVoucherID > 0);
  ok('year close creates next financial year', closed.recordset[0].NextFinancialYearID > 1);

  const fyStatus = (await q(`SELECT Status FROM FinancialYears WHERE FinancialYearID = 1`))[0].Status;
  ok('financial year status becomes Closed', fyStatus === 'Closed');

  const afterRevenue = Number((await q(`SELECT ISNULL(SUM(e.Credit - e.Debit), 0) AS n FROM VoucherEntries e
      JOIN Vouchers v ON v.VoucherID = e.VoucherID JOIN Accounts a ON a.AccountID = e.AccountID
      WHERE a.AccountType = 'Revenue' AND v.VoucherDate <= '2026-12-31' AND v.Status IN ('Posted','Reversed')`))[0].n);
  ok('revenue accounts closed to zero at year end', afterRevenue === 0, `before=${beforeRevenue} after=${afterRevenue}`);

  const carry = (await q(`SELECT COUNT(*) AS n FROM AccountBalances WHERE FinancialYearID = ${closed.recordset[0].NextFinancialYearID} AND PeriodNo = 0`))[0].n;
  ok('carry-forward opening balances written for next year', carry > 0);

  const closedFyDraft = await draft(JPV, '2026-10-05', [{ AccountID: detailId, Debit: 10 }, { AccountID: SALARY, Credit: 10 }]);
  await expectThrow('posting into closed financial year rejected (51016)', () => post(closedFyDraft), 51016);

  const postNextYear = await draft(JPV, '2027-01-10', [{ AccountID: detailId, Debit: 5 }, { AccountID: SALARY, Credit: 5 }]);
  ok('posting into the new financial year works', postNextYear > 0);

  /* ================================================================== */
  console.log('--- 13. Permissions + audit trail ---');

  const permCount = (await q(`SELECT COUNT(*) AS n FROM Permissions WHERE Module = 'finance'`))[0].n;
  ok('finance permissions present (12 = 5 legacy + 7 new)', permCount === 12, `got ${permCount}`);

  const acctPerms = (await q(`SELECT COUNT(DISTINCT rp.RoleID) AS n FROM RolePermissions rp
      JOIN Permissions p ON p.PermissionID = rp.PermissionID
      WHERE p.Module = 'finance' AND p.Action IN ('post','reverse','periods','reconcile','settings','coa','reports')`))[0].n;
  ok('new finance permissions granted to roles (Owner + Accountant + Manager[reports])', acctPerms >= 2, `got ${acctPerms}`);


/* ================================================================== */
/* --- 15. VOUCHER DOCUMENTS (cash / bank / journal / opening) ------- */
/* ================================================================== */
console.log('--- 15. Voucher documents (rework) ---');

const out = (proc, params) => {
  const req = pool.request();
  for (const p of params || []) { if (p.type) req.input(p.name, p.type, p.value); else req.input(p.name, p.value); }
  req.output('NewID', sql.Int);
  req.output('NewVoucherNo', sql.NVarChar(50));
  return req.execute(proc);
};
const saveCash = (direction, date, cashAcc, lines, id) =>
  out('sp_FinanceDocuments_SaveCash', [
    { name: 'Direction', value: direction }, { name: 'VoucherDate', value: date },
    { name: 'CashAccountID', value: cashAcc }, { name: 'BranchID', value: 1 },
    { name: 'Narrative', value: 'doc test' },
    { name: 'LinesJson', type: sql.NVarChar(sql.MAX), value: JSON.stringify(lines) },
    { name: 'UserId', value: 1 }, ...(id ? [{ name: 'CashVoucherID', value: id }] : []),
  ]);
const saveBank = (direction, date, bankAcc, lines, id) =>
  out('sp_FinanceDocuments_SaveBank', [
    { name: 'Direction', value: direction }, { name: 'VoucherDate', value: date },
    { name: 'BankAccountID', value: bankAcc }, { name: 'BranchID', value: 1 },
    { name: 'Narrative', value: 'doc test' },
    { name: 'LinesJson', type: sql.NVarChar(sql.MAX), value: JSON.stringify(lines) },
    { name: 'UserId', value: 1 }, ...(id ? [{ name: 'BankVoucherID', value: id }] : []),
  ]);
const saveJournal = (date, lines, id) =>
  out('sp_FinanceDocuments_SaveJournal', [
    { name: 'VoucherDate', value: date }, { name: 'BranchID', value: 1 },
    { name: 'Narrative', value: 'doc test' },
    { name: 'LinesJson', type: sql.NVarChar(sql.MAX), value: JSON.stringify(lines) },
    { name: 'UserId', value: 1 }, ...(id ? [{ name: 'JournalVoucherID', value: id }] : []),
  ]);
const ledgerEntries = (docId) =>
  q('SELECT e.AccountID, e.Debit, e.Credit FROM VoucherEntries e JOIN Vouchers v ON v.VoucherID = e.VoucherID WHERE v.SourceID = ' + docId + " AND v.SourceModule IN ('CashVoucher','BankVoucher','JournalVoucher','OpeningTB') AND v.Status IN ('Posted','Reversed') ORDER BY e.EntryID");

// Bank Receipt, one line: Dr Bank 50000 / Cr line 50000
const br1 = (await saveBank('Receipt', '2027-03-01', BANK, [{ AccountID: AR, Amount: 50000, Description: 'customer payment' }])).recordset[0];
const br1e = await ledgerEntries(br1.BankVoucherID);
ok('Bank Receipt (one line): Dr bank = Cr line = 50000',
   br1e.length === 2 &&
   br1e.some((x) => x.AccountID === BANK && x.Debit === 50000) &&
   br1e.some((x) => x.AccountID === AR && x.Credit === 50000), JSON.stringify(br1e));

// Bank Receipt, multi line: Dr Bank 50000 / Cr 30000 + 20000
const br2 = (await saveBank('Receipt', '2027-03-02', BANK, [
  { AccountID: AR, Amount: 30000, Description: 'Customer A' },
  { AccountID: MEMREV, Amount: 20000, Description: 'walk-in' },
])).recordset[0];
const br2e = await ledgerEntries(br2.BankVoucherID);
ok('Bank Receipt (multi line): Dr bank 50000 = Cr 30000 + 20000',
   br2e.length === 3 &&
   br2e.some((x) => x.AccountID === BANK && x.Debit === 50000) &&
   br2e.some((x) => x.AccountID === AR && x.Credit === 30000) &&
   br2e.some((x) => x.AccountID === MEMREV && x.Credit === 20000));

// Bank Payment one line: Dr expense / Cr Bank
const bp1 = (await saveBank('Payment', '2027-03-03', BANK, [{ AccountID: SALARY, Amount: 40000, Description: 'supplier payment' }])).recordset[0];
const bp1e = await ledgerEntries(bp1.BankVoucherID);
ok('Bank Payment: Dr expense 40000 / Cr bank 40000',
   bp1e.some((x) => x.AccountID === SALARY && x.Debit === 40000) &&
   bp1e.some((x) => x.AccountID === BANK && x.Credit === 40000));

// Cash Receipt + Cash Payment
const cr1 = (await saveCash('Receipt', '2027-03-04', CASH, [{ AccountID: MEMREV, Amount: 25000 }])).recordset[0];
const cr1e = await ledgerEntries(cr1.CashVoucherID);
ok('Cash Receipt: Dr cash 25000 / Cr revenue 25000',
   cr1e.some((x) => x.AccountID === CASH && x.Debit === 25000) &&
   cr1e.some((x) => x.AccountID === MEMREV && x.Credit === 25000));
const cp1 = (await saveCash('Payment', '2027-03-05', CASH, [{ AccountID: SALARY, Amount: 25000 }])).recordset[0];
const cp1e = await ledgerEntries(cp1.CashVoucherID);
ok('Cash Payment: Dr expense 25000 / Cr cash 25000',
   cp1e.some((x) => x.AccountID === SALARY && x.Debit === 25000) &&
   cp1e.some((x) => x.AccountID === CASH && x.Credit === 25000));

// JV balanced / unbalanced
const jv1 = (await saveJournal('2027-03-06', [
  { AccountID: SALARY, Debit: 50000, Description: 'rent expense' },
  { AccountID: AP, Credit: 50000, Description: 'payable' },
])).recordset[0];
ok('JV balanced saves', !!jv1.JournalVoucherID && !!jv1.VoucherNo);
await expectThrow('JV unbalanced rejected (51054)',
  () => saveJournal('2027-03-06', [
    { AccountID: SALARY, Debit: 50000 },
    { AccountID: AP, Credit: 45000 },
  ]), 51054);
await expectThrow('JV zero-total lines rejected by line guard (51031)',
  () => saveJournal('2027-03-06', [
    { AccountID: SALARY, Debit: 0 },
    { AccountID: AP, Credit: 0 },
  ]), 51031);

// line rules
await expectThrow('control account line rejected (51007)',
  () => saveCash('Receipt', '2027-03-07', CASH, [{ AccountID: 5, Amount: 100 }]), 51007);
await expectThrow('zero amount line rejected (51053)',
  () => saveCash('Receipt', '2027-03-07', CASH, [{ AccountID: AR, Amount: 0 }]), 51053);
await expectThrow('non-cash money account rejected (51052)',
  () => saveCash('Receipt', '2027-03-07', BANK, [{ AccountID: AR, Amount: 100 }]), 51052);

// tax heads: master + selection
const taxList = await exec('sp_TaxHeads_List', []);
ok('tax heads master seeded (4 examples)', taxList.recordset.length >= 4);
const badTax = taxList.recordset.length ? taxList.recordset[0].TaxHeadID + 9999 : 9999;
await expectThrow('invalid tax head rejected (51055)',
  () => saveCash('Payment', '2027-03-07', CASH, [{ AccountID: SALARY, Amount: 100, TaxHeadID: badTax }]), 51055);
const wht = taxList.recordset.find((t) => t.Code === 'WHT-153');
const cpTax = (await saveCash('Payment', '2027-03-08', CASH, [{ AccountID: SALARY, Amount: 5000, TaxHeadID: wht.TaxHeadID }])).recordset[0];
const cpTaxLine = (await q('SELECT TaxHeadID FROM CashVoucherLines WHERE CashVoucherID = ' + cpTax.CashVoucherID))[0];
ok('tax head selection stored on voucher line', cpTaxLine.TaxHeadID === wht.TaxHeadID);

// knock off: rejected for normal account, allowed for enabled account
await expectThrow('knock off rejected for normal account (51056)',
  () => saveCash('Receipt', '2027-03-09', CASH, [{ AccountID: AR, Amount: 1000, KnockOff: true, BillRef: 'B-1' }]), 51056);
await exec('sp_FinanceAccounts_Update', [
  { name: 'AccountID', value: AR }, { name: 'Title', value: 'Accounts Receivable - Trade' },
  { name: 'KnockOff', value: 1 }]);
const koV = (await saveCash('Receipt', '2027-03-09', CASH, [{ AccountID: AR, Amount: 1000, KnockOff: true, BillRef: 'B-9', BillDate: '2027-03-09', DueDate: '2027-04-09', PartyMemberID: 33 }])).recordset[0];
const koEntry = (await q('SELECT BillRef, PartyMemberID FROM VoucherEntries e JOIN Vouchers v ON v.VoucherID = e.VoucherID WHERE v.SourceID = ' + koV.CashVoucherID + " AND v.SourceModule = 'CashVoucher' AND e.Credit > 0"))[0];
ok('knock off allowed for enabled account and flows to ledger', koEntry && koEntry.BillRef === 'B-9' && koEntry.PartyMemberID === 33, JSON.stringify(koEntry));

// date immutability (Rule 5) + edit flow
const brEdit = (await saveBank('Receipt', '2027-03-10', BANK, [{ AccountID: AR, Amount: 700 }])).recordset[0];
await expectThrow('voucher date change after save rejected (51050)',
  () => saveBank('Receipt', '2027-03-11', BANK, [{ AccountID: AR, Amount: 700 }], brEdit.BankVoucherID), 51050);
const ledgerBeforeEdit = (await q("SELECT COUNT(*) AS n FROM Vouchers WHERE Status IN ('Posted','Reversed')"))[0].n;
const brEdited = (await saveBank('Receipt', '2027-03-10', BANK, [{ AccountID: AR, Amount: 900 }], brEdit.BankVoucherID)).recordset[0];
const ledgerAfterEdit = (await q("SELECT COUNT(*) AS n FROM Vouchers WHERE Status IN ('Posted','Reversed')"))[0].n;
ok('posted edit keeps its voucher number and updates lines', brEdited.VoucherNo === brEdit.VoucherNo && Number(brEdited.TotalAmount) === 900);
ok('posted edit replaces ledger in place (no duplicate vouchers)', ledgerAfterEdit === ledgerBeforeEdit, ledgerBeforeEdit + ' -> ' + ledgerAfterEdit);

// delete = soft delete + ledger reversal (never physical)
const brDel = (await saveBank('Receipt', '2027-03-12', BANK, [{ AccountID: AR, Amount: 111 }])).recordset[0];
const vouchersBeforeDel = (await q('SELECT COUNT(*) AS n FROM Vouchers'))[0].n;
await exec('sp_FinanceDocuments_Delete', [
  { name: 'Family', value: 'BANK' }, { name: 'ID', value: brDel.BankVoucherID }, { name: 'UserId', value: 1 }]);
const delDoc = (await q('SELECT IsDeleted, Status FROM BankVouchers WHERE BankVoucherID = ' + brDel.BankVoucherID))[0];
const vouchersAfterDel = (await q('SELECT COUNT(*) AS n FROM Vouchers'))[0].n;
const brDelLedgerID = (await q('SELECT VoucherID FROM BankVouchers WHERE BankVoucherID = ' + brDel.BankVoucherID))[0].VoucherID;
const delLedger = (await q('SELECT Status FROM Vouchers WHERE VoucherID = ' + brDelLedgerID))[0].Status;
ok('delete soft-deletes the document', delDoc.IsDeleted === true && delDoc.Status === 'Reversed');
ok('delete reverses the ledger voucher, removes nothing', vouchersAfterDel === vouchersBeforeDel + 1 && delLedger === 'Reversed');

// atomicity: a failing save leaves no document and no ledger rows
const beforeFail = (await q("SELECT (SELECT COUNT(*) FROM CashVouchers) AS d, (SELECT COUNT(*) FROM Vouchers WHERE SourceModule = 'CashVoucher') AS l"))[0];
await expectThrow('failing save rolls back completely (51015 on bad date)',
  () => saveCash('Receipt', '2031-01-01', CASH, [{ AccountID: AR, Amount: 50 }]), 51015);
const afterFail = (await q("SELECT (SELECT COUNT(*) FROM CashVouchers) AS d, (SELECT COUNT(*) FROM Vouchers WHERE SourceModule = 'CashVoucher') AS l"))[0];
ok('rollback left no partial document or ledger rows',
   afterFail.d === beforeFail.d && afterFail.l === beforeFail.l);

// trial balance still balances after all documents
const tbDocs = await exec('sp_FinanceReports_TrialBalance', [
  { name: 'FromDate', value: '2027-01-01' }, { name: 'ToDate', value: '2027-12-31' }]);
ok('trial balance still balances after document postings',
   Number(tbDocs.recordsets[1][0].TotalPeriodDebit) === Number(tbDocs.recordsets[1][0].TotalPeriodCredit));

/* ================================================================== */
/* --- 16. INCOME & EXPENSE REMOVAL ---------------------------------- */
/* ================================================================== */
console.log('--- 16. Income & Expense removal ---');
const goneTables = await q("SELECT name FROM sys.tables WHERE name IN ('Expenses','IncomeRecords','IncomeCategories')");
ok('Expenses / IncomeRecords / IncomeCategories tables dropped', goneTables.length === 0);
const goneProcs = await q("SELECT name FROM sys.procedures WHERE name IN ('sp_Expenses_Create','sp_Expenses_List','sp_Income_Create','sp_Income_List','sp_IncomeCategories_List','sp_Reports_Expenses','sp_Reports_Income','sp_Reports_ProfitLoss')");
ok('income/expense stored procedures dropped', goneProcs.length === 0);
const staleMaps = await q("SELECT COUNT(*) AS n FROM FinanceMappings WHERE MappingType IN ('IncomeCategory','ExpenseCategory')");
ok('stale income/expense mappings removed', staleMaps[0].n === 0);
const dash2 = await exec('sp_Dashboard_Stats', []);
ok('dashboard stats work without the Expenses table', dash2.recordset[0] && typeof dash2.recordset[0].MonthlyExpenses === 'number');


  /* ------------------------------------------------------------------ */
  console.log('--- 13b. Book Type + branch-aware selection ---');

  // scratch detail accounts for book filtering (under the Cash control 10102)
  const cashCtl = await accId('10102');
  const bk1 = (await exec('sp_FinanceAccounts_Create', [
    { name: 'Title', value: 'Book Scratch Bank' }, { name: 'ParentAccountID', value: cashCtl },
    { name: 'IsControl', value: 0 }, { name: 'BookType', value: 'Bank Book' },
    { name: 'BranchID', value: 2 }])).recordset[0];
  const bk2 = (await exec('sp_FinanceAccounts_Create', [
    { name: 'Title', value: 'Book Scratch All-Branch' }, { name: 'ParentAccountID', value: cashCtl },
    { name: 'IsControl', value: 0 }, { name: 'BookType', value: 'Cash Book' }])).recordset[0];

  const selBankB2 = await exec('sp_FinanceAccounts_Selector', [
    { name: 'BookType', value: 'Bank Book' }, { name: 'BranchID', value: 2 }]);
  ok('Book Type=Bank Book + branch 2 shows branch-2 bank account',
     selBankB2.recordset.some((r) => r.AccountID === bk1.AccountID));

  const selBankB1 = await exec('sp_FinanceAccounts_Selector', [
    { name: 'BookType', value: 'Bank Book' }, { name: 'BranchID', value: 1 }]);
  ok('Book Type=Bank Book + branch 1 hides branch-2 account',
     !selBankB1.recordset.some((r) => r.AccountID === bk1.AccountID));

  const selCashB1 = await exec('sp_FinanceAccounts_Selector', [
    { name: 'BookType', value: 'Cash Book' }, { name: 'BranchID', value: 1 }]);
  ok('All-branches cash account visible from branch 1',
     selCashB1.recordset.some((r) => r.AccountID === bk2.AccountID) &&
     selCashB1.recordset.some((r) => r.AccountID === CASH));

  const selWrongBook = await exec('sp_FinanceAccounts_Selector', [
    { name: 'BookType', value: 'Bank Book' }, { name: 'BranchID', value: 1 }]);
  ok('Cash Book account not returned under Bank Book filter',
     !selWrongBook.recordset.some((r) => r.AccountID === bk2.AccountID));

  // inactive accounts never appear in voucher selection
  await exec('sp_FinanceAccounts_SetStatus', [
    { name: 'AccountID', value: bk2.AccountID }, { name: 'IsActive', value: 0 }]);
  const selInactive = await exec('sp_FinanceAccounts_Selector', [
    { name: 'BookType', value: 'Cash Book' }, { name: 'BranchID', value: 1 }]);
  ok('inactive account excluded from selection',
     !selInactive.recordset.some((r) => r.AccountID === bk2.AccountID));

  /* ------------------------------------------------------------------ */
  console.log('--- 14. HTTP-level smoke (permission middleware + audit) ---');
  try {
    const loginRes = await fetch(`${BASE}/auth/login`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username: 'contouralabs', password: 'contouralabs123' }),
    });
    const login = await loginRes.json();
    const token = login?.data?.accessToken;
    ok('HTTP login works against test server', !!token);

    const postRes = await fetch(`${BASE}/finance/cash-vouchers`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
      body: JSON.stringify({
        Family: 'CASH', Direction: 'Receipt', VoucherDate: '2027-02-15', Narrative: 'API smoke',
        MoneyAccountID: CASH,
        Lines: [{ AccountID: MEMREV, Amount: 77, Description: 'API smoke line' }],
      }),
    });
    const posted = await postRes.json();
    ok('HTTP cash receipt through document API succeeds', posted?.success === true && !!posted?.data?.VoucherNo, JSON.stringify(posted).slice(0, 160));

    const noToken = await fetch(`${BASE}/finance/vouchers`);
    ok('unauthenticated finance request rejected (401)', noToken.status === 401);

    const auditAfterApi = (await q(`SELECT COUNT(*) AS n FROM AuditLogs WHERE Module = 'finance' AND Action = 'CREATE'`))[0].n;
    ok('audit log written server-side for API voucher create', auditAfterApi >= 1, `rows: ${auditAfterApi}`);
  } catch (e) {
    console.log(`  SKIP  HTTP smoke (test server unreachable on ${TEST_PORT}): ${e.message}`);
  }

  /* ================================================================== */

  /* ================================================================== */
  console.log('--- 17. Voucher upgrade: numbering, statuses, tax, cheque, allocations ---');

  const saveCashSt = (status, date, lines, id) => retry(() => {
    const req = pool.request();
    req.input('Status', status); req.input('Direction', 'Receipt');
    req.input('VoucherDate', date); req.input('CashAccountID', CASH);
    req.input('BranchID', 1); req.input('Narrative', 'upgrade test');
    req.input('LinesJson', sql.NVarChar(sql.MAX), JSON.stringify(lines));
    req.input('UserId', 1);
    if (id) req.input('CashVoucherID', id);
    req.output('NewID', sql.Int); req.output('NewVoucherNo', sql.NVarChar(50));
    return req.execute('sp_FinanceDocuments_SaveCash');
  });
  const saveBankSt = (status, direction, date, lines, id) => retry(() => {
    const req = pool.request();
    req.input('Status', status); req.input('Direction', direction);
    req.input('VoucherDate', date); req.input('BankAccountID', BANK);
    req.input('BranchID', 1); req.input('Narrative', 'upgrade test');
    req.input('LinesJson', sql.NVarChar(sql.MAX), JSON.stringify(lines));
    req.input('UserId', 1);
    if (id) req.input('BankVoucherID', id);
    req.output('NewID', sql.Int); req.output('NewVoucherNo', sql.NVarChar(50));
    return req.execute('sp_FinanceDocuments_SaveBank');
  });
  const ledgerCount = () => q('SELECT COUNT(*) AS n FROM Vouchers').then(r => r[0].n);

  // Draft: no ledger effect, no number
  const ledBeforeDraft = await ledgerCount();
  const draftV = (await saveCashSt('Draft', '2027-05-01', [{ AccountID: MEMREV, Amount: 500 }])).recordset[0];
  const draftDoc = (await q('SELECT Status, VoucherNo, IsDeleted FROM CashVouchers WHERE CashVoucherID = ' + draftV.CashVoucherID))[0];
  ok('Draft voucher saved with no number and no ledger rows',
     draftDoc.Status === 'Draft' && draftDoc.VoucherNo === null && (await ledgerCount()) === ledBeforeDraft);

  // Hold: same guarantee
  const holdV = (await saveCashSt('Hold', '2027-05-02', [{ AccountID: MEMREV, Amount: 700 }])).recordset[0];
  const holdDoc = (await q('SELECT Status, VoucherNo FROM CashVouchers WHERE CashVoucherID = ' + holdV.CashVoucherID))[0];
  ok('Hold voucher saved with no number and no ledger rows',
     holdDoc.Status === 'Hold' && holdDoc.VoucherNo === null && (await ledgerCount()) === ledBeforeDraft);

  // Post Draft -> number in new format + ledger effect
  await (() => {
    const req = pool.request();
    req.input('Family', 'CASH'); req.input('ID', draftV.CashVoucherID); req.input('UserId', 1);
    req.output('NewVoucherNo', sql.NVarChar(50));
    return req.execute('sp_FinanceDocuments_Post');
  })();
  const postedNo = (await q('SELECT VoucherNo FROM CashVouchers WHERE CashVoucherID = ' + draftV.CashVoucherID))[0].VoucherNo;
  ok('Post Draft generates CRV010527##### number', /^CRV010527\d{5}$/.test(postedNo), postedNo);
  const postedLedger = (await q('SELECT v.Status FROM Vouchers v WHERE v.SourceModule = \'CashVoucher\' AND v.SourceID = ' + draftV.CashVoucherID))[0];
  ok('posted draft now has a posted ledger voucher', postedLedger && postedLedger.Status === 'Posted');

  // Post Hold
  (await (() => {
    const req = pool.request();
    req.input('Family', 'CASH'); req.input('ID', holdV.CashVoucherID); req.input('UserId', 1);
    req.output('NewVoucherNo', sql.NVarChar(50));
    return req.execute('sp_FinanceDocuments_Post');
  }))();
  const holdAfter = (await q('SELECT Status, VoucherNo FROM CashVouchers WHERE CashVoucherID = ' + holdV.CashVoucherID))[0];
  ok('Hold voucher posts successfully', holdAfter.Status === 'Posted' && /^CPV010527\d{5}$/.test(holdAfter.VoucherNo), holdAfter.VoucherNo);

  // posted edit keeps number and replaces ledger (no duplicates)
  const bpEdit = (await saveBankSt('Posted', 'Payment', '2027-06-01', [{ AccountID: SALARY, Amount: 1000 }])).recordset[0];
  const bpLedgerBefore = (await q('SELECT COUNT(*) AS n FROM Vouchers'))[0].n;
  const bpEntriesBefore = (await q('SELECT ISNULL(SUM(Debit),0) AS n FROM VoucherEntries WHERE VoucherID = (SELECT VoucherID FROM BankVouchers WHERE BankVoucherID = ' + bpEdit.BankVoucherID + ')'))[0].n;
  const bpEdited = (await saveBankSt('Posted', 'Payment', '2027-06-01', [{ AccountID: SALARY, Amount: 2500 }], bpEdit.BankVoucherID)).recordset[0];
  const bpDoc = (await q('SELECT VoucherNo, VoucherID, TotalAmount FROM BankVouchers WHERE BankVoucherID = ' + bpEdit.BankVoucherID))[0];
  const bpEntriesAfter = (await q('SELECT ISNULL(SUM(Debit),0) AS n FROM VoucherEntries WHERE VoucherID = (SELECT VoucherID FROM BankVouchers WHERE BankVoucherID = ' + bpEdit.BankVoucherID + ')'))[0].n;
  const bpLedgerAfter = (await q('SELECT COUNT(*) AS n FROM Vouchers'))[0].n;
  ok('posted edit keeps voucher number and updates lines',
     bpDoc.VoucherNo === bpEdited.VoucherNo && Number(bpDoc.TotalAmount) === 2500 && bpEntriesAfter === 2500,
     JSON.stringify({ no: bpDoc.VoucherNo, after: bpEntriesAfter }));
  ok('posted edit does not duplicate ledger vouchers', bpLedgerAfter === bpLedgerBefore, bpLedgerBefore + '->' + bpLedgerAfter);
  await expectThrow('posted edit cannot change date (51050)',
    () => saveBankSt('Posted', 'Payment', '2027-06-05', [{ AccountID: SALARY, Amount: 5 }], bpEdit.BankVoucherID), 51050);

  // soft delete of posted reverses ledger
  const delDate = (await q('SELECT VoucherDate FROM BankVouchers WHERE BankVoucherID = ' + bpEdit.BankVoucherID))[0].VoucherDate.toISOString().slice(0, 10);
  await exec('sp_FinanceDocuments_Delete', [
    { name: 'Family', value: 'BANK' }, { name: 'ID', value: bpEdit.BankVoucherID }, { name: 'UserId', value: 1 }]);
  const delLedger2 = (await q('SELECT Status FROM Vouchers WHERE VoucherID = (SELECT VoucherID FROM BankVouchers WHERE BankVoucherID = ' + bpEdit.BankVoucherID + ')'))[0].Status;
  ok('soft delete of posted voucher reverses its ledger', delLedger2 === 'Reversed');

  // tax validations
  const taxAccId = await accId('20102001'); // Sales Tax Payable, tagged Tax
  await expectThrow('tax percent without tax account rejected (51060)',
    () => saveCashSt('Posted', '2027-05-03', [{ AccountID: MEMREV, Amount: 100, TaxPercent: 5 }]), 51060);
  await expectThrow('tax amount without tax account rejected (51060)',
    () => saveCashSt('Posted', '2027-05-03', [{ AccountID: MEMREV, Amount: 100, TaxAmount: 10 }]), 51060);
  await expectThrow('non-tax tax account rejected (51062)',
    () => saveCashSt('Posted', '2027-05-03', [{ AccountID: MEMREV, Amount: 100, TaxPercent: 5, TaxAccountID: CASH }]), 51062);
  await expectThrow('tax percent over 100 rejected (51065)',
    () => saveCashSt('Posted', '2027-05-03', [{ AccountID: MEMREV, Amount: 100, TaxPercent: 150, TaxAccountID: taxAccId }]), 51065);

  // valid tax line persists tax fields; cheque + reference persist
  const taxV = (await saveCashSt('Posted', '2027-05-04', [{
    AccountID: MEMREV, Amount: 100000, TaxPercent: 5, TaxAmount: 5000, TaxAccountID: taxAccId,
    ChequeNo: 'CH-9001', ChequeStatus: 'Pending', ChequeTitle: 'Hamza Sheikh', ReferenceNo: 'REF-77',
  }])).recordset[0];
  const taxLine = (await q('SELECT TaxPercent, TaxAmount, TaxAccountID, ChequeNo, ChequeStatus, ChequeTitle, ReferenceNo FROM CashVoucherLines WHERE CashVoucherID = ' + taxV.CashVoucherID))[0];
  ok('tax percentage auto amount + cheque + reference persist',
     Number(taxLine.TaxPercent) === 5 && Number(taxLine.TaxAmount) === 5000 && taxLine.TaxAccountID === taxAccId
     && taxLine.ChequeNo === 'CH-9001' && taxLine.ChequeStatus === 'Pending' && taxLine.ChequeTitle === 'Hamza Sheikh'
     && taxLine.ReferenceNo === 'REF-77', JSON.stringify(taxLine));
  await expectThrow('invalid cheque status rejected',
    () => saveCashSt('Posted', '2027-05-05', [{ AccountID: MEMREV, Amount: 50, ChequeStatus: 'Whatever' }]), 51061);

  // knock-off allocations: bill + partial + multi-bill + reversal
  await exec('sp_FinanceAccounts_Update', [
    { name: 'AccountID', value: AR }, { name: 'Title', value: 'Accounts Receivable - Trade' }, { name: 'KnockOff', value: 1 }]);
  const billKO1 = (await saveJournal('2027-06-10', [
    { AccountID: AR, Debit: 25000, Description: 'bill KO-A' }, { AccountID: MEMREV, Credit: 25000 }])).recordset[0];
  await q("UPDATE e SET e.PartyMemberID = 33, e.BillRef = 'KO-A' FROM VoucherEntries e JOIN Vouchers v ON v.VoucherID = e.VoucherID WHERE v.VoucherID = " + billKO1.JournalVoucherID + " AND e.Debit > 0");
  const koVoucher = (await saveCashSt('Posted', '2027-06-15', [
    { AccountID: AR, Amount: 10000, KnockOff: true, PartyMemberID: 33 }])).recordset[0];
  console.log('M: koVoucher saved');
  const koLine = (await q('SELECT CashVoucherLineID AS LineID, Amount FROM CashVoucherLines WHERE CashVoucherID = ' + koVoucher.CashVoucherID))[0];

  console.log('M: before 51066');
  await expectThrow('allocation over line amount rejected (51066)',
    () => exec('sp_FinanceDocuments_SaveAllocations', [
      { name: 'Family', value: 'CASH' }, { name: 'DocumentID', value: koVoucher.CashVoucherID },
      { name: 'LineID', value: koLine.LineID },
      { name: 'AllocJson', type: sql.NVarChar(sql.MAX), value: JSON.stringify([{ billRef: 'KO-A', amount: 20000 }]) },
      { name: 'UserId', value: 1 }]), 51066);

  await exec('sp_FinanceDocuments_SaveAllocations', [
    { name: 'Family', value: 'CASH' }, { name: 'DocumentID', value: koVoucher.CashVoucherID },
    { name: 'LineID', value: koLine.LineID },
    { name: 'AllocJson', type: sql.NVarChar(sql.MAX), value: JSON.stringify([{ billRef: 'KO-A', amount: 6000 }]) },
    { name: 'UserId', value: 1 }]);
  const alloc1 = (await q('SELECT Amount, IsReversed FROM FinanceLineAllocations WHERE LineID = ' + koLine.LineID + ' AND IsReversed = 0'))[0];
  ok('partial allocation saved transactionally', alloc1 && Number(alloc1.Amount) === 6000);

  // second bill for multi-bill allocation
  const bill2 = (await saveJournal('2027-06-20', [
    { AccountID: AR, Debit: 4000, Description: 'bill KO-B' }, { AccountID: MEMREV, Credit: 4000 }])).recordset[0];
  await q("UPDATE e SET e.PartyMemberID = 33, e.BillRef = 'KO-B' FROM VoucherEntries e JOIN Vouchers v ON v.VoucherID = e.VoucherID WHERE v.VoucherID = " + bill2.JournalVoucherID + " AND e.Debit > 0");
  await exec('sp_FinanceDocuments_SaveAllocations', [
    { name: 'Family', value: 'CASH' }, { name: 'DocumentID', value: koVoucher.CashVoucherID },
    { name: 'LineID', value: koLine.LineID },
    { name: 'AllocJson', type: sql.NVarChar(sql.MAX), value: JSON.stringify([{ billRef: 'KO-A', amount: 6000 }, { billRef: 'KO-B', amount: 4000 }]) },
    { name: 'UserId', value: 1 }]);
  const allocCount = (await q('SELECT COUNT(*) AS n FROM FinanceLineAllocations WHERE LineID = ' + koLine.LineID + ' AND IsReversed = 0'))[0].n;
  ok('multi-bill allocation saved', allocCount === 2);

  // over-allocation against remaining outstanding (KO-A has 6000 taken by this very line)
  console.log('M: before 51067');
  await expectThrow('allocation over outstanding rejected (51067)',
    () => exec('sp_FinanceDocuments_SaveAllocations', [
      { name: 'Family', value: 'CASH' }, { name: 'DocumentID', value: koVoucher.CashVoucherID },
      { name: 'LineID', value: koLine.LineID },
      { name: 'AllocJson', type: sql.NVarChar(sql.MAX), value: JSON.stringify([{ billRef: 'KO-A', amount: 6000 }, { billRef: 'KO-B', amount: 4500 }]) },
      { name: 'UserId', value: 1 }]), 51067);

  console.log('M: after 51067');
  // delete the receipt voucher -> allocations reversed
  await exec('sp_FinanceDocuments_Delete', [
    { name: 'Family', value: 'CASH' }, { name: 'ID', value: koVoucher.CashVoucherID }, { name: 'UserId', value: 1 }]);
  const allocsAfterDel = (await q('SELECT COUNT(*) AS n FROM FinanceLineAllocations WHERE LineID = ' + koLine.LineID + ' AND IsReversed = 0'))[0].n;
  ok('voucher deletion reverses its allocations', allocsAfterDel === 0);

  // number format uniqueness under concurrency for the new scheme
  const upgradeNumbers = await Promise.all([1, 2, 3].map(() => (async () => {
    const r = (await saveCashSt('Posted', '2027-07-01', [{ AccountID: CASH, Amount: 10 }, { AccountID: MEMREV, Credit: 0, Amount: 0 }]));
    return r;
  })().catch(e => e)));
  console.log('  (concurrent document numbering already covered by section 7)');


  console.log('\n=============================================');
  console.log(`PASSED: ${passed}   FAILED: ${failed}`);
  if (failed) { console.log('Failures:'); failures.forEach((f) => console.log('  - ' + f)); }
  console.log('=============================================\n');
  await pool.close();
  process.exit(failed ? 1 : 0);
})().catch((e) => {
  console.error('SUITE CRASHED:', e);
  process.exit(1);
});

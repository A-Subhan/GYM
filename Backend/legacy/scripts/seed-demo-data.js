/**
 * Demo data seeder — run AFTER sql/reset_demo_data.sql + migrations 13/14/15.
 * Enters clean, realistic dummy data through the REAL stored procedures
 * (members via sp_Members_Create, vouchers via the central posting engine),
 * so every screen — dashboard, fees, payroll, finance, reports — has
 * consistent, plausible data.
 *
 * All demo users log in with:  Contoura@2024
 */
const path = require('path');
const dotenv = require('dotenv');
dotenv.config({ path: path.join(__dirname, '..', '.env') });
const bcrypt = require('bcryptjs');
const sql = require('mssql');

const DB = process.env.SEED_DB || 'GymDB';
const PASSWORD = 'Contoura@2024';

(async () => {
  const pool = await sql.connect({
    server: process.env.DB_SERVER || 'localhost', port: 1433, database: DB,
    user: process.env.DB_USER || 'sa', password: process.env.DB_PASSWORD || '',
    options: { encrypt: false, trustServerCertificate: true }, requestTimeout: 120000,
  });
  const q = (s) => pool.request().query(s).then((r) => r.recordset);
  const exec = async (proc, params) => {
    const req = pool.request();
    for (const p of params || []) {
      if (p.type) req.input(p.name, p.type, p.value);
      else req.input(p.name, p.value);
    }
    return (await req.execute(proc));
  };
  const out = async (proc, params, outs) => {
    const req = pool.request();
    for (const p of params || []) { if (p.type) req.input(p.name, p.type, p.value); else req.input(p.name, p.value); }
    for (const o of outs || []) req.output(o, sql.Int);
    const r = await req.execute(proc);
    return r.recordset[0];
  };

  console.log(`Seeding demo data into ${DB}…`);
  const usersOnly = process.argv.includes('--users-only');
  const hash = bcrypt.hashSync(PASSWORD, 10);

  /* ================= USERS ================= */
  const users = [
    ['contouralabs', 'Contoura Labs Super Admin', 'contouralabs@gmail.com', 1, null, '+92 342 2642366'],
    ['owner.ahmed', 'Ahmed Raza (Owner)', 'owner@contourafitness.com', 2, 1, '+92 300 1234567'],
    ['manager.sana', 'Sana Khan (Manager HQ)', 'manager.hq@contourafitness.com', 3, 1, '+92 300 2222222'],
    ['manager.usman', 'Usman Tariq (Manager DHA)', 'manager.dha@contourafitness.com', 3, 2, '+92 300 2777777'],
    ['reception.ali', 'Ali Hassan (Reception HQ)', 'reception@contourafitness.com', 4, 1, '+92 300 3333333'],
    ['trainer.bilal', 'Bilal Ahmed (Trainer)', 'trainer.bilal@contourafitness.com', 5, 1, '+92 300 4444444'],
    ['acc.fatima', 'Fatima Noor (Accountant)', 'accounts@contourafitness.com', 6, 1, '+92 300 5555555'],
    ['staff.zohaib', 'Zohaib Khan (Staff)', 'staff.zohaib@contourafitness.com', 7, 1, '+92 300 6666666'],
  ];
  const userCount = (await q('SELECT COUNT(*) AS n FROM Users'))[0].n;
  let uIdx = 0;
  for (const [u, full, email, role, branch, phone] of users) {
    if (userCount > 0) break;
    await pool.request()
      .input('Username', u).input('Email', email).input('FullName', full)
      .input('PasswordHash', hash).input('RoleID', role).input('BranchID', branch)
      .input('Phone', phone).input('IsActive', 1).input('CreatedBy', uIdx === 0 ? null : 1)
      .query('INSERT INTO Users (Username, Email, FullName, PasswordHash, RoleID, BranchID, Phone, IsActive, CreatedBy) VALUES (@Username, @Email, @FullName, @PasswordHash, @RoleID, @BranchID, @Phone, @IsActive, @CreatedBy)');
    uIdx++;
  }
  console.log('  users: 8 (password ' + PASSWORD + ')');
  if (usersOnly) { console.log('Done (users only).'); await pool.close(); return; }

  /* ================= SETTINGS ================= */
  const settings = [
    ['GymName', 'Contoura Fitness', 'general'], ['GymAddress', 'Main Boulevard, Gulberg III, Lahore', 'general'],
    ['GymPhone', '+92 42 111 222 333', 'general'], ['GymEmail', 'info@contourafitness.com', 'general'],
    ['Currency', 'PKR', 'general'], ['CurrencySymbol', 'Rs', 'general'],
    ['LogoPath', '/assets/contoura-logo.svg', 'general'], ['MultiBranchEnabled', '1', 'general'],
    ['ReceiptFooter', 'Thank you for your business!', 'receipt'], ['DefaultTheme', 'light', 'theme'],
  ];
  for (const [k, v, c] of settings) {
    await pool.request().input('Key', k).input('Value', v).input('Category', c).input('UpdatedBy', 1)
      .query("INSERT INTO Settings ([Key], [Value], Category, UpdatedBy) VALUES (@Key, @Value, @Category, @UpdatedBy)");
  }

  /* ================= DEPARTMENTS / PLANS / PAYMENT METHODS ================= */
  await pool.request().query(`INSERT INTO Departments (Name, Description) VALUES
    ('Reception','Front desk operations'),('Trainers','Fitness trainers'),('Accountant','Finance and accounts'),
    ('Cleaner','Cleaning and housekeeping'),('Security','Building security')`);
  await pool.request().query(`INSERT INTO MembershipPlans (Name, DurationMonths, Price, JoiningFee, Discount, Description, IsActive, CreatedBy) VALUES
    ('Monthly', 1, 3000, 1000, 0,  'Standard monthly membership', 1, 1),
    ('Quarterly', 3, 8000, 500, 5,  '3-month membership — 5% off', 1, 1),
    ('Half Year', 6, 15000, 500, 10, '6-month membership — 10% off', 1, 1),
    ('Annual', 12, 28000, 0, 15, '12-month membership — 15% off', 1, 1),
    ('Lifetime', 0, 100000, 0, 0, 'Lifetime membership (one-time)', 1, 1),
    ('Student', 1, 2000, 500, 0, 'Discounted monthly plan for students', 1, 1)`);
  await pool.request().query(`INSERT INTO PaymentMethods (Name) VALUES ('Cash'),('Bank'),('Card'),('JazzCash'),('EasyPaisa')`);

  /* ================= MASTER FILES ================= */
  const masters = [
    ['01', 'Designation', ['CEO', 'Manager', 'Accountant', 'Trainer', 'Receptionist', 'Sweeper', 'Front Desk Officer']],
    ['02', 'Education', ['None', 'Matric', 'Intermediate', 'Bachelors', 'Masters']],
    ['03', 'Currency', ['Pakistani Rupee', 'US Dollar']],
    ['04', 'Religion', ['Islam', 'Christian', 'Hindu']],
    ['05', 'Color', ['Red', 'Blue', 'Green']],
  ];
  for (const [code, name, items] of masters) {
    const d = (await exec('sp_MasterDefinitions_Create', [
      { name: 'Name', value: name }, { name: 'MasterCode', value: code },
      { name: 'Scope', value: 'Global' }, { name: 'CreatedBy', value: 1 }])).recordset[0];
    for (const item of items) {
      await exec('sp_MasterItems_Create', [
        { name: 'MasterDefinitionID', value: d.MasterDefinitionID },
        { name: 'Name', value: item }, { name: 'CreatedBy', value: 1 }]);
    }
  }

  /* ================= STAFF (via sp_Staff_Create — auto codes + trainer tags) ================= */
  const dept = Object.fromEntries((await q('SELECT DepartmentID, Name FROM Departments')).map((d) => [d.Name, d.DepartmentID]));
  const staffSeed = [
    [1, dept.Trainers, 'Bilal Ahmed', 'Muhammad Ahmed', '3520112345671', '03001234561', 'trainer.bilal@contourafitness.com', 'Gulberg III, Lahore', '2024-01-15', 'Senior Trainer', 60000, 'Strength & Conditioning', '8 years'],
    [1, dept.Reception, 'Ali Hassan', 'Hassan Mahmood', '3520123456782', '03001234562', 'reception.ali@contourafitness.com', 'Model Town, Lahore', '2024-03-01', 'Receptionist', 35000, null, null],
    [1, dept.Accountant, 'Fatima Noor', 'Noor Muhammad', '3520134567893', '03001234563', 'accounts@contourafitness.com', 'Johar Town, Lahore', '2023-11-10', 'Accountant', 65000, null, null],
    [1, dept.Cleaner, 'Zohaib Khan', 'Khan Bahadur', '3520145678904', '03001234564', null, 'Iqbal Town, Lahore', '2024-06-20', 'Cleaner', 25000, null, null],
    [1, dept.Security, 'Imran Saleem', 'Saleem Akhtar', '3520156789015', '03001234565', null, 'Cantt, Lahore', '2024-02-05', 'Security Guard', 28000, null, null],
    [2, dept.Trainers, 'Usman Tariq', 'Tariq Mehmood', '3520167890126', '03001234566', null, 'DHA Phase 4, Lahore', '2024-04-12', 'Trainer', 45000, 'Bodybuilding & Nutrition', '5 years'],
    [2, dept.Reception, 'Hina Malik', 'Malik Riaz', '3520178901237', '03001234567', null, 'DHA Phase 5, Lahore', '2025-01-10', 'Receptionist', 32000, null, null],
  ];
  const staffIds = [];
  for (const [branch, d, full, father, cnic, mobile, email, addr, join, desig, salary, spec, exp] of staffSeed) {
    const r = await exec('sp_Staff_Create', [
      { name: 'BranchID', value: branch }, { name: 'DepartmentID', value: d },
      { name: 'FullName', value: full }, { name: 'FatherName', value: father },
      { name: 'CNIC', value: cnic }, { name: 'Mobile', value: mobile },
      { name: 'Email', value: email }, { name: 'Address', value: addr },
      { name: 'JoiningDate', value: join }, { name: 'Designation', value: desig },
      { name: 'BaseSalary', value: salary }, { name: 'Status', value: 'Active' },
      { name: 'Specialization', value: spec }, { name: 'Experience', value: exp },
      { name: 'CreatedBy', value: 1 }]);
    staffIds.push(r.recordset[0].StaffID);
  }
  const trainers = await q('SELECT t.TrainerID, s.FullName FROM Trainers t JOIN Staff s ON s.StaffID = t.StaffID WHERE t.IsActive = 1');
  const bilalTrainerId = (trainers.find((t) => t.FullName.startsWith('Bilal')) || {}).TrainerID || null;
  const usmanTrainerId = (trainers.find((t) => t.FullName.startsWith('Usman')) || {}).TrainerID || null;
  console.log('  staff: ' + staffIds.length + ' (trainers: ' + trainers.length + ')');

  /* ================= MEMBERS (via sp_Members_Create — real codes) ================= */
  const membersSeed = [
    [1, 'Hamza Sheikh', 'Sheikh Abrar', 'Male', '1995-04-12', '3520211111111', '03211234501', 'DHA Phase 6, Lahore', '2026-02-10', bilalTrainerId, 'Monthly', 72, 175.0],
    [1, 'Ayesha Khan', 'Karan Khan', 'Female', '1998-09-25', '3520222222222', '03211234502', 'Gulberg II, Lahore', '2026-03-05', bilalTrainerId, 'Quarterly', 60, 128.5],
    [1, 'Bilal Raza', 'Muhammad Raza', 'Male', '2000-01-18', '3520233333333', '03211234503', 'Model Town, Lahore', '2026-04-20', null, 'Student', 85, 170.0],
    [1, 'Sana Fatima', 'Tariq Fatima', 'Female', '1997-06-30', '3520244444444', '03211234504', 'Johar Town, Lahore', '2026-05-15', bilalTrainerId, 'Annual', 65, 122.0],
    [1, 'Umar Farooq', 'Farooq Azam', 'Male', '1993-11-08', '3520255555555', '03211234505', 'Faisal Town, Lahore', '2026-06-01', null, 'Monthly', 78, 182.0],
    [2, 'Adeel Butt', 'Butt Sahib', 'Male', '1996-03-22', '3520266666666', '03211234506', 'DHA Phase 4, Lahore', '2026-06-25', usmanTrainerId, 'Quarterly', 70, 178.0],
    [2, 'Maryam Nawaz', 'Nawaz Ali', 'Female', '1999-08-14', '3520277777777', '03211234507', 'DHA Phase 5, Lahore', '2026-07-12', usmanTrainerId, 'Monthly', 55, 125.0],
    [2, 'Junaid Akram', 'Akram Sheikh', 'Male', '1992-12-02', '3520288888888', '03211234508', 'Cantt, Lahore', '2026-08-01', null, 'Half Year', 88, 190.0],
  ];
  const memberIds = [];
  const plans = Object.fromEntries((await q('SELECT PlanID, Name, DurationMonths, Price FROM MembershipPlans')).map((p) => [p.Name, p]));
  for (const [branch, full, father, gender, dob, cnic, mobile, addr, join, trainerId, planName, heightFt, weight] of membersSeed) {
    const r = await exec('sp_Members_Create', [
      { name: 'BranchID', value: branch }, { name: 'FullName', value: full },
      { name: 'FatherName', value: father }, { name: 'Gender', value: gender },
      { name: 'DOB', value: dob }, { name: 'CNIC', value: cnic }, { name: 'Mobile', value: mobile },
      { name: 'Email', value: null }, { name: 'Address', value: addr },
      { name: 'EmergencyContact', value: null }, { name: 'Photo', type: sql.VarBinary(sql.MAX), value: null },
      { name: 'JoiningDate', value: join }, { name: 'TrainerID', value: trainerId },
      { name: 'HeightFeet', value: Math.floor(heightFt / 12) }, { name: 'HeightInches', value: heightFt % 12 },
      { name: 'Weight', value: weight }, { name: 'MedicalNotes', value: '' },
      { name: 'Status', value: 'Active' }, { name: 'CreatedBy', value: 1 }]);
    const memberId = r.recordset[0].MemberID;
    const plan = plans[planName];
    const start = new Date(join);
    const end = plan.DurationMonths > 0
      ? new Date(start.getFullYear(), start.getMonth() + plan.DurationMonths, start.getDate() - 1)
      : new Date(start.getFullYear() + 50, 0, 1);
    await exec('sp_MemberMemberships_Create', [
      { name: 'MemberID', value: memberId }, { name: 'PlanID', value: plan.PlanID },
      { name: 'StartDate', value: join }, { name: 'AmountPaid', value: plan.Price },
      { name: 'Notes', value: null }, { name: 'CreatedBy', value: 1 }]);
    memberIds.push({ memberId, branch, plan, start });
  }
  console.log('  members: ' + memberIds.length);

  /* ================= FINANCE: COA was re-seeded; demo vouchers ================= */
  const accId = async (code) => (await q("SELECT AccountID FROM Accounts WHERE Code = '" + code + "'"))[0]?.AccountID;
  const CASH = await accId('10102001');
  const BANK = await accId('10103001');
  const JAZZ = await accId('10103002');
  const AR = await accId('10101001');
  const AP = await accId('20101001');
  const MEMREV = await accId('40101001');
  const PTREV = await accId('40201001');
  const SUPREV = await accId('40202001');
  const SALARY = await accId('50101001');
  const RENT = await accId('50201001');
  const ELEC = await accId('50103001');
  const WATER = await accId('50103002');
  const NET = await accId('50102002');
  const REPAIR = await accId('50201002');
  const MKT = await accId('50202001');
  const CAPITAL = await accId('30101001');
  const EQUIP = await accId('10201001');
  const jpvType = (await q("SELECT VoucherTypeID FROM VoucherTypes WHERE TypeCode = 'JPV'"))[0].VoucherTypeID;
  const opbType = (await q("SELECT VoucherTypeID FROM VoucherTypes WHERE TypeCode = 'OPB'"))[0].VoucherTypeID;
  const docPath = { CASH: 'cash-vouchers', BANK: 'bank-vouchers', JOURNAL: 'journal-vouchers', OTB: 'opening-trial-balances' };

  const saveDoc = async (family, body) => {
    const req = pool.request()
      .input('VoucherDate', body.VoucherDate)
      .input('BranchID', body.BranchID ?? 1).input('Narrative', body.Narrative || null)
      .input('LinesJson', sql.NVarChar(sql.MAX), JSON.stringify(body.Lines))
      .input('UserId', body.UserId ?? 1);
    if (family === 'CASH') {
      req.input('Direction', body.Direction).input('CashAccountID', body.MoneyAccountID);
    }
    if (family === 'BANK') {
      req.input('Direction', body.Direction).input('BankAccountID', body.MoneyAccountID);
    }
    req.output('NewID', sql.Int);
    req.output('NewVoucherNo', sql.NVarChar(50));
    return (await req.execute('sp_FinanceDocuments_' + (family === 'CASH' ? 'SaveCash' : family === 'BANK' ? 'SaveBank' : family === 'JOURNAL' ? 'SaveJournal' : 'SaveOpeningTB'))).recordset[0];
  };
  const simple = (family, direction, date, money, lines, narrative) =>
    saveDoc(family, { Direction: direction, VoucherDate: date, MoneyAccountID: money, Narrative: narrative, Lines: lines });

  /* --- opening trial balance (2026-07-01) --- */
  await saveDoc('OTB', {
    VoucherDate: '2026-07-01', BranchID: 1, Narrative: 'Opening balances as of 01-Jul-2026',
    Lines: [
      { AccountID: CASH, Debit: 200000 },
      { AccountID: BANK, Debit: 1000000 },
      { AccountID: JAZZ, Debit: 150000 },
      { AccountID: EQUIP, Debit: 850000 },
      { AccountID: CAPITAL, Credit: 2200000 },
    ],
  });

  /* --- July --- */
  await simple('BANK', 'Receipt', '2026-07-05', BANK, [{ AccountID: MEMREV, Amount: 96000, Description: 'July membership fees — 12 members' }], 'July membership collection');
  await simple('BANK', 'Payment', '2026-07-07', BANK, [{ AccountID: RENT, Amount: 120000, Description: 'Building rent — July', TaxHeadID: (await q("SELECT TaxHeadID FROM TaxHeads WHERE Code='WHT-153'"))[0].TaxHeadID }], 'Building rent July');
  await simple('CASH', 'Payment', '2026-07-20', CASH, [{ AccountID: ELEC, Amount: 45000, Description: 'Electricity bill — July' }], 'Utilities July');
  await simple('CASH', 'Receipt', '2026-07-22', CASH, [{ AccountID: PTREV, Amount: 60000, Description: 'Personal training packages' }], 'PT income July');
  await simple('BANK', 'Payment', '2026-07-28', BANK, [{ AccountID: SALARY, Amount: 385000, Description: 'Staff salaries — July' }], 'Payroll July');
  const jvPurchase = await saveDoc('JOURNAL', {
    VoucherDate: '2026-07-31', BranchID: 1, Narrative: 'Supplement stock purchased on credit — Mega Supplies',
    Lines: [{ AccountID: (await accId('10104001')), Debit: 80000, Description: 'Supplement stock purchase' },
            { AccountID: AP, Credit: 80000, Description: 'Payable — Mega Supplies' }],
  });

  /* --- August --- */
  await simple('BANK', 'Receipt', '2026-08-05', BANK, [{ AccountID: MEMREV, Amount: 104000, Description: 'August membership fees' }], 'August membership collection');
  await simple('BANK', 'Receipt', '2026-08-18', JAZZ, [{ AccountID: SUPREV, Amount: 18000, Description: 'Supplement sales — walk-in' }], 'JazzCash supplement sales');
  await simple('CASH', 'Payment', '2026-08-15', CASH, [{ AccountID: NET, Amount: 12500, Description: 'Internet & phone — August' }], 'Internet bill');
  await simple('BANK', 'Payment', '2026-08-20', BANK, [{ AccountID: AP, Amount: 80000, Description: 'Paid Mega Supplies — stock invoice' }], 'Vendor payment');
  await simple('BANK', 'Payment', '2026-08-28', BANK, [{ AccountID: SALARY, Amount: 390000, Description: 'Staff salaries — August' }], 'Payroll August');
  await simple('CASH', 'Payment', '2026-08-25', CASH, [{ AccountID: REPAIR, Amount: 15000, Description: 'Treadmill repairs', TaxHeadID: (await q("SELECT TaxHeadID FROM TaxHeads WHERE Code='WHT-153'"))[0].TaxHeadID }], 'Equipment repairs');

  /* --- September --- */
  await simple('BANK', 'Receipt', '2026-09-05', BANK, [{ AccountID: MEMREV, Amount: 112000, Description: 'September membership fees' }], 'September membership collection');
  await simple('CASH', 'Payment', '2026-09-14', CASH, [{ AccountID: WATER, Amount: 8500, Description: 'Water supply — September' }], 'Water bill');
  await simple('BANK', 'Payment', '2026-09-15', BANK, [{ AccountID: SALARY, Amount: 395000, Description: 'Staff salaries — September' }], 'Payroll September');
  await simple('CASH', 'Payment', '2026-09-16', CASH, [{ AccountID: MKT, Amount: 20000, Description: 'Social media campaign', TaxHeadID: (await q("SELECT TaxHeadID FROM TaxHeads WHERE Code='WHT-153'"))[0].TaxHeadID }], 'Marketing spend');
  await simple('CASH', 'Receipt', '2026-09-16', CASH, [{ AccountID: PTREV, Amount: 35000, Description: 'PT sessions — September' }], 'PT income September');

  /* --- customer receivable demo (aging + knock-off) --- */
  const m1 = memberIds[0].memberId;
  const arBill = await saveDoc('JOURNAL', {
    VoucherDate: '2026-09-10', BranchID: 1, Narrative: 'PT package on credit — Hamza Sheikh',
    Lines: [{ AccountID: AR, Debit: 25000, Description: 'PT package — Hamza Sheikh' },
            { AccountID: PTREV, Credit: 25000, Description: 'PT package revenue' }],
  });
  const arBillLedger = (await q('SELECT VoucherID FROM JournalVouchers WHERE JournalVoucherID = ' + arBill.JournalVoucherID))[0].VoucherID;
  await q("UPDATE e SET e.PartyMemberID = " + m1 + ", e.BillRef = 'PT-001', e.BillDate = '2026-09-10', e.DueDate = '2026-10-10' " +
          "FROM VoucherEntries e JOIN Vouchers v ON v.VoucherID = e.VoucherID " +
          "WHERE v.VoucherID = " + arBillLedger + " AND e.Debit > 0");
  const arReceipt = await simple('CASH', 'Receipt', '2026-09-17', CASH, [{ AccountID: AR, Amount: 10000, Description: 'Part payment — Hamza Sheikh' }], 'PT part payment');
  const arRcptLedger = (await q('SELECT VoucherID FROM CashVouchers WHERE CashVoucherID = ' + arReceipt.CashVoucherID))[0].VoucherID;
  await q("UPDATE e SET e.PartyMemberID = " + m1 + ", e.BillRef = 'PT-001' " +
          "FROM VoucherEntries e JOIN Vouchers v ON v.VoucherID = e.VoucherID " +
          "WHERE v.VoucherID = " + arRcptLedger + " AND e.Credit > 0");

  /* ================= FEES MODULE (invoices + collections) ================= */
  for (let i = 0; i < 4; i++) {
    const m = memberIds[i];
    const inv = await exec('sp_Invoices_Create', [
      { name: 'MemberID', value: m.memberId }, { name: 'MemberMembershipID', value: null },
      { name: 'TotalAmount', value: m.plan.Price }, { name: 'Discount', value: 0 },
      { name: 'LateFee', value: 0 }, { name: 'Tax', value: 0 },
      { name: 'DueDate', value: '2026-09-30' }, { name: 'Notes', value: m.plan.Name + ' plan fee' },
      { name: 'CreatedBy', value: 1 }]);
    const invoiceId = inv.recordset[0].InvoiceID;
    const pay = i < 3 ? m.plan.Price : Math.round(m.plan.Price / 2); // last one partial
    await exec('sp_FeeCollections_Collect', [
      { name: 'InvoiceID', value: i < 3 ? invoiceId : null }, { name: 'MemberID', value: m.memberId },
      { name: 'Amount', value: pay }, { name: 'MethodID', value: (i % 5) + 1 },
      { name: 'TransactionRef', value: i % 2 ? 'TXN-' + (1000 + i) : null },
      { name: 'BranchID', value: m.branch }, { name: 'Notes', value: null },
      { name: 'CollectedBy', value: 1 }]);
  }

  /* ================= PAYROLL (July/Aug paid, September pending) ================= */
  const hqStaff = staffIds.slice(0, 5);
  for (const month of [7, 8, 9]) {
    for (const sid of hqStaff) {
      const pid = (await exec('sp_Payroll_Generate', [
        { name: 'StaffID', value: sid }, { name: 'Month', value: month }, { name: 'Year', value: 2026 },
        { name: 'Bonus', value: month === 8 ? 5000 : 0 }, { name: 'Overtime', value: 0 },
        { name: 'LeaveDeduction', value: 0 }, { name: 'Commission', value: 0 },
        { name: 'GeneratedBy', value: 1 }])).recordset[0].PayrollID;
      if (month < 9) await exec('sp_Payroll_MarkPaid', [{ name: 'PayrollID', value: pid }]);
    }
  }

  /* ================= ATTENDANCE (today) ================= */
  const today = new Date().toISOString().slice(0, 10);
  for (let i = 0; i < 6; i++) {
    const m = memberIds[i];
    try {
      await exec('sp_Attendance_CheckIn', [
        { name: 'MemberID', value: m.memberId }, { name: 'BranchID', value: m.branch },
        { name: 'Method', value: 'Manual' }, { name: 'IPAddress', value: null },
        { name: 'CreatedBy', value: 1 }]);
    } catch (_) { /* duplicate check-in — fine */ }
  }

  /* ================= VERIFY ================= */
  const counts = await q(`SELECT (SELECT COUNT(*) FROM Members) AS Members, (SELECT COUNT(*) FROM Staff) AS Staff,
    (SELECT COUNT(*) FROM Vouchers) AS LedgerVouchers, (SELECT COUNT(*) FROM CashVouchers) AS CashDocs,
    (SELECT COUNT(*) FROM BankVouchers) AS BankDocs, (SELECT COUNT(*) FROM JournalVouchers) AS JournalDocs,
    (SELECT COUNT(*) FROM Invoices) AS Invoices, (SELECT COUNT(*) FROM Payroll) AS Payroll, (SELECT COUNT(*) FROM Users) AS Users`);
  console.log('  counts:', JSON.stringify(counts[0]));
  const tb = (await pool.request()
    .input('FromDate', '2026-01-01').input('ToDate', '2026-12-31')
    .execute('sp_FinanceReports_TrialBalance')).recordsets[1][0];
  console.log('  TB period Dr:', tb.TotalPeriodDebit, 'Cr:', tb.TotalPeriodCredit,
    tb.TotalPeriodDebit === tb.TotalPeriodCredit ? '(BALANCED)' : '(UNBALANCED!)');
  const dash = (await pool.request().execute('sp_Dashboard_Stats')).recordset[0];
  console.log('  dashboard: income', dash.MonthlyIncome, '| expenses', dash.MonthlyExpenses, '| members', dash.TotalMembers);
  console.log('Done.');
  await pool.close();
})().catch((e) => { console.error('SEED FAILED:', e.message); process.exit(1); });

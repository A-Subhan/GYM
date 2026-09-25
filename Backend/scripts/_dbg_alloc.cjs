const dotenv = require('dotenv');
dotenv.config({ path: '.env' });
const sql = require('mssql');
(async () => {
  const pool = await sql.connect({ server: process.env.DB_SERVER, port: 1433, database: 'GymDB_Test', user: process.env.DB_USER, password: process.env.DB_PASSWORD || '', options: { encrypt: false, trustServerCertificate: true } });
  const q = (s) => pool.request().query(s).then(r => r.recordset);
  const AR = (await q("SELECT AccountID FROM Accounts WHERE Code='10101001'"))[0].AccountID;
  const MEMREV = (await q("SELECT AccountID FROM Accounts WHERE Code='40101001'"))[0].AccountID;
  const CASH = (await q("SELECT AccountID FROM Accounts WHERE Code='10102001'"))[0].AccountID;
  await pool.request().input('AccountID', AR).input('Title', 'Accounts Receivable - Trade').input('KnockOff', 1).execute('sp_FinanceAccounts_Update');
  const req = pool.request().input('VoucherDate', '2027-06-10').input('BranchID', 1).input('Narrative', 'bill')
    .input('LinesJson', JSON.stringify([{ AccountID: AR, Debit: 25000, Description: 'bill KO-A' }, { AccountID: MEMREV, Credit: 25000 }])).input('UserId', 1);
  req.output('NewID', sql.Int); req.output('NewVoucherNo', sql.NVarChar(50));
  const bill = (await req.execute('sp_FinanceDocuments_SaveJournal')).recordset[0];
  await q("UPDATE e SET e.PartyMemberID = 33, e.BillRef = 'KO-A' FROM VoucherEntries e JOIN Vouchers v ON v.VoucherID = e.VoucherID WHERE v.VoucherID = " + bill.JournalVoucherID + " AND e.Debit > 0");
  const rreq = pool.request().input('Status', 'Posted').input('Direction', 'Receipt').input('VoucherDate', '2027-06-15')
    .input('CashAccountID', CASH).input('BranchID', 1).input('Narrative', 'rcpt')
    .input('LinesJson', JSON.stringify([{ AccountID: AR, Amount: 10000, KnockOff: true, PartyMemberID: 33 }]))
    .input('UserId', 1);
  rreq.output('NewID', sql.Int); rreq.output('NewVoucherNo', sql.NVarChar(50));
  const rcpt = (await rreq.execute('sp_FinanceDocuments_SaveCash')).recordset[0];
  const line = (await pool.request().input('DocumentID', rcpt.CashVoucherID)
    .query('SELECT CashVoucherLineID AS LineID, PartyMemberID, Amount FROM CashVoucherLines WHERE CashVoucherID = ' + rcpt.CashVoucherID)).recordset[0];
  console.log('line:', JSON.stringify(line));
  const chk = await pool.request().input('LineID', line.LineID)
    .query("SELECT a.BillRef, a.Amount, "
      + "(SELECT ISNULL(SUM(e.Debit - e.Credit), 0) FROM VoucherEntries e JOIN Vouchers v ON v.VoucherID = e.VoucherID AND v.Status IN ('Posted','Reversed') AND v.IsDeleted = 0 WHERE e.PartyMemberID = (SELECT TOP 1 PartyMemberID FROM CashVoucherLines WHERE CashVoucherLineID = a.LineID) AND e.BillRef = a.BillRef) AS Net, "
      + "(SELECT ISNULL(SUM(al.Amount), 0) FROM FinanceLineAllocations al WHERE al.IsReversed = 0 AND al.BillRef = a.BillRef AND NOT (al.Family = 'CASH' AND al.DocumentID = 999999 AND al.LineID = a.LineID)) AS Allocated "
      + "FROM FinanceLineAllocations a WHERE a.LineID = " + line.LineID);
  console.log('alloc rows on line:', JSON.stringify(chk.recordset));
  await pool.close();
})().catch(e => console.log('ERR:', e.number ?? '', e.message));

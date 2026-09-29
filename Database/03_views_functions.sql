-- ============================================================================
-- Contoura Gym Management System - STEP 3: Views and Functions (FINAL design)
-- ============================================================================
-- Reporting views and scalar functions over the FINAL schema:
--   * charts.id IS the account code (no separate Account/code columns)
--   * ledger data lives in the four book tables CashBook/BankBook/JV/OpenTB
--     joined to their line tables (CashBookLine/BankBookLine/JVLine/OpenTBLine)
--   * fee payments reference book vouchers via FeePayment.bookVoucherId
--
-- Every CREATE ... statement is the first statement in its own batch (GO).
-- Safe to re-run (CREATE OR ALTER).
-- Run after 02_schema_tables.sql on the GymDB database.
-- ============================================================================

USE [GymDB];
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ---------------------------------------------------------------------------
-- Scalar functions
-- ---------------------------------------------------------------------------

CREATE OR ALTER FUNCTION dbo.fn_CalculateAge (@dob DATETIME2)
RETURNS INT AS
BEGIN
    IF @dob IS NULL RETURN NULL;
    DECLARE @age INT = DATEDIFF(YEAR, @dob, GETDATE());
    IF DATEADD(YEAR, @age, @dob) > GETDATE() SET @age = @age - 1;
    RETURN @age;
END
GO

CREATE OR ALTER FUNCTION dbo.fn_MemberOutstanding (@memberId NVARCHAR(50))
RETURNS DECIMAL(18,2) AS
BEGIN
    DECLARE @bal DECIMAL(18,2);
    SELECT @bal = ISNULL(SUM(balance), 0)
    FROM dbo.Fee
    WHERE memberId = @memberId AND status <> N'Voided';
    RETURN ISNULL(@bal, 0);
END
GO

-- account balance over ALL FOUR book line tables
CREATE OR ALTER FUNCTION dbo.fn_AccountBalance (@accountId NVARCHAR(50), @fromDate DATETIME2 = NULL, @toDate DATETIME2 = NULL)
RETURNS DECIMAL(18,2) AS
BEGIN
    DECLARE @bal DECIMAL(18,2);
    IF NOT EXISTS (SELECT 1 FROM dbo.charts WHERE id = @accountId) RETURN 0;
    SELECT @bal = ISNULL(SUM(ISNULL(l.debit,0) - ISNULL(l.credit,0)), 0)
    FROM (
        SELECT cb.voucherDate, cl.debit, cl.credit
        FROM dbo.CashBook cb JOIN dbo.CashBookLine cl ON cl.voucherId = cb.id
        WHERE cb.status = N'Posted' AND cl.accountId = @accountId
        UNION ALL
        SELECT bb.voucherDate, bl.debit, bl.credit
        FROM dbo.BankBook bb JOIN dbo.BankBookLine bl ON bl.voucherId = bb.id
        WHERE bb.status = N'Posted' AND bl.accountId = @accountId
        UNION ALL
        SELECT j.voucherDate, jl.debit, jl.credit
        FROM dbo.JV j JOIN dbo.JVLine jl ON jl.voucherId = j.id
        WHERE j.status = N'Posted' AND jl.accountId = @accountId
        UNION ALL
        SELECT o.voucherDate, ol.debit, ol.credit
        FROM dbo.OpenTB o JOIN dbo.OpenTBLine ol ON ol.voucherId = o.id
        WHERE o.status = N'Posted' AND ol.accountId = @accountId
    ) l
    WHERE (@fromDate IS NULL OR l.voucherDate >= @fromDate)
      AND (@toDate   IS NULL OR l.voucherDate <= @toDate);
    RETURN ISNULL(@bal, 0);
END
GO

-- ---------------------------------------------------------------------------
-- Views
-- ---------------------------------------------------------------------------

-- Trial balance over the four books (charts.id = account code)
CREATE OR ALTER VIEW dbo.vw_TrialBalance
AS
WITH ledger AS (
    SELECT cl.accountId, cl.debit, cl.credit FROM dbo.CashBook  cb JOIN dbo.CashBookLine  cl ON cl.voucherId = cb.id WHERE cb.status = N'Posted'
    UNION ALL
    SELECT bl.accountId, bl.debit, bl.credit FROM dbo.BankBook  bb JOIN dbo.BankBookLine  bl ON bl.voucherId = bb.id WHERE bb.status = N'Posted'
    UNION ALL
    SELECT jl.accountId, jl.debit, jl.credit FROM dbo.JV        j  JOIN dbo.JVLine        jl ON jl.voucherId = j.id  WHERE j.status  = N'Posted'
    UNION ALL
    SELECT ol.accountId, ol.debit, ol.credit FROM dbo.OpenTB    o  JOIN dbo.OpenTBLine    ol ON ol.voucherId = o.id  WHERE o.status  = N'Posted'
)
SELECT  c.id AS accountCode, c.name AS accountName, c.accountType, c.bookType,
        c.accountTag, c.isDetail,
        ISNULL(SUM(ISNULL(l.debit, 0)), 0)  AS totalDebit,
        ISNULL(SUM(ISNULL(l.credit, 0)), 0) AS totalCredit,
        ISNULL(SUM(ISNULL(l.debit, 0) - ISNULL(l.credit, 0)), 0) AS netBalance
FROM dbo.charts c
LEFT JOIN ledger l ON l.accountId = c.id
WHERE c.isDetail = 1
GROUP BY c.id, c.name, c.accountType, c.bookType, c.accountTag, c.isDetail;
GO

CREATE OR ALTER VIEW dbo.vw_ActiveMembers
AS
SELECT  m.id, m.id AS memberCode, m.firstName, m.lastName,
        (m.firstName + N' ' + m.lastName) AS fullName,
        m.gender, m.phone, m.email, m.status, m.joiningDate,
        m.billingStartDate, m.isActive,
        p.name AS planName, p.id AS planCode, p.amount AS planAmount,
        b.name AS branchName, b.code AS branchCode,
        s.firstName + N' ' + s.lastName AS trainerName,
        dbo.fn_MemberOutstanding(m.id) AS outstandingBalance
FROM dbo.Member m
LEFT JOIN dbo.MembershipPlan p ON p.id = m.membershipPlanId
LEFT JOIN dbo.Branch b         ON b.id = m.branchId
LEFT JOIN dbo.Staff s          ON s.id = m.assignedTrainerId
WHERE m.isDeleted = 0 AND m.isActive = 1;
GO

CREATE OR ALTER VIEW dbo.vw_OutstandingFees
AS
SELECT  f.id, f.memberId, (m.firstName + N' ' + m.lastName) AS memberName,
        m.id AS memberCode, f.billingPeriodStart, f.billingPeriodEnd,
        f.amount, f.discount, f.paidAmount, f.balance, f.dueDate, f.status,
        b.name AS branchName,
        DATEDIFF(DAY, f.dueDate, GETDATE()) AS daysOverdue
FROM dbo.Fee f
INNER JOIN dbo.Member m ON m.id = f.memberId
LEFT JOIN dbo.Branch b  ON b.id = f.branchId
WHERE f.balance > 0 AND f.status <> N'Voided';
GO

CREATE OR ALTER VIEW dbo.vw_MonthlyRevenue
AS
WITH ledger AS (
    SELECT cb.voucherDate, cl.accountId, cl.debit, cl.credit FROM dbo.CashBook cb JOIN dbo.CashBookLine cl ON cl.voucherId = cb.id WHERE cb.status = N'Posted'
    UNION ALL
    SELECT bb.voucherDate, bl.accountId, bl.debit, bl.credit FROM dbo.BankBook bb JOIN dbo.BankBookLine bl ON bl.voucherId = bb.id WHERE bb.status = N'Posted'
    UNION ALL
    SELECT j.voucherDate,  jl.accountId, jl.debit, jl.credit FROM dbo.JV j      JOIN dbo.JVLine       jl ON jl.voucherId = j.id  WHERE j.status  = N'Posted'
    UNION ALL
    SELECT o.voucherDate,  ol.accountId, ol.debit, ol.credit FROM dbo.OpenTB o  JOIN dbo.OpenTBLine   ol ON ol.voucherId = o.id  WHERE o.status  = N'Posted'
)
SELECT  YEAR(l.voucherDate) AS [year], MONTH(l.voucherDate) AS [month],
        c.accountTag,
        SUM(ISNULL(l.credit, 0) - ISNULL(l.debit, 0)) AS revenue
FROM ledger l
INNER JOIN dbo.charts c ON c.id = l.accountId
WHERE c.accountType = N'Revenue'
GROUP BY YEAR(l.voucherDate), MONTH(l.voucherDate), c.accountTag;
GO

CREATE OR ALTER VIEW dbo.vw_AttendanceLog
AS
SELECT  a.id, a.date, a.checkIn, a.checkOut, a.notes,
        m.id AS memberCode, (m.firstName + N' ' + m.lastName) AS memberName,
        m.membershipPlanId, p.name AS planName,
        b.name AS branchName, b.id AS branchId
FROM dbo.Attendance a
INNER JOIN dbo.Member m ON m.id = a.memberId
LEFT JOIN dbo.MembershipPlan p ON p.id = m.membershipPlanId
LEFT JOIN dbo.Branch b ON b.id = a.branchId;
GO

CREATE OR ALTER VIEW dbo.vw_PayrollRegister
AS
SELECT  p.id, p.payrollNo, p.[month], p.[year], p.basicSalary, p.totalAllowances,
        p.overtimeAmount, p.totalEarnings, p.totalDeductions, p.netPay, p.status,
        p.bookVoucherId,
        s.employeeId, (s.firstName + N' ' + s.lastName) AS staffName,
        s.designation, s.department,
        b.name AS branchName
FROM dbo.Payroll p
INNER JOIN dbo.Staff s ON s.id = p.staffId
LEFT JOIN dbo.Branch b ON b.id = p.branchId;
GO

CREATE OR ALTER VIEW dbo.vw_StockStatus
AS
SELECT  i.id, i.code, i.name, i.category, i.unit, i.quantity, i.reorderLevel,
        i.purchasePrice, i.salePrice, i.status,
        b.name AS branchName,
        CASE WHEN i.quantity <= i.reorderLevel THEN 1 ELSE 0 END AS needsReorder,
        (i.quantity * i.purchasePrice) AS stockValue
FROM dbo.InventoryItem i
LEFT JOIN dbo.Branch b ON b.id = i.branchId
WHERE i.status <> N'Deleted';
GO

-- unified ledger across the four books (line types vary per book)
CREATE OR ALTER VIEW dbo.vw_BookLedger
AS
SELECT 'CASHBOOK' AS bookType, cl.id AS lineId, cl.voucherId, cb.voucherType, cb.voucherDate,
       cb.branchId, cl.accountId, c.name AS accountName, c.accountType,
       cl.debit, cl.credit, cl.amount, cl.taxPercent, cl.taxAmount, cl.total,
       cl.billType, cl.chequeNo, cl.chequeAmount, cl.lineDescription, cl.status AS lineStatus, cb.status AS voucherStatus
FROM dbo.CashBook cb JOIN dbo.CashBookLine cl ON cl.voucherId = cb.id
JOIN dbo.charts c ON c.id = cl.accountId
UNION ALL
SELECT 'BANKBOOK', bl.id, bl.voucherId, bb.voucherType, bb.voucherDate,
       bb.branchId, bl.accountId, c.name, c.accountType,
       bl.debit, bl.credit, bl.amount, bl.taxPercent, bl.taxAmount, bl.total,
       bl.billType, bl.chequeNo, bl.chequeAmount, bl.lineDescription, bl.status, bb.status
FROM dbo.BankBook bb JOIN dbo.BankBookLine bl ON bl.voucherId = bb.id
JOIN dbo.charts c ON c.id = bl.accountId
UNION ALL
SELECT 'JV', jl.id, jl.voucherId, j.voucherType, j.voucherDate,
       j.branchId, jl.accountId, c.name, c.accountType,
       jl.debit, jl.credit, jl.amount, jl.taxPercent, jl.taxAmount, jl.total,
       NULL, NULL, NULL, jl.lineDescription, jl.status, j.status
FROM dbo.JV j JOIN dbo.JVLine jl ON jl.voucherId = j.id
JOIN dbo.charts c ON c.id = jl.accountId
UNION ALL
SELECT 'OTB', ol.id, ol.voucherId, o.voucherType, o.voucherDate,
       o.branchId, ol.accountId, c.name, c.accountType,
       ol.debit, ol.credit, ol.amount, NULL, NULL, NULL,
       NULL, NULL, NULL, ol.lineDescription, ol.status, o.status
FROM dbo.OpenTB o JOIN dbo.OpenTBLine ol ON ol.voucherId = o.id
JOIN dbo.charts c ON c.id = ol.accountId;
GO

PRINT 'Step 03 complete: final views and functions created.';
GO

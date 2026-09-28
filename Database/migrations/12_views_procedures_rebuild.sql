-- ============================================================================
-- Contoura Gym ERP — Migration 12: REBUILD VIEWS / FUNCTIONS / PROCEDURES /
--                                   TRIGGERS against the FINAL schema
-- ============================================================================
-- Everything that referenced renamed or removed objects is rebuilt here,
-- AFTER all table changes, and references ONLY columns that exist in the
-- final schema (charts with id = code, four book tables, bookVoucherId on
-- Fee/FeePayment/PosSale/Payroll, Member.id as the business id, Prospect
-- .branchId, no GymClass/ClassEnrollment).
--
-- Structure: the transaction is opened in the first batch (obsolete drops),
-- every create batch is gated and its CREATE OR ALTER statements are
-- individually atomic + idempotent, and the FINAL batch verifies the end
-- state and commits (or rolls everything back and marks the script Failed).
-- ============================================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET LANGUAGE us_english;
GO

-- ---- batch 1: gate + open transaction + obsolete drops ----------------------
DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'11_remove_removed_modules', @self = N'12_views_procedures_rebuild', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    12 already applied, skipping.'; RETURN; END
BEGIN TRY
    BEGIN TRAN;

    IF OBJECT_ID('dbo.vw_ClassEnrollmentSummary', 'V') IS NOT NULL DROP VIEW dbo.vw_ClassEnrollmentSummary;
    IF OBJECT_ID('dbo.trg_Voucher_BalanceCheck', 'TR') IS NOT NULL DROP TRIGGER dbo.trg_Voucher_BalanceCheck;
    IF OBJECT_ID('dbo.trg_Voucher_touchUpdatedAt', 'TR') IS NOT NULL DROP TRIGGER dbo.trg_Voucher_touchUpdatedAt;
    IF OBJECT_ID('dbo.trg_Account_touchUpdatedAt', 'TR') IS NOT NULL DROP TRIGGER dbo.trg_Account_touchUpdatedAt;
    PRINT '  obsolete objects dropped';
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'12_views_procedures_rebuild';
    THROW;
END CATCH
GO

-- ---- batch 2: functions (gated) ---------------------------------------------
DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'11_remove_removed_modules', @self = N'12_views_procedures_rebuild', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    12 already applied, skipping.'; RETURN; END

CREATE OR ALTER FUNCTION dbo.fn_CalculateAge (@dob DATETIME2)
RETURNS INT AS
BEGIN
    IF @dob IS NULL RETURN NULL;
    DECLARE @age INT = DATEDIFF(YEAR, @dob, GETDATE());
    IF DATEADD(YEAR, @age, @dob) > GETDATE() SET @age = @age - 1;
    RETURN @age;
END
GO

DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'11_remove_removed_modules', @self = N'12_views_procedures_rebuild', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    12 already applied, skipping.'; RETURN; END

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

DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'11_remove_removed_modules', @self = N'12_views_procedures_rebuild', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    12 already applied, skipping.'; RETURN; END

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

-- ---- batch 3: views (gated, one gate per GO-separated sub-batch) -------------
DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'11_remove_removed_modules', @self = N'12_views_procedures_rebuild', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    12 already applied, skipping.'; RETURN; END

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

DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'11_remove_removed_modules', @self = N'12_views_procedures_rebuild', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    12 already applied, skipping.'; RETURN; END

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

DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'11_remove_removed_modules', @self = N'12_views_procedures_rebuild', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    12 already applied, skipping.'; RETURN; END

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

DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'11_remove_removed_modules', @self = N'12_views_procedures_rebuild', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    12 already applied, skipping.'; RETURN; END

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

DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'11_remove_removed_modules', @self = N'12_views_procedures_rebuild', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    12 already applied, skipping.'; RETURN; END

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

DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'11_remove_removed_modules', @self = N'12_views_procedures_rebuild', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    12 already applied, skipping.'; RETURN; END

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

DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'11_remove_removed_modules', @self = N'12_views_procedures_rebuild', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    12 already applied, skipping.'; RETURN; END

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

DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'11_remove_removed_modules', @self = N'12_views_procedures_rebuild', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    12 already applied, skipping.'; RETURN; END

-- unified ledger across the four books
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

-- ---- batch 4: stored procedures ----------------------------------------------
DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'11_remove_removed_modules', @self = N'12_views_procedures_rebuild', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    12 already applied, skipping.'; RETURN; END

CREATE OR ALTER PROCEDURE dbo.sp_GetDashboardStats
    @branchId NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        (SELECT COUNT(*) FROM dbo.Member m
          WHERE m.isDeleted = 0 AND m.isActive = 1
            AND (@branchId IS NULL OR m.branchId = @branchId))              AS activeMembers,
        (SELECT COUNT(*) FROM dbo.Member m
          WHERE m.isDeleted = 0
            AND (@branchId IS NULL OR m.branchId = @branchId))              AS totalMembers,
        (SELECT COUNT(*) FROM dbo.Attendance a
          WHERE a.date = CAST(GETDATE() AS DATE)
            AND (@branchId IS NULL OR a.branchId = @branchId))              AS checkinsToday,
        (SELECT ISNULL(SUM(f.balance), 0) FROM dbo.Fee f
          WHERE f.balance > 0 AND f.status <> N'Voided'
            AND (@branchId IS NULL OR f.branchId = @branchId))              AS outstandingFees,
        (SELECT ISNULL(SUM(l.credit - l.debit), 0)
           FROM dbo.CashBook  cb JOIN dbo.CashBookLine cl ON cl.voucherId = cb.id JOIN dbo.charts c ON c.id = cl.accountId
          WHERE cb.status = N'Posted' AND c.accountType = N'Revenue'
            AND MONTH(cb.voucherDate) = MONTH(GETDATE())
            AND YEAR(cb.voucherDate)  = YEAR(GETDATE())
            AND (@branchId IS NULL OR cb.branchId = @branchId))             +
        (SELECT ISNULL(SUM(l.credit - l.debit), 0)
           FROM dbo.BankBook  bb JOIN dbo.BankBookLine bl ON bl.voucherId = bb.id JOIN dbo.charts c ON c.id = bl.accountId
          WHERE bb.status = N'Posted' AND c.accountType = N'Revenue'
            AND MONTH(bb.voucherDate) = MONTH(GETDATE())
            AND YEAR(bb.voucherDate)  = YEAR(GETDATE())
            AND (@branchId IS NULL OR bb.branchId = @branchId))             AS revenueThisMonth,
        (SELECT COUNT(*) FROM dbo.Prospect p
          WHERE p.status IN (N'New', N'Contacted', N'FollowUp')
            AND (@branchId IS NULL OR p.branchId = @branchId))              AS openProspects,
        (SELECT COUNT(*) FROM dbo.Staff s
          WHERE s.isDeleted = 0 AND s.isActive = 1
            AND (@branchId IS NULL OR s.branchId = @branchId))              AS activeStaff,
        (SELECT COUNT(*) FROM dbo.InventoryItem i
          WHERE i.quantity <= i.reorderLevel AND i.status <> N'Deleted'
            AND (@branchId IS NULL OR i.branchId = @branchId))              AS lowStockItems;
END
GO

DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'11_remove_removed_modules', @self = N'12_views_procedures_rebuild', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    12 already applied, skipping.'; RETURN; END

CREATE OR ALTER PROCEDURE dbo.sp_GetTrialBalance
    @asOfDate DATETIME2 = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT accountCode, accountName, accountType,
           totalDebit, totalCredit, netBalance AS balance
    FROM dbo.vw_TrialBalance
    ORDER BY accountCode;
END
GO

DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'11_remove_removed_modules', @self = N'12_views_procedures_rebuild', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    12 already applied, skipping.'; RETURN; END

CREATE OR ALTER PROCEDURE dbo.sp_GetIncomeStatement
    @fromDate DATETIME2,
    @toDate   DATETIME2
AS
BEGIN
    SET NOCOUNT ON;
    ;WITH ledger AS (
        SELECT cb.voucherDate, cl.accountId, cl.debit, cl.credit FROM dbo.CashBook cb JOIN dbo.CashBookLine cl ON cl.voucherId = cb.id WHERE cb.status = N'Posted'
        UNION ALL
        SELECT bb.voucherDate, bl.accountId, bl.debit, bl.credit FROM dbo.BankBook bb JOIN dbo.BankBookLine bl ON bl.voucherId = bb.id WHERE bb.status = N'Posted'
        UNION ALL
        SELECT j.voucherDate,  jl.accountId, jl.debit, jl.credit FROM dbo.JV j      JOIN dbo.JVLine       jl ON jl.voucherId = j.id  WHERE j.status  = N'Posted'
        UNION ALL
        SELECT o.voucherDate,  ol.accountId, ol.debit, ol.credit FROM dbo.OpenTB o  JOIN dbo.OpenTBLine   ol ON ol.voucherId = o.id  WHERE o.status  = N'Posted'
    ),
    Totals AS (
        SELECT c.accountType, c.id AS code, c.name AS accountName,
               SUM(ISNULL(l.credit,0) - ISNULL(l.debit,0)) AS amount
        FROM ledger l
        INNER JOIN dbo.charts c ON c.id = l.accountId
        WHERE l.voucherDate BETWEEN @fromDate AND @toDate
          AND c.accountType IN (N'Revenue', N'Expense')
        GROUP BY c.accountType, c.id, c.name
    )
    SELECT accountType, code, accountName, amount,
           CASE accountType WHEN N'Expense' THEN -amount ELSE amount END AS signedAmount
    FROM Totals
    ORDER BY accountType, code;
END
GO

DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'11_remove_removed_modules', @self = N'12_views_procedures_rebuild', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    12 already applied, skipping.'; RETURN; END

CREATE OR ALTER PROCEDURE dbo.sp_GetMemberStatement
    @memberId NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT f.id AS feeId, f.billingPeriodStart, f.billingPeriodEnd, f.amount, f.discount,
           f.paidAmount, f.balance, f.dueDate, f.status
    FROM dbo.Fee f
    WHERE f.memberId = @memberId
    ORDER BY f.billingPeriodStart;

    SELECT fp.createdAt AS paidAt, fp.amount, fp.[method],
           fp.bookVoucherId AS voucherNo,
           CASE WHEN fp.bookVoucherId LIKE 'CRV/%' THEN N'CRV'
                WHEN fp.bookVoucherId LIKE 'CPV/%' THEN N'CPV'
                WHEN fp.bookVoucherId LIKE 'BRV/%' THEN N'BRV'
                WHEN fp.bookVoucherId LIKE 'BPV/%' THEN N'BPV'
                ELSE N'BOOK' END AS voucherType,
           a.name AS paidIntoAccount
    FROM dbo.FeePayment fp
    LEFT JOIN dbo.Fee f     ON f.id = fp.feeId
    LEFT JOIN dbo.charts a  ON a.id = fp.accountId
    WHERE f.memberId = @memberId
    ORDER BY fp.createdAt;
END
GO

DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'11_remove_removed_modules', @self = N'12_views_procedures_rebuild', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    12 already applied, skipping.'; RETURN; END

CREATE OR ALTER PROCEDURE dbo.sp_CalculatePayroll
    @[month] INT,
    @[year]  INT,
    @staffId NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @basic DECIMAL(18,2) = (SELECT basicSalary FROM dbo.Staff WHERE id = @staffId);
    DECLARE @ot DECIMAL(18,2) =
        (SELECT ISNULL(SUM(amount), 0) FROM dbo.Overtime
          WHERE staffId = @staffId AND status = N'Approved'
            AND MONTH(date) = @month AND YEAR(date) = @year);
    DECLARE @allowances DECIMAL(18,2) =
        (SELECT ISNULL(fuelAllowance,0) + ISNULL(rentAllowance,0)
              + ISNULL(houseAllowance,0) + ISNULL(otherAllowance,0)
        FROM dbo.Staff WHERE id = @staffId);
    DECLARE @unpaidLeaveDays INT =
        (SELECT ISNULL(SUM(days), 0) FROM dbo.Leave l
          WHERE l.staffId = @staffId AND l.status = N'Approved'
            AND MONTH(l.fromDate) = @month AND YEAR(l.fromDate) = @year);
    SELECT @basic AS basicSalary, @allowances AS totalAllowances, @ot AS overtimeAmount,
           (@basic + @allowances + @ot) AS totalEarnings,
           CAST(0 AS DECIMAL(18,2)) AS totalDeductions,
           (@basic + @allowances + @ot) AS netPay;
END
GO

DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'11_remove_removed_modules', @self = N'12_views_procedures_rebuild', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    12 already applied, skipping.'; RETURN; END

CREATE OR ALTER PROCEDURE dbo.sp_ResetAdminPassword
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.[User]
    SET passwordHash = N'$2b$10$4sWId8YdsNlr39HgQ51wE.5rFtEFE3l5APRnRO6rYlE15bOUryvpy',
        mustChangePassword = 0, isActive = 1, isDeleted = 0, failedLoginCount = 0
    WHERE username = N'admin';
    PRINT 'Admin password reset to: admin123';
END
GO

-- ---- batch 5: triggers --------------------------------------------------------
DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'11_remove_removed_modules', @self = N'12_views_procedures_rebuild', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    12 already applied, skipping.'; RETURN; END

CREATE OR ALTER TRIGGER dbo.trg_Member_touchUpdatedAt ON dbo.Member AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    UPDATE m SET updatedAt = GETDATE()
    FROM dbo.Member m
    INNER JOIN inserted i ON i.id = m.id
    INNER JOIN deleted  d ON d.id = i.id
    WHERE i.updatedAt = d.updatedAt;
END
GO

DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'11_remove_removed_modules', @self = N'12_views_procedures_rebuild', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    12 already applied, skipping.'; RETURN; END

CREATE OR ALTER TRIGGER dbo.trg_Staff_touchUpdatedAt ON dbo.Staff AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    UPDATE s SET updatedAt = GETDATE()
    FROM dbo.Staff s
    INNER JOIN inserted i ON i.id = s.id
    INNER JOIN deleted  d ON d.id = i.id
    WHERE i.updatedAt = d.updatedAt;
END
GO

DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'11_remove_removed_modules', @self = N'12_views_procedures_rebuild', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    12 already applied, skipping.'; RETURN; END

CREATE OR ALTER TRIGGER dbo.trg_charts_touchUpdatedAt ON dbo.charts AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    UPDATE a SET updatedAt = GETDATE()
    FROM dbo.charts a
    INNER JOIN inserted i ON i.id = a.id
    INNER JOIN deleted  d ON d.id = i.id
    WHERE i.updatedAt = d.updatedAt;
END
GO

DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'11_remove_removed_modules', @self = N'12_views_procedures_rebuild', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    12 already applied, skipping.'; RETURN; END

CREATE OR ALTER TRIGGER dbo.trg_Fee_touchUpdatedAt ON dbo.Fee AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    UPDATE f SET updatedAt = GETDATE()
    FROM dbo.Fee f
    INNER JOIN inserted i ON i.id = f.id
    INNER JOIN deleted  d ON d.id = i.id
    WHERE i.updatedAt = d.updatedAt;
END
GO

DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'11_remove_removed_modules', @self = N'12_views_procedures_rebuild', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    12 already applied, skipping.'; RETURN; END

CREATE OR ALTER TRIGGER dbo.trg_InventoryItem_touchUpdatedAt ON dbo.InventoryItem AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    UPDATE it SET updatedAt = GETDATE()
    FROM dbo.InventoryItem it
    INNER JOIN inserted i ON i.id = it.id
    INNER JOIN deleted  d ON d.id = i.id
    WHERE i.updatedAt = d.updatedAt;
END
GO

DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'11_remove_removed_modules', @self = N'12_views_procedures_rebuild', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    12 already applied, skipping.'; RETURN; END

CREATE OR ALTER TRIGGER dbo.trg_Payroll_Audit ON dbo.Payroll AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.AuditLog (id, userId, action, module, details, ipAddress, location, createdAt)
    SELECT REPLACE(CAST(NEWID() AS NVARCHAR(50)), '-', ''),
           NULL, N'PAYROLL_STATUS', N'payroll',
           N'{"payrollNo":"' + i.payrollNo + N'","from":"' + ISNULL(d.status, N'') + N'","to":"' + ISNULL(i.status, N'') + N'"}',
           NULL, NULL, GETDATE()
    FROM inserted i
    INNER JOIN deleted d ON d.id = i.id
    WHERE ISNULL(d.status, N'') <> ISNULL(i.status, N'');
END
GO

-- NOTE: there is deliberately NO balance-check trigger on the book tables:
-- OpenTB must allow saving an unbalanced trial balance; cash/bank voucher
-- balance rules are enforced by the application.
PRINT '  functions, views, procedures and triggers rebuilt';
GO

-- ---- final batch: verify + commit ---------------------------------------------
DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'11_remove_removed_modules', @self = N'12_views_procedures_rebuild', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    12 already applied, skipping.'; RETURN; END
BEGIN TRY
    IF OBJECT_ID('dbo.vw_TrialBalance', 'V') IS NULL THROW 51120, 'verification failed: vw_TrialBalance missing', 1;
    IF OBJECT_ID('dbo.vw_BookLedger', 'V') IS NULL THROW 51120, 'verification failed: vw_BookLedger missing', 1;
    IF OBJECT_ID('dbo.fn_AccountBalance', 'FN') IS NULL THROW 51120, 'verification failed: fn_AccountBalance missing', 1;
    IF OBJECT_ID('dbo.sp_GetMemberStatement', 'P') IS NULL THROW 51120, 'verification failed: sp_GetMemberStatement missing', 1;
    IF OBJECT_ID('dbo.trg_charts_touchUpdatedAt', 'TR') IS NULL THROW 51120, 'verification failed: trg_charts_touchUpdatedAt missing', 1;

    EXEC dbo.__mig_Done @self = N'12_views_procedures_rebuild';
    IF @@TRANCOUNT > 0 COMMIT TRAN;
    PRINT '=== 12 done - all migrations complete ===';
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'12_views_procedures_rebuild';
    THROW;
END CATCH
GO

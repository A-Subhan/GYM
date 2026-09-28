-- ============================================================================
-- Contoura Gym Management System — STEP 4: Stored Procedures
-- ============================================================================
-- Server-side helpers for reporting and administration.
-- Matches the FINAL schema (charts id = account code; CashBook/BankBook/JV/
-- OpenTB books; bookVoucherId references). Identical to the objects created
-- by Database/migrations/12_views_procedures_rebuild.sql.
-- Safe to re-run (CREATE OR ALTER).
-- ============================================================================

USE [GymDB];
GO

-- ---- batch 4: stored procedures ----------------------------------------------

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
PRINT 'Step 04 complete: final stored procedures created.';
GO

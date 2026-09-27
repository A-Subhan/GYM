-- ============================================================================
-- Contoura Gym Management System — STEP 4: Stored Procedures
-- ============================================================================
-- Server-side helpers for reporting and administration. The application's
-- transactional logic lives in the backend (D:\GYM\Backend) — these
-- procedures are read-side / administrative utilities.
-- Safe to re-run (CREATE OR ALTER).
-- ============================================================================

USE [GymDB];
GO

-- Dashboard statistics for one branch (or all when @branchId IS NULL)
GO
CREATE OR ALTER PROCEDURE dbo.sp_GetDashboardStats
    @branchId NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        (SELECT COUNT(*) FROM dbo.[Member] m
          WHERE m.isDeleted = 0 AND m.isActive = 1
            AND (@branchId IS NULL OR m.branchId = @branchId))              AS activeMembers,

        (SELECT COUNT(*) FROM dbo.[Member] m
          WHERE m.isDeleted = 0
            AND (@branchId IS NULL OR m.branchId = @branchId))              AS totalMembers,

        (SELECT COUNT(*) FROM dbo.Attendance a
          WHERE a.date = CAST(GETDATE() AS DATE)
            AND (@branchId IS NULL OR a.branchId = @branchId))              AS checkinsToday,

        (SELECT ISNULL(SUM(f.balance), 0) FROM dbo.[Fee] f
          WHERE f.balance > 0 AND f.status <> N'Voided'
            AND (@branchId IS NULL OR f.branchId = @branchId))              AS outstandingFees,

        (SELECT ISNULL(SUM(l.credit - l.debit), 0)
           FROM dbo.Voucher v
           INNER JOIN dbo.VoucherLine l ON l.voucherId = v.id
           INNER JOIN dbo.[Account] a    ON a.id = l.accountId
          WHERE v.status = N'Posted' AND a.accountType = N'Revenue'
            AND MONTH(v.voucherDate) = MONTH(GETDATE())
            AND YEAR(v.voucherDate)  = YEAR(GETDATE())
            AND (@branchId IS NULL OR v.branchId = @branchId))              AS revenueThisMonth,

        (SELECT COUNT(*) FROM dbo.Prospect p
          WHERE p.status IN (N'New', N'Contacted', N'FollowUp')
            AND (@branchId IS NULL OR p.preferredBranchId = @branchId))     AS openProspects,

        (SELECT COUNT(*) FROM dbo.Staff s
          WHERE s.isDeleted = 0 AND s.isActive = 1
            AND (@branchId IS NULL OR s.branchId = @branchId))              AS activeStaff,

        (SELECT COUNT(*) FROM dbo.InventoryItem i
          WHERE i.quantity <= i.reorderLevel AND i.status <> N'Deleted'
            AND (@branchId IS NULL OR i.branchId = @branchId))              AS lowStockItems;
END
GO

-- Trial balance as of a date
GO
CREATE OR ALTER PROCEDURE dbo.sp_GetTrialBalance
    @asOfDate DATETIME2 = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @asOfDate IS NULL SET @asOfDate = GETDATE();

    SELECT  a.code, a.name AS accountName, a.accountType,
            ISNULL(SUM(ISNULL(l.debit, 0)), 0)  AS totalDebit,
            ISNULL(SUM(ISNULL(l.credit, 0)), 0) AS totalCredit,
            ISNULL(SUM(ISNULL(l.debit, 0) - ISNULL(l.credit, 0)), 0) AS balance
    FROM dbo.[Account] a
    LEFT JOIN dbo.VoucherLine l ON l.accountId = a.id
    LEFT JOIN dbo.Voucher v ON v.id = l.voucherId
        AND v.status = N'Posted' AND v.voucherDate <= @asOfDate
    WHERE a.isDetail = 1
    GROUP BY a.code, a.name, a.accountType
    ORDER BY a.code;
END
GO

-- Income statement between two dates (from posted vouchers)
GO
CREATE OR ALTER PROCEDURE dbo.sp_GetIncomeStatement
    @fromDate DATETIME2,
    @toDate   DATETIME2
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH Totals AS (
        SELECT a.accountType, a.code, a.name AS accountName,
               SUM(ISNULL(l.credit,0) - ISNULL(l.debit,0)) AS amount
        FROM dbo.Voucher v
        INNER JOIN dbo.VoucherLine l ON l.voucherId = v.id
        INNER JOIN dbo.[Account] a   ON a.id = l.accountId
        WHERE v.status = N'Posted'
          AND v.voucherDate BETWEEN @fromDate AND @toDate
          AND a.accountType IN (N'Revenue', N'Expense')
        GROUP BY a.accountType, a.code, a.name
    )
    SELECT accountType, code, accountName, amount,
           CASE accountType WHEN N'Expense' THEN -amount ELSE amount END AS signedAmount
    FROM Totals
    ORDER BY accountType, code;
END
GO

-- Complete statement of a member: invoices, payments and linked vouchers
GO
CREATE OR ALTER PROCEDURE dbo.sp_GetMemberStatement
    @memberId NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT f.feeNo, f.billingPeriodStart, f.billingPeriodEnd, f.amount, f.discount,
           f.paidAmount, f.balance, f.dueDate, f.status
    FROM dbo.[Fee] f
    WHERE f.memberId = @memberId
    ORDER BY f.billingPeriodStart;

    SELECT fp.createdAt AS paidAt, fp.amount, fp.[method],
           v.voucherNo, v.voucherType, a.name AS paidIntoAccount
    FROM dbo.FeePayment fp
    LEFT JOIN dbo.Voucher v ON v.id = fp.voucherId
    LEFT JOIN dbo.[Fee] f   ON f.id = fp.feeId
    LEFT JOIN dbo.[Account] a ON a.id = fp.accountId
    WHERE f.memberId = @memberId
    ORDER BY fp.createdAt;
END
GO

-- Compute a payroll draft for one staff member (no rows written)
GO
CREATE OR ALTER PROCEDURE dbo.sp_CalculatePayroll
    @staffId NVARCHAR(50),
    @[month] INT,
    @[year]  INT
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
        (SELECT ISNULL(SUM(days), 0) FROM dbo.[Leave] l
          WHERE l.staffId = @staffId AND l.status = N'Approved'
            AND MONTH(l.fromDate) = @month AND YEAR(l.fromDate) = @year);

    SELECT @basic AS basicSalary, @allowances AS totalAllowances, @ot AS overtimeAmount,
           (@basic + @allowances + @ot) AS totalEarnings,
           CAST(0 AS DECIMAL(18,2)) AS totalDeductions,
           (@basic + @allowances + @ot) AS netPay;
END
GO

-- Administrative: reset the admin user's password to admin123
GO
CREATE OR ALTER PROCEDURE dbo.sp_ResetAdminPassword
AS
BEGIN
    SET NOCOUNT ON;
    -- bcrypt hash of "admin123" (same hashing as the backend, cost 10)
    UPDATE dbo.[User]
    SET passwordHash = N'$2b$10$4sWId8YdsNlr39HgQ51wE.5rFtEFE3l5APRnRO6rYlE15bOUryvpy',
        mustChangePassword = 0, isActive = 1, isDeleted = 0, failedLoginCount = 0
    WHERE username = N'admin';
    PRINT 'Admin password reset to: admin123';
END
GO

PRINT 'Step 04 complete: stored procedures created.';
GO

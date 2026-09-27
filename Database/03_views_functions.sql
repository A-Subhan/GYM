-- ============================================================================
-- Contoura Gym Management System — STEP 3: Views and Functions
-- ============================================================================
-- Reporting views and scalar functions used for analytics and convenience.
-- Safe to re-run (CREATE OR ALTER).
-- ============================================================================

USE [GymDB];
GO

-- ================================================================
-- FUNCTIONS
-- ================================================================

-- Age of a member/staff from date of birth
GO
CREATE OR ALTER FUNCTION dbo.fn_CalculateAge (@dob DATETIME2)
RETURNS INT
AS
BEGIN
    IF @dob IS NULL RETURN NULL;
    DECLARE @age INT = DATEDIFF(YEAR, @dob, GETDATE());
    IF DATEADD(YEAR, @age, @dob) > GETDATE() SET @age = @age - 1;
    RETURN @age;
END
GO

-- Current outstanding balance of a member (sum of unpaid fee balances)
GO
CREATE OR ALTER FUNCTION dbo.fn_MemberOutstanding (@memberId NVARCHAR(50))
RETURNS DECIMAL(18,2)
AS
BEGIN
    DECLARE @bal DECIMAL(18,2);
    SELECT @bal = ISNULL(SUM(balance), 0)
    FROM dbo.[Fee]
    WHERE memberId = @memberId AND status <> N'Voided';
    RETURN ISNULL(@bal, 0);
END
GO

-- Net movement (debit - credit) posted on an account, optionally within a range
GO
CREATE OR ALTER FUNCTION dbo.fn_AccountBalance (@accountId NVARCHAR(50), @fromDate DATETIME2 = NULL, @toDate DATETIME2 = NULL)
RETURNS DECIMAL(18,2)
AS
BEGIN
    DECLARE @bal DECIMAL(18,2);
    SELECT @bal = ISNULL(SUM(ISNULL(l.debit,0) - ISNULL(l.credit,0)), 0)
    FROM dbo.VoucherLine l
    INNER JOIN dbo.Voucher v ON v.id = l.voucherId
    WHERE l.accountId = @accountId
      AND v.status = N'Posted'
      AND (@fromDate IS NULL OR v.voucherDate >= @fromDate)
      AND (@toDate   IS NULL OR v.voucherDate <= @toDate);
    RETURN ISNULL(@bal, 0);
END
GO

-- ================================================================
-- VIEWS
-- ================================================================

-- Active members with plan and branch info
GO
CREATE OR ALTER VIEW dbo.vw_ActiveMembers
AS
SELECT  m.id, m.memberId, m.firstName, m.lastName,
        (m.firstName + N' ' + m.lastName) AS fullName,
        m.gender, m.phone, m.email, m.status, m.joiningDate,
        m.billingStartDate, m.isActive,
        p.name AS planName, p.code AS planCode, p.amount AS planAmount,
        b.name AS branchName, b.code AS branchCode,
        s.firstName + N' ' + s.lastName AS trainerName,
        dbo.fn_MemberOutstanding(m.id) AS outstandingBalance
FROM dbo.[Member] m
LEFT JOIN dbo.MembershipPlan p ON p.id = m.membershipPlanId
LEFT JOIN dbo.Branch b         ON b.id = m.branchId
LEFT JOIN dbo.Staff s          ON s.id = m.assignedTrainerId
WHERE m.isDeleted = 0 AND m.isActive = 1;
GO

-- Fees that still carry an outstanding balance
GO
CREATE OR ALTER VIEW dbo.vw_OutstandingFees
AS
SELECT  f.id, f.feeNo, f.memberId, (m.firstName + N' ' + m.lastName) AS memberName,
        m.memberId AS memberCode, f.billingPeriodStart, f.billingPeriodEnd,
        f.amount, f.discount, f.paidAmount, f.balance, f.dueDate, f.status,
        b.name AS branchName,
        DATEDIFF(DAY, f.dueDate, GETDATE()) AS daysOverdue
FROM dbo.[Fee] f
INNER JOIN dbo.[Member] m ON m.id = f.memberId
LEFT JOIN dbo.Branch b    ON b.id = f.branchId
WHERE f.balance > 0 AND f.status <> N'Voided';
GO

-- Trial balance: per-account posted debit/credit totals
GO
CREATE OR ALTER VIEW dbo.vw_TrialBalance
AS
SELECT  a.id AS accountId, a.code, a.name AS accountName, a.accountType, a.bookType,
        a.accountTag, a.isDetail,
        ISNULL(SUM(ISNULL(l.debit, 0)), 0)  AS totalDebit,
        ISNULL(SUM(ISNULL(l.credit, 0)), 0) AS totalCredit,
        ISNULL(SUM(ISNULL(l.debit, 0) - ISNULL(l.credit, 0)), 0) AS netBalance
FROM dbo.[Account] a
LEFT JOIN dbo.VoucherLine l ON l.accountId = a.id
LEFT JOIN dbo.Voucher v     ON v.id = l.voucherId AND v.status = N'Posted'
WHERE a.isDetail = 1
GROUP BY a.id, a.code, a.name, a.accountType, a.bookType, a.accountTag, a.isDetail;
GO

-- Monthly revenue (fee income + POS income) from posted vouchers
GO
CREATE OR ALTER VIEW dbo.vw_MonthlyRevenue
AS
SELECT  YEAR(v.voucherDate) AS [year], MONTH(v.voucherDate) AS [month],
        a.accountTag,
        SUM(ISNULL(l.credit, 0) - ISNULL(l.debit, 0)) AS revenue
FROM dbo.Voucher v
INNER JOIN dbo.VoucherLine l ON l.voucherId = v.id
INNER JOIN dbo.[Account] a   ON a.id = l.accountId
WHERE v.status = N'Posted' AND a.accountType = N'Revenue'
GROUP BY YEAR(v.voucherDate), MONTH(v.voucherDate), a.accountTag;
GO

-- Attendance with member context (gym reports)
GO
CREATE OR ALTER VIEW dbo.vw_AttendanceLog
AS
SELECT  a.id, a.date, a.checkIn, a.checkOut, a.notes,
        m.memberId AS memberCode, (m.firstName + N' ' + m.lastName) AS memberName,
        m.membershipPlanId, p.name AS planName,
        b.name AS branchName, b.id AS branchId
FROM dbo.Attendance a
INNER JOIN dbo.[Member] m ON m.id = a.memberId
LEFT JOIN dbo.MembershipPlan p ON p.id = m.membershipPlanId
LEFT JOIN dbo.Branch b ON b.id = a.branchId;
GO

-- Payroll register per staff per month
GO
CREATE OR ALTER VIEW dbo.vw_PayrollRegister
AS
SELECT  p.id, p.payrollNo, p.[month], p.[year], p.basicSalary, p.totalAllowances,
        p.overtimeAmount, p.totalEarnings, p.totalDeductions, p.netPay, p.status,
        s.employeeId, (s.firstName + N' ' + s.lastName) AS staffName,
        s.designation, s.department,
        b.name AS branchName
FROM dbo.Payroll p
INNER JOIN dbo.Staff s ON s.id = p.staffId
LEFT JOIN dbo.Branch b ON b.id = p.branchId;
GO

-- Inventory stock status with reorder flags
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

-- Class enrollment counts
GO
CREATE OR ALTER VIEW dbo.vw_ClassEnrollmentSummary
AS
SELECT  c.id AS classId, c.name AS className, c.capacity, c.dayOfWeek,
        c.startTime, c.endTime, c.status,
        (s.firstName + N' ' + s.lastName) AS trainerName,
        b.name AS branchName,
        COUNT(e.id) AS enrolled,
        (c.capacity - COUNT(e.id)) AS seatsLeft
FROM dbo.GymClass c
LEFT JOIN dbo.Staff s ON s.id = c.trainerId
LEFT JOIN dbo.Branch b ON b.id = c.branchId
LEFT JOIN dbo.ClassEnrollment e ON e.classId = c.id AND e.status = N'Active'
GROUP BY c.id, c.name, c.capacity, c.dayOfWeek, c.startTime, c.endTime, c.status,
         s.firstName, s.lastName, b.name;
GO

PRINT 'Step 03 complete: views and functions created.';
GO

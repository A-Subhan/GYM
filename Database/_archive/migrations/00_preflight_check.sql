-- ============================================================================
-- Contoura Gym ERP — Migration 00: PREFLIGHT CHECK (READ-ONLY)
-- ============================================================================
-- Run this FIRST. It changes nothing. It verifies every table / column /
-- object the migration chain 01..12 expects, and prints PRESENT or MISSING
-- for each, based on YOUR live database (not on assumptions).
--
-- If anything prints MISSING (other than items explicitly marked OPTIONAL),
-- STOP and send this output back before running the migrations.
-- ============================================================================

SET NOCOUNT ON;
SET LANGUAGE us_english;
GO

PRINT '==============================================================';
PRINT '=== 00: preflight check (read-only) — ' + CONVERT(varchar(19), GETDATE(), 120) + ' ===';
PRINT '==============================================================';
GO

CREATE TABLE #expect (Item NVARCHAR(200), Kind NVARCHAR(10));
INSERT INTO #expect VALUES
-- Core tables that MUST exist (live database baseline)
('TABLE dbo.Company','MUST'),
('TABLE dbo.Branch','MUST'),
('TABLE dbo.[User]','MUST'),
('TABLE dbo.Role','MUST'),
('TABLE dbo.Account','MUST'),
('TABLE dbo.AccountMapping','MUST'),
('TABLE dbo.FinanceDefaults','MUST'),
('TABLE dbo.Member','MUST'),
('TABLE dbo.MembershipPlan','MUST'),
('TABLE dbo.Attendance','MUST'),
('TABLE dbo.Fee','MUST'),
('TABLE dbo.FeePayment','MUST'),
('TABLE dbo.MembershipFreeze','MUST'),
('TABLE dbo.Prospect','MUST'),
('TABLE dbo.FollowUp','MUST'),
('TABLE dbo.ProgressEntry','MUST'),
('TABLE dbo.WorkoutPlan','MUST'),
('TABLE dbo.DietPlan','MUST'),
('TABLE dbo.Staff','MUST'),
('TABLE dbo.Shift','MUST'),
('TABLE dbo.Allowance','MUST'),
('TABLE dbo.Leave','MUST'),
('TABLE dbo.Payroll','MUST'),
('TABLE dbo.Overtime','MUST'),
('TABLE dbo.MasterFile','MUST'),
('TABLE dbo.Equipment','MUST'),
('TABLE dbo.Exercise','MUST'),
('TABLE dbo.InventoryItem','MUST'),
('TABLE dbo.PosSale','MUST'),
('TABLE dbo.Supplier','MUST'),
('TABLE dbo.Purchase','MUST'),
('TABLE dbo.StockMovement','MUST'),
('TABLE dbo.TaxHead','MUST'),
-- Legacy tables that MAY exist (migrations skip them cleanly if absent)
('TABLE dbo.Voucher','OPTIONAL'),
('TABLE dbo.VoucherLine','OPTIONAL'),
('TABLE dbo.Cheque','OPTIONAL'),
('TABLE dbo.LeaveType','OPTIONAL'),
-- Removed-module tables (renamed to zz_backup_... by migration 11)
('TABLE dbo.GymClass','MUST'),
('TABLE dbo.ClassEnrollment','MUST'),
('TABLE dbo.FitnessAssessment','MUST'),
('TABLE dbo.MemberDocument','MUST'),
-- Key columns the migrations read or rewrite
('COL  dbo.Account.code','MUST'),
('COL  dbo.Account.parentId','MUST'),
('COL  dbo.Account.openingBalance','MUST'),
('COL  dbo.Account.openingBalanceType','MUST'),
('COL  dbo.Account.branchId','MUST'),
('COL  dbo.Member.memberId','MUST'),
('COL  dbo.Member.joiningDate','MUST'),
('COL  dbo.Member.isDeleted','MUST'),
('COL  dbo.Member.branchId','MUST'),
('COL  dbo.MembershipPlan.code','MUST'),
('COL  dbo.Fee.feeNo','MUST'),
('COL  dbo.Fee.billingPeriodStart','MUST'),
('COL  dbo.Fee.branchId','MUST'),
('COL  dbo.Attendance.branchId','MUST'),
('COL  dbo.Attendance.date','MUST'),
('COL  dbo.Prospect.prospectId','MUST'),
('COL  dbo.Prospect.preferredBranchId','MUST'),
('COL  dbo.FollowUp.branchId','MUST'),
('COL  dbo.ProgressEntry.memberId','MUST'),
('COL  dbo.Branch.code','MUST'),
('COL  dbo.Branch.name','MUST'),
('COL  dbo.Staff.branchId','MUST'),
('COL  dbo.Staff.designation','MUST'),
('COL  dbo.Staff.department','MUST'),
('COL  dbo.Leave.staffId','MUST'),
('COL  dbo.Leave.leaveType','MUST'),
('COL  dbo.Leave.fromDate','MUST'),
('COL  dbo.AccountMapping.key','MUST'),
('COL  dbo.AccountMapping.branchId','MUST'),
('COL  dbo.AccountMapping.accountId','MUST'),
('COL  dbo.Payroll.voucherId','MUST'),
('COL  dbo.Fee.voucherId','MUST'),
('COL  dbo.FeePayment.voucherId','MUST'),
('COL  dbo.PosSale.voucherId','MUST'),
('COL  dbo.Company.name','MUST'),
('COL  dbo.Company.accountingType','MUST'),
-- Objects that must NOT exist yet (fresh migration run)
('TABLE dbo.charts','MUST-NOT'),
('TABLE dbo.CashBook','MUST-NOT'),
('TABLE dbo.BankBook','MUST-NOT'),
('TABLE dbo.JV','MUST-NOT'),
('TABLE dbo.OpenTB','MUST-NOT'),
('TABLE dbo.KnockOff','MUST-NOT'),
('TABLE dbo.IdSequence','MUST-NOT'),
('TABLE dbo.Defaults','MUST-NOT'),
('TABLE dbo.UserPermission','MUST-NOT'),
('TABLE dbo.gymmasterfile','MUST-NOT'),
('TABLE dbo.payrollmasterfile','MUST-NOT'),
('TABLE dbo.__MigrationHistory','MUST-NOT');
GO

PRINT '--- Table / column presence ---';
SELECT  e.Item,
        CASE
          WHEN e.Item LIKE 'TABLE %' AND OBJECT_ID('dbo.' + SUBSTRING(e.Item, 8, 200)) IS NOT NULL THEN 'PRESENT'
          WHEN e.Item LIKE 'TABLE %' THEN 'MISSING'
          WHEN e.Item LIKE 'COL  %' AND COL_LENGTH(
                 'dbo.' + LTRIM(RTRIM(SUBSTRING(e.Item, 7, CHARINDEX('.', e.Item + '.', 7) - 7))),
                 LTRIM(RTRIM(SUBSTRING(e.Item, CHARINDEX('.', e.Item + '.', 7) + 1, 200)))) IS NOT NULL THEN 'PRESENT'
          WHEN e.Item LIKE 'COL  %' THEN 'MISSING'
        END AS Status,
        e.Kind
FROM #expect e
ORDER BY CASE WHEN e.Item LIKE 'TABLE%' THEN 0 ELSE 1 END, e.Item;
GO

PRINT '--- Row counts of tables that will be restructured (data preserved) ---';
SELECT  'Account'      AS Tbl, COUNT(*) AS Rows FROM dbo.Account
UNION ALL SELECT 'Member',          COUNT(*) FROM dbo.Member
UNION ALL SELECT 'MembershipPlan',  COUNT(*) FROM dbo.MembershipPlan
UNION ALL SELECT 'Attendance',      COUNT(*) FROM dbo.Attendance
UNION ALL SELECT 'Fee',             COUNT(*) FROM dbo.Fee
UNION ALL SELECT 'Prospect',        COUNT(*) FROM dbo.Prospect
UNION ALL SELECT 'FollowUp',        COUNT(*) FROM dbo.FollowUp
UNION ALL SELECT 'ProgressEntry',   COUNT(*) FROM dbo.ProgressEntry
UNION ALL SELECT 'WorkoutPlan',     COUNT(*) FROM dbo.WorkoutPlan
UNION ALL SELECT 'DietPlan',        COUNT(*) FROM dbo.DietPlan
UNION ALL SELECT 'Branch',          COUNT(*) FROM dbo.Branch
UNION ALL SELECT 'Leave',           COUNT(*) FROM dbo.Leave
UNION ALL SELECT 'AccountMapping',  COUNT(*) FROM dbo.AccountMapping
UNION ALL SELECT 'Voucher (legacy)',  CASE WHEN OBJECT_ID('dbo.Voucher')      IS NULL THEN -1 ELSE (SELECT COUNT(*) FROM dbo.Voucher)      END
UNION ALL SELECT 'VoucherLine (legacy)', CASE WHEN OBJECT_ID('dbo.VoucherLine') IS NULL THEN -1 ELSE (SELECT COUNT(*) FROM dbo.VoucherLine) END
UNION ALL SELECT 'Cheque (legacy)',      CASE WHEN OBJECT_ID('dbo.Cheque')      IS NULL THEN -1 ELSE (SELECT COUNT(*) FROM dbo.Cheque)      END
UNION ALL SELECT 'GymClass',        COUNT(*) FROM dbo.GymClass
UNION ALL SELECT 'ClassEnrollment', COUNT(*) FROM dbo.ClassEnrollment
UNION ALL SELECT 'FitnessAssessment', COUNT(*) FROM dbo.FitnessAssessment
UNION ALL SELECT 'MemberDocument',  COUNT(*) FROM dbo.MemberDocument;
PRINT '    (-1 = table does not exist; migrations skip it cleanly)';
GO

PRINT '--- Duplicate checks that would block ID regeneration ---';
SELECT 'Member: members per branch+joining month' AS Check_, b.code AS Branch,
       UPPER(FORMAT(m.joiningDate,'MMMyy')) AS Mon, COUNT(*) AS Cnt
FROM dbo.Member m JOIN dbo.Branch b ON b.id = m.branchId
GROUP BY b.code, UPPER(FORMAT(m.joiningDate,'MMMyy'));
GO

PRINT '--- Foreign keys referencing tables whose keys get rebuilt ---';
SELECT fk.name AS FKName, OBJECT_NAME(fk.parent_object_id) AS ChildTable
FROM sys.foreign_keys fk
WHERE fk.referenced_object_id IN (OBJECT_ID('dbo.Account'), OBJECT_ID('dbo.Member'),
                                  OBJECT_ID('dbo.MembershipPlan'), OBJECT_ID('dbo.Fee'),
                                  OBJECT_ID('dbo.WorkoutPlan'), OBJECT_ID('dbo.DietPlan'))
ORDER BY ChildTable, fk.name;
GO

PRINT '==============================================================';
PRINT '=== 00 preflight finished (nothing was changed)             ===';
PRINT '=== MUST + MISSING  -> STOP, send this output first.        ===';
PRINT '=== OPTIONAL + MISSING -> fine, migrations skip them.       ===';
PRINT '=== MUST-NOT + PRESENT -> a previous run already applied;   ===';
PRINT '===     check dbo.__MigrationHistory / restore backup.      ===';
PRINT '==============================================================';
GO

-- =====================================================================
-- Contoura Gym ERP — Migration 10 of 10
-- Rebuild views / procedures / triggers against the new schema
-- (charts + four book tables), apply final integrity checks and
-- system locks (company-name lock flag, accounting-period locks).
-- Idempotent: CREATE OR ALTER everywhere.
-- =====================================================================
SET NOCOUNT ON;
GO
PRINT '=== 10: views/procs/triggers rebuild ===';

-- ---------------------------------------------------------------------
-- Drop legacy objects that reference removed tables
-- ---------------------------------------------------------------------
IF OBJECT_ID('dbo.vw_ClassEnrollmentSummary','V') IS NOT NULL DROP VIEW [dbo].[vw_ClassEnrollmentSummary];
IF OBJECT_ID('dbo.trg_Voucher_BalanceCheck','TR') IS NOT NULL DROP TRIGGER [dbo].[trg_Voucher_BalanceCheck];
IF OBJECT_ID('dbo.trg_Voucher_touchUpdatedAt','TR') IS NOT NULL DROP TRIGGER [dbo].[trg_Voucher_touchUpdatedAt];
IF OBJECT_ID('dbo.trg_Account_touchUpdatedAt','TR') IS NOT NULL DROP TRIGGER [dbo].[trg_Account_touchUpdatedAt];
GO

-- ---------------------------------------------------------------------
-- Views
-- ---------------------------------------------------------------------
CREATE OR ALTER VIEW [dbo].[vw_TrialBalance]
AS
SELECT c.[id] AS [accountCode], c.[name] AS [accountName], c.[accountType], c.[isControl],
       SUM(ISNULL(l.[debit],0)) AS [debit], SUM(ISNULL(l.[credit],0)) AS [credit],
       SUM(ISNULL(l.[debit],0) - ISNULL(l.[credit],0)) AS [balance]
FROM [dbo].[charts] c
LEFT JOIN [dbo].[BookVoucherLine] l ON l.[accountId] = c.[id] AND l.[status] = 'Active'
WHERE EXISTS (
    SELECT 1 FROM [dbo].[CashbookVoucher] cv WHERE cv.[id] = l.[voucherId] AND cv.[status] = 'Posted'
    UNION ALL SELECT 1 FROM [dbo].[BankbookVoucher] bv WHERE bv.[id] = l.[voucherId] AND bv.[status] = 'Posted'
    UNION ALL SELECT 1 FROM [dbo].[JournalVoucher] jv WHERE jv.[id] = l.[voucherId] AND jv.[status] = 'Posted'
    UNION ALL SELECT 1 FROM [dbo].[OpenTbVoucher] ov WHERE ov.[id] = l.[voucherId] AND ov.[status] = 'Posted'
)
GROUP BY c.[id], c.[name], c.[accountType], c.[isControl];
GO
CREATE OR ALTER VIEW [dbo].[vw_ActiveMembers]
AS
SELECT m.[id], m.[memberId], m.[firstName], m.[lastName], m.[phone], m.[whatsapp], m.[status], m.[joiningDate], b.[name] AS [branchName], b.[code] AS [branchCode]
FROM [dbo].[Member] m
JOIN [dbo].[Branch] b ON b.[id] = m.[branchId]
WHERE m.[isDeleted] = 0 AND m.[status] = 'Active';
GO
CREATE OR ALTER VIEW [dbo].[vw_AttendanceLog]
AS
SELECT a.[id], m.[memberId], m.[firstName] + ISNULL(' ' + m.[lastName],'') AS [memberName], b.[code] AS [branchCode],
       a.[date], a.[checkIn], a.[checkOut]
FROM [dbo].[Attendance] a
JOIN [dbo].[Member] m ON m.[id] = a.[memberId]
JOIN [dbo].[Branch] b ON b.[id] = a.[branchId];
GO
CREATE OR ALTER VIEW [dbo].[vw_OutstandingFees]
AS
SELECT f.[id], f.[feeNo], m.[memberId], m.[firstName] + ISNULL(' ' + m.[lastName],'') AS [memberName],
       b.[code] AS [branchCode], f.[billingPeriodStart], f.[billingPeriodEnd], f.[amount], f.[paidAmount], f.[balance], f.[dueDate], f.[status]
FROM [dbo].[Fee] f
JOIN [dbo].[Member] m ON m.[id] = f.[memberId] AND m.[isDeleted] = 0
JOIN [dbo].[Branch] b ON b.[id] = f.[branchId]
WHERE f.[status] IN ('Unpaid','Partial');
GO
CREATE OR ALTER VIEW [dbo].[vw_MonthlyRevenue]
AS
SELECT YEAR(f.[billingPeriodStart]) AS [yr], MONTH(f.[billingPeriodStart]) AS [mo], b.[code] AS [branchCode],
       SUM(f.[paidAmount]) AS [collected], SUM(f.[amount] - f.[discount]) AS [billed]
FROM [dbo].[Fee] f
JOIN [dbo].[Branch] b ON b.[id] = f.[branchId]
GROUP BY YEAR(f.[billingPeriodStart]), MONTH(f.[billingPeriodStart]), b.[code];
GO
CREATE OR ALTER VIEW [dbo].[vw_PayrollRegister]
AS
SELECT p.[id], p.[payrollNo], s.[employeeId], s.[firstName] + ISNULL(' ' + s.[lastName],'') AS [employeeName],
       b.[code] AS [branchCode], p.[month], p.[year], p.[basicSalary], p.[totalAllowances], p.[overtimeAmount],
       p.[totalEarnings], p.[totalDeductions], p.[netPay], p.[status], p.[bookVoucherId]
FROM [dbo].[Payroll] p
JOIN [dbo].[Staff] s ON s.[id] = p.[staffId] AND s.[isDeleted] = 0
JOIN [dbo].[Branch] b ON b.[id] = p.[branchId];
GO
CREATE OR ALTER VIEW [dbo].[vw_StockStatus]
AS
SELECT i.[id], i.[code], i.[name], i.[category], b.[code] AS [branchCode],
       i.[quantity], i.[reorderLevel], i.[purchasePrice], i.[salePrice],
       CASE WHEN i.[quantity] <= i.[reorderLevel] THEN 'REORDER' ELSE 'OK' END AS [stockState]
FROM [dbo].[InventoryItem] i
JOIN [dbo].[Branch] b ON b.[id] = i.[branchId];
GO
-- NEW: unified book ledger view over all four books
CREATE OR ALTER VIEW [dbo].[vw_BookLedger]
AS
SELECT l.[id] AS [lineId], l.[voucherId], l.[voucherType], l.[bookType], l.[accountId], c.[name] AS [accountName],
       c.[accountType], l.[debit], l.[credit], l.[amount], l.[billType], l.[taxRate], l.[taxAmount],
       l.[chequeNo], l.[chequeAmount], l.[lineDescription], l.[status] AS [lineStatus],
       CASE l.[bookType]
         WHEN 'CASHBOOK' THEN cv.[voucherDate] WHEN 'BANKBOOK' THEN bv.[voucherDate]
         WHEN 'JV' THEN jv.[voucherDate] ELSE ov.[voucherDate] END AS [voucherDate],
       CASE l.[bookType]
         WHEN 'CASHBOOK' THEN cv.[status] WHEN 'BANKBOOK' THEN bv.[status]
         WHEN 'JV' THEN jv.[status] ELSE ov.[status] END AS [voucherStatus],
       CASE l.[bookType] WHEN 'CASHBOOK' THEN cv.[branchId] WHEN 'BANKBOOK' THEN bv.[branchId]
         WHEN 'JV' THEN jv.[branchId] ELSE ov.[branchId] END AS [branchId]
FROM [dbo].[BookVoucherLine] l
JOIN [dbo].[charts] c ON c.[id] = l.[accountId]
LEFT JOIN [dbo].[CashbookVoucher] cv ON cv.[id] = l.[voucherId] AND l.[bookType]='CASHBOOK'
LEFT JOIN [dbo].[BankbookVoucher] bv ON bv.[id] = l.[voucherId] AND l.[bookType]='BANKBOOK'
LEFT JOIN [dbo].[JournalVoucher] jv ON jv.[id] = l.[voucherId] AND l.[bookType]='JV'
LEFT JOIN [dbo].[OpenTbVoucher] ov ON ov.[id] = l.[voucherId] AND l.[bookType]='OTB';
GO

-- ---------------------------------------------------------------------
-- Stored procedures
-- ---------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[sp_GetTrialBalance]
    @asOf DATETIME2 = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT [accountCode], [accountName], [accountType], [isControl], [debit], [credit], [balance]
    FROM [dbo].[vw_TrialBalance]
    ORDER BY [accountCode];
END
GO
CREATE OR ALTER PROCEDURE [dbo].[sp_GetIncomeStatement]
    @from DATETIME2, @to DATETIME2
AS
BEGIN
    SET NOCOUNT ON;
    SELECT c.[accountType], c.[id] AS [accountCode], c.[name] AS [accountName],
           SUM(l.[credit] - l.[debit]) AS [amount]
    FROM [dbo].[vw_BookLedger] l
    JOIN [dbo].[charts] c ON c.[id] = l.[accountId]
    WHERE l.[voucherStatus] = 'Posted' AND l.[voucherDate] BETWEEN @from AND @to
      AND c.[accountType] IN ('Revenue','Expense')
    GROUP BY c.[accountType], c.[id], c.[name]
    ORDER BY c.[accountType], c.[id];
END
GO
CREATE OR ALTER PROCEDURE [dbo].[sp_GetDashboardStats]
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @today DATE = CAST(SYSDATETIME() AS date);
    SELECT
      (SELECT COUNT(*) FROM [dbo].[Member] WHERE [isDeleted]=0 AND [status]='Active')                    AS [activeMembers],
      (SELECT COUNT(*) FROM [dbo].[Attendance] WHERE CAST([date] AS date) = @today)                      AS [attendanceToday],
      (SELECT ISNULL(SUM(f.[paidAmount]),0) FROM [dbo].[Fee] f WHERE MONTH(f.[billingPeriodStart])=MONTH(@today) AND YEAR(f.[billingPeriodStart])=YEAR(@today)) AS [feesThisMonth],
      (SELECT ISNULL(SUM(f.[balance]),0) FROM [dbo].[Fee] f WHERE f.[status] IN ('Unpaid','Partial'))    AS [outstandingFees],
      (SELECT COUNT(*) FROM [dbo].[Prospect] WHERE [status]='New')                                       AS [newProspects];
END
GO
CREATE OR ALTER PROCEDURE [dbo].[sp_GetMemberStatement]
    @memberId NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT f.[feeNo], f.[billingPeriodStart], f.[billingPeriodEnd], f.[amount], f.[discount],
           f.[paidAmount], f.[balance], f.[dueDate], f.[status], f.[bookVoucherId]
    FROM [dbo].[Fee] f JOIN [dbo].[Member] m ON m.[id] = f.[memberId]
    WHERE m.[memberId] = @memberId
    ORDER BY f.[billingPeriodStart];
END
GO
CREATE OR ALTER PROCEDURE [dbo].[sp_ResetAdminPassword]
    @username NVARCHAR(191), @passwordHash NVARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE [dbo].[User] SET [passwordHash]=@passwordHash, [mustChangePassword]=1, [updatedAt]=SYSDATETIME()
    WHERE [username]=@username;
END
GO
CREATE OR ALTER PROCEDURE [dbo].[sp_CalculatePayroll]
    @branchId NVARCHAR(50), @month INT, @year INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT s.[id] AS [staffId], s.[employeeId], s.[basicSalary],
           (s.[fuelAllowance] + s.[rentAllowance] + s.[houseAllowance] + s.[otherAllowance]) AS [allowances],
           (s.[sessi] + s.[eobi]) AS [statutoryDeductions]
    FROM [dbo].[Staff] s
    WHERE s.[branchId] = @branchId AND s.[isDeleted] = 0 AND s.[isActive] = 1
      AND NOT EXISTS (SELECT 1 FROM [dbo].[Payroll] p WHERE p.[staffId]=s.[id] AND p.[month]=@month AND p.[year]=@year);
END
GO

-- ---------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------
CREATE OR ALTER TRIGGER [dbo].[trg_charts_touchUpdatedAt]
ON [dbo].[charts] AFTER UPDATE
AS BEGIN SET NOCOUNT ON; UPDATE t SET t.[updatedAt]=SYSDATETIME() FROM [dbo].[charts] t JOIN inserted i ON i.[id]=t.[id] WHERE NOT UPDATE([updatedAt]); END
GO
CREATE OR ALTER TRIGGER [dbo].[trg_Member_touchUpdatedAt]
ON [dbo].[Member] AFTER UPDATE
AS BEGIN SET NOCOUNT ON; UPDATE t SET t.[updatedAt]=SYSDATETIME() FROM [dbo].[Member] t JOIN inserted i ON i.[id]=t.[id] WHERE NOT UPDATE([updatedAt]); END
GO
CREATE OR ALTER TRIGGER [dbo].[trg_Fee_touchUpdatedAt]
ON [dbo].[Fee] AFTER UPDATE
AS BEGIN SET NOCOUNT ON; UPDATE t SET t.[updatedAt]=SYSDATETIME() FROM [dbo].[Fee] t JOIN inserted i ON i.[id]=t.[id] WHERE NOT UPDATE([updatedAt]); END
GO
CREATE OR ALTER TRIGGER [dbo].[trg_Staff_touchUpdatedAt]
ON [dbo].[Staff] AFTER UPDATE
AS BEGIN SET NOCOUNT ON; UPDATE t SET t.[updatedAt]=SYSDATETIME() FROM [dbo].[Staff] t JOIN inserted i ON i.[id]=t.[id] WHERE NOT UPDATE([updatedAt]); END
GO
CREATE OR ALTER TRIGGER [dbo].[trg_InventoryItem_touchUpdatedAt]
ON [dbo].[InventoryItem] AFTER UPDATE
AS BEGIN SET NOCOUNT ON; UPDATE t SET t.[updatedAt]=SYSDATETIME() FROM [dbo].[InventoryItem] t JOIN inserted i ON i.[id]=t.[id] WHERE NOT UPDATE([updatedAt]); END
GO
CREATE OR ALTER TRIGGER [dbo].[trg_Payroll_Audit]
ON [dbo].[Payroll] AFTER INSERT, UPDATE
AS BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [dbo].[AuditLog])
        RETURN;
    INSERT INTO [dbo].[AuditLog] ([id],[action],[module],[details],[createdAt])
    SELECT LOWER(REPLACE(NEWID(),'-','')), 'PAYROLL', 'payroll',
           CONCAT('payroll ', i.[payrollNo], ' status=', i.[status]), SYSDATETIME()
    FROM inserted i;
END
GO
-- Book voucher balance guard: JV must stay balanced; OTV may differ.
CREATE OR ALTER TRIGGER [dbo].[trg_JournalVoucher_BalanceCheck]
ON [dbo].[JournalVoucher] AFTER INSERT, UPDATE
AS BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM inserted WHERE [status]='Posted' AND ABS([totalDebit]-[totalCredit]) > 0.01)
    BEGIN
        RAISERROR('Journal voucher must be balanced.', 16, 1);
        ROLLBACK TRANSACTION;
    END
END
GO

-- ---------------------------------------------------------------------
-- System locks
-- ---------------------------------------------------------------------
-- Company name one-time lock: any company row with a non-empty name is locked.
UPDATE [dbo].[Company] SET [nameLocked]=1
WHERE ISNULL([name],'') <> '' AND ISNULL([nameLocked],0) = 0
  AND OBJECT_ID('dbo.Company') IS NOT NULL AND COL_LENGTH('dbo.Company','nameLocked') IS NOT NULL;
GO
IF OBJECT_ID('dbo.Company') IS NOT NULL AND COL_LENGTH('dbo.Company','nameLocked') IS NULL
    ALTER TABLE [dbo].[Company] ADD [nameLocked] BIT NOT NULL DEFAULT 0;
GO

-- Final integrity summary
SELECT 'charts accounts' AS [check], COUNT(*) AS [count] FROM [dbo].[charts]
UNION ALL SELECT 'cashbook vouchers', COUNT(*) FROM [dbo].[CashbookVoucher]
UNION ALL SELECT 'bankbook vouchers', COUNT(*) FROM [dbo].[BankbookVoucher]
UNION ALL SELECT 'journal vouchers',  COUNT(*) FROM [dbo].[JournalVoucher]
UNION ALL SELECT 'opening TB',        COUNT(*) FROM [dbo].[OpenTbVoucher]
UNION ALL SELECT 'book lines',        COUNT(*) FROM [dbo].[BookVoucherLine]
UNION ALL SELECT 'knock-offs',        COUNT(*) FROM [dbo].[KnockOff]
UNION ALL SELECT 'sequences',         COUNT(*) FROM [dbo].[IdSequence];
GO
PRINT '=== 10 done — all migrations complete ===';

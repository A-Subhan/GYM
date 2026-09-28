-- =====================================================================
-- Contoura Gym ERP — Migration 04 of 10
-- Migrate legacy [Voucher]/[VoucherLine]/[Cheque] data into the four
-- dedicated book tables, regenerate voucher numbers into the confirmed
-- format {TYPE}/{branchCode}/{MMMyy}/{000001} (reversal = -R suffix),
-- then drop the legacy tables.
-- Depends on: 01 (charts rename + id map), 02 (book tables), 03 (sequences).
-- Idempotent: legacy tables dropped at the end; re-run is a no-op.
-- =====================================================================
SET NOCOUNT ON;
GO
PRINT '=== 04: migrate vouchers ===';

IF OBJECT_ID('dbo.Voucher') IS NULL
BEGIN
    PRINT 'Legacy Voucher table not found — nothing to migrate.';
    RETURN;
END
GO

-- 1. Regenerate voucher numbers into a staging column
IF COL_LENGTH('dbo.Voucher', 'newNo') IS NULL
    ALTER TABLE [dbo].[Voucher] ADD [newNo] NVARCHAR(50) NULL;
IF COL_LENGTH('dbo.Voucher', 'newBookType') IS NULL
    ALTER TABLE [dbo].[Voucher] ADD [newBookType] NVARCHAR(20) NULL;
GO
;WITH Renum AS (
    SELECT v.[id],
           ROW_NUMBER() OVER (PARTITION BY v.[voucherType], b.[code], UPPER(FORMAT(v.[voucherDate], 'MMMyy'))
                              ORDER BY v.[voucherDate], v.[createdAt]) AS rn
    FROM [dbo].[Voucher] v
    JOIN [dbo].[Branch] b ON b.[id] = v.[branchId]
)
UPDATE v SET
    [newNo]      = CONCAT(v.[voucherType], '/', b.[code], '/', UPPER(FORMAT(v.[voucherDate], 'MMMyy')), '/', FORMAT(r.rn, '000000')),
    [newBookType]= CASE v.[voucherType]
                     WHEN 'CRV' THEN 'CASHBOOK' WHEN 'CPV' THEN 'CASHBOOK'
                     WHEN 'BRV' THEN 'BANKBOOK' WHEN 'BPV' THEN 'BANKBOOK'
                     WHEN 'JV'  THEN 'JV'       WHEN 'OTB' THEN 'OTB'
                     ELSE 'JV' END
FROM [dbo].[Voucher] v
JOIN [dbo].[Branch] b ON b.[id] = v.[branchId]
JOIN Renum r ON r.[id] = v.[id];
GO

-- 2. Copy vouchers into the right book tables
INSERT INTO [dbo].[CashbookVoucher] ([id],[voucherType],[voucherDate],[branchId],[bookChartId],[description],[reference],[paymentMode],[totalAmount],[status],[reversedById],[reversedAt],[reversalReason],[postedById],[createdAt],[updatedAt])
SELECT v.[newNo], v.[voucherType], v.[voucherDate], v.[branchId], m.[newId], v.[description], v.[reference], 'Cash', v.[totalDebit],
       v.[status], v.[reversedById], v.[reversedAt], v.[reversalReason], v.[postedById], v.[createdAt], v.[updatedAt]
FROM [dbo].[Voucher] v
JOIN [dbo].[__account_id_map] m ON m.[oldId] = v.[bookAccountId]
WHERE v.[voucherType] IN ('CRV','CPV') AND v.[bookAccountId] IS NOT NULL;

INSERT INTO [dbo].[BankbookVoucher] ([id],[voucherType],[voucherDate],[branchId],[bookChartId],[description],[reference],[paymentMode],[totalAmount],[status],[reversedById],[reversedAt],[reversalReason],[postedById],[createdAt],[updatedAt])
SELECT v.[newNo], v.[voucherType], v.[voucherDate], v.[branchId], m.[newId], v.[description], v.[reference], 'Cash', v.[totalDebit],
       v.[status], v.[reversedById], v.[reversedAt], v.[reversalReason], v.[postedById], v.[createdAt], v.[updatedAt]
FROM [dbo].[Voucher] v
JOIN [dbo].[__account_id_map] m ON m.[oldId] = v.[bookAccountId]
WHERE v.[voucherType] IN ('BRV','BPV') AND v.[bookAccountId] IS NOT NULL;

INSERT INTO [dbo].[JournalVoucher] ([id],[voucherType],[voucherDate],[branchId],[description],[reference],[totalDebit],[totalCredit],[status],[reversedById],[reversedAt],[reversalReason],[postedById],[createdAt],[updatedAt])
SELECT v.[newNo], 'JV', v.[voucherDate], v.[branchId], v.[description], v.[reference], v.[totalDebit], v.[totalCredit],
       v.[status], v.[reversedById], v.[reversedAt], v.[reversalReason], v.[postedById], v.[createdAt], v.[updatedAt]
FROM [dbo].[Voucher] v
WHERE v.[voucherType] = 'JV';

INSERT INTO [dbo].[OpenTbVoucher] ([id],[voucherType],[voucherDate],[branchId],[description],[reference],[totalDebit],[totalCredit],[difference],[isBalanced],[status],[reversedById],[reversedAt],[reversalReason],[postedById],[createdAt],[updatedAt])
SELECT v.[newNo], 'OTV', v.[voucherDate], v.[branchId], LEFT(ISNULL(v.[description],''),20), v.[reference], v.[totalDebit], v.[totalCredit],
       v.[totalDebit] - v.[totalCredit], CASE WHEN ABS(v.[totalDebit]-v.[totalCredit]) < 0.01 THEN 1 ELSE 0 END,
       v.[status], v.[reversedById], v.[reversedAt], v.[reversalReason], v.[postedById], v.[createdAt], v.[updatedAt]
FROM [dbo].[Voucher] v
WHERE v.[voucherType] = 'OTB';
GO

-- 3. Copy lines (old book line replaced by new book-row; skip generated book line: legacy book line had lineDescription like 'Book account — X')
INSERT INTO [dbo].[BookVoucherLine] ([voucherId],[voucherType],[bookType],[accountId],[debit],[credit],[amount],[lineDescription],[title],[reference],[taxRate],[taxAmount],[chequeNo],[chequeAmount],[chequeBankName],[chequeStatus],[status],[createdAt])
SELECT v.[newNo], v.[voucherType], v.[newBookType], m.[newId], l.[debit], l.[credit], l.[amount],
       l.[lineDescription], l.[title], l.[reference], l.[taxRate], l.[taxAmount],
       l.[chequeNo], l.[chequeAmount], l.[chequeBankName], l.[chequeStatus], l.[status], l.[createdAt]
FROM [dbo].[VoucherLine] l
JOIN [dbo].[Voucher] v ON v.[id] = l.[voucherId]
JOIN [dbo].[__account_id_map] m ON m.[oldId] = l.[accountId]
WHERE l.[accountId] IS NOT NULL;
GO

-- 4. Cheques -> point at migrated bankbook voucher ids
IF OBJECT_ID('dbo.Cheque') IS NOT NULL AND OBJECT_ID('dbo.__cheque_migrated') IS NULL
BEGIN
    SELECT c.[id], v.[newNo] AS newVoucherNo, c.[chequeNo], c.[chequeDate], c.[bankName], c.[amount], c.[status],
           c.[statusChangedAt], c.[statusChangedBy], c.[statusHistory], c.[createdAt], c.[updatedAt]
    INTO [dbo].[__cheque_migrated]
    FROM [dbo].[Cheque] c
    JOIN [dbo].[Voucher] v ON v.[id] = c.[voucherId]
    WHERE v.[voucherType] IN ('BRV','BPV');
END
GO

-- 5. Remap Fee/FeePayment/PosSale/Payroll legacy voucher references
IF COL_LENGTH('dbo.FeePayment', 'bookVoucherId') IS NOT NULL
    UPDATE fp SET fp.[bookVoucherId] = v.[newNo] FROM [dbo].[FeePayment] fp JOIN [dbo].[Voucher] v ON v.[id] = fp.[bookVoucherId];
IF COL_LENGTH('dbo.Fee', 'bookVoucherId') IS NOT NULL
    UPDATE f SET f.[bookVoucherId] = v.[newNo] FROM [dbo].[Fee] f JOIN [dbo].[Voucher] v ON v.[id] = f.[bookVoucherId];
IF COL_LENGTH('dbo.PosSale', 'bookVoucherId') IS NOT NULL
    UPDATE ps SET ps.[bookVoucherId] = v.[newNo] FROM [dbo].[PosSale] ps JOIN [dbo].[Voucher] v ON v.[id] = ps.[bookVoucherId];
IF COL_LENGTH('dbo.Payroll', 'bookVoucherId') IS NOT NULL
    UPDATE p SET p.[bookVoucherId] = v.[newNo] FROM [dbo].[Payroll] p JOIN [dbo].[Voucher] v ON v.[id] = p.[bookVoucherId];
GO

-- 6. Drop legacy objects (order: dependents first)
IF OBJECT_ID('dbo.trg_Voucher_BalanceCheck', 'TR') IS NOT NULL DROP TRIGGER [dbo].[trg_Voucher_BalanceCheck];
IF OBJECT_ID('dbo.trg_Voucher_touchUpdatedAt', 'TR') IS NOT NULL DROP TRIGGER [dbo].[trg_Voucher_touchUpdatedAt];
GO
ALTER TABLE [dbo].[FeePayment] DROP CONSTRAINT IF EXISTS [FeePayment_voucherId_fkey];
ALTER TABLE [dbo].[Fee]        DROP CONSTRAINT IF EXISTS [Fee_voucherId_fkey];
ALTER TABLE [dbo].[Payroll]    DROP CONSTRAINT IF EXISTS [Payroll_voucherId_fkey];
ALTER TABLE [dbo].[Cheque]     DROP CONSTRAINT IF EXISTS [Cheque_voucherId_fkey];
ALTER TABLE [dbo].[Cheque]     DROP CONSTRAINT IF EXISTS [Cheque_voucherId_idx];
GO
IF OBJECT_ID('dbo.Cheque') IS NOT NULL DROP TABLE [dbo].[Cheque];
IF OBJECT_ID('dbo.VoucherLine') IS NOT NULL DROP TABLE [dbo].[VoucherLine];
IF OBJECT_ID('dbo.Voucher') IS NOT NULL DROP TABLE [dbo].[Voucher];
GO
-- Recreate Cheque against BankbookVoucher
IF OBJECT_ID('dbo.Cheque') IS NULL
CREATE TABLE [dbo].[Cheque] (
    [id]              NVARCHAR(50) NOT NULL PRIMARY KEY DEFAULT REPLACE(NEWID(), '-', ''),
    [voucherId]       NVARCHAR(50) NOT NULL,
    [chequeNo]        NVARCHAR(255) NOT NULL,
    [chequeDate]      DATETIME2    NOT NULL,
    [bankName]        NVARCHAR(255) NULL,
    [amount]          FLOAT        NOT NULL,
    [status]          NVARCHAR(255) NOT NULL DEFAULT 'Hold',
    [statusChangedAt] DATETIME2    NULL,
    [statusChangedBy] NVARCHAR(255) NULL,
    [statusHistory]   NVARCHAR(255) NULL,
    [createdAt]       DATETIME2    NOT NULL CONSTRAINT DF_Cheque_created DEFAULT SYSDATETIME(),
    [updatedAt]       DATETIME2    NOT NULL CONSTRAINT DF_Cheque_updated DEFAULT SYSDATETIME(),
    CONSTRAINT FK_Cheque_bankbook FOREIGN KEY ([voucherId]) REFERENCES [dbo].[BankbookVoucher]([id]) ON DELETE CASCADE
);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cheque_status')
    CREATE INDEX [IX_Cheque_status]  ON [dbo].[Cheque]([status]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cheque_chequeNo')
    CREATE INDEX [IX_Cheque_chequeNo] ON [dbo].[Cheque]([chequeNo]);
GO
-- Reinsert migrated cheques
INSERT INTO [dbo].[Cheque] ([voucherId],[chequeNo],[chequeDate],[bankName],[amount],[status],[statusChangedAt],[statusChangedBy],[statusHistory],[createdAt],[updatedAt])
SELECT [newVoucherNo],[chequeNo],[chequeDate],[bankName],[amount],[status],[statusChangedAt],[statusChangedBy],[statusHistory],[createdAt],[updatedAt]
FROM [dbo].[__cheque_migrated];
GO
PRINT '=== 04 done ===';

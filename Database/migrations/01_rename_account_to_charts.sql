-- =====================================================================
-- Contoura Gym ERP — Migration 01 of 10
-- Rename COA table [dbo].[Account] -> [dbo].[charts]; add STRN/NTN/FBR/
-- Payment Terms; remove Opening Balance fields; detach dependent FKs and
-- build an old-id -> new-code mapping for later scripts.
-- Run against GymDB AFTER a full backup, in order 01..10.
-- Idempotent: safe to re-run.
-- =====================================================================
SET NOCOUNT ON;
GO
PRINT '=== 01: Account -> charts ===';

-- 1. Drop dependent FKs (rebuilt in later scripts)
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'VoucherLine_accountId_fkey')
    ALTER TABLE [dbo].[VoucherLine] DROP CONSTRAINT [VoucherLine_accountId_fkey];
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'AccountMapping_accountId_fkey')
    ALTER TABLE [dbo].[AccountMapping] DROP CONSTRAINT [AccountMapping_accountId_fkey];
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'Voucher_bookAccountId_fkey')
    ALTER TABLE [dbo].[Voucher] DROP CONSTRAINT [Voucher_bookAccountId_fkey];
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'Account_parentId_fkey')
    ALTER TABLE [dbo].[Account] DROP CONSTRAINT [Account_parentId_fkey];
GO

-- 2. Rename the table
IF EXISTS (SELECT 1 FROM sys.tables WHERE name = 'Account' AND schema_id = SCHEMA_ID('dbo'))
   AND NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'charts' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
    EXEC sp_rename 'dbo.Account', 'charts';
    PRINT 'Table Account renamed to charts.';
END
GO

-- 3. Add new columns
IF COL_LENGTH('dbo.charts', 'STRN') IS NULL
    ALTER TABLE [dbo].[charts] ADD [STRN] NVARCHAR(255) NULL;
IF COL_LENGTH('dbo.charts', 'NTN') IS NULL
    ALTER TABLE [dbo].[charts] ADD [NTN] NVARCHAR(255) NULL;
IF COL_LENGTH('dbo.charts', 'FBR') IS NULL
    ALTER TABLE [dbo].[charts] ADD [FBR] NVARCHAR(255) NULL;
IF COL_LENGTH('dbo.charts', 'PaymentTerms') IS NULL
    ALTER TABLE [dbo].[charts] ADD [PaymentTerms] NVARCHAR(255) NULL;
GO

-- 4. Drop opening balance fields (opening balances now live in OTV vouchers)
IF COL_LENGTH('dbo.charts', 'openingBalance') IS NOT NULL
    ALTER TABLE [dbo].[charts] DROP CONSTRAINT IF EXISTS [charts_openingBalance_df];
IF COL_LENGTH('dbo.charts', 'openingBalance') IS NOT NULL
    ALTER TABLE [dbo].[charts] DROP COLUMN [openingBalance];
IF COL_LENGTH('dbo.charts', 'openingBalanceType') IS NOT NULL
    ALTER TABLE [dbo].[charts] DROP COLUMN [openingBalanceType];
GO

-- 5. Mapping table old account id -> account code (used by 04/05)
IF OBJECT_ID('dbo.__account_id_map') IS NOT NULL DROP TABLE [dbo].[__account_id_map];
CREATE TABLE [dbo].[__account_id_map] (
    [oldId]   NVARCHAR(50)  NOT NULL PRIMARY KEY,
    [newId]   NVARCHAR(50)  NOT NULL
);
INSERT INTO [dbo].[__account_id_map] ([oldId], [newId])
SELECT [id], [code] FROM [dbo].[charts];
PRINT 'Mapped ' + CAST(@@ROWCOUNT AS varchar(10)) + ' accounts old-id -> code.';
GO

-- 6. Touch-updated trigger recreated later (10) with new table name
IF OBJECT_ID('dbo.trg_Account_touchUpdatedAt', 'TR') IS NOT NULL
    DROP TRIGGER [dbo].[trg_Account_touchUpdatedAt];
GO
PRINT '=== 01 done ===';

-- =====================================================================
-- Contoura Gym ERP — Migration 05 of 10
-- Rebuild [charts] primary key so id IS the account code; remap
-- AccountMapping.accountId from legacy cuids; restore hierarchy.
-- Depends on: 01 (id map), 04 (Voucher/VoucherLine dropped).
-- Idempotent: re-run detects the rebuilt state and skips.
-- =====================================================================
SET NOCOUNT ON;
GO
PRINT '=== 05: charts PK rebuild ===';

-- 1. Remap AccountMapping to codes first (FK dropped in 01)
UPDATE am SET am.[accountId] = m.[newId]
FROM [dbo].[AccountMapping] am
JOIN [dbo].[__account_id_map] m ON m.[oldId] = am.[accountId];
GO

-- 2. Rebuild PK: current id is a cuid, code column holds the business code.
IF COL_LENGTH('dbo.charts', 'code') IS NOT NULL
BEGIN
    -- duplicate codes guard: suffix duplicates with '-2', '-3'...
    ;WITH Dup AS (
        SELECT [id], [code], ROW_NUMBER() OVER (PARTITION BY [code] ORDER BY [createdAt]) rn
        FROM [dbo].[charts]
    )
    UPDATE Dup SET [code] = [code] + '-' + CAST(rn AS varchar(5)) WHERE rn > 1;

    ALTER TABLE [dbo].[charts] DROP CONSTRAINT IF EXISTS [charts_parentId_fkey];
    ALTER TABLE [dbo].[charts] DROP CONSTRAINT IF EXISTS [Account_parentId_fkey];
    DECLARE @pk sysname = (SELECT name FROM sys.key_constraints WHERE type = 'PK' AND parent_object_id = OBJECT_ID('dbo.charts'));
    IF @pk IS NOT NULL EXEC ('ALTER TABLE [dbo].[charts] DROP CONSTRAINT [' + @pk + ']');

    -- id <- code, then drop the code column
    UPDATE [dbo].[charts] SET [id] = [code];
    ALTER TABLE [dbo].[charts] DROP COLUMN [code];
    ALTER TABLE [dbo].[charts] ALTER COLUMN [id] NVARCHAR(50) NOT NULL;
    ALTER TABLE [dbo].[charts] ADD CONSTRAINT PK_charts PRIMARY KEY ([id]);

    -- self hierarchy FK
    ALTER TABLE [dbo].[charts] ADD CONSTRAINT FK_charts_parent FOREIGN KEY ([parentId]) REFERENCES [dbo].[charts]([id]);
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_charts_parentId')
        CREATE INDEX [IX_charts_parentId] ON [dbo].[charts]([parentId]);
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_charts_branchId')
        CREATE INDEX [IX_charts_branchId] ON [dbo].[charts]([branchId]);
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_charts_accountType')
        CREATE INDEX [IX_charts_accountType] ON [dbo].[charts]([accountType]);
    PRINT 'charts PK rebuilt on account code.';
END
ELSE
    PRINT 'charts already rebuilt (no code column) — skipped.';
GO

-- 3. Restore AccountMapping FK to charts
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_AccountMapping_chart')
   AND OBJECT_ID('dbo.AccountMapping') IS NOT NULL
    ALTER TABLE [dbo].[AccountMapping] ADD CONSTRAINT FK_AccountMapping_chart
        FOREIGN KEY ([accountId]) REFERENCES [dbo].[charts]([id]);
GO

-- 4. Branch FK on charts (branchId column existed as branchId in legacy Account)
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_charts_branch')
   AND COL_LENGTH('dbo.charts', 'branchId') IS NOT NULL
    ALTER TABLE [dbo].[charts] ADD CONSTRAINT FK_charts_branch
        FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]);
GO

-- 5. Book voucher FKs to charts + branch
IF OBJECT_ID('dbo.BookVoucherLine') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_BKVL_chart')
    ALTER TABLE [dbo].[BookVoucherLine] ADD CONSTRAINT FK_BKVL_chart FOREIGN KEY ([accountId]) REFERENCES [dbo].[charts]([id]);
IF OBJECT_ID('dbo.KnockOff') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_KnockOff_chart')
    ALTER TABLE [dbo].[KnockOff] ADD CONSTRAINT FK_KnockOff_chart FOREIGN KEY ([accountId]) REFERENCES [dbo].[charts]([id]);
IF OBJECT_ID('dbo.CashbookVoucher') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_CashbookV_branch')
    ALTER TABLE [dbo].[CashbookVoucher] ADD CONSTRAINT FK_CashbookV_branch FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]);
IF OBJECT_ID('dbo.BankbookVoucher') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_BankbookV_branch')
    ALTER TABLE [dbo].[BankbookVoucher] ADD CONSTRAINT FK_BankbookV_branch FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]);
IF OBJECT_ID('dbo.JournalVoucher') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_JournalV_branch')
    ALTER TABLE [dbo].[JournalVoucher] ADD CONSTRAINT FK_JournalV_branch FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]);
IF OBJECT_ID('dbo.OpenTbVoucher') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_OpenTbV_branch')
    ALTER TABLE [dbo].[OpenTbVoucher] ADD CONSTRAINT FK_OpenTbV_branch FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]);
IF OBJECT_ID('dbo.CashbookVoucher') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_CashbookV_book')
    ALTER TABLE [dbo].[CashbookVoucher] ADD CONSTRAINT FK_CashbookV_book FOREIGN KEY ([bookChartId]) REFERENCES [dbo].[charts]([id]);
IF OBJECT_ID('dbo.BankbookVoucher') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_BankbookV_book')
    ALTER TABLE [dbo].[BankbookVoucher] ADD CONSTRAINT FK_BankbookV_book FOREIGN KEY ([bookChartId]) REFERENCES [dbo].[charts]([id]);
GO
PRINT '=== 05 done ===';

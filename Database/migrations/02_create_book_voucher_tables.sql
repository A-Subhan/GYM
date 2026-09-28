-- =====================================================================
-- Contoura Gym ERP — Migration 02 of 10
-- Create the four dedicated book voucher tables (cashbook / bankbook /
-- journal / opening TB), the shared BookVoucherLine table, KnockOff and
-- IdSequence. Old [Voucher]/[VoucherLine]/[Cheque] are kept for now and
-- migrated/dropped in 04.
-- Idempotent: safe to re-run.
-- =====================================================================
SET NOCOUNT ON;
GO
PRINT '=== 02: book voucher tables ===';

IF OBJECT_ID('dbo.CashbookVoucher') IS NULL
CREATE TABLE [dbo].[CashbookVoucher] (
    [id]             NVARCHAR(50)  NOT NULL PRIMARY KEY,  -- voucher number e.g. CRV/BR-001/Sep25/000001
    [voucherType]    NVARCHAR(255) NOT NULL,               -- CRV | CPV
    [voucherDate]    DATETIME2     NOT NULL,
    [branchId]       NVARCHAR(50)  NOT NULL,
    [bookChartId]    NVARCHAR(50)  NOT NULL,
    [description]    NVARCHAR(MAX) NULL,
    [reference]      NVARCHAR(255) NULL,
    [paymentMode]    NVARCHAR(255) NULL,                   -- Cash | Cheque
    [totalAmount]    FLOAT         NOT NULL DEFAULT 0,
    [status]         NVARCHAR(255) NOT NULL DEFAULT 'Posted',
    [reversedById]   NVARCHAR(50)  NULL,
    [reversedAt]     DATETIME2     NULL,
    [reversalReason] NVARCHAR(255) NULL,
    [postedById]     NVARCHAR(50)  NULL,
    [createdAt]      DATETIME2     NOT NULL CONSTRAINT DF_CashbookV_created DEFAULT SYSDATETIME(),
    [updatedAt]      DATETIME2     NOT NULL CONSTRAINT DF_CashbookV_updated DEFAULT SYSDATETIME()
);
GO
IF OBJECT_ID('dbo.BankbookVoucher') IS NULL
CREATE TABLE [dbo].[BankbookVoucher] (
    [id]             NVARCHAR(50)  NOT NULL PRIMARY KEY,
    [voucherType]    NVARCHAR(255) NOT NULL,               -- BRV | BPV
    [voucherDate]    DATETIME2     NOT NULL,
    [branchId]       NVARCHAR(50)  NOT NULL,
    [bookChartId]    NVARCHAR(50)  NOT NULL,
    [description]    NVARCHAR(MAX) NULL,
    [reference]      NVARCHAR(255) NULL,
    [paymentMode]    NVARCHAR(255) NULL,                   -- Cash | Cheque | Online Transfer
    [totalAmount]    FLOAT         NOT NULL DEFAULT 0,
    [status]         NVARCHAR(255) NOT NULL DEFAULT 'Posted',
    [reversedById]   NVARCHAR(50)  NULL,
    [reversedAt]     DATETIME2     NULL,
    [reversalReason] NVARCHAR(255) NULL,
    [postedById]     NVARCHAR(50)  NULL,
    [createdAt]      DATETIME2     NOT NULL CONSTRAINT DF_BankbookV_created DEFAULT SYSDATETIME(),
    [updatedAt]      DATETIME2     NOT NULL CONSTRAINT DF_BankbookV_updated DEFAULT SYSDATETIME()
);
GO
IF OBJECT_ID('dbo.JournalVoucher') IS NULL
CREATE TABLE [dbo].[JournalVoucher] (
    [id]             NVARCHAR(50)  NOT NULL PRIMARY KEY,
    [voucherType]    NVARCHAR(255) NOT NULL DEFAULT 'JV',
    [voucherDate]    DATETIME2     NOT NULL,
    [branchId]       NVARCHAR(50)  NOT NULL,
    [description]    NVARCHAR(MAX) NULL,
    [reference]      NVARCHAR(255) NULL,
    [totalDebit]     FLOAT         NOT NULL DEFAULT 0,
    [totalCredit]    FLOAT         NOT NULL DEFAULT 0,
    [status]         NVARCHAR(255) NOT NULL DEFAULT 'Posted',
    [reversedById]   NVARCHAR(50)  NULL,
    [reversedAt]     DATETIME2     NULL,
    [reversalReason] NVARCHAR(255) NULL,
    [postedById]     NVARCHAR(50)  NULL,
    [createdAt]      DATETIME2     NOT NULL CONSTRAINT DF_JournalV_created DEFAULT SYSDATETIME(),
    [updatedAt]      DATETIME2     NOT NULL CONSTRAINT DF_JournalV_updated DEFAULT SYSDATETIME()
);
GO
IF OBJECT_ID('dbo.OpenTbVoucher') IS NULL
CREATE TABLE [dbo].[OpenTbVoucher] (
    [id]             NVARCHAR(50)  NOT NULL PRIMARY KEY,
    [voucherType]    NVARCHAR(255) NOT NULL DEFAULT 'OTV',
    [voucherDate]    DATETIME2     NOT NULL,
    [branchId]       NVARCHAR(50)  NOT NULL,
    [description]    NVARCHAR(255) NULL,                   -- max 20 chars (app enforced)
    [reference]      NVARCHAR(255) NULL,
    [totalDebit]     FLOAT         NOT NULL DEFAULT 0,
    [totalCredit]    FLOAT         NOT NULL DEFAULT 0,
    [difference]     FLOAT         NOT NULL DEFAULT 0,
    [isBalanced]     BIT           NOT NULL DEFAULT 0,
    [status]         NVARCHAR(255) NOT NULL DEFAULT 'Posted',
    [reversedById]   NVARCHAR(50)  NULL,
    [reversedAt]     DATETIME2     NULL,
    [reversalReason] NVARCHAR(255) NULL,
    [postedById]     NVARCHAR(50)  NULL,
    [createdAt]      DATETIME2     NOT NULL CONSTRAINT DF_OpenTbV_created DEFAULT SYSDATETIME(),
    [updatedAt]      DATETIME2     NOT NULL CONSTRAINT DF_OpenTbV_updated DEFAULT SYSDATETIME()
);
GO
IF OBJECT_ID('dbo.BookVoucherLine') IS NULL
CREATE TABLE [dbo].[BookVoucherLine] (
    [id]              NVARCHAR(50)  NOT NULL PRIMARY KEY DEFAULT REPLACE(NEWID(), '-', ''),
    [voucherId]       NVARCHAR(50)  NOT NULL,
    [voucherType]     NVARCHAR(255) NOT NULL,
    [bookType]        NVARCHAR(255) NOT NULL,              -- CASHBOOK | BANKBOOK | JV | OTB
    [accountId]       NVARCHAR(50)  NOT NULL,
    [debit]           FLOAT         NOT NULL DEFAULT 0,
    [credit]          FLOAT         NOT NULL DEFAULT 0,
    [amount]          FLOAT         NOT NULL DEFAULT 0,
    [lineDescription] NVARCHAR(255) NULL,
    [title]           NVARCHAR(255) NULL,
    [reference]       NVARCHAR(255) NULL,
    [billType]        NVARCHAR(255) NULL,
    [taxAccountId]    NVARCHAR(50)  NULL,
    [taxRate]         FLOAT         NOT NULL DEFAULT 0,
    [taxAmount]       FLOAT         NOT NULL DEFAULT 0,
    [chequeNo]        NVARCHAR(255) NULL,
    [chequeAmount]    FLOAT         NULL,
    [chequeBankName]  NVARCHAR(255) NULL,
    [chequeStatus]    NVARCHAR(255) NULL,
    [status]          NVARCHAR(255) NOT NULL DEFAULT 'Active',
    [createdAt]       DATETIME2     NOT NULL CONSTRAINT DF_BKVL_created DEFAULT SYSDATETIME(),
    CONSTRAINT FK_BKVL_cashbook FOREIGN KEY ([voucherId]) REFERENCES [dbo].[CashbookVoucher]([id]) ON DELETE CASCADE,
    CONSTRAINT FK_BKVL_bankbook FOREIGN KEY ([voucherId]) REFERENCES [dbo].[BankbookVoucher]([id]) ON DELETE CASCADE,
    CONSTRAINT FK_BKVL_journal  FOREIGN KEY ([voucherId]) REFERENCES [dbo].[JournalVoucher]([id])  ON DELETE CASCADE,
    CONSTRAINT FK_BKVL_opentb   FOREIGN KEY ([voucherId]) REFERENCES [dbo].[OpenTbVoucher]([id])   ON DELETE CASCADE
);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_BKVL_voucherId')
    CREATE INDEX [IX_BKVL_voucherId] ON [dbo].[BookVoucherLine]([voucherId]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_BKVL_accountId')
    CREATE INDEX [IX_BKVL_accountId] ON [dbo].[BookVoucherLine]([accountId]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_BKVL_bookType')
    CREATE INDEX [IX_BKVL_bookType]  ON [dbo].[BookVoucherLine]([bookType]);
GO
IF OBJECT_ID('dbo.KnockOff') IS NULL
CREATE TABLE [dbo].[KnockOff] (
    [id]              NVARCHAR(50)  NOT NULL PRIMARY KEY DEFAULT REPLACE(NEWID(), '-', ''),
    [billId]          NVARCHAR(50)  NOT NULL,              -- OTB-{branch}/{0000001}
    [openTbVoucherId] NVARCHAR(50)  NOT NULL,
    [accountId]       NVARCHAR(50)  NOT NULL,
    [description]     NVARCHAR(255) NOT NULL,              -- max 20 chars (app enforced)
    [amount]          FLOAT         NOT NULL,
    [side]            NVARCHAR(10)  NOT NULL,              -- Debit | Credit
    [knockedOffAt]    DATETIME2     NOT NULL CONSTRAINT DF_KnockOff_at DEFAULT SYSDATETIME(),
    [createdById]     NVARCHAR(50)  NULL,
    [createdAt]       DATETIME2     NOT NULL CONSTRAINT DF_KnockOff_created DEFAULT SYSDATETIME(),
    CONSTRAINT FK_KnockOff_opentb FOREIGN KEY ([openTbVoucherId]) REFERENCES [dbo].[OpenTbVoucher]([id]) ON DELETE CASCADE
);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_KnockOff_opentb')
    CREATE INDEX [IX_KnockOff_opentb] ON [dbo].[KnockOff]([openTbVoucherId]);
GO
IF OBJECT_ID('dbo.IdSequence') IS NULL
CREATE TABLE [dbo].[IdSequence] (
    [key]      NVARCHAR(191) NOT NULL PRIMARY KEY,
    [next]     INT           NOT NULL DEFAULT 1,
    [updatedAt] DATETIME2    NOT NULL CONSTRAINT DF_IdSequence_updated DEFAULT SYSDATETIME()
);
GO
PRINT '=== 02 done ===';

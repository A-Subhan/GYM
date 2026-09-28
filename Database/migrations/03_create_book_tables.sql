-- ============================================================================
-- Contoura Gym ERP — Migration 03: CREATE BOOK TABLES (+ fold opening balances)
-- ============================================================================
-- Creates the finance book structure:
--   dbo.CashBook  (CRV + CPV)  + dbo.CashBookLine
--   dbo.BankBook  (BRV + BPV)  + dbo.BankBookLine
--   dbo.JV        (journal)    + dbo.JVLine
--   dbo.OpenTB    (opening TB) + dbo.OpenTBLine   -- UNBALANCED save allowed:
--                                                 -- no constraint and no
--                                                 -- trigger enforces Dr = Cr
--   dbo.KnockOff  (bill-wise knock-offs, Bill ID OTB-{branch}/{0000001})
--   dbo.IdSequence (per book type / branch / month counters)
--
-- Voucher ID = voucher number, one column:
--   {CRV|CPV|BRV|BPV|JV|OTV}/{branchCode}/{MMMyy UPPER}/{000001}
--   reversal appends -R   (e.g. CRV/BR-001/SEP26/000001-R)
--
-- Account FKs on the line tables are intentionally created in migration 05
-- (after charts.id becomes the account code and children are remapped).
--
-- If zz_backup_charts_opening_<date> exists (created by 02) and OpenTB is
-- empty, one OTV voucher per branch is generated from it — opening balances
-- are preserved as real book data.
-- ============================================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET LANGUAGE us_english;
GO

DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'02_rename_account_to_charts', @self = N'03_create_book_tables', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    03 already applied, skipping.'; RETURN; END
BEGIN TRY
    BEGIN TRAN;

    IF OBJECT_ID('dbo.CashBook') IS NULL
    CREATE TABLE dbo.CashBook (
        id             NVARCHAR(50)  NOT NULL CONSTRAINT PK_CashBook PRIMARY KEY, -- voucher number
        voucherType    NVARCHAR(10)  NOT NULL,           -- CRV | CPV
        voucherDate    DATETIME2     NOT NULL,
        branchId       NVARCHAR(50)  NOT NULL,
        bookChartId    NVARCHAR(50)  NOT NULL,           -- cash book account (charts.id)
        description    NVARCHAR(MAX) NULL,
        reference      NVARCHAR(255) NULL,
        paymentMode    NVARCHAR(255) NULL,               -- Cash | Cheque
        totalAmount    FLOAT         NOT NULL CONSTRAINT DF_CashBook_total DEFAULT 0,
        status         NVARCHAR(255) NOT NULL CONSTRAINT DF_CashBook_status DEFAULT 'Posted',
        reversedById   NVARCHAR(50)  NULL,
        reversedAt     DATETIME2     NULL,
        reversalReason NVARCHAR(255) NULL,
        postedById     NVARCHAR(50)  NULL,
        createdAt      DATETIME2     NOT NULL CONSTRAINT DF_CashBook_created DEFAULT SYSDATETIME(),
        updatedAt      DATETIME2     NOT NULL CONSTRAINT DF_CashBook_updated DEFAULT SYSDATETIME(),
        CONSTRAINT FK_CashBook_branch FOREIGN KEY (branchId) REFERENCES dbo.Branch (id)
    );
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_CashBook_branch')  CREATE INDEX IX_CashBook_branch  ON dbo.CashBook (branchId);
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_CashBook_date')    CREATE INDEX IX_CashBook_date    ON dbo.CashBook (voucherDate);
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_CashBook_type')    CREATE INDEX IX_CashBook_type    ON dbo.CashBook (voucherType);

    IF OBJECT_ID('dbo.CashBookLine') IS NULL
    CREATE TABLE dbo.CashBookLine (
        id              NVARCHAR(50) NOT NULL CONSTRAINT PK_CashBookLine PRIMARY KEY CONSTRAINT DF_CBL_id DEFAULT REPLACE(NEWID(), '-', ''),
        voucherId       NVARCHAR(50) NOT NULL,
        accountId       NVARCHAR(50) NOT NULL,            -- charts.id (FK added in 05)
        debit           FLOAT        NOT NULL CONSTRAINT DF_CBL_debit  DEFAULT 0,
        credit          FLOAT        NOT NULL CONSTRAINT DF_CBL_credit DEFAULT 0,
        amount          FLOAT        NOT NULL CONSTRAINT DF_CBL_amount DEFAULT 0,
        taxPercent      FLOAT        NOT NULL CONSTRAINT DF_CBL_taxPct   DEFAULT 0,
        taxAmount       FLOAT        NOT NULL CONSTRAINT DF_CBL_taxAmt   DEFAULT 0,
        total           FLOAT        NOT NULL CONSTRAINT DF_CBL_total    DEFAULT 0,  -- amount + taxAmount
        lineDescription NVARCHAR(255) NULL,
        title           NVARCHAR(255) NULL,
        reference       NVARCHAR(255) NULL,
        billType        NVARCHAR(255) NULL,
        chequeNo        NVARCHAR(255) NULL,
        chequeAmount    FLOAT         NULL,
        chequeBankName  NVARCHAR(255) NULL,
        chequeStatus    NVARCHAR(255) NULL,
        status          NVARCHAR(255) NOT NULL CONSTRAINT DF_CBL_status DEFAULT 'Active',
        createdAt       DATETIME2     NOT NULL CONSTRAINT DF_CBL_created DEFAULT SYSDATETIME(),
        CONSTRAINT FK_CashBookLine_voucher FOREIGN KEY (voucherId) REFERENCES dbo.CashBook (id) ON DELETE CASCADE
    );
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_CBL_voucher')  CREATE INDEX IX_CBL_voucher  ON dbo.CashBookLine (voucherId);
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_CBL_account')  CREATE INDEX IX_CBL_account  ON dbo.CashBookLine (accountId);

    IF OBJECT_ID('dbo.BankBook') IS NULL
    CREATE TABLE dbo.BankBook (
        id             NVARCHAR(50)  NOT NULL CONSTRAINT PK_BankBook PRIMARY KEY, -- voucher number
        voucherType    NVARCHAR(10)  NOT NULL,           -- BRV | BPV
        voucherDate    DATETIME2     NOT NULL,
        branchId       NVARCHAR(50)  NOT NULL,
        bookChartId    NVARCHAR(50)  NOT NULL,           -- bank book account (charts.id)
        description    NVARCHAR(MAX) NULL,
        reference      NVARCHAR(255) NULL,
        paymentMode    NVARCHAR(255) NULL,               -- Cash | Cheque | Online Transfer
        totalAmount    FLOAT         NOT NULL CONSTRAINT DF_BankBook_total DEFAULT 0,
        status         NVARCHAR(255) NOT NULL CONSTRAINT DF_BankBook_status DEFAULT 'Posted',
        reversedById   NVARCHAR(50)  NULL,
        reversedAt     DATETIME2     NULL,
        reversalReason NVARCHAR(255) NULL,
        postedById     NVARCHAR(50)  NULL,
        createdAt      DATETIME2     NOT NULL CONSTRAINT DF_BankBook_created DEFAULT SYSDATETIME(),
        updatedAt      DATETIME2     NOT NULL CONSTRAINT DF_BankBook_updated DEFAULT SYSDATETIME(),
        CONSTRAINT FK_BankBook_branch FOREIGN KEY (branchId) REFERENCES dbo.Branch (id)
    );
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_BankBook_branch') CREATE INDEX IX_BankBook_branch ON dbo.BankBook (branchId);
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_BankBook_date')   CREATE INDEX IX_BankBook_date   ON dbo.BankBook (voucherDate);
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_BankBook_type')   CREATE INDEX IX_BankBook_type   ON dbo.BankBook (voucherType);

    IF OBJECT_ID('dbo.BankBookLine') IS NULL
    CREATE TABLE dbo.BankBookLine (
        id              NVARCHAR(50) NOT NULL CONSTRAINT PK_BankBookLine PRIMARY KEY CONSTRAINT DF_BBL_id DEFAULT REPLACE(NEWID(), '-', ''),
        voucherId       NVARCHAR(50) NOT NULL,
        accountId       NVARCHAR(50) NOT NULL,            -- charts.id (FK added in 05)
        debit           FLOAT        NOT NULL CONSTRAINT DF_BBL_debit  DEFAULT 0,
        credit          FLOAT        NOT NULL CONSTRAINT DF_BBL_credit DEFAULT 0,
        amount          FLOAT        NOT NULL CONSTRAINT DF_BBL_amount DEFAULT 0,
        taxPercent      FLOAT        NOT NULL CONSTRAINT DF_BBL_taxPct   DEFAULT 0,
        taxAmount       FLOAT        NOT NULL CONSTRAINT DF_BBL_taxAmt   DEFAULT 0,
        total           FLOAT        NOT NULL CONSTRAINT DF_BBL_total    DEFAULT 0,  -- amount + taxAmount
        lineDescription NVARCHAR(255) NULL,
        title           NVARCHAR(255) NULL,
        reference       NVARCHAR(255) NULL,
        billType        NVARCHAR(255) NULL,
        -- Bank voucher line: chequeAmount is derived from amount. The column is
        -- kept and populated; the APPLICATION keeps it synced to amount.
        chequeNo        NVARCHAR(255) NULL,
        chequeAmount    FLOAT         NULL,
        chequeBankName  NVARCHAR(255) NULL,
        chequeStatus    NVARCHAR(255) NULL,
        status          NVARCHAR(255) NOT NULL CONSTRAINT DF_BBL_status DEFAULT 'Active',
        createdAt       DATETIME2     NOT NULL CONSTRAINT DF_BBL_created DEFAULT SYSDATETIME(),
        CONSTRAINT FK_BankBookLine_voucher FOREIGN KEY (voucherId) REFERENCES dbo.BankBook (id) ON DELETE CASCADE
    );
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_BBL_voucher') CREATE INDEX IX_BBL_voucher ON dbo.BankBookLine (voucherId);
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_BBL_account') CREATE INDEX IX_BBL_account ON dbo.BankBookLine (accountId);

    IF OBJECT_ID('dbo.JV') IS NULL
    CREATE TABLE dbo.JV (
        id             NVARCHAR(50)  NOT NULL CONSTRAINT PK_JV PRIMARY KEY, -- voucher number
        voucherType    NVARCHAR(10)  NOT NULL CONSTRAINT DF_JV_type DEFAULT 'JV',
        voucherDate    DATETIME2     NOT NULL,
        branchId       NVARCHAR(50)  NOT NULL,
        description    NVARCHAR(MAX) NULL,
        reference      NVARCHAR(255) NULL,
        totalDebit     FLOAT         NOT NULL CONSTRAINT DF_JV_td DEFAULT 0,
        totalCredit    FLOAT         NOT NULL CONSTRAINT DF_JV_tc DEFAULT 0,
        status         NVARCHAR(255) NOT NULL CONSTRAINT DF_JV_status DEFAULT 'Posted',
        reversedById   NVARCHAR(50)  NULL,
        reversedAt     DATETIME2     NULL,
        reversalReason NVARCHAR(255) NULL,
        postedById     NVARCHAR(50)  NULL,
        createdAt      DATETIME2     NOT NULL CONSTRAINT DF_JV_created DEFAULT SYSDATETIME(),
        updatedAt      DATETIME2     NOT NULL CONSTRAINT DF_JV_updated DEFAULT SYSDATETIME(),
        CONSTRAINT FK_JV_branch FOREIGN KEY (branchId) REFERENCES dbo.Branch (id)
    );
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_JV_branch') CREATE INDEX IX_JV_branch ON dbo.JV (branchId);
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_JV_date')   CREATE INDEX IX_JV_date   ON dbo.JV (voucherDate);

    IF OBJECT_ID('dbo.JVLine') IS NULL
    CREATE TABLE dbo.JVLine (
        id              NVARCHAR(50) NOT NULL CONSTRAINT PK_JVLine PRIMARY KEY CONSTRAINT DF_JVL_id DEFAULT REPLACE(NEWID(), '-', ''),
        voucherId       NVARCHAR(50) NOT NULL,
        accountId       NVARCHAR(50) NOT NULL,            -- charts.id (FK added in 05)
        debit           FLOAT        NOT NULL CONSTRAINT DF_JVL_debit  DEFAULT 0,
        credit          FLOAT        NOT NULL CONSTRAINT DF_JVL_credit DEFAULT 0,
        amount          FLOAT        NOT NULL CONSTRAINT DF_JVL_amount DEFAULT 0,
        taxPercent      FLOAT        NOT NULL CONSTRAINT DF_JVL_taxPct DEFAULT 0,
        taxAmount       FLOAT        NOT NULL CONSTRAINT DF_JVL_taxAmt DEFAULT 0,
        total           FLOAT        NOT NULL CONSTRAINT DF_JVL_total  DEFAULT 0,  -- amount + taxAmount
        lineDescription NVARCHAR(255) NULL,
        reference       NVARCHAR(255) NULL,
        status          NVARCHAR(255) NOT NULL CONSTRAINT DF_JVL_status DEFAULT 'Active',
        createdAt       DATETIME2     NOT NULL CONSTRAINT DF_JVL_created DEFAULT SYSDATETIME(),
        CONSTRAINT FK_JVLine_voucher FOREIGN KEY (voucherId) REFERENCES dbo.JV (id) ON DELETE CASCADE
    );
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_JVL_voucher') CREATE INDEX IX_JVL_voucher ON dbo.JVLine (voucherId);
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_JVL_account') CREATE INDEX IX_JVL_account ON dbo.JVLine (accountId);

    IF OBJECT_ID('dbo.OpenTB') IS NULL
    CREATE TABLE dbo.OpenTB (
        id             NVARCHAR(50)  NOT NULL CONSTRAINT PK_OpenTB PRIMARY KEY, -- voucher number
        voucherType    NVARCHAR(10)  NOT NULL CONSTRAINT DF_OTB_type DEFAULT 'OTV',
        voucherDate    DATETIME2     NOT NULL,
        branchId       NVARCHAR(50)  NOT NULL,
        description    NVARCHAR(255) NULL,
        reference      NVARCHAR(255) NULL,
        totalDebit     FLOAT         NOT NULL CONSTRAINT DF_OTB_td DEFAULT 0,
        totalCredit    FLOAT         NOT NULL CONSTRAINT DF_OTB_tc DEFAULT 0,
        difference     FLOAT         NOT NULL CONSTRAINT DF_OTB_diff DEFAULT 0,
        isBalanced     BIT           NOT NULL CONSTRAINT DF_OTB_bal  DEFAULT 0,
        status         NVARCHAR(255) NOT NULL CONSTRAINT DF_OTB_status DEFAULT 'Posted',
        reversedById   NVARCHAR(50)  NULL,
        reversedAt     DATETIME2     NULL,
        reversalReason NVARCHAR(255) NULL,
        postedById     NVARCHAR(50)  NULL,
        createdAt      DATETIME2     NOT NULL CONSTRAINT DF_OTB_created DEFAULT SYSDATETIME(),
        updatedAt      DATETIME2     NOT NULL CONSTRAINT DF_OTB_updated DEFAULT SYSDATETIME(),
        CONSTRAINT FK_OpenTB_branch FOREIGN KEY (branchId) REFERENCES dbo.Branch (id)
        -- NOTE: intentionally NO check constraint and NO trigger enforcing
        -- totalDebit = totalCredit. An unbalanced opening TB may be saved.
    );
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_OpenTB_branch') CREATE INDEX IX_OpenTB_branch ON dbo.OpenTB (branchId);

    IF OBJECT_ID('dbo.OpenTBLine') IS NULL
    CREATE TABLE dbo.OpenTBLine (
        id              NVARCHAR(50) NOT NULL CONSTRAINT PK_OpenTBLine PRIMARY KEY CONSTRAINT DF_OTL_id DEFAULT REPLACE(NEWID(), '-', ''),
        voucherId       NVARCHAR(50) NOT NULL,
        accountId       NVARCHAR(50) NOT NULL,            -- charts.id (FK added in 05)
        debit           FLOAT        NOT NULL CONSTRAINT DF_OTL_debit  DEFAULT 0,
        credit          FLOAT        NOT NULL CONSTRAINT DF_OTL_credit DEFAULT 0,
        amount          FLOAT        NOT NULL CONSTRAINT DF_OTL_amount DEFAULT 0,
        lineDescription NVARCHAR(255) NULL,
        reference       NVARCHAR(255) NULL,
        status          NVARCHAR(255) NOT NULL CONSTRAINT DF_OTL_status DEFAULT 'Active',
        createdAt       DATETIME2     NOT NULL CONSTRAINT DF_OTL_created DEFAULT SYSDATETIME(),
        CONSTRAINT FK_OpenTBLine_voucher FOREIGN KEY (voucherId) REFERENCES dbo.OpenTB (id) ON DELETE CASCADE
    );
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_OTL_voucher') CREATE INDEX IX_OTL_voucher ON dbo.OpenTBLine (voucherId);
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_OTL_account') CREATE INDEX IX_OTL_account ON dbo.OpenTBLine (accountId);

    IF OBJECT_ID('dbo.KnockOff') IS NULL
    CREATE TABLE dbo.KnockOff (
        id               NVARCHAR(50)  NOT NULL CONSTRAINT PK_KnockOff PRIMARY KEY CONSTRAINT DF_KO_id DEFAULT REPLACE(NEWID(), '-', ''),
        billId           NVARCHAR(50)  NOT NULL,        -- OTB-{branchCode}/{0000001} (unique)
        billNumber       NVARCHAR(255) NULL,
        referenceNumber  NVARCHAR(255) NULL,
        billType         NVARCHAR(255) NULL,
        amount           FLOAT         NOT NULL,
        dcFlag           NVARCHAR(10)  NOT NULL CONSTRAINT DF_KO_dc DEFAULT 'Debit', -- Debit | Credit
        referenceDate    DATETIME2     NULL,
        dueDate          DATETIME2     NULL,
        description      NVARCHAR(20)  NULL,            -- max 20 chars (app enforced)
        accountId        NVARCHAR(50)  NOT NULL,        -- charts.id (FK added in 05)
        branchId         NVARCHAR(50)  NOT NULL,
        createdById      NVARCHAR(50)  NULL,
        createdAt        DATETIME2     NOT NULL CONSTRAINT DF_KO_created DEFAULT SYSDATETIME(),
        updatedAt        DATETIME2     NOT NULL CONSTRAINT DF_KO_updated DEFAULT SYSDATETIME(),
        CONSTRAINT FK_KnockOff_branch FOREIGN KEY (branchId) REFERENCES dbo.Branch (id)
        -- Account Tag rule (Customer / Supplier) is enforced by the
        -- APPLICATION: only charts rows with accountTag of Customer or
        -- Supplier may be selected for bill-wise knock-offs.
    );
    IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'UQ_KnockOff_billId')
        ALTER TABLE dbo.KnockOff ADD CONSTRAINT UQ_KnockOff_billId UNIQUE (billId);
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_KnockOff_account') CREATE INDEX IX_KnockOff_account ON dbo.KnockOff (accountId);
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_KnockOff_branch')  CREATE INDEX IX_KnockOff_branch  ON dbo.KnockOff (branchId);

    IF OBJECT_ID('dbo.IdSequence') IS NULL
    CREATE TABLE dbo.IdSequence (
        [key]     NVARCHAR(191) NOT NULL CONSTRAINT PK_IdSequence PRIMARY KEY,
        [next]    INT           NOT NULL CONSTRAINT DF_IdSeq_next DEFAULT 1,
        updatedAt DATETIME2     NOT NULL CONSTRAINT DF_IdSeq_updated DEFAULT SYSDATETIME()
    );

    PRINT '  book tables created (CashBook/BankBook/JV/OpenTB + lines, KnockOff, IdSequence)';
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'03_create_book_tables';
    THROW;
END CATCH
GO

-- Fold archived opening balances into OpenTB (one OTV voucher per branch).
-- Reads from zz_backup_charts_opening_<date> created by migration 02 (the
-- charts table no longer carries opening columns at this point).
DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'02_rename_account_to_charts', @self = N'03_create_book_tables', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    03 already applied, skipping.'; RETURN; END
BEGIN TRY
    DECLARE @bak sysname = NULL;
    SELECT @bak = name FROM sys.tables
    WHERE name LIKE 'zz_backup_charts_opening%' AND schema_id = SCHEMA_ID('dbo')
    ORDER BY create_date DESC;

    IF @bak IS NOT NULL AND (SELECT COUNT(*) FROM dbo.OpenTB) = 0
    BEGIN
        DECLARE @defBranch NVARCHAR(50) = (SELECT TOP 1 id FROM dbo.Branch ORDER BY createdAt);
        DECLARE @mon NVARCHAR(5) = UPPER(FORMAT(SYSDATETIME(), 'MMMyy'));
        DECLARE @rowc int;

        -- copy the (dynamically named) archive into a real scratch table
        IF OBJECT_ID('dbo.__mig_tmp_openrows') IS NOT NULL DROP TABLE dbo.__mig_tmp_openrows;
        EXEC (N'SELECT id AS accountOldId, branchId, openingBalance, openingBalanceType
                 INTO dbo.__mig_tmp_openrows
                 FROM dbo.' + QUOTENAME(@bak) + N'
                 WHERE openingBalance IS NOT NULL AND openingBalance <> 0;');
        UPDATE dbo.__mig_tmp_openrows SET branchId = @defBranch WHERE branchId IS NULL;
        SET @rowc = (SELECT COUNT(*) FROM dbo.__mig_tmp_openrows);
        PRINT '  folding ' + CAST(@rowc AS varchar(10)) + ' archived opening balances into OpenTB';

        -- voucher number per branch, materialized once (deterministic)
        IF OBJECT_ID('dbo.__mig_tmp_vouchers') IS NOT NULL DROP TABLE dbo.__mig_tmp_vouchers;
        SELECT  b.code AS branchCode, o.branchId,
                CONCAT('OTV/', b.code, '/', @mon, '/',
                       FORMAT(ROW_NUMBER() OVER (ORDER BY b.code), '000000')) AS voucherId
        INTO dbo.__mig_tmp_vouchers
        FROM (SELECT DISTINCT branchId FROM dbo.__mig_tmp_openrows) o
        JOIN dbo.Branch b ON b.id = o.branchId;

        INSERT INTO dbo.OpenTB (id, voucherType, voucherDate, branchId, description, reference,
                                totalDebit, totalCredit, difference, isBalanced, status, createdAt, updatedAt)
        SELECT v.voucherId, 'OTV', SYSDATETIME(), v.branchId, 'Opening balances (migrated)', 'MIGRATION',
               ISNULL(SUM(CASE WHEN UPPER(o.openingBalanceType) LIKE 'C%' THEN 0 ELSE o.openingBalance END), 0),
               ISNULL(SUM(CASE WHEN UPPER(o.openingBalanceType) LIKE 'C%' THEN o.openingBalance ELSE 0 END), 0),
               0, 0, 'Posted', SYSDATETIME(), SYSDATETIME()
        FROM dbo.__mig_tmp_vouchers v
        JOIN dbo.__mig_tmp_openrows o ON o.branchId = v.branchId
        GROUP BY v.voucherId, v.branchId;

        INSERT INTO dbo.OpenTBLine (voucherId, accountId, debit, credit, amount, lineDescription, reference, status, createdAt)
        SELECT v.voucherId, o.accountOldId,
               CASE WHEN UPPER(o.openingBalanceType) LIKE 'C%' THEN 0 ELSE o.openingBalance END,
               CASE WHEN UPPER(o.openingBalanceType) LIKE 'C%' THEN o.openingBalance ELSE 0 END,
               o.openingBalance, 'Opening balance', 'MIGRATION', 'Active', SYSDATETIME()
        FROM dbo.__mig_tmp_openrows o
        JOIN dbo.__mig_tmp_vouchers v ON v.branchId = o.branchId;

        PRINT '  created ' + CAST((SELECT COUNT(*) FROM dbo.__mig_tmp_vouchers) AS varchar(10)) + ' OpenTB voucher(s)';
        DROP TABLE dbo.__mig_tmp_openrows;
        DROP TABLE dbo.__mig_tmp_vouchers;
    END
    ELSE
        PRINT '  opening archive absent or OpenTB already populated - fold skipped';
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'03_create_book_tables';
    THROW;
END CATCH
GO

-- Final verification + Success marker
DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'02_rename_account_to_charts', @self = N'03_create_book_tables', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    03 already applied, skipping.'; RETURN; END
BEGIN TRY
    IF OBJECT_ID('dbo.CashBook')  IS NULL THROW 51020, 'verification failed: CashBook missing', 1;
    IF OBJECT_ID('dbo.BankBook')  IS NULL THROW 51020, 'verification failed: BankBook missing', 1;
    IF OBJECT_ID('dbo.JV')        IS NULL THROW 51020, 'verification failed: JV missing', 1;
    IF OBJECT_ID('dbo.OpenTB')    IS NULL THROW 51020, 'verification failed: OpenTB missing', 1;
    IF OBJECT_ID('dbo.KnockOff')  IS NULL THROW 51020, 'verification failed: KnockOff missing', 1;
    IF OBJECT_ID('dbo.IdSequence') IS NULL THROW 51020, 'verification failed: IdSequence missing', 1;

    EXEC dbo.__mig_Done @self = N'03_create_book_tables';
    IF @@TRANCOUNT > 0 COMMIT TRAN;
    PRINT '=== 03 done ===';
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'03_create_book_tables';
    THROW;
END CATCH
GO

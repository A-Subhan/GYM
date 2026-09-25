/* ============================================================================
   CONTOURA LABS — GYM MANAGEMENT SYSTEM
   FINANCE & ACCOUNTING MODULE — SCHEMA (11_finance_schema.sql)
   ----------------------------------------------------------------------------
   Idempotent + non-destructive. Safe to run more than once.
   Target: any database created from the GymDB schema (GymDB / GymDB_Test).
   Run BEFORE 12_finance_procedures.sql and 13_finance_permissions_defaults.sql.

   Creates (only when missing):
     FinanceCoaLevels          — configurable COA level/digit structure (max 7 levels / 12 digits)
     FinancialYears            — fiscal years (Open / Locked / Closed)
     AccountingPeriods         — monthly periods per fiscal year (Open / Locked / Closed)
     Accounts                  — chart of accounts (hierarchical, Control vs Detail)
     AccountTags               — account tags (Customer / Vendor / Bank / Cash / Employee / Tax / ...)
     VoucherTypes              — CRV/CPV/BRV/BPV/JPV/OPB + configurable prefix (lockable)
     Vouchers                  — voucher headers (Draft / Posted / Reversed)
     VoucherEntries            — double-entry ledger lines (single source of truth)
     AccountBalances           — per account / FY / period aggregate cache (maintained by engine)
     FinanceSequences          — concurrency-safe voucher number sequences
     FinanceMappings           — configurable source→account mappings (payment methods, categories, ...)
     BankReconciliationRuns    — bank statement runs (reconciliation layer; ledger untouched)
     BankReconciliationLines   — per-entry reconciliation marks
     UserReportFormats         — per-user custom report column formats
   ============================================================================ */

/* ------------------------------------------------------------------ */
/* COA STRUCTURE CONFIG — levels and digits per level                  */
/* Example: [1,2,2,3] = 4 levels, 8 total digits.                      */
/* System maximums enforced in SPs: 7 levels, 12 digits total.         */
/* The structure becomes locked once changing it would invalidate      */
/* existing account codes (checked by sp_FinanceCoaLevels_Set).        */
/* ------------------------------------------------------------------ */
IF OBJECT_ID('dbo.FinanceCoaLevels', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.FinanceCoaLevels (
        LevelNo      INT         NOT NULL PRIMARY KEY,
        Digits       INT         NOT NULL CHECK (Digits BETWEEN 1 AND 12),
        UpdatedAt    DATETIME2   NOT NULL DEFAULT SYSUTCDATETIME(),
        UpdatedBy    INT         NULL FOREIGN KEY REFERENCES dbo.Users(UserID)
    );
END
GO

/* ------------------------------------------------------------------ */
/* FINANCIAL YEARS                                                     */
/* The voucher date (user supplied) determines the year — never the    */
/* server clock. Status: Open / Locked / Closed.                       */
/* Overlap prevention is enforced in sp_FinanceYears_Create.           */
/* ------------------------------------------------------------------ */
IF OBJECT_ID('dbo.FinancialYears', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.FinancialYears (
        FinancialYearID INT IDENTITY(1,1) PRIMARY KEY,
        Name            NVARCHAR(50) NOT NULL UNIQUE,
        StartDate       DATE NOT NULL,
        EndDate         DATE NOT NULL,
        Status          NVARCHAR(20) NOT NULL DEFAULT 'Open'
                        CHECK (Status IN ('Open','Locked','Closed')),
        CONSTRAINT CK_FinancialYears_Range CHECK (EndDate >= StartDate),
        CreatedAt       DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CreatedBy       INT NULL FOREIGN KEY REFERENCES dbo.Users(UserID),
        UpdatedAt       DATETIME2 NULL,
        UpdatedBy       INT NULL FOREIGN KEY REFERENCES dbo.Users(UserID)
    );
END
GO

/* ------------------------------------------------------------------ */
/* ACCOUNTING PERIODS — monthly (12 per financial year)                */
/* ------------------------------------------------------------------ */
IF OBJECT_ID('dbo.AccountingPeriods', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.AccountingPeriods (
        PeriodID        INT IDENTITY(1,1) PRIMARY KEY,
        FinancialYearID INT NOT NULL FOREIGN KEY REFERENCES dbo.FinancialYears(FinancialYearID),
        PeriodNo        INT NOT NULL CHECK (PeriodNo BETWEEN 1 AND 12),
        StartDate       DATE NOT NULL,
        EndDate         DATE NOT NULL,
        Status          NVARCHAR(20) NOT NULL DEFAULT 'Open'
                        CHECK (Status IN ('Open','Locked','Closed')),
        CONSTRAINT CK_AccountingPeriods_Range CHECK (EndDate >= StartDate),
        CONSTRAINT UQ_AccountingPeriods_FY_No UNIQUE (FinancialYearID, PeriodNo),
        CreatedAt       DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CreatedBy       INT NULL FOREIGN KEY REFERENCES dbo.Users(UserID),
        UpdatedAt       DATETIME2 NULL,
        UpdatedBy       INT NULL FOREIGN KEY REFERENCES dbo.Users(UserID)
    );
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_AccountingPeriods_Dates' AND object_id = OBJECT_ID('dbo.AccountingPeriods'))
    CREATE INDEX IX_AccountingPeriods_Dates ON dbo.AccountingPeriods(StartDate, EndDate);
GO

/* ------------------------------------------------------------------ */
/* ACCOUNTS — chart of accounts                                        */
/* AccountType: Asset / Liability / Capital / Revenue / Expense        */
/* IsControl = 1 → grouping account, CANNOT receive postings.          */
/* Only IsControl = 0 (Detail) + IsActive = 1 + IsDeleted = 0 accounts */
/* may receive voucher lines (enforced by the posting engine).         */
/* ------------------------------------------------------------------ */
IF OBJECT_ID('dbo.Accounts', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Accounts (
        AccountID       INT IDENTITY(1,1) PRIMARY KEY,
        Code            NVARCHAR(12) NOT NULL UNIQUE,
        Title           NVARCHAR(150) NOT NULL,
        AccountType     NVARCHAR(20) NOT NULL
                        CHECK (AccountType IN ('Asset','Liability','Capital','Revenue','Expense')),
        ParentAccountID INT NULL FOREIGN KEY REFERENCES dbo.Accounts(AccountID),
        LevelNo         INT NOT NULL CHECK (LevelNo BETWEEN 1 AND 7),
        IsControl       BIT NOT NULL DEFAULT 1,
        IsActive        BIT NOT NULL DEFAULT 1,
        IsDeleted       BIT NOT NULL DEFAULT 0,
        CreatedAt       DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CreatedBy       INT NULL FOREIGN KEY REFERENCES dbo.Users(UserID),
        UpdatedAt       DATETIME2 NULL,
        UpdatedBy       INT NULL FOREIGN KEY REFERENCES dbo.Users(UserID)
    );
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Accounts_Parent' AND object_id = OBJECT_ID('dbo.Accounts'))
    CREATE INDEX IX_Accounts_Parent ON dbo.Accounts(ParentAccountID);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Accounts_Type' AND object_id = OBJECT_ID('dbo.Accounts'))
    CREATE INDEX IX_Accounts_Type ON dbo.Accounts(AccountType, IsActive);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Accounts_Title' AND object_id = OBJECT_ID('dbo.Accounts'))
    CREATE INDEX IX_Accounts_Title ON dbo.Accounts(Title);
GO

/* ------------------------------------------------------------------ */
/* ACCOUNT TAGS — Customer / Vendor / Bank / Cash / Employee / Tax ... */
/* An account may carry multiple tags. Selectors filter on exact tag.  */
/* ------------------------------------------------------------------ */
IF OBJECT_ID('dbo.AccountTags', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.AccountTags (
        AccountID   INT NOT NULL FOREIGN KEY REFERENCES dbo.Accounts(AccountID),
        Tag         NVARCHAR(30) NOT NULL,
        CreatedAt   DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_AccountTags PRIMARY KEY (AccountID, Tag)
    );
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_AccountTags_Tag' AND object_id = OBJECT_ID('dbo.AccountTags'))
    CREATE INDEX IX_AccountTags_Tag ON dbo.AccountTags(Tag, AccountID);
GO

/* ------------------------------------------------------------------ */
/* VOUCHER TYPES                                                       */
/* TenderTag = the tag required on the money side of the voucher       */
/* (Cash for CRV/CPV, Bank for BRV/BPV, NULL for journal/opening).     */
/* PrefixLocked is set automatically when the first voucher is posted. */
/* ------------------------------------------------------------------ */
IF OBJECT_ID('dbo.VoucherTypes', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.VoucherTypes (
        VoucherTypeID INT IDENTITY(1,1) PRIMARY KEY,
        TypeCode      NVARCHAR(10) NOT NULL UNIQUE,
        Title         NVARCHAR(100) NOT NULL,
        Prefix        NVARCHAR(10) NOT NULL,
        PrefixLocked  BIT NOT NULL DEFAULT 0,
        TenderTag     NVARCHAR(30) NULL,
        Nature        NVARCHAR(20) NOT NULL
                      CHECK (Nature IN ('Receipt','Payment','Journal','Opening')),
        IsActive      BIT NOT NULL DEFAULT 1,
        CreatedAt     DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CreatedBy     INT NULL FOREIGN KEY REFERENCES dbo.Users(UserID),
        UpdatedAt     DATETIME2 NULL,
        UpdatedBy     INT NULL FOREIGN KEY REFERENCES dbo.Users(UserID)
    );
END
GO

/* ------------------------------------------------------------------ */
/* VOUCHERS — headers                                                  */
/* Posted vouchers are immutable. Corrections only via reversal.       */
/* Drafts may be edited / deleted (soft delete via IsDeleted).         */
/* DebitTotal/CreditTotal are snapshot totals for register/reporting.  */
/* ------------------------------------------------------------------ */
IF OBJECT_ID('dbo.Vouchers', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Vouchers (
        VoucherID           INT IDENTITY(1,1) PRIMARY KEY,
        VoucherNo           NVARCHAR(50) NULL,          -- NULL while Draft; assigned at post time
        VoucherTypeID       INT NOT NULL FOREIGN KEY REFERENCES dbo.VoucherTypes(VoucherTypeID),
        VoucherDate         DATE NOT NULL,
        BranchID            INT NOT NULL FOREIGN KEY REFERENCES dbo.Branches(BranchID),
        FinancialYearID     INT NULL FOREIGN KEY REFERENCES dbo.FinancialYears(FinancialYearID),
        Narrative           NVARCHAR(500) NULL,
        Status              NVARCHAR(20) NOT NULL DEFAULT 'Draft'
                            CHECK (Status IN ('Draft','Posted','Reversed')),
        DebitTotal          DECIMAL(18,2) NULL,
        CreditTotal         DECIMAL(18,2) NULL,
        SourceModule        NVARCHAR(50) NULL,          -- e.g. 'fees', 'payroll', 'YearClose', 'Reversal'
        SourceID            INT NULL,
        ReversalOfVoucherID INT NULL FOREIGN KEY REFERENCES dbo.Vouchers(VoucherID),
        PostedBy            INT NULL FOREIGN KEY REFERENCES dbo.Users(UserID),
        PostedAt            DATETIME2 NULL,
        ReversedBy          INT NULL FOREIGN KEY REFERENCES dbo.Users(UserID),
        ReversedAt          DATETIME2 NULL,
        CreatedAt           DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CreatedBy           INT NULL FOREIGN KEY REFERENCES dbo.Users(UserID),
        UpdatedAt           DATETIME2 NULL,
        UpdatedBy           INT NULL FOREIGN KEY REFERENCES dbo.Users(UserID),
        IsDeleted           BIT NOT NULL DEFAULT 0
    );
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Vouchers_Date' AND object_id = OBJECT_ID('dbo.Vouchers'))
    CREATE INDEX IX_Vouchers_Date ON dbo.Vouchers(VoucherDate, VoucherTypeID);
GO
/* Drafts share VoucherNo = NULL, so uniqueness must be enforced only on real numbers. */
DECLARE @uq NVARCHAR(200) = (SELECT kc.name FROM sys.key_constraints kc
    WHERE kc.parent_object_id = OBJECT_ID('dbo.Vouchers') AND kc.type = 'UQ'
      AND EXISTS (SELECT 1 FROM sys.index_columns ic
                  WHERE ic.object_id = kc.parent_object_id AND ic.index_id = kc.unique_index_id
                    AND COL_NAME(ic.object_id, ic.column_id) = 'VoucherNo'));
IF @uq IS NOT NULL EXEC('ALTER TABLE dbo.Vouchers DROP CONSTRAINT ' + @uq);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_Vouchers_VoucherNo' AND object_id = OBJECT_ID('dbo.Vouchers'))
    CREATE UNIQUE INDEX UX_Vouchers_VoucherNo ON dbo.Vouchers(VoucherNo) WHERE VoucherNo IS NOT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Vouchers_BranchDate' AND object_id = OBJECT_ID('dbo.Vouchers'))
    CREATE INDEX IX_Vouchers_BranchDate ON dbo.Vouchers(BranchID, VoucherDate);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Vouchers_Status' AND object_id = OBJECT_ID('dbo.Vouchers'))
    CREATE INDEX IX_Vouchers_Status ON dbo.Vouchers(Status, VoucherDate);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Vouchers_Source' AND object_id = OBJECT_ID('dbo.Vouchers'))
    CREATE INDEX IX_Vouchers_Source ON dbo.Vouchers(SourceModule, SourceID);
GO

/* ------------------------------------------------------------------ */
/* VOUCHER ENTRIES — the ledger (single source of truth for reports)   */
/* Party references reuse existing Members / Suppliers / Staff.        */
/* Bill-wise: BillRef + BillDate + DueDate on AR/AP lines.             */
/* ------------------------------------------------------------------ */
IF OBJECT_ID('dbo.VoucherEntries', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.VoucherEntries (
        EntryID         BIGINT IDENTITY(1,1) PRIMARY KEY,
        VoucherID       INT NOT NULL FOREIGN KEY REFERENCES dbo.Vouchers(VoucherID),
        AccountID       INT NOT NULL FOREIGN KEY REFERENCES dbo.Accounts(AccountID),
        Debit           DECIMAL(18,2) NOT NULL DEFAULT 0 CHECK (Debit >= 0),
        Credit          DECIMAL(18,2) NOT NULL DEFAULT 0 CHECK (Credit >= 0),
        CONSTRAINT CK_VoucherEntries_Side CHECK (Debit + Credit > 0 AND NOT (Debit > 0 AND Credit > 0)),
        Narrative       NVARCHAR(500) NULL,
        PartyMemberID   INT NULL FOREIGN KEY REFERENCES dbo.Members(MemberID),
        PartySupplierID INT NULL FOREIGN KEY REFERENCES dbo.Suppliers(SupplierID),
        PartyStaffID    INT NULL FOREIGN KEY REFERENCES dbo.Staff(StaffID),
        BillRef         NVARCHAR(50) NULL,
        BillDate        DATE NULL,
        DueDate         DATE NULL,
        CreatedBy       INT NULL FOREIGN KEY REFERENCES dbo.Users(UserID),
        CreatedAt       DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
    );
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_VoucherEntries_Voucher' AND object_id = OBJECT_ID('dbo.VoucherEntries'))
    CREATE INDEX IX_VoucherEntries_Voucher ON dbo.VoucherEntries(VoucherID);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_VoucherEntries_Account' AND object_id = OBJECT_ID('dbo.VoucherEntries'))
    CREATE INDEX IX_VoucherEntries_Account ON dbo.VoucherEntries(AccountID, VoucherID);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_VoucherEntries_Member' AND object_id = OBJECT_ID('dbo.VoucherEntries'))
    CREATE INDEX IX_VoucherEntries_Member ON dbo.VoucherEntries(PartyMemberID) WHERE PartyMemberID IS NOT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_VoucherEntries_Supplier' AND object_id = OBJECT_ID('dbo.VoucherEntries'))
    CREATE INDEX IX_VoucherEntries_Supplier ON dbo.VoucherEntries(PartySupplierID) WHERE PartySupplierID IS NOT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_VoucherEntries_Staff' AND object_id = OBJECT_ID('dbo.VoucherEntries'))
    CREATE INDEX IX_VoucherEntries_Staff ON dbo.VoucherEntries(PartyStaffID) WHERE PartyStaffID IS NOT NULL;
GO

/* ------------------------------------------------------------------ */
/* ACCOUNT BALANCES — engine-maintained aggregate cache                */
/* PeriodNo = 0 → carry-forward opening row (written at year close).   */
/* PeriodNo 1..12 → monthly aggregate. Reports still compute from      */
/* VoucherEntries (ground truth); this cache powers fast dashboards.   */
/* ------------------------------------------------------------------ */
IF OBJECT_ID('dbo.AccountBalances', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.AccountBalances (
        AccountID       INT NOT NULL FOREIGN KEY REFERENCES dbo.Accounts(AccountID),
        FinancialYearID INT NOT NULL FOREIGN KEY REFERENCES dbo.FinancialYears(FinancialYearID),
        PeriodNo        INT NOT NULL CHECK (PeriodNo BETWEEN 0 AND 12),
        DebitTotal      DECIMAL(18,2) NOT NULL DEFAULT 0,
        CreditTotal     DECIMAL(18,2) NOT NULL DEFAULT 0,
        UpdatedAt       DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_AccountBalances PRIMARY KEY (AccountID, FinancialYearID, PeriodNo)
    );
END
GO

/* ------------------------------------------------------------------ */
/* FINANCE SEQUENCES — concurrency-safe numbering                      */
/* ScopeKey example: 'VT1-BR1-FY3' (voucher type / branch / FY).       */
/* The posting engine takes UPDLOCK on the row — no MAX+1 races.       */
/* ------------------------------------------------------------------ */
IF OBJECT_ID('dbo.FinanceSequences', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.FinanceSequences (
        ScopeKey NVARCHAR(60) NOT NULL PRIMARY KEY,
        NextSeq  INT NOT NULL DEFAULT 1,
        UpdatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
    );
END
GO

/* ------------------------------------------------------------------ */
/* FINANCE MAPPINGS — configurable source → account mappings           */
/* MappingType: PaymentMethod / IncomeCategory / ExpenseCategory /     */
/*              Payroll / MembershipRevenue / DefaultBank / DefaultCash*/
/* SourceKey: source identifier as string ('1'..'5' for payment        */
/* methods, category name for expense categories, NULL = singleton).   */
/* ------------------------------------------------------------------ */
IF OBJECT_ID('dbo.FinanceMappings', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.FinanceMappings (
        MappingID   INT IDENTITY(1,1) PRIMARY KEY,
        MappingType NVARCHAR(50) NOT NULL,
        SourceKey   NVARCHAR(50) NULL,
        AccountID   INT NOT NULL FOREIGN KEY REFERENCES dbo.Accounts(AccountID),
        IsActive    BIT NOT NULL DEFAULT 1,
        UpdatedAt   DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        UpdatedBy   INT NULL FOREIGN KEY REFERENCES dbo.Users(UserID)
    );
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_FinanceMappings_Source' AND object_id = OBJECT_ID('dbo.FinanceMappings'))
    CREATE UNIQUE INDEX UX_FinanceMappings_Source ON dbo.FinanceMappings(MappingType, SourceKey) WHERE SourceKey IS NOT NULL;
GO

/* ------------------------------------------------------------------ */
/* BANK RECONCILIATION — statement runs + per-entry marks              */
/* Purely a reconciliation layer: never modifies Vouchers/Entries.     */
/* ------------------------------------------------------------------ */
IF OBJECT_ID('dbo.BankReconciliationRuns', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.BankReconciliationRuns (
        ReconID                  INT IDENTITY(1,1) PRIMARY KEY,
        AccountID                INT NOT NULL FOREIGN KEY REFERENCES dbo.Accounts(AccountID),
        BranchID                 INT NULL FOREIGN KEY REFERENCES dbo.Branches(BranchID),
        StatementDate            DATE NOT NULL,
        StatementOpeningBalance  DECIMAL(18,2) NOT NULL DEFAULT 0,
        StatementClosingBalance  DECIMAL(18,2) NOT NULL DEFAULT 0,
        Status                   NVARCHAR(20) NOT NULL DEFAULT 'Open'
                                 CHECK (Status IN ('Open','Completed')),
        Notes                    NVARCHAR(500) NULL,
        CreatedAt                DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CreatedBy                INT NULL FOREIGN KEY REFERENCES dbo.Users(UserID),
        CompletedAt              DATETIME2 NULL,
        CompletedBy              INT NULL FOREIGN KEY REFERENCES dbo.Users(UserID)
    );
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_BankReconRuns_Account' AND object_id = OBJECT_ID('dbo.BankReconciliationRuns'))
    CREATE INDEX IX_BankReconRuns_Account ON dbo.BankReconciliationRuns(AccountID, StatementDate);
GO

IF OBJECT_ID('dbo.BankReconciliationLines', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.BankReconciliationLines (
        LineID         BIGINT IDENTITY(1,1) PRIMARY KEY,
        ReconID        INT NOT NULL FOREIGN KEY REFERENCES dbo.BankReconciliationRuns(ReconID),
        VoucherEntryID BIGINT NOT NULL FOREIGN KEY REFERENCES dbo.VoucherEntries(EntryID),
        IsReconciled   BIT NOT NULL DEFAULT 0,
        ReconciledAt   DATETIME2 NULL,
        ReconciledBy   INT NULL FOREIGN KEY REFERENCES dbo.Users(UserID),
        CONSTRAINT UQ_BankReconLines_Entry UNIQUE (VoucherEntryID)  -- an entry lives in at most one run
    );
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_BankReconLines_Recon' AND object_id = OBJECT_ID('dbo.BankReconciliationLines'))
    CREATE INDEX IX_BankReconLines_Recon ON dbo.BankReconciliationLines(ReconID, IsReconciled);
GO

/* ------------------------------------------------------------------ */
/* USER REPORT FORMATS — per-user custom report column layouts         */
/* ColumnsJson = [{key,label,visible,order,width}, ...]                */
/* The standard (global) report definition is never modified.          */
/* ------------------------------------------------------------------ */
IF OBJECT_ID('dbo.UserReportFormats', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.UserReportFormats (
        FormatID    INT IDENTITY(1,1) PRIMARY KEY,
        UserID      INT NOT NULL FOREIGN KEY REFERENCES dbo.Users(UserID),
        ReportKey   NVARCHAR(50) NOT NULL,
        FormatName  NVARCHAR(100) NOT NULL,
        ColumnsJson NVARCHAR(MAX) NOT NULL,
        IsDefault   BIT NOT NULL DEFAULT 0,
        CreatedAt   DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        UpdatedAt   DATETIME2 NULL
    );
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_UserReportFormats' AND object_id = OBJECT_ID('dbo.UserReportFormats'))
    CREATE UNIQUE INDEX UX_UserReportFormats ON dbo.UserReportFormats(UserID, ReportKey, FormatName);
GO

PRINT '=== 11_finance_schema.sql applied successfully. ===';
GO

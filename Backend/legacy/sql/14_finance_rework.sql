/* ============================================================================
   CONTOURA LABS — GYM MANAGEMENT SYSTEM
   FINANCE REWORK (14_finance_rework.sql)
   ----------------------------------------------------------------------------
   Idempotent. Run AFTER 13_finance_permissions_defaults.sql.

   PART 1 — REMOVE INCOME & EXPENSE
     - Drops income/expense SPs (incl. legacy report SPs)
     - Drops Expenses / IncomeRecords / IncomeCategories tables
     - Removes stale FinanceMappings rows for those sources

   PART 2 — TAX HEADS MASTER
     - TaxHeads table + CRUD SPs + example seed rows (configurable master data)

   PART 3 — KNOCK-OFF / BILL WISE ACCOUNT FLAG
     - Accounts.KnockOff BIT (0 = Normal, 1 = Bill Wise / Knock Off)

   PART 4 — SEPARATE VOUCHER DOCUMENT TABLES
     - CashVouchers + CashVoucherLines   (Cash Receipt / Cash Payment)
     - BankVouchers + BankVoucherLines   (Bank Receipt / Bank Payment)
     - JournalVouchers + JournalVoucherLines
     - OpeningTrialBalances + OpeningTBLines
     Documents are the source documents; the double-entry ledger remains the
     single unified Vouchers/VoucherEntries architecture fed through the
     existing central posting engine (sp_Accounting_*).

   PART 5 — DOCUMENT SPs + ENGINE CORES
     - sp_Accounting_CreateAndPostCore / sp_Accounting_ReverseCore
       (transaction-free cores; the existing wrappers are redefined on top)
     - sp_FinanceDocuments_SaveCash/Bank/Journal/OpeningTB (atomic save = post;
       edit = date-locked reverse-and-repost; delete = soft delete + reversal)
     - sp_FinanceDocuments_List / Get / Delete

   PART 6 — DASHBOARD SPs REWRITTEN OFF THE LEDGER
     - sp_Dashboard_Stats / sp_Dashboard_Charts no longer read Expenses.
   ============================================================================ */

/* ================================================================== */
/* PART 1 — REMOVE INCOME & EXPENSE                                   */
/* ================================================================== */

DROP PROCEDURE IF EXISTS dbo.sp_Expenses_Create;
DROP PROCEDURE IF EXISTS dbo.sp_Expenses_List;
DROP PROCEDURE IF EXISTS dbo.sp_Income_Create;
DROP PROCEDURE IF EXISTS dbo.sp_Income_List;
DROP PROCEDURE IF EXISTS dbo.sp_IncomeCategories_List;
DROP PROCEDURE IF EXISTS dbo.sp_Reports_Expenses;
DROP PROCEDURE IF EXISTS dbo.sp_Reports_Income;
DROP PROCEDURE IF EXISTS dbo.sp_Reports_ProfitLoss;
GO

IF OBJECT_ID('dbo.IncomeRecords', 'U') IS NOT NULL DROP TABLE dbo.IncomeRecords;
GO
IF OBJECT_ID('dbo.IncomeCategories', 'U') IS NOT NULL DROP TABLE dbo.IncomeCategories;
GO
IF OBJECT_ID('dbo.Expenses', 'U') IS NOT NULL DROP TABLE dbo.Expenses;
GO

DELETE FROM dbo.FinanceMappings WHERE MappingType IN ('IncomeCategory', 'ExpenseCategory');
GO

/* ================================================================== */
/* PART 2 — TAX HEADS MASTER                                          */
/* ================================================================== */

IF OBJECT_ID('dbo.TaxHeads', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.TaxHeads (
        TaxHeadID   INT IDENTITY(1,1) PRIMARY KEY,
        Code        NVARCHAR(20)  NOT NULL UNIQUE,
        Name        NVARCHAR(150) NOT NULL,
        Description NVARCHAR(500) NULL,
        RatePercent DECIMAL(9,4)  NULL,
        TaxType     NVARCHAR(30)  NULL,          -- Withholding / SalesTax / Other
        IsActive    BIT NOT NULL DEFAULT 1,
        CreatedAt   DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CreatedBy   INT NULL FOREIGN KEY REFERENCES dbo.Users(UserID),
        UpdatedAt   DATETIME2 NULL,
        UpdatedBy   INT NULL FOREIGN KEY REFERENCES dbo.Users(UserID)
    );
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_TaxHeads_List
    @IncludeInactive BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TaxHeadID, Code, Name, Description, RatePercent, TaxType, IsActive, CreatedAt, UpdatedAt
    FROM dbo.TaxHeads
    WHERE (@IncludeInactive = 1 OR IsActive = 1)
    ORDER BY Code;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_TaxHeads_Create
    @Code NVARCHAR(20), @Name NVARCHAR(150), @Description NVARCHAR(500) = NULL,
    @RatePercent DECIMAL(9,4) = NULL, @TaxType NVARCHAR(30) = NULL, @CreatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM dbo.TaxHeads WHERE Code = @Code)
        THROW 51058, 'A tax head with this code already exists.', 1;
    INSERT INTO dbo.TaxHeads (Code, Name, Description, RatePercent, TaxType, CreatedBy)
    VALUES (@Code, @Name, @Description, @RatePercent, @TaxType, @CreatedBy);
    SELECT CAST(SCOPE_IDENTITY() AS INT) AS TaxHeadID;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_TaxHeads_Update
    @TaxHeadID INT, @Name NVARCHAR(150), @Description NVARCHAR(500) = NULL,
    @RatePercent DECIMAL(9,4) = NULL, @TaxType NVARCHAR(30) = NULL, @UpdatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.TaxHeads WHERE TaxHeadID = @TaxHeadID)
        THROW 51055, 'Tax head not found.', 1;
    UPDATE dbo.TaxHeads
       SET Name = @Name, Description = @Description, RatePercent = @RatePercent,
           TaxType = @TaxType, UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @UpdatedBy
     WHERE TaxHeadID = @TaxHeadID;
    SELECT 'OK' AS Result;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_TaxHeads_SetStatus
    @TaxHeadID INT, @IsActive BIT, @UpdatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.TaxHeads WHERE TaxHeadID = @TaxHeadID)
        THROW 51055, 'Tax head not found.', 1;
    UPDATE dbo.TaxHeads SET IsActive = @IsActive, UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @UpdatedBy
    WHERE TaxHeadID = @TaxHeadID;
    SELECT 'OK' AS Result;
END
GO

/* Example tax heads as configurable master data (idempotent seed) */
IF NOT EXISTS (SELECT 1 FROM dbo.TaxHeads)
BEGIN
    INSERT INTO dbo.TaxHeads (Code, Name, Description, RatePercent, TaxType)
    VALUES
        ('WHT-149', 'Withholding Tax - Salary (Section 149)',      'Withholding tax on salary payments',                      NULL, 'Withholding'),
        ('WHT-153', 'Payments for Goods & Services (Section 153)', 'WHT on payments for goods, services and contracts',       NULL, 'Withholding'),
        ('WHT-IT',  'IT & IT Enabled Services (4% filers)',         'Withholding tax on IT / IT-enabled services, 4% filers',  4.0,  'Withholding'),
        ('ST-18',   'Sales Tax 18%',                                'Standard sales tax rate',                                 18.0, 'SalesTax');
END
GO

/* ================================================================== */
/* PART 3 — KNOCK-OFF / BILL WISE FLAG ON ACCOUNTS                    */
/* ================================================================== */

IF COL_LENGTH('dbo.Accounts', 'KnockOff') IS NULL
    ALTER TABLE dbo.Accounts ADD KnockOff BIT NOT NULL DEFAULT 0;
GO

/* ================================================================== */
/* PART 4 — SEPARATE VOUCHER DOCUMENT TABLES                          */
/* ================================================================== */

IF OBJECT_ID('dbo.CashVouchers', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.CashVouchers (
        CashVoucherID    INT IDENTITY(1,1) PRIMARY KEY,
        VoucherNo        NVARCHAR(50) NULL,
        VoucherID        INT NULL FOREIGN KEY REFERENCES dbo.Vouchers(VoucherID),  -- ledger voucher
        Direction        NVARCHAR(10) NOT NULL CHECK (Direction IN ('Receipt','Payment')),
        VoucherDate      DATE NOT NULL,
        CashAccountID    INT NOT NULL FOREIGN KEY REFERENCES dbo.Accounts(AccountID),
        BranchID         INT NOT NULL FOREIGN KEY REFERENCES dbo.Branches(BranchID),
        FinancialYearID  INT NULL FOREIGN KEY REFERENCES dbo.FinancialYears(FinancialYearID),
        Narrative        NVARCHAR(500) NULL,
        TotalAmount      DECIMAL(18,2) NULL,
        Status           NVARCHAR(20) NOT NULL DEFAULT 'Posted' CHECK (Status IN ('Posted','Reversed')),
        PostedBy         INT NULL FOREIGN KEY REFERENCES dbo.Users(UserID),
        PostedAt         DATETIME2 NULL,
        ReversedBy       INT NULL FOREIGN KEY REFERENCES dbo.Users(UserID),
        ReversedAt       DATETIME2 NULL,
        CreatedAt        DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CreatedBy        INT NULL FOREIGN KEY REFERENCES dbo.Users(UserID),
        UpdatedAt        DATETIME2 NULL,
        UpdatedBy        INT NULL FOREIGN KEY REFERENCES dbo.Users(UserID),
        IsDeleted        BIT NOT NULL DEFAULT 0
    );
END
GO
IF OBJECT_ID('dbo.CashVoucherLines', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.CashVoucherLines (
        CashVoucherLineID BIGINT IDENTITY(1,1) PRIMARY KEY,
        CashVoucherID     INT NOT NULL FOREIGN KEY REFERENCES dbo.CashVouchers(CashVoucherID),
        AccountID         INT NOT NULL FOREIGN KEY REFERENCES dbo.Accounts(AccountID),
        Description       NVARCHAR(500) NULL,
        Amount            DECIMAL(18,2) NOT NULL CHECK (Amount > 0),
        TaxHeadID         INT NULL FOREIGN KEY REFERENCES dbo.TaxHeads(TaxHeadID),
        KnockOff          BIT NOT NULL DEFAULT 0,
        BillRef           NVARCHAR(50) NULL,
        BillDate          DATE NULL,
        DueDate           DATE NULL,
        PartyMemberID     INT NULL FOREIGN KEY REFERENCES dbo.Members(MemberID),
        PartySupplierID   INT NULL FOREIGN KEY REFERENCES dbo.Suppliers(SupplierID),
        PartyStaffID      INT NULL FOREIGN KEY REFERENCES dbo.Staff(StaffID),
        CreatedAt         DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CreatedBy         INT NULL
    );
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_CashVoucherLines_Voucher' AND object_id = OBJECT_ID('dbo.CashVoucherLines'))
    CREATE INDEX IX_CashVoucherLines_Voucher ON dbo.CashVoucherLines(CashVoucherID);
GO

IF OBJECT_ID('dbo.BankVouchers', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.BankVouchers (
        BankVoucherID    INT IDENTITY(1,1) PRIMARY KEY,
        VoucherNo        NVARCHAR(50) NULL,
        VoucherID        INT NULL FOREIGN KEY REFERENCES dbo.Vouchers(VoucherID),
        Direction        NVARCHAR(10) NOT NULL CHECK (Direction IN ('Receipt','Payment')),
        VoucherDate      DATE NOT NULL,
        BankAccountID    INT NOT NULL FOREIGN KEY REFERENCES dbo.Accounts(AccountID),
        BranchID         INT NOT NULL FOREIGN KEY REFERENCES dbo.Branches(BranchID),
        FinancialYearID  INT NULL FOREIGN KEY REFERENCES dbo.FinancialYears(FinancialYearID),
        Narrative        NVARCHAR(500) NULL,
        TotalAmount      DECIMAL(18,2) NULL,
        Status           NVARCHAR(20) NOT NULL DEFAULT 'Posted' CHECK (Status IN ('Posted','Reversed')),
        PostedBy         INT NULL FOREIGN KEY REFERENCES dbo.Users(UserID),
        PostedAt         DATETIME2 NULL,
        ReversedBy       INT NULL FOREIGN KEY REFERENCES dbo.Users(UserID),
        ReversedAt       DATETIME2 NULL,
        CreatedAt        DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CreatedBy        INT NULL FOREIGN KEY REFERENCES dbo.Users(UserID),
        UpdatedAt        DATETIME2 NULL,
        UpdatedBy        INT NULL FOREIGN KEY REFERENCES dbo.Users(UserID),
        IsDeleted        BIT NOT NULL DEFAULT 0
    );
END
GO
IF OBJECT_ID('dbo.BankVoucherLines', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.BankVoucherLines (
        BankVoucherLineID BIGINT IDENTITY(1,1) PRIMARY KEY,
        BankVoucherID     INT NOT NULL FOREIGN KEY REFERENCES dbo.BankVouchers(BankVoucherID),
        AccountID         INT NOT NULL FOREIGN KEY REFERENCES dbo.Accounts(AccountID),
        Description       NVARCHAR(500) NULL,
        Amount            DECIMAL(18,2) NOT NULL CHECK (Amount > 0),
        TaxHeadID         INT NULL FOREIGN KEY REFERENCES dbo.TaxHeads(TaxHeadID),
        KnockOff          BIT NOT NULL DEFAULT 0,
        BillRef           NVARCHAR(50) NULL,
        BillDate          DATE NULL,
        DueDate           DATE NULL,
        PartyMemberID     INT NULL FOREIGN KEY REFERENCES dbo.Members(MemberID),
        PartySupplierID   INT NULL FOREIGN KEY REFERENCES dbo.Suppliers(SupplierID),
        PartyStaffID      INT NULL FOREIGN KEY REFERENCES dbo.Staff(StaffID),
        CreatedAt         DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CreatedBy         INT NULL
    );
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_BankVoucherLines_Voucher' AND object_id = OBJECT_ID('dbo.BankVoucherLines'))
    CREATE INDEX IX_BankVoucherLines_Voucher ON dbo.BankVoucherLines(BankVoucherID);
GO

IF OBJECT_ID('dbo.JournalVouchers', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.JournalVouchers (
        JournalVoucherID INT IDENTITY(1,1) PRIMARY KEY,
        VoucherNo        NVARCHAR(50) NULL,
        VoucherID        INT NULL FOREIGN KEY REFERENCES dbo.Vouchers(VoucherID),
        VoucherDate      DATE NOT NULL,
        BranchID         INT NOT NULL FOREIGN KEY REFERENCES dbo.Branches(BranchID),
        FinancialYearID  INT NULL FOREIGN KEY REFERENCES dbo.FinancialYears(FinancialYearID),
        Narrative        NVARCHAR(500) NULL,
        DebitTotal       DECIMAL(18,2) NULL,
        CreditTotal      DECIMAL(18,2) NULL,
        Status           NVARCHAR(20) NOT NULL DEFAULT 'Posted' CHECK (Status IN ('Posted','Reversed')),
        PostedBy         INT NULL FOREIGN KEY REFERENCES dbo.Users(UserID),
        PostedAt         DATETIME2 NULL,
        ReversedBy       INT NULL FOREIGN KEY REFERENCES dbo.Users(UserID),
        ReversedAt       DATETIME2 NULL,
        CreatedAt        DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CreatedBy        INT NULL FOREIGN KEY REFERENCES dbo.Users(UserID),
        UpdatedAt        DATETIME2 NULL,
        UpdatedBy        INT NULL FOREIGN KEY REFERENCES dbo.Users(UserID),
        IsDeleted        BIT NOT NULL DEFAULT 0
    );
END
GO
IF OBJECT_ID('dbo.JournalVoucherLines', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.JournalVoucherLines (
        JournalVoucherLineID BIGINT IDENTITY(1,1) PRIMARY KEY,
        JournalVoucherID     INT NOT NULL FOREIGN KEY REFERENCES dbo.JournalVouchers(JournalVoucherID),
        AccountID            INT NOT NULL FOREIGN KEY REFERENCES dbo.Accounts(AccountID),
        Debit                DECIMAL(18,2) NOT NULL DEFAULT 0,
        Credit               DECIMAL(18,2) NOT NULL DEFAULT 0,
        Description          NVARCHAR(500) NULL,
        CreatedAt            DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CreatedBy            INT NULL,
        CONSTRAINT CK_JournalVoucherLines_Side CHECK (Debit >= 0 AND Credit >= 0 AND (Debit + Credit) > 0 AND NOT (Debit > 0 AND Credit > 0))
    );
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_JournalVoucherLines_Voucher' AND object_id = OBJECT_ID('dbo.JournalVoucherLines'))
    CREATE INDEX IX_JournalVoucherLines_Voucher ON dbo.JournalVoucherLines(JournalVoucherID);
GO

IF OBJECT_ID('dbo.OpeningTrialBalances', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.OpeningTrialBalances (
        OpeningTBID      INT IDENTITY(1,1) PRIMARY KEY,
        VoucherNo        NVARCHAR(50) NULL,
        VoucherID        INT NULL FOREIGN KEY REFERENCES dbo.Vouchers(VoucherID),
        VoucherDate      DATE NOT NULL,
        BranchID         INT NOT NULL FOREIGN KEY REFERENCES dbo.Branches(BranchID),
        FinancialYearID  INT NULL FOREIGN KEY REFERENCES dbo.FinancialYears(FinancialYearID),
        Narrative        NVARCHAR(500) NULL,
        DebitTotal       DECIMAL(18,2) NULL,
        CreditTotal      DECIMAL(18,2) NULL,
        Status           NVARCHAR(20) NOT NULL DEFAULT 'Posted' CHECK (Status IN ('Posted','Reversed')),
        PostedBy         INT NULL FOREIGN KEY REFERENCES dbo.Users(UserID),
        PostedAt         DATETIME2 NULL,
        ReversedBy       INT NULL FOREIGN KEY REFERENCES dbo.Users(UserID),
        ReversedAt       DATETIME2 NULL,
        CreatedAt        DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CreatedBy        INT NULL FOREIGN KEY REFERENCES dbo.Users(UserID),
        UpdatedAt        DATETIME2 NULL,
        UpdatedBy        INT NULL FOREIGN KEY REFERENCES dbo.Users(UserID),
        IsDeleted        BIT NOT NULL DEFAULT 0
    );
END
GO
IF OBJECT_ID('dbo.OpeningTBLines', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.OpeningTBLines (
        OpeningTBLineID  BIGINT IDENTITY(1,1) PRIMARY KEY,
        OpeningTBID      INT NOT NULL FOREIGN KEY REFERENCES dbo.OpeningTrialBalances(OpeningTBID),
        AccountID        INT NOT NULL FOREIGN KEY REFERENCES dbo.Accounts(AccountID),
        Debit            DECIMAL(18,2) NOT NULL DEFAULT 0,
        Credit           DECIMAL(18,2) NOT NULL DEFAULT 0,
        Description      NVARCHAR(500) NULL,
        CreatedAt        DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CreatedBy        INT NULL,
        CONSTRAINT CK_OpeningTBLines_Side CHECK (Debit >= 0 AND Credit >= 0 AND (Debit + Credit) > 0 AND NOT (Debit > 0 AND Credit > 0))
    );
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_OpeningTBLines_Voucher' AND object_id = OBJECT_ID('dbo.OpeningTBLines'))
    CREATE INDEX IX_OpeningTBLines_Voucher ON dbo.OpeningTBLines(OpeningTBID);
GO

/* List-page indexes */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_CashVouchers_Date' AND object_id = OBJECT_ID('dbo.CashVouchers'))
    CREATE INDEX IX_CashVouchers_Date ON dbo.CashVouchers(VoucherDate, Direction, Status);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_BankVouchers_Date' AND object_id = OBJECT_ID('dbo.BankVouchers'))
    CREATE INDEX IX_BankVouchers_Date ON dbo.BankVouchers(VoucherDate, Direction, Status);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_JournalVouchers_Date' AND object_id = OBJECT_ID('dbo.JournalVouchers'))
    CREATE INDEX IX_JournalVouchers_Date ON dbo.JournalVouchers(VoucherDate, Status);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_OpeningTB_Date' AND object_id = OBJECT_ID('dbo.OpeningTrialBalances'))
    CREATE INDEX IX_OpeningTB_Date ON dbo.OpeningTrialBalances(VoucherDate, Status);
GO
/* ================================================================== */
/* PART 5a — ENGINE CORES (transaction-free, for composition)         */
/* The existing wrappers are redefined on top of these cores.         */
/* ================================================================== */

CREATE OR ALTER PROCEDURE dbo.sp_Accounting_CreateAndPostCore
    @VoucherTypeID INT,
    @VoucherDate   DATE,
    @BranchID      INT,
    @Narrative     NVARCHAR(500) = NULL,
    @SourceModule  NVARCHAR(50) = NULL,
    @SourceID      INT = NULL,
    @ReversalOfVoucherID INT = NULL,
    @EntriesJson   NVARCHAR(MAX),
    @UserId        INT = NULL,
    @NewVoucherID  INT OUTPUT,
    @NewVoucherNo  NVARCHAR(50) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ID INT = NULL;
    EXEC dbo.sp_FinanceVouchers_SaveDraftCore
         @VoucherID = @ID OUTPUT,
         @VoucherTypeID = @VoucherTypeID, @VoucherDate = @VoucherDate,
         @BranchID = @BranchID, @Narrative = @Narrative,
         @EntriesJson = @EntriesJson, @UserId = @UserId;

    UPDATE dbo.Vouchers
       SET SourceModule = @SourceModule, SourceID = @SourceID,
           ReversalOfVoucherID = @ReversalOfVoucherID
     WHERE VoucherID = @ID;

    DECLARE @No NVARCHAR(50);
    EXEC dbo.sp_Accounting_PostCore @VoucherID = @ID, @PostedBy = @UserId, @VoucherNo = @No OUTPUT;

    SET @NewVoucherID = @ID;
    SET @NewVoucherNo = @No;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_Accounting_ReverseCore
    @VoucherID    INT,
    @ReversalDate DATE,
    @Narrative    NVARCHAR(500) = NULL,
    @UserId       INT = NULL,
    @NewVoucherID INT OUTPUT,
    @NewVoucherNo NVARCHAR(50) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Type INT, @BranchID INT, @Status NVARCHAR(20), @OrigNo NVARCHAR(50);
    SELECT @Type = VoucherTypeID, @BranchID = BranchID, @Status = Status, @OrigNo = VoucherNo
    FROM dbo.Vouchers WITH (UPDLOCK, HOLDLOCK)
    WHERE VoucherID = @VoucherID AND IsDeleted = 0;

    IF @Type IS NULL THROW 51001, 'Voucher not found.', 1;
    IF @Status = 'Draft' THROW 51023, 'A draft voucher cannot be reversed - delete it instead.', 1;
    IF @Status = 'Reversed' THROW 51022, 'This voucher has already been reversed.', 1;

    DECLARE @EntriesJson NVARCHAR(MAX);
    SET @EntriesJson = (
        SELECT AccountID,
               Credit AS Debit,
               Debit  AS Credit,
               CONCAT('Reversal of ', @OrigNo, CASE WHEN e.Narrative IS NULL THEN '' ELSE ' - ' + e.Narrative END) AS Narrative,
               PartyMemberID, PartySupplierID, PartyStaffID, BillRef, BillDate, DueDate
        FROM dbo.VoucherEntries e
        WHERE e.VoucherID = @VoucherID
        FOR JSON PATH
    );

    DECLARE @RevNarrative NVARCHAR(500) =
        COALESCE(NULLIF(LTRIM(RTRIM(@Narrative)), ''), CONCAT('Reversal of voucher ', @OrigNo));

    DECLARE @NewID INT = NULL;
    EXEC dbo.sp_FinanceVouchers_SaveDraftCore
         @VoucherID = @NewID OUTPUT,
         @VoucherTypeID = @Type, @VoucherDate = @ReversalDate,
         @BranchID = @BranchID, @Narrative = @RevNarrative,
         @EntriesJson = @EntriesJson, @UserId = @UserId;

    UPDATE dbo.Vouchers
       SET SourceModule = 'Reversal', SourceID = @VoucherID, ReversalOfVoucherID = @VoucherID
     WHERE VoucherID = @NewID;

    DECLARE @No NVARCHAR(50);
    EXEC dbo.sp_Accounting_PostCore @VoucherID = @NewID, @PostedBy = @UserId, @VoucherNo = @No OUTPUT;

    UPDATE dbo.Vouchers
       SET Status = 'Reversed', ReversedBy = @UserId, ReversedAt = SYSUTCDATETIME(),
           UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @UserId
     WHERE VoucherID = @VoucherID;

    SET @NewVoucherID = @NewID;
    SET @NewVoucherNo = @No;
END
GO

/* Wrappers redefined on top of the cores (same public behavior) */
CREATE OR ALTER PROCEDURE dbo.sp_Accounting_CreateAndPostVoucher
    @VoucherTypeID INT,
    @VoucherDate   DATE,
    @BranchID      INT,
    @Narrative     NVARCHAR(500) = NULL,
    @SourceModule  NVARCHAR(50) = NULL,
    @SourceID      INT = NULL,
    @ReversalOfVoucherID INT = NULL,
    @EntriesJson   NVARCHAR(MAX),
    @UserId        INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @ID INT, @No NVARCHAR(50);
        EXEC dbo.sp_Accounting_CreateAndPostCore
             @VoucherTypeID = @VoucherTypeID, @VoucherDate = @VoucherDate, @BranchID = @BranchID,
             @Narrative = @Narrative, @SourceModule = @SourceModule, @SourceID = @SourceID,
             @ReversalOfVoucherID = @ReversalOfVoucherID, @EntriesJson = @EntriesJson,
             @UserId = @UserId, @NewVoucherID = @ID OUTPUT, @NewVoucherNo = @No OUTPUT;
        DECLARE @FY INT = (SELECT FinancialYearID FROM dbo.Vouchers WHERE VoucherID = @ID);
        COMMIT TRANSACTION;
        SELECT @ID AS VoucherID, @No AS VoucherNo, @FY AS FinancialYearID;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_Accounting_ReverseVoucher
    @VoucherID    INT,
    @ReversalDate DATE,
    @Narrative    NVARCHAR(500) = NULL,
    @UserId       INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @ID INT, @No NVARCHAR(50);
        EXEC dbo.sp_Accounting_ReverseCore
             @VoucherID = @VoucherID, @ReversalDate = @ReversalDate, @Narrative = @Narrative,
             @UserId = @UserId, @NewVoucherID = @ID OUTPUT, @NewVoucherNo = @No OUTPUT;
        DECLARE @FY INT = (SELECT FinancialYearID FROM dbo.Vouchers WHERE VoucherID = @ID);
        COMMIT TRANSACTION;
        SELECT @ID AS VoucherID, @No AS VoucherNo, @FY AS FinancialYearID;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

/* ================================================================== */
/* PART 5b — DOCUMENT SAVE SPs                                        */
/* One atomic transaction per save: validate → (reverse old on edit)  */
/* → post new ledger voucher through the central engine → store the   */
/* document + lines. Date is immutable after the first save.          */
/* ================================================================== */

/* ---------------- CASH VOUCHERS (Receipt / Payment) ---------------- */

CREATE OR ALTER PROCEDURE dbo.sp_FinanceDocuments_SaveCash
    @CashVoucherID  INT = NULL,             -- NULL = create; otherwise edit
    @Direction      NVARCHAR(10),
    @VoucherDate    DATE,
    @CashAccountID  INT,
    @BranchID       INT,
    @Narrative      NVARCHAR(500) = NULL,
    @LinesJson      NVARCHAR(MAX),
    @UserId         INT = NULL,
    @NewID          INT OUTPUT,
    @NewVoucherNo   NVARCHAR(50) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF @Direction NOT IN ('Receipt','Payment')
            THROW 51051, 'Invalid cash voucher direction.', 1;

        DECLARE @ExistingDate DATE = NULL, @ExistingLedger INT = NULL, @Deleted BIT = NULL;
        IF @CashVoucherID IS NOT NULL
            SELECT @ExistingDate = VoucherDate, @ExistingLedger = VoucherID, @Deleted = IsDeleted
            FROM dbo.CashVouchers WHERE CashVoucherID = @CashVoucherID;

        IF @CashVoucherID IS NOT NULL AND @ExistingDate IS NULL
            THROW 51001, 'Cash voucher not found.', 1;
        IF @Deleted = 1
            THROW 51001, 'This cash voucher has been deleted.', 1;

        -- DATE IMMUTABILITY (Rule 5) — enforced server-side
        IF @ExistingDate IS NOT NULL AND @VoucherDate <> @ExistingDate
            THROW 51050, 'The voucher date cannot be changed after the voucher has been saved.', 1;

        -- money account: active detail account tagged Cash
        IF NOT EXISTS (SELECT 1 FROM dbo.Accounts a
                       JOIN dbo.AccountTags t ON t.AccountID = a.AccountID AND t.Tag = 'Cash'
                       WHERE a.AccountID = @CashAccountID AND a.IsControl = 0 AND a.IsActive = 1 AND a.IsDeleted = 0)
            THROW 51052, 'Select an active Detail account tagged Cash.', 1;

        IF OBJECT_ID('tempdb..#DocLines') IS NOT NULL DROP TABLE #DocLines;
        CREATE TABLE #DocLines (
            RowNum INT IDENTITY(1,1) PRIMARY KEY,
            AccountID INT, Description NVARCHAR(500), Amount DECIMAL(18,2),
            TaxHeadID INT, KnockOff BIT, BillRef NVARCHAR(50), BillDate DATE, DueDate DATE,
            PartyMemberID INT, PartySupplierID INT, PartyStaffID INT);

        INSERT INTO #DocLines (AccountID, Description, Amount, TaxHeadID, KnockOff, BillRef, BillDate, DueDate, PartyMemberID, PartySupplierID, PartyStaffID)
        SELECT AccountID, Description, Amount, TaxHeadID,
               ISNULL(KnockOff, 0), BillRef, BillDate, DueDate, PartyMemberID, PartySupplierID, PartyStaffID
        FROM OPENJSON(@LinesJson)
        WITH (
            AccountID INT '$.AccountID',
            Description NVARCHAR(500) '$.Description',
            Amount DECIMAL(18,2) '$.Amount',
            TaxHeadID INT '$.TaxHeadID',
            KnockOff BIT '$.KnockOff',
            BillRef NVARCHAR(50) '$.BillRef',
            BillDate DATE '$.BillDate',
            DueDate DATE '$.DueDate',
            PartyMemberID INT '$.PartyMemberID',
            PartySupplierID INT '$.PartySupplierID',
            PartyStaffID INT '$.PartyStaffID'
        );

        IF NOT EXISTS (SELECT 1 FROM #DocLines)
            THROW 51057, 'Add at least one detail line.', 1;
        IF EXISTS (SELECT 1 FROM #DocLines WHERE AccountID IS NULL)
            THROW 51008, 'Every line must reference an account.', 1;
        IF EXISTS (SELECT 1 FROM #DocLines WHERE Amount IS NULL OR Amount <= 0)
            THROW 51053, 'Every line amount must be greater than zero.', 1;
        IF EXISTS (SELECT 1 FROM #DocLines l JOIN dbo.Accounts a ON a.AccountID = l.AccountID
                   WHERE a.IsControl = 1)
            THROW 51007, 'Control accounts cannot receive postings. Select Detail accounts only.', 1;
        IF EXISTS (SELECT 1 FROM #DocLines l JOIN dbo.Accounts a ON a.AccountID = l.AccountID
                   WHERE a.IsActive = 0 OR a.IsDeleted = 1)
            THROW 51008, 'One or more selected accounts are inactive or deleted.', 1;
        IF EXISTS (SELECT 1 FROM #DocLines l LEFT JOIN dbo.TaxHeads t ON t.TaxHeadID = l.TaxHeadID
                   WHERE l.TaxHeadID IS NOT NULL AND (t.TaxHeadID IS NULL OR t.IsActive = 0))
            THROW 51055, 'Invalid or inactive tax head on one or more lines.', 1;
        -- Knock Off only for accounts configured as Bill Wise (Rule 10)
        IF EXISTS (SELECT 1 FROM #DocLines l JOIN dbo.Accounts a ON a.AccountID = l.AccountID
                   WHERE ISNULL(l.KnockOff, 0) = 1 AND ISNULL(a.KnockOff, 0) = 0)
            THROW 51056, 'Knock Off is not enabled for one or more selected accounts.', 1;
        IF EXISTS (SELECT 1 FROM #DocLines l LEFT JOIN dbo.Members m ON m.MemberID = l.PartyMemberID
                   WHERE l.PartyMemberID IS NOT NULL AND m.MemberID IS NULL)
            THROW 51019, 'Invalid customer reference.', 1;
        IF EXISTS (SELECT 1 FROM #DocLines l LEFT JOIN dbo.Suppliers s ON s.SupplierID = l.PartySupplierID
                   WHERE l.PartySupplierID IS NOT NULL AND s.SupplierID IS NULL)
            THROW 51019, 'Invalid vendor reference.', 1;
        IF EXISTS (SELECT 1 FROM #DocLines l LEFT JOIN dbo.Staff st ON st.StaffID = l.PartyStaffID
                   WHERE l.PartyStaffID IS NOT NULL AND st.StaffID IS NULL)
            THROW 51019, 'Invalid employee reference.', 1;

        DECLARE @Total DECIMAL(18,2) = (SELECT ISNULL(SUM(Amount), 0) FROM #DocLines);
        IF @Total <= 0 THROW 51006, 'The voucher total must be greater than zero.', 1;

        -- on edit: reverse the previous ledger voucher (correction stays in history)
        IF @ExistingLedger IS NOT NULL
        BEGIN
            DECLARE @RevID INT, @RevNo NVARCHAR(50);
            EXEC dbo.sp_Accounting_ReverseCore
                 @VoucherID = @ExistingLedger, @ReversalDate = @ExistingDate,
                 @UserId = @UserId, @NewVoucherID = @RevID OUTPUT, @NewVoucherNo = @RevNo OUTPUT;
        END

        -- generate ledger entries: the money side is derived from the direction (Rules 1-4)
        DECLARE @EntriesJson NVARCHAR(MAX);
        IF @Direction = 'Receipt'
            SET @EntriesJson = (
                SELECT * FROM (
                SELECT @CashAccountID AS AccountID, @Total AS Debit, 0 AS Credit,
                       @Narrative AS Narrative, NULL AS PartyMemberID, NULL AS PartySupplierID, NULL AS PartyStaffID,
                       NULL AS BillRef, NULL AS BillDate, NULL AS DueDate
                UNION ALL
                SELECT AccountID, 0 AS Debit, Amount AS Credit, Description AS Narrative,
                       PartyMemberID, PartySupplierID, PartyStaffID,
                       CASE WHEN KnockOff = 1 THEN NULLIF(BillRef,'') ELSE NULL END AS BillRef,
                       CASE WHEN KnockOff = 1 THEN BillDate ELSE NULL END AS BillDate,
                       CASE WHEN KnockOff = 1 THEN DueDate ELSE NULL END AS DueDate
                FROM #DocLines
                ) x
                FOR JSON PATH
            );
        ELSE
            SET @EntriesJson = (
                SELECT * FROM (
                SELECT AccountID, Amount AS Debit, 0 AS Credit, Description AS Narrative,
                       PartyMemberID, PartySupplierID, PartyStaffID,
                       CASE WHEN KnockOff = 1 THEN NULLIF(BillRef,'') ELSE NULL END AS BillRef,
                       CASE WHEN KnockOff = 1 THEN BillDate ELSE NULL END AS BillDate,
                       CASE WHEN KnockOff = 1 THEN DueDate ELSE NULL END AS DueDate
                FROM #DocLines
                UNION ALL
                SELECT @CashAccountID AS AccountID, 0 AS Debit, @Total AS Credit,
                       @Narrative AS Narrative, NULL AS PartyMemberID, NULL AS PartySupplierID, NULL AS PartyStaffID,
                       NULL AS BillRef, NULL AS BillDate, NULL AS DueDate
                ) x
                FOR JSON PATH
            );

        DECLARE @TypeCode NVARCHAR(10) = CASE WHEN @Direction = 'Receipt' THEN 'CRV' ELSE 'CPV' END;
        DECLARE @VoucherTypeID INT = (SELECT VoucherTypeID FROM dbo.VoucherTypes WHERE TypeCode = @TypeCode AND IsActive = 1);
        IF @VoucherTypeID IS NULL THROW 51021, 'Cash voucher type not found or inactive.', 1;

        DECLARE @LedgerID INT, @LedgerNo NVARCHAR(50);
        EXEC dbo.sp_Accounting_CreateAndPostCore
             @VoucherTypeID = @VoucherTypeID, @VoucherDate = @VoucherDate, @BranchID = @BranchID,
             @Narrative = @Narrative, @SourceModule = 'CashVoucher', @SourceID = @CashVoucherID,
             @EntriesJson = @EntriesJson, @UserId = @UserId,
             @NewVoucherID = @LedgerID OUTPUT, @NewVoucherNo = @LedgerNo OUTPUT;

        IF @CashVoucherID IS NULL
        BEGIN
            INSERT INTO dbo.CashVouchers (Direction, VoucherDate, CashAccountID, BranchID, Narrative, TotalAmount,
                                          VoucherID, VoucherNo, FinancialYearID, Status, PostedBy, PostedAt, CreatedBy)
            SELECT @Direction, @VoucherDate, @CashAccountID, @BranchID, @Narrative, @Total,
                   @LedgerID, @LedgerNo, v.FinancialYearID, 'Posted', @UserId, SYSUTCDATETIME(), @UserId
            FROM dbo.Vouchers v WHERE v.VoucherID = @LedgerID;
            SET @CashVoucherID = CAST(SCOPE_IDENTITY() AS INT);
        END
        ELSE
        BEGIN
            UPDATE dbo.CashVouchers
               SET CashAccountID = @CashAccountID, Narrative = @Narrative, TotalAmount = @Total,
                   VoucherID = @LedgerID, VoucherNo = @LedgerNo,
                   UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @UserId
             WHERE CashVoucherID = @CashVoucherID;
            DELETE FROM dbo.CashVoucherLines WHERE CashVoucherID = @CashVoucherID;
        END

        -- the document id exists only after the header insert; complete the integration link
        UPDATE dbo.Vouchers SET SourceID = @CashVoucherID WHERE VoucherID = @LedgerID;

        INSERT INTO dbo.CashVoucherLines (CashVoucherID, AccountID, Description, Amount, TaxHeadID, KnockOff,
                                          BillRef, BillDate, DueDate, PartyMemberID, PartySupplierID, PartyStaffID, CreatedBy)
        SELECT @CashVoucherID, AccountID, Description, Amount, TaxHeadID, ISNULL(KnockOff, 0),
               NULLIF(BillRef, ''), BillDate, DueDate, PartyMemberID, PartySupplierID, PartyStaffID, @UserId
        FROM #DocLines;

        COMMIT TRANSACTION;
        SET @NewID = @CashVoucherID;
        SET @NewVoucherNo = @LedgerNo;
        SELECT @CashVoucherID AS CashVoucherID, @LedgerNo AS VoucherNo, @Total AS TotalAmount;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

/* ---------------- BANK VOUCHERS (Receipt / Payment) ---------------- */

CREATE OR ALTER PROCEDURE dbo.sp_FinanceDocuments_SaveBank
    @BankVoucherID  INT = NULL,
    @Direction      NVARCHAR(10),
    @VoucherDate    DATE,
    @BankAccountID  INT,
    @BranchID       INT,
    @Narrative      NVARCHAR(500) = NULL,
    @LinesJson      NVARCHAR(MAX),
    @UserId         INT = NULL,
    @NewID          INT OUTPUT,
    @NewVoucherNo   NVARCHAR(50) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF @Direction NOT IN ('Receipt','Payment')
            THROW 51051, 'Invalid bank voucher direction.', 1;

        DECLARE @ExistingDate DATE = NULL, @ExistingLedger INT = NULL, @Deleted BIT = NULL;
        IF @BankVoucherID IS NOT NULL
            SELECT @ExistingDate = VoucherDate, @ExistingLedger = VoucherID, @Deleted = IsDeleted
            FROM dbo.BankVouchers WHERE BankVoucherID = @BankVoucherID;

        IF @BankVoucherID IS NOT NULL AND @ExistingDate IS NULL
            THROW 51001, 'Bank voucher not found.', 1;
        IF @Deleted = 1
            THROW 51001, 'This bank voucher has been deleted.', 1;
        IF @ExistingDate IS NOT NULL AND @VoucherDate <> @ExistingDate
            THROW 51050, 'The voucher date cannot be changed after the voucher has been saved.', 1;

        IF NOT EXISTS (SELECT 1 FROM dbo.Accounts a
                       JOIN dbo.AccountTags t ON t.AccountID = a.AccountID AND t.Tag = 'Bank'
                       WHERE a.AccountID = @BankAccountID AND a.IsControl = 0 AND a.IsActive = 1 AND a.IsDeleted = 0)
            THROW 51052, 'Select an active Detail account tagged Bank.', 1;

        IF OBJECT_ID('tempdb..#DocLines') IS NOT NULL DROP TABLE #DocLines;
        CREATE TABLE #DocLines (
            RowNum INT IDENTITY(1,1) PRIMARY KEY,
            AccountID INT, Description NVARCHAR(500), Amount DECIMAL(18,2),
            TaxHeadID INT, KnockOff BIT, BillRef NVARCHAR(50), BillDate DATE, DueDate DATE,
            PartyMemberID INT, PartySupplierID INT, PartyStaffID INT);

        INSERT INTO #DocLines (AccountID, Description, Amount, TaxHeadID, KnockOff, BillRef, BillDate, DueDate, PartyMemberID, PartySupplierID, PartyStaffID)
        SELECT AccountID, Description, Amount, TaxHeadID,
               ISNULL(KnockOff, 0), BillRef, BillDate, DueDate, PartyMemberID, PartySupplierID, PartyStaffID
        FROM OPENJSON(@LinesJson)
        WITH (
            AccountID INT '$.AccountID',
            Description NVARCHAR(500) '$.Description',
            Amount DECIMAL(18,2) '$.Amount',
            TaxHeadID INT '$.TaxHeadID',
            KnockOff BIT '$.KnockOff',
            BillRef NVARCHAR(50) '$.BillRef',
            BillDate DATE '$.BillDate',
            DueDate DATE '$.DueDate',
            PartyMemberID INT '$.PartyMemberID',
            PartySupplierID INT '$.PartySupplierID',
            PartyStaffID INT '$.PartyStaffID'
        );

        IF NOT EXISTS (SELECT 1 FROM #DocLines)
            THROW 51057, 'Add at least one detail line.', 1;
        IF EXISTS (SELECT 1 FROM #DocLines WHERE AccountID IS NULL)
            THROW 51008, 'Every line must reference an account.', 1;
        IF EXISTS (SELECT 1 FROM #DocLines WHERE Amount IS NULL OR Amount <= 0)
            THROW 51053, 'Every line amount must be greater than zero.', 1;
        IF EXISTS (SELECT 1 FROM #DocLines l JOIN dbo.Accounts a ON a.AccountID = l.AccountID
                   WHERE a.IsControl = 1)
            THROW 51007, 'Control accounts cannot receive postings. Select Detail accounts only.', 1;
        IF EXISTS (SELECT 1 FROM #DocLines l JOIN dbo.Accounts a ON a.AccountID = l.AccountID
                   WHERE a.IsActive = 0 OR a.IsDeleted = 1)
            THROW 51008, 'One or more selected accounts are inactive or deleted.', 1;
        IF EXISTS (SELECT 1 FROM #DocLines l LEFT JOIN dbo.TaxHeads t ON t.TaxHeadID = l.TaxHeadID
                   WHERE l.TaxHeadID IS NOT NULL AND (t.TaxHeadID IS NULL OR t.IsActive = 0))
            THROW 51055, 'Invalid or inactive tax head on one or more lines.', 1;
        IF EXISTS (SELECT 1 FROM #DocLines l JOIN dbo.Accounts a ON a.AccountID = l.AccountID
                   WHERE ISNULL(l.KnockOff, 0) = 1 AND ISNULL(a.KnockOff, 0) = 0)
            THROW 51056, 'Knock Off is not enabled for one or more selected accounts.', 1;
        IF EXISTS (SELECT 1 FROM #DocLines l LEFT JOIN dbo.Members m ON m.MemberID = l.PartyMemberID
                   WHERE l.PartyMemberID IS NOT NULL AND m.MemberID IS NULL)
            THROW 51019, 'Invalid customer reference.', 1;
        IF EXISTS (SELECT 1 FROM #DocLines l LEFT JOIN dbo.Suppliers s ON s.SupplierID = l.PartySupplierID
                   WHERE l.PartySupplierID IS NOT NULL AND s.SupplierID IS NULL)
            THROW 51019, 'Invalid vendor reference.', 1;
        IF EXISTS (SELECT 1 FROM #DocLines l LEFT JOIN dbo.Staff st ON st.StaffID = l.PartyStaffID
                   WHERE l.PartyStaffID IS NOT NULL AND st.StaffID IS NULL)
            THROW 51019, 'Invalid employee reference.', 1;

        DECLARE @Total DECIMAL(18,2) = (SELECT ISNULL(SUM(Amount), 0) FROM #DocLines);
        IF @Total <= 0 THROW 51006, 'The voucher total must be greater than zero.', 1;

        IF @ExistingLedger IS NOT NULL
        BEGIN
            DECLARE @RevID INT, @RevNo NVARCHAR(50);
            EXEC dbo.sp_Accounting_ReverseCore
                 @VoucherID = @ExistingLedger, @ReversalDate = @ExistingDate,
                 @UserId = @UserId, @NewVoucherID = @RevID OUTPUT, @NewVoucherNo = @RevNo OUTPUT;
        END

        DECLARE @EntriesJson NVARCHAR(MAX);
        IF @Direction = 'Receipt'
            SET @EntriesJson = (
                SELECT * FROM (
                SELECT @BankAccountID AS AccountID, @Total AS Debit, 0 AS Credit,
                       @Narrative AS Narrative, NULL AS PartyMemberID, NULL AS PartySupplierID, NULL AS PartyStaffID,
                       NULL AS BillRef, NULL AS BillDate, NULL AS DueDate
                UNION ALL
                SELECT AccountID, 0 AS Debit, Amount AS Credit, Description AS Narrative,
                       PartyMemberID, PartySupplierID, PartyStaffID,
                       CASE WHEN KnockOff = 1 THEN NULLIF(BillRef,'') ELSE NULL END AS BillRef,
                       CASE WHEN KnockOff = 1 THEN BillDate ELSE NULL END AS BillDate,
                       CASE WHEN KnockOff = 1 THEN DueDate ELSE NULL END AS DueDate
                FROM #DocLines
                ) x
                FOR JSON PATH
            );
        ELSE
            SET @EntriesJson = (
                SELECT * FROM (
                SELECT AccountID, Amount AS Debit, 0 AS Credit, Description AS Narrative,
                       PartyMemberID, PartySupplierID, PartyStaffID,
                       CASE WHEN KnockOff = 1 THEN NULLIF(BillRef,'') ELSE NULL END AS BillRef,
                       CASE WHEN KnockOff = 1 THEN BillDate ELSE NULL END AS BillDate,
                       CASE WHEN KnockOff = 1 THEN DueDate ELSE NULL END AS DueDate
                FROM #DocLines
                UNION ALL
                SELECT @BankAccountID AS AccountID, 0 AS Debit, @Total AS Credit,
                       @Narrative AS Narrative, NULL AS PartyMemberID, NULL AS PartySupplierID, NULL AS PartyStaffID,
                       NULL AS BillRef, NULL AS BillDate, NULL AS DueDate
                ) x
                FOR JSON PATH
            );

        DECLARE @TypeCode NVARCHAR(10) = CASE WHEN @Direction = 'Receipt' THEN 'BRV' ELSE 'BPV' END;
        DECLARE @VoucherTypeID INT = (SELECT VoucherTypeID FROM dbo.VoucherTypes WHERE TypeCode = @TypeCode AND IsActive = 1);
        IF @VoucherTypeID IS NULL THROW 51021, 'Bank voucher type not found or inactive.', 1;

        DECLARE @LedgerID INT, @LedgerNo NVARCHAR(50);
        EXEC dbo.sp_Accounting_CreateAndPostCore
             @VoucherTypeID = @VoucherTypeID, @VoucherDate = @VoucherDate, @BranchID = @BranchID,
             @Narrative = @Narrative, @SourceModule = 'BankVoucher', @SourceID = @BankVoucherID,
             @EntriesJson = @EntriesJson, @UserId = @UserId,
             @NewVoucherID = @LedgerID OUTPUT, @NewVoucherNo = @LedgerNo OUTPUT;

        IF @BankVoucherID IS NULL
        BEGIN
            INSERT INTO dbo.BankVouchers (Direction, VoucherDate, BankAccountID, BranchID, Narrative, TotalAmount,
                                          VoucherID, VoucherNo, FinancialYearID, Status, PostedBy, PostedAt, CreatedBy)
            SELECT @Direction, @VoucherDate, @BankAccountID, @BranchID, @Narrative, @Total,
                   @LedgerID, @LedgerNo, v.FinancialYearID, 'Posted', @UserId, SYSUTCDATETIME(), @UserId
            FROM dbo.Vouchers v WHERE v.VoucherID = @LedgerID;
            SET @BankVoucherID = CAST(SCOPE_IDENTITY() AS INT);
        END
        ELSE
        BEGIN
            UPDATE dbo.BankVouchers
               SET BankAccountID = @BankAccountID, Narrative = @Narrative, TotalAmount = @Total,
                   VoucherID = @LedgerID, VoucherNo = @LedgerNo,
                   UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @UserId
             WHERE BankVoucherID = @BankVoucherID;
            DELETE FROM dbo.BankVoucherLines WHERE BankVoucherID = @BankVoucherID;
        END

        -- the document id exists only after the header insert; complete the integration link
        UPDATE dbo.Vouchers SET SourceID = @BankVoucherID WHERE VoucherID = @LedgerID;

        INSERT INTO dbo.BankVoucherLines (BankVoucherID, AccountID, Description, Amount, TaxHeadID, KnockOff,
                                          BillRef, BillDate, DueDate, PartyMemberID, PartySupplierID, PartyStaffID, CreatedBy)
        SELECT @BankVoucherID, AccountID, Description, Amount, TaxHeadID, ISNULL(KnockOff, 0),
               NULLIF(BillRef, ''), BillDate, DueDate, PartyMemberID, PartySupplierID, PartyStaffID, @UserId
        FROM #DocLines;

        COMMIT TRANSACTION;
        SET @NewID = @BankVoucherID;
        SET @NewVoucherNo = @LedgerNo;
        SELECT @BankVoucherID AS BankVoucherID, @LedgerNo AS VoucherNo, @Total AS TotalAmount;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

/* ---------------- JOURNAL VOUCHERS (explicit Dr / Cr) -------------- */

CREATE OR ALTER PROCEDURE dbo.sp_FinanceDocuments_SaveJournal
    @JournalVoucherID INT = NULL,
    @VoucherDate      DATE,
    @BranchID         INT,
    @Narrative        NVARCHAR(500) = NULL,
    @LinesJson        NVARCHAR(MAX),
    @UserId           INT = NULL,
    @NewID            INT OUTPUT,
    @NewVoucherNo     NVARCHAR(50) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @ExistingDate DATE = NULL, @ExistingLedger INT = NULL, @Deleted BIT = NULL;
        IF @JournalVoucherID IS NOT NULL
            SELECT @ExistingDate = VoucherDate, @ExistingLedger = VoucherID, @Deleted = IsDeleted
            FROM dbo.JournalVouchers WHERE JournalVoucherID = @JournalVoucherID;

        IF @JournalVoucherID IS NOT NULL AND @ExistingDate IS NULL
            THROW 51001, 'Journal voucher not found.', 1;
        IF @Deleted = 1
            THROW 51001, 'This journal voucher has been deleted.', 1;
        IF @ExistingDate IS NOT NULL AND @VoucherDate <> @ExistingDate
            THROW 51050, 'The voucher date cannot be changed after the voucher has been saved.', 1;

        IF OBJECT_ID('tempdb..#DocLines') IS NOT NULL DROP TABLE #DocLines;
        CREATE TABLE #DocLines (
            RowNum INT IDENTITY(1,1) PRIMARY KEY,
            AccountID INT, Debit DECIMAL(18,2), Credit DECIMAL(18,2), Description NVARCHAR(500));

        INSERT INTO #DocLines (AccountID, Debit, Credit, Description)
        SELECT AccountID, ISNULL(Debit, 0), ISNULL(Credit, 0), Description
        FROM OPENJSON(@LinesJson)
        WITH (
            AccountID INT '$.AccountID',
            Debit DECIMAL(18,2) '$.Debit',
            Credit DECIMAL(18,2) '$.Credit',
            Description NVARCHAR(500) '$.Description'
        );

        IF NOT EXISTS (SELECT 1 FROM #DocLines)
            THROW 51057, 'Add at least one detail line.', 1;
        IF EXISTS (SELECT 1 FROM #DocLines WHERE AccountID IS NULL)
            THROW 51008, 'Every line must reference an account.', 1;
        IF EXISTS (SELECT 1 FROM #DocLines WHERE Debit < 0 OR Credit < 0)
            THROW 51053, 'Line amounts cannot be negative.', 1;
        IF EXISTS (SELECT 1 FROM #DocLines WHERE Debit > 0 AND Credit > 0)
            THROW 51031, 'A line cannot have both debit and credit amounts.', 1;
        IF EXISTS (SELECT 1 FROM #DocLines WHERE Debit = 0 AND Credit = 0)
            THROW 51031, 'A line must have either a debit or a credit amount.', 1;
        IF EXISTS (SELECT 1 FROM #DocLines l JOIN dbo.Accounts a ON a.AccountID = l.AccountID
                   WHERE a.IsControl = 1)
            THROW 51007, 'Control accounts cannot receive postings. Select Detail accounts only.', 1;
        IF EXISTS (SELECT 1 FROM #DocLines l JOIN dbo.Accounts a ON a.AccountID = l.AccountID
                   WHERE a.IsActive = 0 OR a.IsDeleted = 1)
            THROW 51008, 'One or more selected accounts are inactive or deleted.', 1;

        DECLARE @Dr DECIMAL(18,2) = (SELECT ISNULL(SUM(Debit), 0) FROM #DocLines);
        DECLARE @Cr DECIMAL(18,2) = (SELECT ISNULL(SUM(Credit), 0) FROM #DocLines);
        IF @Dr <> @Cr
            THROW 51054, 'The journal voucher is not balanced: total debit and total credit must be equal.', 1;
        IF @Dr <= 0
            THROW 51054, 'The journal voucher is not balanced: debit and credit totals must be greater than zero.', 1;

        IF @ExistingLedger IS NOT NULL
        BEGIN
            DECLARE @RevID INT, @RevNo NVARCHAR(50);
            EXEC dbo.sp_Accounting_ReverseCore
                 @VoucherID = @ExistingLedger, @ReversalDate = @ExistingDate,
                 @UserId = @UserId, @NewVoucherID = @RevID OUTPUT, @NewVoucherNo = @RevNo OUTPUT;
        END

        DECLARE @EntriesJson NVARCHAR(MAX) = (
            SELECT AccountID, Debit, Credit, Description AS Narrative,
                   NULL AS PartyMemberID, NULL AS PartySupplierID, NULL AS PartyStaffID,
                   NULL AS BillRef, NULL AS BillDate, NULL AS DueDate
            FROM #DocLines
            FOR JSON PATH
        );

        DECLARE @VoucherTypeID INT = (SELECT VoucherTypeID FROM dbo.VoucherTypes WHERE TypeCode = 'JPV' AND IsActive = 1);
        IF @VoucherTypeID IS NULL THROW 51021, 'Journal voucher type not found or inactive.', 1;

        DECLARE @LedgerID INT, @LedgerNo NVARCHAR(50);
        EXEC dbo.sp_Accounting_CreateAndPostCore
             @VoucherTypeID = @VoucherTypeID, @VoucherDate = @VoucherDate, @BranchID = @BranchID,
             @Narrative = @Narrative, @SourceModule = 'JournalVoucher', @SourceID = @JournalVoucherID,
             @EntriesJson = @EntriesJson, @UserId = @UserId,
             @NewVoucherID = @LedgerID OUTPUT, @NewVoucherNo = @LedgerNo OUTPUT;

        IF @JournalVoucherID IS NULL
        BEGIN
            INSERT INTO dbo.JournalVouchers (VoucherDate, BranchID, Narrative, DebitTotal, CreditTotal,
                                             VoucherID, VoucherNo, FinancialYearID, Status, PostedBy, PostedAt, CreatedBy)
            SELECT @VoucherDate, @BranchID, @Narrative, @Dr, @Cr,
                   @LedgerID, @LedgerNo, v.FinancialYearID, 'Posted', @UserId, SYSUTCDATETIME(), @UserId
            FROM dbo.Vouchers v WHERE v.VoucherID = @LedgerID;
            SET @JournalVoucherID = CAST(SCOPE_IDENTITY() AS INT);
        END
        ELSE
        BEGIN
            UPDATE dbo.JournalVouchers
               SET Narrative = @Narrative, DebitTotal = @Dr, CreditTotal = @Cr,
                   VoucherID = @LedgerID, VoucherNo = @LedgerNo,
                   UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @UserId
             WHERE JournalVoucherID = @JournalVoucherID;
            DELETE FROM dbo.JournalVoucherLines WHERE JournalVoucherID = @JournalVoucherID;
        END

        -- the document id exists only after the header insert; complete the integration link
        UPDATE dbo.Vouchers SET SourceID = @JournalVoucherID WHERE VoucherID = @LedgerID;

        INSERT INTO dbo.JournalVoucherLines (JournalVoucherID, AccountID, Debit, Credit, Description, CreatedBy)
        SELECT @JournalVoucherID, AccountID, Debit, Credit, Description, @UserId
        FROM #DocLines;

        COMMIT TRANSACTION;
        SET @NewID = @JournalVoucherID;
        SET @NewVoucherNo = @LedgerNo;
        SELECT @JournalVoucherID AS JournalVoucherID, @LedgerNo AS VoucherNo, @Dr AS DebitTotal;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

/* ---------------- OPENING TRIAL BALANCE ---------------------------- */

CREATE OR ALTER PROCEDURE dbo.sp_FinanceDocuments_SaveOpeningTB
    @OpeningTBID    INT = NULL,
    @VoucherDate    DATE,
    @BranchID       INT,
    @Narrative      NVARCHAR(500) = NULL,
    @LinesJson      NVARCHAR(MAX),
    @UserId         INT = NULL,
    @NewID          INT OUTPUT,
    @NewVoucherNo   NVARCHAR(50) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @ExistingDate DATE = NULL, @ExistingLedger INT = NULL, @Deleted BIT = NULL;
        IF @OpeningTBID IS NOT NULL
            SELECT @ExistingDate = VoucherDate, @ExistingLedger = VoucherID, @Deleted = IsDeleted
            FROM dbo.OpeningTrialBalances WHERE OpeningTBID = @OpeningTBID;

        IF @OpeningTBID IS NOT NULL AND @ExistingDate IS NULL
            THROW 51001, 'Opening trial balance not found.', 1;
        IF @Deleted = 1
            THROW 51001, 'This opening trial balance has been deleted.', 1;
        IF @ExistingDate IS NOT NULL AND @VoucherDate <> @ExistingDate
            THROW 51050, 'The voucher date cannot be changed after the voucher has been saved.', 1;

        IF OBJECT_ID('tempdb..#DocLines') IS NOT NULL DROP TABLE #DocLines;
        CREATE TABLE #DocLines (
            RowNum INT IDENTITY(1,1) PRIMARY KEY,
            AccountID INT, Debit DECIMAL(18,2), Credit DECIMAL(18,2), Description NVARCHAR(500));

        INSERT INTO #DocLines (AccountID, Debit, Credit, Description)
        SELECT AccountID, ISNULL(Debit, 0), ISNULL(Credit, 0), Description
        FROM OPENJSON(@LinesJson)
        WITH (
            AccountID INT '$.AccountID',
            Debit DECIMAL(18,2) '$.Debit',
            Credit DECIMAL(18,2) '$.Credit',
            Description NVARCHAR(500) '$.Description'
        );

        IF NOT EXISTS (SELECT 1 FROM #DocLines)
            THROW 51057, 'Add at least one detail line.', 1;
        IF EXISTS (SELECT 1 FROM #DocLines WHERE AccountID IS NULL)
            THROW 51008, 'Every line must reference an account.', 1;
        IF EXISTS (SELECT 1 FROM #DocLines WHERE Debit < 0 OR Credit < 0)
            THROW 51053, 'Line amounts cannot be negative.', 1;
        IF EXISTS (SELECT 1 FROM #DocLines WHERE Debit > 0 AND Credit > 0)
            THROW 51031, 'A line cannot have both debit and credit amounts.', 1;
        IF EXISTS (SELECT 1 FROM #DocLines WHERE Debit = 0 AND Credit = 0)
            THROW 51031, 'A line must have either a debit or a credit amount.', 1;
        IF EXISTS (SELECT 1 FROM #DocLines l JOIN dbo.Accounts a ON a.AccountID = l.AccountID
                   WHERE a.IsControl = 1)
            THROW 51007, 'Control accounts cannot receive postings. Select Detail accounts only.', 1;
        IF EXISTS (SELECT 1 FROM #DocLines l JOIN dbo.Accounts a ON a.AccountID = l.AccountID
                   WHERE a.IsActive = 0 OR a.IsDeleted = 1)
            THROW 51008, 'One or more selected accounts are inactive or deleted.', 1;

        DECLARE @Dr DECIMAL(18,2) = (SELECT ISNULL(SUM(Debit), 0) FROM #DocLines);
        DECLARE @Cr DECIMAL(18,2) = (SELECT ISNULL(SUM(Credit), 0) FROM #DocLines);
        IF @Dr <> @Cr
            THROW 51054, 'The opening trial balance is not balanced: total debit and total credit must be equal.', 1;
        IF @Dr <= 0
            THROW 51054, 'The opening trial balance is not balanced: debit and credit totals must be greater than zero.', 1;

        IF @ExistingLedger IS NOT NULL
        BEGIN
            DECLARE @RevID INT, @RevNo NVARCHAR(50);
            EXEC dbo.sp_Accounting_ReverseCore
                 @VoucherID = @ExistingLedger, @ReversalDate = @ExistingDate,
                 @UserId = @UserId, @NewVoucherID = @RevID OUTPUT, @NewVoucherNo = @RevNo OUTPUT;
        END

        DECLARE @EntriesJson NVARCHAR(MAX) = (
            SELECT AccountID, Debit, Credit, Description AS Narrative,
                   NULL AS PartyMemberID, NULL AS PartySupplierID, NULL AS PartyStaffID,
                   NULL AS BillRef, NULL AS BillDate, NULL AS DueDate
            FROM #DocLines
            FOR JSON PATH
        );

        DECLARE @VoucherTypeID INT = (SELECT VoucherTypeID FROM dbo.VoucherTypes WHERE TypeCode = 'OPB' AND IsActive = 1);
        IF @VoucherTypeID IS NULL THROW 51021, 'Opening trial balance type not found or inactive.', 1;

        DECLARE @LedgerID INT, @LedgerNo NVARCHAR(50);
        EXEC dbo.sp_Accounting_CreateAndPostCore
             @VoucherTypeID = @VoucherTypeID, @VoucherDate = @VoucherDate, @BranchID = @BranchID,
             @Narrative = @Narrative, @SourceModule = 'OpeningTB', @SourceID = @OpeningTBID,
             @EntriesJson = @EntriesJson, @UserId = @UserId,
             @NewVoucherID = @LedgerID OUTPUT, @NewVoucherNo = @LedgerNo OUTPUT;

        IF @OpeningTBID IS NULL
        BEGIN
            INSERT INTO dbo.OpeningTrialBalances (VoucherDate, BranchID, Narrative, DebitTotal, CreditTotal,
                                                  VoucherID, VoucherNo, FinancialYearID, Status, PostedBy, PostedAt, CreatedBy)
            SELECT @VoucherDate, @BranchID, @Narrative, @Dr, @Cr,
                   @LedgerID, @LedgerNo, v.FinancialYearID, 'Posted', @UserId, SYSUTCDATETIME(), @UserId
            FROM dbo.Vouchers v WHERE v.VoucherID = @LedgerID;
            SET @OpeningTBID = CAST(SCOPE_IDENTITY() AS INT);
        END
        ELSE
        BEGIN
            UPDATE dbo.OpeningTrialBalances
               SET Narrative = @Narrative, DebitTotal = @Dr, CreditTotal = @Cr,
                   VoucherID = @LedgerID, VoucherNo = @LedgerNo,
                   UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @UserId
             WHERE OpeningTBID = @OpeningTBID;
            DELETE FROM dbo.OpeningTBLines WHERE OpeningTBID = @OpeningTBID;
        END

        -- the document id exists only after the header insert; complete the integration link
        UPDATE dbo.Vouchers SET SourceID = @OpeningTBID WHERE VoucherID = @LedgerID;

        INSERT INTO dbo.OpeningTBLines (OpeningTBID, AccountID, Debit, Credit, Description, CreatedBy)
        SELECT @OpeningTBID, AccountID, Debit, Credit, Description, @UserId
        FROM #DocLines;

        COMMIT TRANSACTION;
        SET @NewID = @OpeningTBID;
        SET @NewVoucherNo = @LedgerNo;
        SELECT @OpeningTBID AS OpeningTBID, @LedgerNo AS VoucherNo, @Dr AS DebitTotal;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
/* ================================================================== */
/* PART 5c — DOCUMENT LIST / GET / DELETE (family-parameterized)      */
/* ================================================================== */

CREATE OR ALTER PROCEDURE dbo.sp_FinanceDocuments_List
    @Family   NVARCHAR(10),                 -- CASH / BANK / JOURNAL / OTB
    @Page INT = 1, @PageSize INT = 15,
    @Direction NVARCHAR(10) = NULL,
    @Status NVARCHAR(20) = NULL,
    @BranchID INT = NULL,
    @FromDate DATE = NULL,
    @ToDate DATE = NULL,
    @Search NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Offset INT = (@Page - 1) * @PageSize;

    IF @Family = 'CASH'
    BEGIN
        SELECT  v.CashVoucherID AS ID, v.VoucherNo, v.VoucherDate, v.Direction, v.Narrative,
                v.TotalAmount AS Amount, v.TotalAmount AS DebitTotal, v.TotalAmount AS CreditTotal,
                v.Status, v.BranchID, b.Name AS BranchName,
                a.Code AS MoneyAccountCode, a.Title AS MoneyAccountTitle,
                u.FullName AS CreatedByName, v.CreatedAt
        FROM dbo.CashVouchers v
        JOIN dbo.Branches b ON b.BranchID = v.BranchID
        JOIN dbo.Accounts a ON a.AccountID = v.CashAccountID
        LEFT JOIN dbo.Users u ON u.UserID = v.CreatedBy
        WHERE v.IsDeleted = 0
          AND (@Direction IS NULL OR v.Direction = @Direction)
          AND (@Status IS NULL OR v.Status = @Status)
          AND (@BranchID IS NULL OR v.BranchID = @BranchID)
          AND (@FromDate IS NULL OR v.VoucherDate >= @FromDate)
          AND (@ToDate IS NULL OR v.VoucherDate <= @ToDate)
          AND (@Search IS NULL OR v.VoucherNo LIKE '%' + @Search + '%' OR v.Narrative LIKE '%' + @Search + '%')
        ORDER BY v.VoucherDate DESC, v.CashVoucherID DESC
        OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;

        SELECT COUNT(*) AS Total, ISNULL(SUM(v.TotalAmount), 0) AS TotalAmount
        FROM dbo.CashVouchers v
        WHERE v.IsDeleted = 0
          AND (@Direction IS NULL OR v.Direction = @Direction)
          AND (@Status IS NULL OR v.Status = @Status)
          AND (@BranchID IS NULL OR v.BranchID = @BranchID)
          AND (@FromDate IS NULL OR v.VoucherDate >= @FromDate)
          AND (@ToDate IS NULL OR v.VoucherDate <= @ToDate)
          AND (@Search IS NULL OR v.VoucherNo LIKE '%' + @Search + '%' OR v.Narrative LIKE '%' + @Search + '%');
    END
    ELSE IF @Family = 'BANK'
    BEGIN
        SELECT  v.BankVoucherID AS ID, v.VoucherNo, v.VoucherDate, v.Direction, v.Narrative,
                v.TotalAmount AS Amount, v.TotalAmount AS DebitTotal, v.TotalAmount AS CreditTotal,
                v.Status, v.BranchID, b.Name AS BranchName,
                a.Code AS MoneyAccountCode, a.Title AS MoneyAccountTitle,
                u.FullName AS CreatedByName, v.CreatedAt
        FROM dbo.BankVouchers v
        JOIN dbo.Branches b ON b.BranchID = v.BranchID
        JOIN dbo.Accounts a ON a.AccountID = v.BankAccountID
        LEFT JOIN dbo.Users u ON u.UserID = v.CreatedBy
        WHERE v.IsDeleted = 0
          AND (@Direction IS NULL OR v.Direction = @Direction)
          AND (@Status IS NULL OR v.Status = @Status)
          AND (@BranchID IS NULL OR v.BranchID = @BranchID)
          AND (@FromDate IS NULL OR v.VoucherDate >= @FromDate)
          AND (@ToDate IS NULL OR v.VoucherDate <= @ToDate)
          AND (@Search IS NULL OR v.VoucherNo LIKE '%' + @Search + '%' OR v.Narrative LIKE '%' + @Search + '%')
        ORDER BY v.VoucherDate DESC, v.BankVoucherID DESC
        OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;

        SELECT COUNT(*) AS Total, ISNULL(SUM(v.TotalAmount), 0) AS TotalAmount
        FROM dbo.BankVouchers v
        WHERE v.IsDeleted = 0
          AND (@Direction IS NULL OR v.Direction = @Direction)
          AND (@Status IS NULL OR v.Status = @Status)
          AND (@BranchID IS NULL OR v.BranchID = @BranchID)
          AND (@FromDate IS NULL OR v.VoucherDate >= @FromDate)
          AND (@ToDate IS NULL OR v.VoucherDate <= @ToDate)
          AND (@Search IS NULL OR v.VoucherNo LIKE '%' + @Search + '%' OR v.Narrative LIKE '%' + @Search + '%');
    END
    ELSE IF @Family = 'JOURNAL'
    BEGIN
        SELECT  v.JournalVoucherID AS ID, v.VoucherNo, v.VoucherDate, NULL AS Direction, v.Narrative,
                v.DebitTotal AS Amount, v.DebitTotal AS DebitTotal, v.CreditTotal AS CreditTotal,
                v.Status, v.BranchID, b.Name AS BranchName,
                NULL AS MoneyAccountCode, NULL AS MoneyAccountTitle,
                u.FullName AS CreatedByName, v.CreatedAt
        FROM dbo.JournalVouchers v
        JOIN dbo.Branches b ON b.BranchID = v.BranchID
        LEFT JOIN dbo.Users u ON u.UserID = v.CreatedBy
        WHERE v.IsDeleted = 0
          AND (@Status IS NULL OR v.Status = @Status)
          AND (@BranchID IS NULL OR v.BranchID = @BranchID)
          AND (@FromDate IS NULL OR v.VoucherDate >= @FromDate)
          AND (@ToDate IS NULL OR v.VoucherDate <= @ToDate)
          AND (@Search IS NULL OR v.VoucherNo LIKE '%' + @Search + '%' OR v.Narrative LIKE '%' + @Search + '%')
        ORDER BY v.VoucherDate DESC, v.JournalVoucherID DESC
        OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;

        SELECT COUNT(*) AS Total, ISNULL(SUM(v.DebitTotal), 0) AS TotalAmount
        FROM dbo.JournalVouchers v
        WHERE v.IsDeleted = 0
          AND (@Status IS NULL OR v.Status = @Status)
          AND (@BranchID IS NULL OR v.BranchID = @BranchID)
          AND (@FromDate IS NULL OR v.VoucherDate >= @FromDate)
          AND (@ToDate IS NULL OR v.VoucherDate <= @ToDate)
          AND (@Search IS NULL OR v.VoucherNo LIKE '%' + @Search + '%' OR v.Narrative LIKE '%' + @Search + '%');
    END
    ELSE IF @Family = 'OTB'
    BEGIN
        SELECT  v.OpeningTBID AS ID, v.VoucherNo, v.VoucherDate, NULL AS Direction, v.Narrative,
                v.DebitTotal AS Amount, v.DebitTotal AS DebitTotal, v.CreditTotal AS CreditTotal,
                v.Status, v.BranchID, b.Name AS BranchName,
                NULL AS MoneyAccountCode, NULL AS MoneyAccountTitle,
                u.FullName AS CreatedByName, v.CreatedAt
        FROM dbo.OpeningTrialBalances v
        JOIN dbo.Branches b ON b.BranchID = v.BranchID
        LEFT JOIN dbo.Users u ON u.UserID = v.CreatedBy
        WHERE v.IsDeleted = 0
          AND (@Status IS NULL OR v.Status = @Status)
          AND (@BranchID IS NULL OR v.BranchID = @BranchID)
          AND (@FromDate IS NULL OR v.VoucherDate >= @FromDate)
          AND (@ToDate IS NULL OR v.VoucherDate <= @ToDate)
          AND (@Search IS NULL OR v.VoucherNo LIKE '%' + @Search + '%' OR v.Narrative LIKE '%' + @Search + '%')
        ORDER BY v.VoucherDate DESC, v.OpeningTBID DESC
        OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;

        SELECT COUNT(*) AS Total, ISNULL(SUM(v.DebitTotal), 0) AS TotalAmount
        FROM dbo.OpeningTrialBalances v
        WHERE v.IsDeleted = 0
          AND (@Status IS NULL OR v.Status = @Status)
          AND (@BranchID IS NULL OR v.BranchID = @BranchID)
          AND (@FromDate IS NULL OR v.VoucherDate >= @FromDate)
          AND (@ToDate IS NULL OR v.VoucherDate <= @ToDate)
          AND (@Search IS NULL OR v.VoucherNo LIKE '%' + @Search + '%' OR v.Narrative LIKE '%' + @Search + '%');
    END
    ELSE
        THROW 51051, 'Invalid voucher family.', 1;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_FinanceDocuments_Get
    @Family NVARCHAR(10),
    @ID INT
AS
BEGIN
    SET NOCOUNT ON;

    IF @Family = 'CASH'
    BEGIN
        SELECT  v.CashVoucherID AS ID, v.VoucherNo, v.VoucherDate, v.Direction, v.Narrative,
                v.TotalAmount AS Amount, v.TotalAmount AS DebitTotal, v.TotalAmount AS CreditTotal,
                v.Status, v.BranchID, b.Name AS BranchName,
                v.CashAccountID AS MoneyAccountID, a.Code AS MoneyAccountCode, a.Title AS MoneyAccountTitle,
                v.LedgerVoucherNo, v.LedgerStatus, v.ReversedAt,
                u.FullName AS CreatedByName, v.CreatedAt
        FROM (
            SELECT v.*, lv.VoucherNo AS LedgerVoucherNo, lv.Status AS LedgerStatus
            FROM dbo.CashVouchers v
            LEFT JOIN dbo.Vouchers lv ON lv.VoucherID = v.VoucherID
        ) v
        JOIN dbo.Branches b ON b.BranchID = v.BranchID
        JOIN dbo.Accounts a ON a.AccountID = v.CashAccountID
        LEFT JOIN dbo.Users u ON u.UserID = v.CreatedBy
        WHERE v.CashVoucherID = @ID AND v.IsDeleted = 0;

        SELECT  l.CashVoucherLineID AS LineID, l.AccountID, a.Code AS AccountCode, a.Title AS AccountTitle,
                l.Description, l.Amount, CAST(NULL AS DECIMAL(18,2)) AS Debit, CAST(NULL AS DECIMAL(18,2)) AS Credit,
                l.TaxHeadID, t.Code AS TaxHeadCode, t.Name AS TaxHeadName, t.RatePercent AS TaxRatePercent,
                l.KnockOff, l.BillRef, l.BillDate, l.DueDate,
                l.PartyMemberID, m.FullName AS PartyMemberName,
                l.PartySupplierID, s.Name AS PartySupplierName,
                l.PartyStaffID, st.FullName AS PartyStaffName
        FROM dbo.CashVoucherLines l
        JOIN dbo.Accounts a ON a.AccountID = l.AccountID
        LEFT JOIN dbo.TaxHeads t ON t.TaxHeadID = l.TaxHeadID
        LEFT JOIN dbo.Members m ON m.MemberID = l.PartyMemberID
        LEFT JOIN dbo.Suppliers s ON s.SupplierID = l.PartySupplierID
        LEFT JOIN dbo.Staff st ON st.StaffID = l.PartyStaffID
        WHERE l.CashVoucherID = @ID
        ORDER BY l.CashVoucherLineID;
    END
    ELSE IF @Family = 'BANK'
    BEGIN
        SELECT  v.BankVoucherID AS ID, v.VoucherNo, v.VoucherDate, v.Direction, v.Narrative,
                v.TotalAmount AS Amount, v.TotalAmount AS DebitTotal, v.TotalAmount AS CreditTotal,
                v.Status, v.BranchID, b.Name AS BranchName,
                v.BankAccountID AS MoneyAccountID, a.Code AS MoneyAccountCode, a.Title AS MoneyAccountTitle,
                v.LedgerVoucherNo, v.LedgerStatus, v.ReversedAt,
                u.FullName AS CreatedByName, v.CreatedAt
        FROM (
            SELECT v.*, lv.VoucherNo AS LedgerVoucherNo, lv.Status AS LedgerStatus
            FROM dbo.BankVouchers v
            LEFT JOIN dbo.Vouchers lv ON lv.VoucherID = v.VoucherID
        ) v
        JOIN dbo.Branches b ON b.BranchID = v.BranchID
        JOIN dbo.Accounts a ON a.AccountID = v.BankAccountID
        LEFT JOIN dbo.Users u ON u.UserID = v.CreatedBy
        WHERE v.BankVoucherID = @ID AND v.IsDeleted = 0;

        SELECT  l.BankVoucherLineID AS LineID, l.AccountID, a.Code AS AccountCode, a.Title AS AccountTitle,
                l.Description, l.Amount, CAST(NULL AS DECIMAL(18,2)) AS Debit, CAST(NULL AS DECIMAL(18,2)) AS Credit,
                l.TaxHeadID, t.Code AS TaxHeadCode, t.Name AS TaxHeadName, t.RatePercent AS TaxRatePercent,
                l.KnockOff, l.BillRef, l.BillDate, l.DueDate,
                l.PartyMemberID, m.FullName AS PartyMemberName,
                l.PartySupplierID, s.Name AS PartySupplierName,
                l.PartyStaffID, st.FullName AS PartyStaffName
        FROM dbo.BankVoucherLines l
        JOIN dbo.Accounts a ON a.AccountID = l.AccountID
        LEFT JOIN dbo.TaxHeads t ON t.TaxHeadID = l.TaxHeadID
        LEFT JOIN dbo.Members m ON m.MemberID = l.PartyMemberID
        LEFT JOIN dbo.Suppliers s ON s.SupplierID = l.PartySupplierID
        LEFT JOIN dbo.Staff st ON st.StaffID = l.PartyStaffID
        WHERE l.BankVoucherID = @ID
        ORDER BY l.BankVoucherLineID;
    END
    ELSE IF @Family = 'JOURNAL'
    BEGIN
        SELECT  v.JournalVoucherID AS ID, v.VoucherNo, v.VoucherDate, NULL AS Direction, v.Narrative,
                v.DebitTotal AS Amount, v.DebitTotal AS DebitTotal, v.CreditTotal AS CreditTotal,
                v.Status, v.BranchID, b.Name AS BranchName,
                NULL AS MoneyAccountID, NULL AS MoneyAccountCode, NULL AS MoneyAccountTitle,
                v.LedgerVoucherNo, v.LedgerStatus, v.ReversedAt,
                u.FullName AS CreatedByName, v.CreatedAt
        FROM (
            SELECT v.*, lv.VoucherNo AS LedgerVoucherNo, lv.Status AS LedgerStatus
            FROM dbo.JournalVouchers v
            LEFT JOIN dbo.Vouchers lv ON lv.VoucherID = v.VoucherID
        ) v
        JOIN dbo.Branches b ON b.BranchID = v.BranchID
        LEFT JOIN dbo.Users u ON u.UserID = v.CreatedBy
        WHERE v.JournalVoucherID = @ID AND v.IsDeleted = 0;

        SELECT  l.JournalVoucherLineID AS LineID, l.AccountID, a.Code AS AccountCode, a.Title AS AccountTitle,
                l.Description, CAST(NULL AS DECIMAL(18,2)) AS Amount, l.Debit, l.Credit,
                CAST(NULL AS INT) AS TaxHeadID, CAST(NULL AS NVARCHAR(20)) AS TaxHeadCode, CAST(NULL AS NVARCHAR(150)) AS TaxHeadName, CAST(NULL AS DECIMAL(9,4)) AS TaxRatePercent,
                CAST(0 AS BIT) AS KnockOff, CAST(NULL AS NVARCHAR(50)) AS BillRef, CAST(NULL AS DATE) AS BillDate, CAST(NULL AS DATE) AS DueDate,
                CAST(NULL AS INT) AS PartyMemberID, CAST(NULL AS INT) AS PartySupplierID, CAST(NULL AS INT) AS PartyStaffID
        FROM dbo.JournalVoucherLines l
        JOIN dbo.Accounts a ON a.AccountID = l.AccountID
        WHERE l.JournalVoucherID = @ID
        ORDER BY l.JournalVoucherLineID;
    END
    ELSE IF @Family = 'OTB'
    BEGIN
        SELECT  v.OpeningTBID AS ID, v.VoucherNo, v.VoucherDate, NULL AS Direction, v.Narrative,
                v.DebitTotal AS Amount, v.DebitTotal AS DebitTotal, v.CreditTotal AS CreditTotal,
                v.Status, v.BranchID, b.Name AS BranchName,
                NULL AS MoneyAccountID, NULL AS MoneyAccountCode, NULL AS MoneyAccountTitle,
                v.LedgerVoucherNo, v.LedgerStatus, v.ReversedAt,
                u.FullName AS CreatedByName, v.CreatedAt
        FROM (
            SELECT v.*, lv.VoucherNo AS LedgerVoucherNo, lv.Status AS LedgerStatus
            FROM dbo.OpeningTrialBalances v
            LEFT JOIN dbo.Vouchers lv ON lv.VoucherID = v.VoucherID
        ) v
        JOIN dbo.Branches b ON b.BranchID = v.BranchID
        LEFT JOIN dbo.Users u ON u.UserID = v.CreatedBy
        WHERE v.OpeningTBID = @ID AND v.IsDeleted = 0;

        SELECT  l.OpeningTBLineID AS LineID, l.AccountID, a.Code AS AccountCode, a.Title AS AccountTitle,
                l.Description, CAST(NULL AS DECIMAL(18,2)) AS Amount, l.Debit, l.Credit,
                CAST(NULL AS INT) AS TaxHeadID, CAST(NULL AS NVARCHAR(20)) AS TaxHeadCode, CAST(NULL AS NVARCHAR(150)) AS TaxHeadName, CAST(NULL AS DECIMAL(9,4)) AS TaxRatePercent,
                CAST(0 AS BIT) AS KnockOff, CAST(NULL AS NVARCHAR(50)) AS BillRef, CAST(NULL AS DATE) AS BillDate, CAST(NULL AS DATE) AS DueDate,
                CAST(NULL AS INT) AS PartyMemberID, CAST(NULL AS INT) AS PartySupplierID, CAST(NULL AS INT) AS PartyStaffID
        FROM dbo.OpeningTBLines l
        JOIN dbo.Accounts a ON a.AccountID = l.AccountID
        WHERE l.OpeningTBID = @ID
        ORDER BY l.OpeningTBLineID;
    END
    ELSE
        THROW 51051, 'Invalid voucher family.', 1;
END
GO

/* Delete = soft delete the document + reverse the linked ledger voucher.
   Accounting history is never physically removed. */
CREATE OR ALTER PROCEDURE dbo.sp_FinanceDocuments_Delete
    @Family NVARCHAR(10),
    @ID INT,
    @UserId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @LedgerID INT = NULL, @DocDate DATE = NULL;

        IF @Family = 'CASH'
        BEGIN
            SELECT @LedgerID = VoucherID, @DocDate = VoucherDate FROM dbo.CashVouchers
            WHERE CashVoucherID = @ID AND IsDeleted = 0;
            IF @LedgerID IS NULL THROW 51001, 'Cash voucher not found.', 1;
            UPDATE dbo.CashVouchers
               SET IsDeleted = 1, Status = 'Reversed', ReversedBy = @UserId, ReversedAt = SYSUTCDATETIME(),
                   UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @UserId
             WHERE CashVoucherID = @ID;
        END
        ELSE IF @Family = 'BANK'
        BEGIN
            SELECT @LedgerID = VoucherID, @DocDate = VoucherDate FROM dbo.BankVouchers
            WHERE BankVoucherID = @ID AND IsDeleted = 0;
            IF @LedgerID IS NULL THROW 51001, 'Bank voucher not found.', 1;
            UPDATE dbo.BankVouchers
               SET IsDeleted = 1, Status = 'Reversed', ReversedBy = @UserId, ReversedAt = SYSUTCDATETIME(),
                   UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @UserId
             WHERE BankVoucherID = @ID;
        END
        ELSE IF @Family = 'JOURNAL'
        BEGIN
            SELECT @LedgerID = VoucherID, @DocDate = VoucherDate FROM dbo.JournalVouchers
            WHERE JournalVoucherID = @ID AND IsDeleted = 0;
            IF @LedgerID IS NULL THROW 51001, 'Journal voucher not found.', 1;
            UPDATE dbo.JournalVouchers
               SET IsDeleted = 1, Status = 'Reversed', ReversedBy = @UserId, ReversedAt = SYSUTCDATETIME(),
                   UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @UserId
             WHERE JournalVoucherID = @ID;
        END
        ELSE IF @Family = 'OTB'
        BEGIN
            SELECT @LedgerID = VoucherID, @DocDate = VoucherDate FROM dbo.OpeningTrialBalances
            WHERE OpeningTBID = @ID AND IsDeleted = 0;
            IF @LedgerID IS NULL THROW 51001, 'Opening trial balance not found.', 1;
            UPDATE dbo.OpeningTrialBalances
               SET IsDeleted = 1, Status = 'Reversed', ReversedBy = @UserId, ReversedAt = SYSUTCDATETIME(),
                   UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @UserId
             WHERE OpeningTBID = @ID;
        END
        ELSE
            THROW 51051, 'Invalid voucher family.', 1;

        IF @LedgerID IS NOT NULL
        BEGIN
            DECLARE @RevID INT, @RevNo NVARCHAR(50);
            DECLARE @LedgerStatus NVARCHAR(20) = (SELECT Status FROM dbo.Vouchers WHERE VoucherID = @LedgerID);
            IF @LedgerStatus = 'Posted'
                EXEC dbo.sp_Accounting_ReverseCore
                     @VoucherID = @LedgerID, @ReversalDate = @DocDate,
                     @UserId = @UserId, @NewVoucherID = @RevID OUTPUT, @NewVoucherNo = @RevNo OUTPUT;
        END

        COMMIT TRANSACTION;
        SELECT 'OK' AS Result;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

/* ================================================================== */
/* PART 6 — DASHBOARD SPs REWRITTEN OFF THE LEDGER                    */
/* ================================================================== */

CREATE OR ALTER PROCEDURE dbo.sp_Dashboard_Stats
    @BranchID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @TotalMembers INT, @ActiveMembers INT, @ExpiredMembers INT, @NewMembers INT;
    DECLARE @TodayAttendance INT, @MonthlyIncome DECIMAL(18,2), @MonthlyExpenses DECIMAL(18,2);
    DECLARE @PendingFees DECIMAL(18,2), @SalaryDue DECIMAL(18,2), @RentDue DECIMAL(18,2);
    DECLARE @EquipmentMaintenance INT, @MembershipExpiryAlerts INT;

    SELECT @TotalMembers  = COUNT(*) FROM Members WHERE IsDeleted = 0 AND (@BranchID IS NULL OR BranchID = @BranchID);
    SELECT @ActiveMembers = COUNT(*) FROM Members WHERE IsDeleted = 0 AND Status = 'Active' AND (@BranchID IS NULL OR BranchID = @BranchID);
    SELECT @ExpiredMembers = COUNT(*) FROM Members WHERE IsDeleted = 0 AND Status = 'Expired' AND (@BranchID IS NULL OR BranchID = @BranchID);
    SELECT @NewMembers = COUNT(*) FROM Members WHERE IsDeleted = 0 AND MONTH(JoiningDate) = MONTH(GETDATE()) AND YEAR(JoiningDate) = YEAR(GETDATE()) AND (@BranchID IS NULL OR BranchID = @BranchID);

    SELECT @TodayAttendance = COUNT(*) FROM Attendance WHERE CAST(CheckInTime AS DATE) = CAST(GETDATE() AS DATE) AND (@BranchID IS NULL OR BranchID = @BranchID);

    SELECT @MonthlyIncome = ISNULL(SUM(Amount),0) FROM FeeCollections
     WHERE MONTH(CollectedAt) = MONTH(GETDATE()) AND YEAR(CollectedAt) = YEAR(GETDATE())
       AND IsDeleted = 0 AND (@BranchID IS NULL OR BranchID = @BranchID);

    -- Expenses now come from the accounting ledger (Expense detail accounts)
    SELECT @MonthlyExpenses = ISNULL(SUM(e.Debit - e.Credit), 0)
    FROM dbo.VoucherEntries e
    JOIN dbo.Vouchers v ON v.VoucherID = e.VoucherID
         AND v.Status IN ('Posted','Reversed') AND v.IsDeleted = 0
         AND MONTH(v.VoucherDate) = MONTH(GETDATE()) AND YEAR(v.VoucherDate) = YEAR(GETDATE())
         AND (@BranchID IS NULL OR v.BranchID = @BranchID)
    JOIN dbo.Accounts a ON a.AccountID = e.AccountID AND a.IsControl = 0 AND a.AccountType = 'Expense';

    SELECT @PendingFees = ISNULL(SUM(NetAmount - PaidAmount),0) FROM Invoices
     WHERE Status IN ('Unpaid','Partial') AND IsDeleted = 0
       AND (@BranchID IS NULL OR MemberID IN (SELECT MemberID FROM Members WHERE BranchID = @BranchID));

    SELECT @SalaryDue = ISNULL(SUM(p.BaseSalary + p.Bonus + p.Overtime + p.Commission - p.LeaveDeduction),0)
    FROM Payroll p JOIN Staff s ON s.StaffID = p.StaffID
    WHERE p.Status = 'Generated' AND p.[Month] = MONTH(GETDATE()) AND p.[Year] = YEAR(GETDATE())
      AND (@BranchID IS NULL OR s.BranchID = @BranchID);

    -- Rent due: from the ledger, on the account mapped to the Rent expense category
    DECLARE @RentAccountID INT = (
        SELECT AccountID FROM dbo.FinanceMappings
        WHERE MappingType = 'ExpenseCategory' AND SourceKey = 'Rent' AND IsActive = 1);
    SET @RentDue = 0;
    IF @RentAccountID IS NOT NULL
        SELECT @RentDue = ISNULL(SUM(e.Debit - e.Credit), 0)
        FROM dbo.VoucherEntries e
        JOIN dbo.Vouchers v ON v.VoucherID = e.VoucherID
             AND v.Status IN ('Posted','Reversed') AND v.IsDeleted = 0
             AND v.VoucherDate <= EOMONTH(GETDATE())
             AND (@BranchID IS NULL OR v.BranchID = @BranchID)
        WHERE e.AccountID = @RentAccountID;

    SELECT @EquipmentMaintenance = COUNT(*) FROM Equipment
     WHERE Status = 'Maintenance' AND IsDeleted = 0 AND (@BranchID IS NULL OR BranchID = @BranchID);

    SELECT @MembershipExpiryAlerts = COUNT(*)
    FROM MemberMemberships mm JOIN Members m ON m.MemberID = mm.MemberID
    WHERE mm.Status = 'Active' AND DATEDIFF(DAY, GETDATE(), mm.EndDate) <= 7
      AND (@BranchID IS NULL OR m.BranchID = @BranchID);

    SELECT  @TotalMembers AS TotalMembers, @ActiveMembers AS ActiveMembers,
            @ExpiredMembers AS ExpiredMembers, @NewMembers AS NewMembers,
            @TodayAttendance AS TodayAttendance, @MonthlyIncome AS MonthlyIncome,
            @MonthlyExpenses AS MonthlyExpenses, @PendingFees AS PendingFees,
            @SalaryDue AS SalaryDue, @RentDue AS RentDue,
            @EquipmentMaintenance AS EquipmentUnderMaintenance,
            @MembershipExpiryAlerts AS MembershipExpiryAlerts;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_Dashboard_Charts
    @Months INT = 6,
    @BranchID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Start DATE = DATEADD(MONTH, -@Months + 1, DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1));

    -- Revenue per month (FeeCollections)
    SELECT  FORMAT(d.DateMonth, 'yyyy-MM') AS [Month],
            ISNULL(SUM(fc.Amount), 0) AS Revenue
    FROM    (SELECT TOP (@Months) DATEADD(MONTH, NUMBER, @Start) AS DateMonth
             FROM master..spt_values WHERE type='P' ORDER BY NUMBER) d
    LEFT JOIN FeeCollections fc ON FORMAT(fc.CollectedAt,'yyyy-MM') = FORMAT(d.DateMonth,'yyyy-MM')
                                AND fc.IsDeleted = 0
                                AND (@BranchID IS NULL OR fc.BranchID = @BranchID)
    GROUP BY d.DateMonth
    ORDER BY d.DateMonth;

    -- Expenses per month (accounting ledger: Expense detail accounts)
    SELECT  FORMAT(d.DateMonth, 'yyyy-MM') AS [Month],
            ISNULL(SUM(e.Amount), 0) AS Expenses
    FROM    (SELECT TOP (@Months) DATEADD(MONTH, NUMBER, @Start) AS DateMonth
             FROM master..spt_values WHERE type='P' ORDER BY NUMBER) d
    LEFT JOIN (
        SELECT CAST(v.VoucherDate AS DATE) AS ExpenseDate, e.Debit - e.Credit AS Amount, v.BranchID
        FROM dbo.VoucherEntries e
        JOIN dbo.Vouchers v ON v.VoucherID = e.VoucherID
             AND v.Status IN ('Posted','Reversed') AND v.IsDeleted = 0
        JOIN dbo.Accounts a ON a.AccountID = e.AccountID AND a.IsControl = 0 AND a.AccountType = 'Expense'
    ) e ON FORMAT(e.ExpenseDate,'yyyy-MM') = FORMAT(d.DateMonth,'yyyy-MM')
        AND e.Amount <> 0
        AND (@BranchID IS NULL OR e.BranchID = @BranchID)
    GROUP BY d.DateMonth
    ORDER BY d.DateMonth;

    -- Attendance per day (last 14 days)
    SELECT  FORMAT(d.DateDay, 'yyyy-MM-dd') AS [Date],
            ISNULL(COUNT(a.AttendanceID),0) AS Attendance
    FROM    (SELECT TOP (14) DATEADD(DAY, NUMBER*-1, CAST(GETDATE() AS DATE)) AS DateDay
             FROM master..spt_values WHERE type='P' ORDER BY NUMBER DESC) d
    LEFT JOIN Attendance a ON CAST(a.CheckInTime AS DATE) = d.DateDay
                           AND (@BranchID IS NULL OR a.BranchID = @BranchID)
    GROUP BY d.DateDay
    ORDER BY d.DateDay;

    -- Membership growth per month (cumulative)
    SELECT  FORMAT(d.DateMonth,'yyyy-MM') AS [Month],
            (SELECT COUNT(*) FROM Members m
              WHERE m.JoiningDate <= EOMONTH(d.DateMonth) AND m.IsDeleted = 0
                AND (@BranchID IS NULL OR m.BranchID = @BranchID)) AS TotalMembers
    FROM    (SELECT TOP (@Months) DATEADD(MONTH, NUMBER, @Start) AS DateMonth
             FROM master..spt_values WHERE type='P' ORDER BY NUMBER) d
    ORDER BY d.DateMonth;
END;
GO

PRINT '=== 14_finance_rework.sql applied successfully. ===';
GO
/* ================================================================== */
/* PART 7 — KNOCK-OFF SUPPORT IN COA CRUD + LISTING                   */
/* ================================================================== */

CREATE OR ALTER PROCEDURE dbo.sp_FinanceAccounts_List
    @Search      NVARCHAR(100) = NULL,
    @AccountType NVARCHAR(20)  = NULL,
    @IsControl   BIT           = NULL,
    @IsActive    BIT           = NULL,
    @Tag         NVARCHAR(30)  = NULL,
    @IncludeDeleted BIT        = 0
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  a.AccountID, a.Code, a.Title, a.AccountType, a.ParentAccountID,
            p.Code AS ParentCode, p.Title AS ParentTitle,
            a.LevelNo, a.IsControl, a.IsActive, a.IsDeleted,
            ISNULL(a.KnockOff, 0) AS KnockOff,
            a.CreatedAt, a.UpdatedAt,
            STUFF((SELECT ',' + t.Tag FROM dbo.AccountTags t
                   WHERE t.AccountID = a.AccountID ORDER BY t.Tag FOR XML PATH('')), 1, 1, '') AS Tags,
            CASE WHEN EXISTS (SELECT 1 FROM dbo.VoucherEntries e WHERE e.AccountID = a.AccountID)
                 THEN 1 ELSE 0 END AS HasTransactions,
            (SELECT COUNT(*) FROM dbo.Accounts c WHERE c.ParentAccountID = a.AccountID AND c.IsDeleted = 0) AS ChildCount
    FROM    dbo.Accounts a
    LEFT JOIN dbo.Accounts p ON p.AccountID = a.ParentAccountID
    WHERE   (@IncludeDeleted = 1 OR a.IsDeleted = 0)
      AND   (@Search IS NULL OR a.Code LIKE '%' + @Search + '%' OR a.Title LIKE '%' + @Search + '%')
      AND   (@AccountType IS NULL OR a.AccountType = @AccountType)
      AND   (@IsControl IS NULL OR a.IsControl = @IsControl)
      AND   (@IsActive IS NULL OR a.IsActive = @IsActive)
      AND   (@Tag IS NULL OR EXISTS (SELECT 1 FROM dbo.AccountTags t WHERE t.AccountID = a.AccountID AND t.Tag = @Tag))
    ORDER BY a.Code;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_FinanceAccounts_Get
    @AccountID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  a.AccountID, a.Code, a.Title, a.AccountType, a.ParentAccountID,
            p.Code AS ParentCode, p.Title AS ParentTitle,
            a.LevelNo, a.IsControl, a.IsActive, a.IsDeleted, ISNULL(a.KnockOff, 0) AS KnockOff,
            a.CreatedAt, a.UpdatedAt,
            CASE WHEN EXISTS (SELECT 1 FROM dbo.VoucherEntries e WHERE e.AccountID = a.AccountID)
                 THEN 1 ELSE 0 END AS HasTransactions
    FROM dbo.Accounts a
    LEFT JOIN dbo.Accounts p ON p.AccountID = a.ParentAccountID
    WHERE a.AccountID = @AccountID;

    SELECT Tag FROM dbo.AccountTags WHERE AccountID = @AccountID ORDER BY Tag;

    SELECT c.AccountID, c.Code, c.Title, c.AccountType, c.IsControl, c.IsActive
    FROM dbo.Accounts c
    WHERE c.ParentAccountID = @AccountID AND c.IsDeleted = 0
    ORDER BY c.Code;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_FinanceAccounts_Create
    @Code        NVARCHAR(12),
    @Title       NVARCHAR(150),
    @AccountType NVARCHAR(20),
    @ParentAccountID INT = NULL,
    @IsControl   BIT = 1,
    @KnockOff    BIT = 0,
    @TagsJson    NVARCHAR(MAX) = NULL,
    @CreatedBy   INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @C NVARCHAR(12) = LTRIM(RTRIM(@Code));

        IF @C IS NULL OR @C NOT LIKE '[0-9]%' OR @C LIKE '%[^0-9]%'
            THROW 51012, 'Account code must contain digits only.', 1;
        IF LEN(@C) > 12
            THROW 51012, 'Account code cannot exceed 12 digits.', 1;
        IF EXISTS (SELECT 1 FROM dbo.Accounts WHERE Code = @C AND IsDeleted = 0)
            THROW 51011, 'An account with this code already exists.', 1;
        IF @AccountType NOT IN ('Asset','Liability','Capital','Revenue','Expense')
            THROW 51012, 'Invalid account type.', 1;
        IF @KnockOff = 1 AND @IsControl = 1
            THROW 51012, 'Knock Off applies to Detail (posting) accounts only.', 1;

        DECLARE @LevelNo INT = NULL;
        SELECT @LevelNo = p.LevelNo
        FROM dbo.FinanceCoaLevels l
        JOIN (SELECT l3.LevelNo, (SELECT SUM(Digits) FROM dbo.FinanceCoaLevels l4 WHERE l4.LevelNo <= l3.LevelNo) AS Cum
              FROM dbo.FinanceCoaLevels l3) p ON p.LevelNo = l.LevelNo
        WHERE p.Cum = LEN(@C);

        IF @LevelNo IS NULL
            THROW 51012, 'Account code length does not match any configured COA level. Review the COA structure in Finance Defaults.', 1;

        DECLARE @ParentLevel INT = NULL, @ParentType NVARCHAR(20) = NULL, @ParentIsControl BIT = NULL;
        IF @ParentAccountID IS NOT NULL
        BEGIN
            SELECT @ParentLevel = LevelNo, @ParentType = AccountType, @ParentIsControl = IsControl
            FROM dbo.Accounts WHERE AccountID = @ParentAccountID AND IsDeleted = 0;

            IF @ParentLevel IS NULL
                THROW 51008, 'Parent account not found.', 1;
            IF @ParentLevel + 1 <> @LevelNo
                THROW 51012, 'Child account code/level does not sit directly below its parent.', 1;
            IF LEFT(@C, LEN((SELECT Code FROM dbo.Accounts WHERE AccountID = @ParentAccountID))) <>
               (SELECT Code FROM dbo.Accounts WHERE AccountID = @ParentAccountID)
                THROW 51012, 'Child account code must start with its parent account code.', 1;
            IF @ParentType <> @AccountType
                THROW 51012, 'Child account type must match its parent account type.', 1;
            IF @ParentIsControl = 0
                THROW 51012, 'Cannot create a child account under a Detail (posting) account.', 1;
        END
        ELSE IF @LevelNo <> 1
            THROW 51012, 'Root accounts must use the first level code length.', 1;

        INSERT INTO dbo.Accounts (Code, Title, AccountType, ParentAccountID, LevelNo, IsControl, KnockOff, CreatedBy)
        VALUES (@C, LTRIM(RTRIM(@Title)), @AccountType, @ParentAccountID, @LevelNo, @IsControl, @KnockOff, @CreatedBy);

        DECLARE @NewID INT = CAST(SCOPE_IDENTITY() AS INT);

        IF @TagsJson IS NOT NULL
            INSERT INTO dbo.AccountTags (AccountID, Tag)
            SELECT DISTINCT @NewID, LTRIM(RTRIM(CAST([value] AS NVARCHAR(30))))
            FROM OPENJSON(@TagsJson)
            WHERE LTRIM(RTRIM(CAST([value] AS NVARCHAR(30)))) <> '';

        COMMIT TRANSACTION;
        SELECT @NewID AS AccountID, @C AS Code, @LevelNo AS LevelNo;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_FinanceAccounts_Update
    @AccountID INT,
    @Title     NVARCHAR(150),
    @KnockOff  BIT = NULL,
    @TagsJson  NVARCHAR(MAX) = NULL,
    @UpdatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        IF NOT EXISTS (SELECT 1 FROM dbo.Accounts WHERE AccountID = @AccountID AND IsDeleted = 0)
            THROW 51008, 'Account not found.', 1;

        IF @KnockOff IS NOT NULL
           AND EXISTS (SELECT 1 FROM dbo.Accounts WHERE AccountID = @AccountID AND IsControl = 1)
           AND @KnockOff = 1
            THROW 51012, 'Knock Off applies to Detail (posting) accounts only.', 1;

        UPDATE dbo.Accounts
           SET Title = LTRIM(RTRIM(@Title)),
               KnockOff = COALESCE(@KnockOff, KnockOff),
               UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @UpdatedBy
        WHERE AccountID = @AccountID;

        IF @TagsJson IS NOT NULL
        BEGIN
            DELETE FROM dbo.AccountTags WHERE AccountID = @AccountID;
            INSERT INTO dbo.AccountTags (AccountID, Tag)
            SELECT DISTINCT @AccountID, LTRIM(RTRIM(CAST([value] AS NVARCHAR(30))))
            FROM OPENJSON(@TagsJson)
            WHERE LTRIM(RTRIM(CAST([value] AS NVARCHAR(30)))) <> '';
        END

        COMMIT TRANSACTION;
        SELECT 'OK' AS Result;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

PRINT '=== 14_finance_rework.sql (COA knock-off support) applied. ===';
GO

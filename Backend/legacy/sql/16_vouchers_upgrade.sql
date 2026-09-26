/* ============================================================================
   CONTOURA LABS — VOUCHER UPGRADE (16_vouchers_upgrade.sql)
   ----------------------------------------------------------------------------
   Idempotent. Run AFTER 15_coa_enhancement.sql. JV untouched.

   - Cash/Bank voucher lines: Tax Account, Tax %, Tax Amount, Cheque No /
     Status / Title, Reference Number.
   - Document statuses: Draft / Hold / Posted / Reversed
     (Draft + Hold have NO ledger/accounting effect until posted).
   - FinanceLineAllocations: bill-wise knock-off allocations per line.
   - New voucher number format: PREFIX + BR(2) + MM(2) + YY(2) + SEQ(5)
     e.g. CRV01092600001 — concurrency-safe via FinanceSequences,
     unique index enforced. Scope: type + branch + month.
   - Save SPs: Draft/Hold save without ledger effect; Posted save replaces
     the previous ledger effect atomically (same voucher number kept).
   - sp_FinanceDocuments_Post: Draft/Hold -> Posted, transactional.
   - Allocation save/reverse SPs.
   ============================================================================ */

/* ------------------------------------------------------------------ */
/* 1. LINE COLUMNS (cash + bank)                                       */
/* ------------------------------------------------------------------ */
IF COL_LENGTH('dbo.CashVoucherLines', 'TaxAccountID') IS NULL
    ALTER TABLE dbo.CashVoucherLines ADD TaxAccountID INT NULL FOREIGN KEY REFERENCES dbo.Accounts(AccountID);
GO
IF COL_LENGTH('dbo.CashVoucherLines', 'TaxPercent') IS NULL
    ALTER TABLE dbo.CashVoucherLines ADD TaxPercent DECIMAL(9,4) NULL;
GO
IF COL_LENGTH('dbo.CashVoucherLines', 'TaxAmount') IS NULL
    ALTER TABLE dbo.CashVoucherLines ADD TaxAmount DECIMAL(18,2) NULL;
GO
IF COL_LENGTH('dbo.CashVoucherLines', 'ChequeNo') IS NULL
    ALTER TABLE dbo.CashVoucherLines ADD ChequeNo NVARCHAR(50) NULL;
GO
IF COL_LENGTH('dbo.CashVoucherLines', 'ChequeStatus') IS NULL
    ALTER TABLE dbo.CashVoucherLines ADD ChequeStatus NVARCHAR(20) NULL
        CHECK (ChequeStatus IN (N'Hold', N'Pending', N'Cleared', N'Bounced', N'Cancelled'));
GO
IF COL_LENGTH('dbo.CashVoucherLines', 'ChequeTitle') IS NULL
    ALTER TABLE dbo.CashVoucherLines ADD ChequeTitle NVARCHAR(150) NULL;
GO
IF COL_LENGTH('dbo.CashVoucherLines', 'ReferenceNo') IS NULL
    ALTER TABLE dbo.CashVoucherLines ADD ReferenceNo NVARCHAR(50) NULL;
GO
IF COL_LENGTH('dbo.BankVoucherLines', 'TaxAccountID') IS NULL
    ALTER TABLE dbo.BankVoucherLines ADD TaxAccountID INT NULL FOREIGN KEY REFERENCES dbo.Accounts(AccountID);
GO
IF COL_LENGTH('dbo.BankVoucherLines', 'TaxPercent') IS NULL
    ALTER TABLE dbo.BankVoucherLines ADD TaxPercent DECIMAL(9,4) NULL;
GO
IF COL_LENGTH('dbo.BankVoucherLines', 'TaxAmount') IS NULL
    ALTER TABLE dbo.BankVoucherLines ADD TaxAmount DECIMAL(18,2) NULL;
GO
IF COL_LENGTH('dbo.BankVoucherLines', 'ChequeNo') IS NULL
    ALTER TABLE dbo.BankVoucherLines ADD ChequeNo NVARCHAR(50) NULL;
GO
IF COL_LENGTH('dbo.BankVoucherLines', 'ChequeStatus') IS NULL
    ALTER TABLE dbo.BankVoucherLines ADD ChequeStatus NVARCHAR(20) NULL
        CHECK (ChequeStatus IN (N'Hold', N'Pending', N'Cleared', N'Bounced', N'Cancelled'));
GO
IF COL_LENGTH('dbo.BankVoucherLines', 'ChequeTitle') IS NULL
    ALTER TABLE dbo.BankVoucherLines ADD ChequeTitle NVARCHAR(150) NULL;
GO
IF COL_LENGTH('dbo.BankVoucherLines', 'ReferenceNo') IS NULL
    ALTER TABLE dbo.BankVoucherLines ADD ReferenceNo NVARCHAR(50) NULL;
GO

/* ------------------------------------------------------------------ */
/* 2. DOCUMENT STATUS: Draft / Hold / Posted / Reversed                */
/* ------------------------------------------------------------------ */
DECLARE @sql NVARCHAR(MAX) = N'';
SELECT @sql = STRING_AGG(
    N'ALTER TABLE ' + QUOTENAME(SCHEMA_NAME(t.schema_id)) + N'.' + QUOTENAME(t.name)
    + N' DROP CONSTRAINT ' + QUOTENAME(cc.name), N'; ')
FROM sys.check_constraints cc
JOIN sys.tables t ON t.object_id = cc.parent_object_id
WHERE t.name IN ('CashVouchers','BankVouchers')
  AND cc.definition LIKE '%Posted%' AND cc.definition LIKE '%Reversed%'
  AND cc.definition NOT LIKE '%Draft%';
IF @sql IS NOT NULL EXEC(@sql);
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE parent_object_id = OBJECT_ID('dbo.CashVouchers') AND definition LIKE '%Draft%')
    ALTER TABLE dbo.CashVouchers ADD CONSTRAINT CK_CashVouchers_Status
        CHECK (Status IN ('Draft','Hold','Posted','Reversed'));
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE parent_object_id = OBJECT_ID('dbo.BankVouchers') AND definition LIKE '%Draft%')
    ALTER TABLE dbo.BankVouchers ADD CONSTRAINT CK_BankVouchers_Status
        CHECK (Status IN ('Draft','Hold','Posted','Reversed'));
GO
/* default 'Posted' already exists from the original CREATE TABLE */
GO

/* ------------------------------------------------------------------ */
/* 3. KNOCK-OFF ALLOCATIONS                                            */
/* ------------------------------------------------------------------ */
IF OBJECT_ID('dbo.FinanceLineAllocations', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.FinanceLineAllocations (
        AllocationID    BIGINT IDENTITY(1,1) PRIMARY KEY,
        Family          NVARCHAR(10) NOT NULL,
        DocumentID      INT NOT NULL,
        LineID          BIGINT NOT NULL,
        BillRef         NVARCHAR(50) NOT NULL,
        PartyMemberID   INT NULL FOREIGN KEY REFERENCES dbo.Members(MemberID),
        PartySupplierID INT NULL FOREIGN KEY REFERENCES dbo.Suppliers(SupplierID),
        Amount          DECIMAL(18,2) NOT NULL CHECK (Amount > 0),
        IsReversed      BIT NOT NULL DEFAULT 0,
        CreatedAt       DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CreatedBy       INT NULL
    );
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_FinanceLineAllocations_Doc' AND object_id = OBJECT_ID('dbo.FinanceLineAllocations'))
    CREATE INDEX IX_FinanceLineAllocations_Doc ON dbo.FinanceLineAllocations(Family, DocumentID, IsReversed);
GO

PRINT '=== 16_vouchers_upgrade.sql (schema) applied. ===';
GO
/* ================================================================== */
/* 4. NUMBERING: PREFIX + BR(2) + MM(2) + YY(2) + SEQ(5)              */
/* Scope: voucher type + branch + month. Concurrency-safe via          */
/* FinanceSequences UPDLOCK. Explicit number reuse on posted edits.    */
/* ================================================================== */
CREATE OR ALTER PROCEDURE dbo.sp_Accounting_PostCore
    @VoucherID INT,
    @PostedBy  INT,
    @VoucherNo NVARCHAR(50) OUTPUT,
    @ExplicitVoucherNo NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Type INT, @Nature NVARCHAR(20), @TenderTag NVARCHAR(30), @Status NVARCHAR(20),
            @VDate DATE, @BranchID INT, @RevOf INT, @Prefix NVARCHAR(10);
    SELECT  @Type = v.VoucherTypeID, @Nature = t.Nature, @TenderTag = t.TenderTag,
            @Status = v.Status, @VDate = v.VoucherDate, @BranchID = v.BranchID, @RevOf = v.ReversalOfVoucherID,
            @Prefix = t.Prefix
    FROM    dbo.Vouchers v WITH (UPDLOCK, HOLDLOCK)
    JOIN    dbo.VoucherTypes t ON t.VoucherTypeID = v.VoucherTypeID
    WHERE   v.VoucherID = @VoucherID AND v.IsDeleted = 0;

    IF @Type IS NULL  THROW 51001, 'Voucher not found.', 1;
    IF @Status <> 'Draft' THROW 51003, 'Voucher is already posted or reversed.', 1;

    DECLARE @Lines INT, @Dr DECIMAL(18,2), @Cr DECIMAL(18,2);
    SELECT @Lines = COUNT(*), @Dr = ISNULL(SUM(Debit), 0), @Cr = ISNULL(SUM(Credit), 0)
    FROM dbo.VoucherEntries WHERE VoucherID = @VoucherID;

    IF @Lines < 2 THROW 51005, 'A posted voucher must contain at least two entries.', 1;
    IF @Dr <> @Cr THROW 51004, 'Debit and credit totals do not match.', 1;
    IF @Dr <= 0 THROW 51006, 'Debit total must be greater than zero.', 1;

    DECLARE @FYID INT;
    SELECT @FYID = FinancialYearID FROM dbo.FinancialYears WHERE @VDate BETWEEN StartDate AND EndDate;
    IF @FYID IS NULL THROW 51015, 'No financial year covers the voucher date.', 1;
    IF (SELECT Status FROM dbo.FinancialYears WHERE FinancialYearID = @FYID) <> 'Open'
        THROW 51016, 'The financial year is locked or closed.', 1;

    DECLARE @PeriodID INT;
    SELECT @PeriodID = PeriodID FROM dbo.AccountingPeriods
    WHERE FinancialYearID = @FYID AND @VDate BETWEEN StartDate AND EndDate;
    IF @PeriodID IS NULL THROW 51017, 'No accounting period covers the voucher date.', 1;
    IF (SELECT Status FROM dbo.AccountingPeriods WHERE PeriodID = @PeriodID) <> 'Open'
        THROW 51017, 'The accounting period is closed or locked.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Branches WHERE BranchID = @BranchID AND IsActive = 1 AND IsDeleted = 0)
        THROW 51018, 'Invalid or inactive branch.', 1;

    IF EXISTS (SELECT 1 FROM dbo.VoucherEntries e JOIN dbo.Accounts a ON a.AccountID = e.AccountID
               WHERE e.VoucherID = @VoucherID AND (a.IsControl = 1 OR a.IsActive = 0 OR a.IsDeleted = 1))
        THROW 51007, 'All entries must target active Detail accounts.', 1;

    IF @Nature = 'Receipt' AND @TenderTag IS NOT NULL AND @RevOf IS NULL
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM dbo.VoucherEntries e
                       JOIN dbo.AccountTags tg ON tg.AccountID = e.AccountID AND tg.Tag = @TenderTag
                       WHERE e.VoucherID = @VoucherID AND e.Debit > 0)
            THROW 51039, 'The receipt side (debit) must include an account tagged Cash or Bank.', 1;
        IF EXISTS (SELECT 1 FROM dbo.VoucherEntries e JOIN dbo.Accounts a ON a.AccountID = e.AccountID
                   WHERE e.VoucherID = @VoucherID AND e.Debit > 0
                     AND NOT EXISTS (SELECT 1 FROM dbo.AccountTags tg WHERE tg.AccountID = a.AccountID AND tg.Tag = @TenderTag))
            THROW 51039, 'Every debit account of this voucher type must be tagged Cash or Bank.', 1;
    END
    IF @Nature = 'Payment' AND @TenderTag IS NOT NULL AND @RevOf IS NULL
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM dbo.VoucherEntries e
                       JOIN dbo.AccountTags tg ON tg.AccountID = e.AccountID AND tg.Tag = @TenderTag
                       WHERE e.VoucherID = @VoucherID AND e.Credit > 0)
            THROW 51039, 'The payment side (credit) must include an account tagged Cash or Bank.', 1;
        IF EXISTS (SELECT 1 FROM dbo.VoucherEntries e JOIN dbo.Accounts a ON a.AccountID = e.AccountID
                   WHERE e.VoucherID = @VoucherID AND e.Credit > 0
                     AND NOT EXISTS (SELECT 1 FROM dbo.AccountTags tg WHERE tg.AccountID = a.AccountID AND tg.Tag = @TenderTag))
            THROW 51039, 'Every credit account of this voucher type must be tagged Cash or Bank.', 1;
    END

    SELECT @VoucherNo = VoucherNo FROM dbo.Vouchers WHERE VoucherID = @VoucherID;
    IF @VoucherNo IS NULL
    BEGIN
        IF @ExplicitVoucherNo IS NOT NULL
        BEGIN
            IF EXISTS (SELECT 1 FROM dbo.Vouchers WHERE VoucherNo = @ExplicitVoucherNo)
                THROW 51001, 'The explicit voucher number is already in use.', 1;
            SET @VoucherNo = @ExplicitVoucherNo;
        END
        ELSE
        BEGIN
            DECLARE @Branch2 NVARCHAR(2) = RIGHT('00' + CAST(@BranchID AS NVARCHAR(10)), 2);
            DECLARE @MM NVARCHAR(2) = FORMAT(@VDate, 'MM');
            DECLARE @YY NVARCHAR(2) = RIGHT(CAST(YEAR(@VDate) AS NVARCHAR(4)), 2);
            DECLARE @YM NVARCHAR(6) = FORMAT(@VDate, 'yyyyMM');
            DECLARE @Scope NVARCHAR(60) = 'VT' + CAST(@Type AS NVARCHAR(10)) + '-BR' + CAST(@BranchID AS NVARCHAR(10)) + '-YM' + @YM;
            DECLARE @Seq INT = NULL;

            UPDATE s SET @Seq = s.NextSeq, s.NextSeq = s.NextSeq + 1, s.UpdatedAt = SYSUTCDATETIME()
            FROM dbo.FinanceSequences s WITH (UPDLOCK, HOLDLOCK)
            WHERE s.ScopeKey = @Scope;

            IF @Seq IS NULL
            BEGIN
                INSERT INTO dbo.FinanceSequences (ScopeKey, NextSeq) VALUES (@Scope, 2);
                SET @Seq = 1;
            END

            SET @VoucherNo = @Prefix + @Branch2 + @MM + @YY + RIGHT(REPLICATE('0', 10) + CAST(@Seq AS NVARCHAR(10)), 5);
        END

        IF EXISTS (SELECT 1 FROM dbo.Vouchers WHERE VoucherNo = @VoucherNo)
            THROW 51001, 'Generated voucher number already exists.', 1;
        UPDATE dbo.Vouchers SET VoucherNo = @VoucherNo WHERE VoucherID = @VoucherID;
    END

    UPDATE dbo.VoucherTypes SET PrefixLocked = 1
     WHERE VoucherTypeID = @Type AND PrefixLocked = 0
       AND EXISTS (SELECT 1 FROM dbo.Vouchers v2 WHERE v2.VoucherTypeID = @Type AND v2.Status IN ('Posted','Reversed'));

    UPDATE dbo.Vouchers
       SET Status = 'Posted', FinancialYearID = @FYID, DebitTotal = @Dr, CreditTotal = @Cr,
           PostedBy = @PostedBy, PostedAt = SYSUTCDATETIME(),
           UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @PostedBy
     WHERE VoucherID = @VoucherID;

    DECLARE @PeriodNo INT = (SELECT PeriodNo FROM dbo.AccountingPeriods WHERE PeriodID = @PeriodID);
    ;WITH agg AS (SELECT AccountID, SUM(Debit) AS D, SUM(Credit) AS C
                  FROM dbo.VoucherEntries WHERE VoucherID = @VoucherID GROUP BY AccountID)
    MERGE dbo.AccountBalances WITH (HOLDLOCK) AS t
    USING agg AS s ON t.AccountID = s.AccountID AND t.FinancialYearID = @FYID AND t.PeriodNo = @PeriodNo
    WHEN MATCHED THEN UPDATE SET DebitTotal = t.DebitTotal + s.D, CreditTotal = t.CreditTotal + s.C, UpdatedAt = SYSUTCDATETIME()
    WHEN NOT MATCHED THEN INSERT (AccountID, FinancialYearID, PeriodNo, DebitTotal, CreditTotal)
        VALUES (s.AccountID, @FYID, @PeriodNo, s.D, s.C);
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_Accounting_CreateAndPostCore
    @VoucherTypeID INT, @VoucherDate DATE, @BranchID INT,
    @Narrative NVARCHAR(500) = NULL, @SourceModule NVARCHAR(50) = NULL, @SourceID INT = NULL,
    @ReversalOfVoucherID INT = NULL, @EntriesJson NVARCHAR(MAX), @UserId INT = NULL,
    @ExplicitVoucherNo NVARCHAR(50) = NULL,
    @NewVoucherID INT OUTPUT, @NewVoucherNo NVARCHAR(50) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ID INT = NULL;
    EXEC dbo.sp_FinanceVouchers_SaveDraftCore
         @VoucherID = @ID OUTPUT, @VoucherTypeID = @VoucherTypeID, @VoucherDate = @VoucherDate,
         @BranchID = @BranchID, @Narrative = @Narrative, @EntriesJson = @EntriesJson, @UserId = @UserId;
    UPDATE dbo.Vouchers SET SourceModule = @SourceModule, SourceID = @SourceID,
           ReversalOfVoucherID = @ReversalOfVoucherID WHERE VoucherID = @ID;
    DECLARE @No NVARCHAR(50);
    EXEC dbo.sp_Accounting_PostCore @VoucherID = @ID, @PostedBy = @UserId,
         @VoucherNo = @No OUTPUT, @ExplicitVoucherNo = @ExplicitVoucherNo;
    SET @NewVoucherID = @ID;
    SET @NewVoucherNo = @No;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_Accounting_CreateAndPostVoucher
    @VoucherTypeID INT, @VoucherDate DATE, @BranchID INT,
    @Narrative NVARCHAR(500) = NULL, @SourceModule NVARCHAR(50) = NULL, @SourceID INT = NULL,
    @ReversalOfVoucherID INT = NULL, @EntriesJson NVARCHAR(MAX), @UserId INT = NULL
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
             @ReversalOfVoucherID = @ReversalOfVoucherID, @EntriesJson = @EntriesJson, @UserId = @UserId,
             @NewVoucherID = @ID OUTPUT, @NewVoucherNo = @No OUTPUT;
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
    @VoucherID INT, @ReversalDate DATE, @Narrative NVARCHAR(500) = NULL, @UserId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @ID INT, @No NVARCHAR(50);
        EXEC dbo.sp_Accounting_ReverseCore @VoucherID = @VoucherID, @ReversalDate = @ReversalDate,
             @Narrative = @Narrative, @UserId = @UserId, @NewVoucherID = @ID OUTPUT, @NewVoucherNo = @No OUTPUT;
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
/* 5. SAVE SPs v2 — statuses, tax, cheque, ref, posted-edit replace   */
/* ================================================================== */

/* ---------------- CASH VOUCHERS ------------------------------------ */
CREATE OR ALTER PROCEDURE dbo.sp_FinanceDocuments_SaveCash
    @CashVoucherID  INT = NULL,
    @Status         NVARCHAR(20) = 'Posted',
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

        IF @Status NOT IN ('Draft','Hold','Posted')
            THROW 51064, 'Invalid voucher status. Use Draft, Hold or Posted.', 1;
        IF @Direction NOT IN ('Receipt','Payment')
            THROW 51051, 'Invalid cash voucher direction.', 1;
        IF LEN(@Narrative) > 200
            THROW 51012, 'Voucher description cannot exceed 200 characters.', 1;

        DECLARE @ExistingDate DATE = NULL, @ExistingLedger INT = NULL,
                @Deleted BIT = NULL, @ExistingStatus NVARCHAR(20) = NULL, @OldNo NVARCHAR(50) = NULL;
        IF @CashVoucherID IS NOT NULL
            SELECT @ExistingDate = VoucherDate, @ExistingLedger = VoucherID,
                   @Deleted = IsDeleted, @ExistingStatus = Status, @OldNo = VoucherNo
            FROM dbo.CashVouchers WHERE CashVoucherID = @CashVoucherID;

        IF @CashVoucherID IS NOT NULL AND @ExistingDate IS NULL
            THROW 51001, 'Cash voucher not found.', 1;
        IF @Deleted = 1
            THROW 51001, 'This cash voucher has been deleted.', 1;

        /* posted vouchers keep their identity; drafts/holds may change freely */
        IF @ExistingDate IS NOT NULL AND @VoucherDate <> @ExistingDate
            THROW 51050, 'The voucher date cannot be changed after the voucher has been saved.', 1;

        IF NOT EXISTS (SELECT 1 FROM dbo.Accounts a
                       WHERE a.AccountID = @CashAccountID AND a.BookType = N'Cash Book'
                         AND a.IsControl = 0 AND a.IsActive = 1 AND a.IsDeleted = 0
                         AND (a.BranchID IS NULL OR a.BranchID = @BranchID))
            THROW 51052, 'Select an active Cash Book account available to this branch.', 1;

        IF OBJECT_ID('tempdb..#DocLines') IS NOT NULL DROP TABLE #DocLines;
        CREATE TABLE #DocLines (
            RowNum INT IDENTITY(1,1) PRIMARY KEY,
            AccountID INT, Description NVARCHAR(500), Amount DECIMAL(18,2),
            TaxAccountID INT, TaxPercent DECIMAL(9,4), TaxAmount DECIMAL(18,2),
            TaxHeadID INT,
            ChequeNo NVARCHAR(50), ChequeStatus NVARCHAR(20), ChequeTitle NVARCHAR(150),
            ReferenceNo NVARCHAR(50),
            KnockOff BIT, BillRef NVARCHAR(50), BillDate DATE, DueDate DATE,
            PartyMemberID INT, PartySupplierID INT, PartyStaffID INT);

        INSERT INTO #DocLines (AccountID, Description, Amount, TaxAccountID, TaxPercent, TaxAmount, TaxHeadID,
                               ChequeNo, ChequeStatus, ChequeTitle, ReferenceNo,
                               KnockOff, BillRef, BillDate, DueDate, PartyMemberID, PartySupplierID, PartyStaffID)
        SELECT AccountID, Description, Amount, TaxAccountID, TaxPercent, TaxAmount, TaxHeadID,
               ChequeNo, ChequeStatus, ChequeTitle, ReferenceNo,
               ISNULL(KnockOff, 0), BillRef, BillDate, DueDate, PartyMemberID, PartySupplierID, PartyStaffID
        FROM OPENJSON(@LinesJson)
        WITH (
            AccountID INT '$.AccountID',
            Description NVARCHAR(500) '$.Description',
            Amount DECIMAL(18,2) '$.Amount',
            TaxAccountID INT '$.TaxAccountID',
            TaxPercent DECIMAL(9,4) '$.TaxPercent',
            TaxAmount DECIMAL(18,2) '$.TaxAmount',
            TaxHeadID INT '$.TaxHeadID',
            ChequeNo NVARCHAR(50) '$.ChequeNo',
            ChequeStatus NVARCHAR(20) '$.ChequeStatus',
            ChequeTitle NVARCHAR(150) '$.ChequeTitle',
            ReferenceNo NVARCHAR(50) '$.ReferenceNo',
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
        /* branch visibility of line accounts (Rule 17/18) */
        IF EXISTS (SELECT 1 FROM #DocLines l JOIN dbo.Accounts a ON a.AccountID = l.AccountID
                   WHERE a.BranchID IS NOT NULL AND a.BranchID <> @BranchID)
            THROW 51063, 'One or more selected accounts are not available for this branch.', 1;
        /* tax rules (Part 8/9/21) */
        IF EXISTS (SELECT 1 FROM #DocLines
                   WHERE (ISNULL(TaxPercent, 0) > 0 OR ISNULL(TaxAmount, 0) > 0) AND TaxAccountID IS NULL)
            THROW 51060, 'Tax Account is mandatory when tax percentage or tax amount is entered.', 1;
        IF EXISTS (SELECT 1 FROM #DocLines WHERE TaxPercent IS NOT NULL AND (TaxPercent < 0 OR TaxPercent > 100))
            THROW 51065, 'Tax Percentage must be between 0 and 100.', 1;
        IF EXISTS (SELECT 1 FROM #DocLines WHERE TaxAmount IS NOT NULL AND TaxAmount < 0)
            THROW 51053, 'Tax amount cannot be negative.', 1;
        IF EXISTS (SELECT 1 FROM #DocLines l LEFT JOIN dbo.TaxHeads t ON t.TaxHeadID = l.TaxHeadID
                   WHERE l.TaxHeadID IS NOT NULL AND (t.TaxHeadID IS NULL OR t.IsActive = 0))
            THROW 51055, 'Invalid or inactive tax head on one or more lines.', 1;
        IF EXISTS (SELECT 1 FROM #DocLines l
                   JOIN dbo.Accounts a ON a.AccountID = l.TaxAccountID
                   WHERE l.TaxAccountID IS NOT NULL AND (a.IsControl = 1 OR a.IsActive = 0 OR a.IsDeleted = 1
                         OR NOT EXISTS (SELECT 1 FROM dbo.AccountTags tg WHERE tg.AccountID = a.AccountID AND tg.Tag = N'Tax')))
            THROW 51062, 'Tax Account must be an active Detail account tagged Tax (from the Tax File).', 1;
        IF EXISTS (SELECT 1 FROM #DocLines
                   WHERE ChequeStatus IS NOT NULL
                     AND ChequeStatus NOT IN (N'Hold', N'Pending', N'Cleared', N'Bounced', N'Cancelled'))
            THROW 51061, 'Invalid cheque status. Use Hold, Pending, Cleared, Bounced or Cancelled.', 1;
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

        /* posted edit: replace the previous ledger effect, keeping the number */
        DECLARE @PostedEdit BIT = 0;
        IF @ExistingStatus = 'Posted' AND @Status = 'Posted'
        BEGIN
            SET @PostedEdit = 1;
            IF EXISTS (SELECT 1 FROM dbo.BankReconciliationLines l
                       JOIN dbo.VoucherEntries e ON e.EntryID = l.VoucherEntryID
                       WHERE e.VoucherID = @ExistingLedger)
                THROW 51059, 'This voucher has reconciled entries and cannot be edited.', 1;

            ;WITH agg AS (SELECT e.AccountID, SUM(e.Debit) AS D, SUM(e.Credit) AS C
                          FROM dbo.VoucherEntries e WHERE e.VoucherID = @ExistingLedger GROUP BY e.AccountID)
            UPDATE ab
               SET ab.DebitTotal = ab.DebitTotal - agg.D, ab.CreditTotal = ab.CreditTotal - agg.C,
                   ab.UpdatedAt = SYSUTCDATETIME()
            FROM dbo.AccountBalances ab
            JOIN agg ON agg.AccountID = ab.AccountID
            JOIN dbo.Vouchers v ON v.VoucherID = @ExistingLedger
            WHERE ab.FinancialYearID = v.FinancialYearID
              AND ab.PeriodNo = (SELECT PeriodNo FROM dbo.AccountingPeriods p
                                 JOIN dbo.Vouchers v2 ON v2.FinancialYearID = p.FinancialYearID
                                 WHERE v2.VoucherID = @ExistingLedger
                                   AND v2.VoucherDate BETWEEN p.StartDate AND p.EndDate);

            UPDATE dbo.CashVouchers SET VoucherID = NULL WHERE CashVoucherID = @CashVoucherID;
            DELETE FROM dbo.VoucherEntries WHERE VoucherID = @ExistingLedger;
            DELETE FROM dbo.Vouchers WHERE VoucherID = @ExistingLedger;
            UPDATE dbo.FinanceLineAllocations SET IsReversed = 1
             WHERE Family = 'CASH' AND DocumentID = @CashVoucherID;
        END

        IF @Status = 'Posted'
        BEGIN
            DECLARE @EntriesJson NVARCHAR(MAX);
            IF @Direction = 'Receipt'
                SET @EntriesJson = (
                    SELECT * FROM (
                        SELECT @CashAccountID AS AccountID, @Total AS Debit, 0 AS Credit,
                               @Narrative AS Narrative, NULL AS PartyMemberID, NULL AS PartySupplierID,
                               NULL AS PartyStaffID, NULL AS BillRef, NULL AS BillDate, NULL AS DueDate
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
                               @Narrative AS Narrative, NULL AS PartyMemberID, NULL AS PartySupplierID,
                               NULL AS PartyStaffID, NULL AS BillRef, NULL AS BillDate, NULL AS DueDate
                        FROM #DocLines
                    ) x
                    FOR JSON PATH
                );

            DECLARE @TypeCode NVARCHAR(10) = CASE WHEN @Direction = 'Receipt' THEN 'CRV' ELSE 'CPV' END;
            DECLARE @VoucherTypeID INT = (SELECT VoucherTypeID FROM dbo.VoucherTypes WHERE TypeCode = @TypeCode AND IsActive = 1);
            IF @VoucherTypeID IS NULL THROW 51021, 'Cash voucher type not found or inactive.', 1;

            DECLARE @LedgerID INT, @LedgerNo NVARCHAR(50);
            DECLARE @ExplicitNo NVARCHAR(50) = CASE WHEN @PostedEdit = 1 THEN @OldNo ELSE NULL END;
            EXEC dbo.sp_Accounting_CreateAndPostCore
                 @VoucherTypeID = @VoucherTypeID, @VoucherDate = @VoucherDate, @BranchID = @BranchID,
                 @Narrative = @Narrative, @SourceModule = 'CashVoucher', @SourceID = @CashVoucherID,
                 @EntriesJson = @EntriesJson, @UserId = @UserId, @ExplicitVoucherNo = @ExplicitNo,
                 @NewVoucherID = @LedgerID OUTPUT, @NewVoucherNo = @LedgerNo OUTPUT;
        END

        IF @CashVoucherID IS NULL
        BEGIN
            DECLARE @LedgerFY INT = CASE WHEN @Status = 'Posted'
                THEN (SELECT FinancialYearID FROM dbo.Vouchers WHERE VoucherID = @LedgerID) END;
            INSERT INTO dbo.CashVouchers (Direction, VoucherDate, CashAccountID, BranchID, Narrative, TotalAmount,
                                          VoucherID, VoucherNo, FinancialYearID, Status, PostedBy, PostedAt, CreatedBy)
            VALUES (@Direction, @VoucherDate, @CashAccountID, @BranchID, @Narrative, @Total,
                    CASE WHEN @Status = 'Posted' THEN @LedgerID END,
                    CASE WHEN @Status = 'Posted' THEN @LedgerNo END,
                    @LedgerFY, @Status,
                    CASE WHEN @Status = 'Posted' THEN @UserId END,
                    CASE WHEN @Status = 'Posted' THEN SYSUTCDATETIME() END,
                    @UserId);
            SET @CashVoucherID = CAST(SCOPE_IDENTITY() AS INT);
            UPDATE dbo.Vouchers SET SourceID = @CashVoucherID WHERE VoucherID = @LedgerID;
        END
        ELSE
        BEGIN
            UPDATE dbo.CashVouchers
               SET CashAccountID = @CashAccountID, Narrative = @Narrative, TotalAmount = @Total,
                   VoucherID = CASE WHEN @Status = 'Posted' THEN @LedgerID ELSE VoucherID END,
                   VoucherNo = CASE WHEN @Status = 'Posted' THEN @LedgerNo ELSE VoucherNo END,
                   Status = @Status,
                   ReversedBy = NULL, ReversedAt = NULL,
                   UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @UserId
             WHERE CashVoucherID = @CashVoucherID;
            DELETE FROM dbo.CashVoucherLines WHERE CashVoucherID = @CashVoucherID;
        END

        INSERT INTO dbo.CashVoucherLines (CashVoucherID, AccountID, Description, Amount, TaxHeadID,
                                          TaxAccountID, TaxPercent, TaxAmount,
                                          ChequeNo, ChequeStatus, ChequeTitle, ReferenceNo,
                                          KnockOff, BillRef, BillDate, DueDate,
                                          PartyMemberID, PartySupplierID, PartyStaffID, CreatedBy)
        SELECT @CashVoucherID, AccountID, Description, Amount, TaxHeadID,
               TaxAccountID, TaxPercent, TaxAmount,
               NULLIF(ChequeNo, ''), ChequeStatus, NULLIF(ChequeTitle, ''), NULLIF(ReferenceNo, ''),
               ISNULL(KnockOff, 0), NULLIF(BillRef, ''), BillDate, DueDate,
               PartyMemberID, PartySupplierID, PartyStaffID, @UserId
        FROM #DocLines;

        COMMIT TRANSACTION;
        SET @NewID = @CashVoucherID;
        SET @NewVoucherNo = CASE WHEN @Status = 'Posted' THEN @LedgerNo ELSE NULL END;
        SELECT @CashVoucherID AS CashVoucherID, @NewVoucherNo AS VoucherNo, @Total AS TotalAmount, @Status AS Status;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
/* ---------------- BANK VOUCHERS (same structure, Bank Book) -------- */
CREATE OR ALTER PROCEDURE dbo.sp_FinanceDocuments_SaveBank
    @BankVoucherID  INT = NULL,
    @Status         NVARCHAR(20) = 'Posted',
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

        IF @Status NOT IN ('Draft','Hold','Posted')
            THROW 51064, 'Invalid voucher status. Use Draft, Hold or Posted.', 1;
        IF @Direction NOT IN ('Receipt','Payment')
            THROW 51051, 'Invalid bank voucher direction.', 1;
        IF LEN(@Narrative) > 200
            THROW 51012, 'Voucher description cannot exceed 200 characters.', 1;

        DECLARE @ExistingDate DATE = NULL, @ExistingLedger INT = NULL,
                @Deleted BIT = NULL, @ExistingStatus NVARCHAR(20) = NULL, @OldNo NVARCHAR(50) = NULL;
        IF @BankVoucherID IS NOT NULL
            SELECT @ExistingDate = VoucherDate, @ExistingLedger = VoucherID,
                   @Deleted = IsDeleted, @ExistingStatus = Status, @OldNo = VoucherNo
            FROM dbo.BankVouchers WHERE BankVoucherID = @BankVoucherID;

        IF @BankVoucherID IS NOT NULL AND @ExistingDate IS NULL
            THROW 51001, 'Bank voucher not found.', 1;
        IF @Deleted = 1
            THROW 51001, 'This bank voucher has been deleted.', 1;
        IF @ExistingDate IS NOT NULL AND @VoucherDate <> @ExistingDate
            THROW 51050, 'The voucher date cannot be changed after the voucher has been saved.', 1;

        IF NOT EXISTS (SELECT 1 FROM dbo.Accounts a
                       WHERE a.AccountID = @BankAccountID AND a.BookType = N'Bank Book'
                         AND a.IsControl = 0 AND a.IsActive = 1 AND a.IsDeleted = 0
                         AND (a.BranchID IS NULL OR a.BranchID = @BranchID))
            THROW 51052, 'Select an active Bank Book account available to this branch.', 1;

        IF OBJECT_ID('tempdb..#DocLines') IS NOT NULL DROP TABLE #DocLines;
        CREATE TABLE #DocLines (
            RowNum INT IDENTITY(1,1) PRIMARY KEY,
            AccountID INT, Description NVARCHAR(500), Amount DECIMAL(18,2),
            TaxAccountID INT, TaxPercent DECIMAL(9,4), TaxAmount DECIMAL(18,2), TaxHeadID INT,
            ChequeNo NVARCHAR(50), ChequeStatus NVARCHAR(20), ChequeTitle NVARCHAR(150),
            ReferenceNo NVARCHAR(50),
            KnockOff BIT, BillRef NVARCHAR(50), BillDate DATE, DueDate DATE,
            PartyMemberID INT, PartySupplierID INT, PartyStaffID INT);

        INSERT INTO #DocLines (AccountID, Description, Amount, TaxAccountID, TaxPercent, TaxAmount, TaxHeadID,
                               ChequeNo, ChequeStatus, ChequeTitle, ReferenceNo,
                               KnockOff, BillRef, BillDate, DueDate, PartyMemberID, PartySupplierID, PartyStaffID)
        SELECT AccountID, Description, Amount, TaxAccountID, TaxPercent, TaxAmount, TaxHeadID,
               ChequeNo, ChequeStatus, ChequeTitle, ReferenceNo,
               ISNULL(KnockOff, 0), BillRef, BillDate, DueDate, PartyMemberID, PartySupplierID, PartyStaffID
        FROM OPENJSON(@LinesJson)
        WITH (
            AccountID INT '$.AccountID',
            Description NVARCHAR(500) '$.Description',
            Amount DECIMAL(18,2) '$.Amount',
            TaxAccountID INT '$.TaxAccountID',
            TaxPercent DECIMAL(9,4) '$.TaxPercent',
            TaxAmount DECIMAL(18,2) '$.TaxAmount',
            TaxHeadID INT '$.TaxHeadID',
            ChequeNo NVARCHAR(50) '$.ChequeNo',
            ChequeStatus NVARCHAR(20) '$.ChequeStatus',
            ChequeTitle NVARCHAR(150) '$.ChequeTitle',
            ReferenceNo NVARCHAR(50) '$.ReferenceNo',
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
        IF EXISTS (SELECT 1 FROM #DocLines l JOIN dbo.Accounts a ON a.AccountID = l.AccountID
                   WHERE a.BranchID IS NOT NULL AND a.BranchID <> @BranchID)
            THROW 51063, 'One or more selected accounts are not available for this branch.', 1;
        IF EXISTS (SELECT 1 FROM #DocLines
                   WHERE (ISNULL(TaxPercent, 0) > 0 OR ISNULL(TaxAmount, 0) > 0) AND TaxAccountID IS NULL)
            THROW 51060, 'Tax Account is mandatory when tax percentage or tax amount is entered.', 1;
        IF EXISTS (SELECT 1 FROM #DocLines WHERE TaxPercent IS NOT NULL AND (TaxPercent < 0 OR TaxPercent > 100))
            THROW 51065, 'Tax Percentage must be between 0 and 100.', 1;
        IF EXISTS (SELECT 1 FROM #DocLines WHERE TaxAmount IS NOT NULL AND TaxAmount < 0)
            THROW 51053, 'Tax amount cannot be negative.', 1;
        IF EXISTS (SELECT 1 FROM #DocLines l LEFT JOIN dbo.TaxHeads t ON t.TaxHeadID = l.TaxHeadID
                   WHERE l.TaxHeadID IS NOT NULL AND (t.TaxHeadID IS NULL OR t.IsActive = 0))
            THROW 51055, 'Invalid or inactive tax head on one or more lines.', 1;
        IF EXISTS (SELECT 1 FROM #DocLines l
                   JOIN dbo.Accounts a ON a.AccountID = l.TaxAccountID
                   WHERE l.TaxAccountID IS NOT NULL AND (a.IsControl = 1 OR a.IsActive = 0 OR a.IsDeleted = 1
                         OR NOT EXISTS (SELECT 1 FROM dbo.AccountTags tg WHERE tg.AccountID = a.AccountID AND tg.Tag = N'Tax')))
            THROW 51062, 'Tax Account must be an active Detail account tagged Tax (from the Tax File).', 1;
        IF EXISTS (SELECT 1 FROM #DocLines
                   WHERE ChequeStatus IS NOT NULL
                     AND ChequeStatus NOT IN (N'Hold', N'Pending', N'Cleared', N'Bounced', N'Cancelled'))
            THROW 51061, 'Invalid cheque status. Use Hold, Pending, Cleared, Bounced or Cancelled.', 1;
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

        DECLARE @PostedEdit BIT = 0;
        IF @ExistingStatus = 'Posted' AND @Status = 'Posted'
        BEGIN
            SET @PostedEdit = 1;
            IF EXISTS (SELECT 1 FROM dbo.BankReconciliationLines l
                       JOIN dbo.VoucherEntries e ON e.EntryID = l.VoucherEntryID
                       WHERE e.VoucherID = @ExistingLedger)
                THROW 51059, 'This voucher has reconciled entries and cannot be edited.', 1;

            ;WITH agg AS (SELECT e.AccountID, SUM(e.Debit) AS D, SUM(e.Credit) AS C
                          FROM dbo.VoucherEntries e WHERE e.VoucherID = @ExistingLedger GROUP BY e.AccountID)
            UPDATE ab
               SET ab.DebitTotal = ab.DebitTotal - agg.D, ab.CreditTotal = ab.CreditTotal - agg.C,
                   ab.UpdatedAt = SYSUTCDATETIME()
            FROM dbo.AccountBalances ab
            JOIN agg ON agg.AccountID = ab.AccountID
            JOIN dbo.Vouchers v ON v.VoucherID = @ExistingLedger
            WHERE ab.FinancialYearID = v.FinancialYearID
              AND ab.PeriodNo = (SELECT PeriodNo FROM dbo.AccountingPeriods p
                                 JOIN dbo.Vouchers v2 ON v2.FinancialYearID = p.FinancialYearID
                                 WHERE v2.VoucherID = @ExistingLedger
                                   AND v2.VoucherDate BETWEEN p.StartDate AND p.EndDate);

            UPDATE dbo.BankVouchers SET VoucherID = NULL WHERE BankVoucherID = @BankVoucherID;
            DELETE FROM dbo.VoucherEntries WHERE VoucherID = @ExistingLedger;
            DELETE FROM dbo.Vouchers WHERE VoucherID = @ExistingLedger;
            UPDATE dbo.FinanceLineAllocations SET IsReversed = 1
             WHERE Family = 'BANK' AND DocumentID = @BankVoucherID;
        END

        IF @Status = 'Posted'
        BEGIN
            DECLARE @EntriesJson NVARCHAR(MAX);
            IF @Direction = 'Receipt'
                SET @EntriesJson = (
                    SELECT * FROM (
                        SELECT @BankAccountID AS AccountID, @Total AS Debit, 0 AS Credit,
                               @Narrative AS Narrative, NULL AS PartyMemberID, NULL AS PartySupplierID,
                               NULL AS PartyStaffID, NULL AS BillRef, NULL AS BillDate, NULL AS DueDate
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
                               @Narrative AS Narrative, NULL AS PartyMemberID, NULL AS PartySupplierID,
                               NULL AS PartyStaffID, NULL AS BillRef, NULL AS BillDate, NULL AS DueDate
                        FROM #DocLines
                    ) x
                    FOR JSON PATH
                );

            DECLARE @TypeCode NVARCHAR(10) = CASE WHEN @Direction = 'Receipt' THEN 'BRV' ELSE 'BPV' END;
            DECLARE @VoucherTypeID INT = (SELECT VoucherTypeID FROM dbo.VoucherTypes WHERE TypeCode = @TypeCode AND IsActive = 1);
            IF @VoucherTypeID IS NULL THROW 51021, 'Bank voucher type not found or inactive.', 1;

            DECLARE @LedgerID INT, @LedgerNo NVARCHAR(50);
            DECLARE @ExplicitNo NVARCHAR(50) = CASE WHEN @PostedEdit = 1 THEN @OldNo ELSE NULL END;
            EXEC dbo.sp_Accounting_CreateAndPostCore
                 @VoucherTypeID = @VoucherTypeID, @VoucherDate = @VoucherDate, @BranchID = @BranchID,
                 @Narrative = @Narrative, @SourceModule = 'BankVoucher', @SourceID = @BankVoucherID,
                 @EntriesJson = @EntriesJson, @UserId = @UserId, @ExplicitVoucherNo = @ExplicitNo,
                 @NewVoucherID = @LedgerID OUTPUT, @NewVoucherNo = @LedgerNo OUTPUT;
        END

        IF @BankVoucherID IS NULL
        BEGIN
            DECLARE @LedgerFY INT = CASE WHEN @Status = 'Posted'
                THEN (SELECT FinancialYearID FROM dbo.Vouchers WHERE VoucherID = @LedgerID) END;
            INSERT INTO dbo.BankVouchers (Direction, VoucherDate, BankAccountID, BranchID, Narrative, TotalAmount,
                                          VoucherID, VoucherNo, FinancialYearID, Status, PostedBy, PostedAt, CreatedBy)
            VALUES (@Direction, @VoucherDate, @BankAccountID, @BranchID, @Narrative, @Total,
                    CASE WHEN @Status = 'Posted' THEN @LedgerID END,
                    CASE WHEN @Status = 'Posted' THEN @LedgerNo END,
                    @LedgerFY, @Status,
                    CASE WHEN @Status = 'Posted' THEN @UserId END,
                    CASE WHEN @Status = 'Posted' THEN SYSUTCDATETIME() END,
                    @UserId);
            SET @BankVoucherID = CAST(SCOPE_IDENTITY() AS INT);
            UPDATE dbo.Vouchers SET SourceID = @BankVoucherID WHERE VoucherID = @LedgerID;
        END
        ELSE
        BEGIN
            UPDATE dbo.BankVouchers
               SET BankAccountID = @BankAccountID, Narrative = @Narrative, TotalAmount = @Total,
                   VoucherID = CASE WHEN @Status = 'Posted' THEN @LedgerID ELSE VoucherID END,
                   VoucherNo = CASE WHEN @Status = 'Posted' THEN @LedgerNo ELSE VoucherNo END,
                   Status = @Status,
                   ReversedBy = NULL, ReversedAt = NULL,
                   UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @UserId
             WHERE BankVoucherID = @BankVoucherID;
            DELETE FROM dbo.BankVoucherLines WHERE BankVoucherID = @BankVoucherID;
        END

        INSERT INTO dbo.BankVoucherLines (BankVoucherID, AccountID, Description, Amount, TaxHeadID,
                                          TaxAccountID, TaxPercent, TaxAmount,
                                          ChequeNo, ChequeStatus, ChequeTitle, ReferenceNo,
                                          KnockOff, BillRef, BillDate, DueDate,
                                          PartyMemberID, PartySupplierID, PartyStaffID, CreatedBy)
        SELECT @BankVoucherID, AccountID, Description, Amount, TaxHeadID,
               TaxAccountID, TaxPercent, TaxAmount,
               NULLIF(ChequeNo, ''), ChequeStatus, NULLIF(ChequeTitle, ''), NULLIF(ReferenceNo, ''),
               ISNULL(KnockOff, 0), NULLIF(BillRef, ''), BillDate, DueDate,
               PartyMemberID, PartySupplierID, PartyStaffID, @UserId
        FROM #DocLines;

        COMMIT TRANSACTION;
        SET @NewID = @BankVoucherID;
        SET @NewVoucherNo = CASE WHEN @Status = 'Posted' THEN @LedgerNo ELSE NULL END;
        SELECT @BankVoucherID AS BankVoucherID, @NewVoucherNo AS VoucherNo, @Total AS TotalAmount, @Status AS Status;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

/* ================================================================== */
/* 6. POST Draft / Hold vouchers                                       */
/* ================================================================== */
CREATE OR ALTER PROCEDURE dbo.sp_FinanceDocuments_Post
    @Family NVARCHAR(10), @ID INT, @UserId INT = NULL,
    @NewVoucherNo NVARCHAR(50) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @DocStatus NVARCHAR(20), @LedgerID INT = NULL;
        IF @Family = 'CASH'
            SELECT @DocStatus = Status, @LedgerID = VoucherID FROM dbo.CashVouchers WHERE CashVoucherID = @ID AND IsDeleted = 0;
        ELSE IF @Family = 'BANK'
            SELECT @DocStatus = Status, @LedgerID = VoucherID FROM dbo.BankVouchers WHERE BankVoucherID = @ID AND IsDeleted = 0;
        ELSE
            THROW 51051, 'Posting is available for cash and bank vouchers only in this endpoint.', 1;

        IF @DocStatus IS NULL THROW 51001, 'Voucher not found.', 1;
        IF @DocStatus = 'Posted' THROW 51003, 'Voucher is already posted.', 1;

        IF @LedgerID IS NULL
        BEGIN
            /* build entries from stored lines */
            IF @Family = 'CASH'
            BEGIN
                DECLARE @Dir NVARCHAR(10), @CashAcc INT;
                DECLARE @Total DECIMAL(18,2) = (SELECT ISNULL(SUM(Amount), 0) FROM dbo.CashVoucherLines WHERE CashVoucherID = @ID);
                SELECT @Dir = Direction, @CashAcc = CashAccountID FROM dbo.CashVouchers WHERE CashVoucherID = @ID;
                DECLARE @CJson NVARCHAR(MAX) = (
                    SELECT * FROM (
                        SELECT l.AccountID,
                               CASE WHEN @Dir = 'Payment' THEN l.Amount ELSE 0 END AS Debit,
                               CASE WHEN @Dir = 'Receipt' THEN l.Amount ELSE 0 END AS Credit,
                               l.Description AS Narrative,
                               l.PartyMemberID, l.PartySupplierID, l.PartyStaffID,
                               CASE WHEN l.KnockOff = 1 THEN l.BillRef END AS BillRef,
                               CASE WHEN l.KnockOff = 1 THEN l.BillDate END AS BillDate,
                               CASE WHEN l.KnockOff = 1 THEN l.DueDate END AS DueDate
                        FROM dbo.CashVoucherLines l WHERE l.CashVoucherID = @ID
                        UNION ALL
                        SELECT @CashAcc AS AccountID,
                               CASE WHEN @Dir = 'Receipt' THEN @Total ELSE 0 END AS Debit,
                               CASE WHEN @Dir = 'Payment' THEN @Total ELSE 0 END AS Credit,
                               c.Narrative AS Narrative,
                               CAST(NULL AS INT), CAST(NULL AS INT), CAST(NULL AS INT),
                               CAST(NULL AS NVARCHAR(50)), CAST(NULL AS DATE), CAST(NULL AS DATE)
                        FROM (SELECT Narrative FROM dbo.CashVouchers WHERE CashVoucherID = @ID) c
                    ) x
                    FOR JSON PATH);
                DECLARE @CType INT = (SELECT VoucherTypeID FROM dbo.VoucherTypes
                                      WHERE TypeCode = CASE WHEN @Dir = 'Receipt' THEN 'CRV' ELSE 'CPV' END);
                DECLARE @CBr INT = (SELECT BranchID FROM dbo.CashVouchers WHERE CashVoucherID = @ID);
                DECLARE @CDate DATE = (SELECT VoucherDate FROM dbo.CashVouchers WHERE CashVoucherID = @ID);
                DECLARE @CId INT, @CNo NVARCHAR(50);
                DECLARE @CNar NVARCHAR(500) = (SELECT Narrative FROM dbo.CashVouchers WHERE CashVoucherID = @ID);
                EXEC dbo.sp_Accounting_CreateAndPostCore @VoucherTypeID = @CType, @VoucherDate = @CDate,
                     @BranchID = @CBr, @Narrative = @CNar,
                     @SourceModule = 'CashVoucher', @SourceID = @ID, @EntriesJson = @CJson, @UserId = @UserId,
                     @NewVoucherID = @CId OUTPUT, @NewVoucherNo = @CNo OUTPUT;
                UPDATE dbo.CashVouchers SET VoucherID = @CId, VoucherNo = @CNo,
                       FinancialYearID = (SELECT FinancialYearID FROM dbo.Vouchers WHERE VoucherID = @CId),
                       Status = 'Posted', PostedBy = @UserId, PostedAt = SYSUTCDATETIME()
                 WHERE CashVoucherID = @ID;
                SET @NewVoucherNo = @CNo;
            END
            ELSE
            BEGIN
                DECLARE @BDir NVARCHAR(10), @BAcc INT;
                DECLARE @TotalB DECIMAL(18,2) = (SELECT ISNULL(SUM(Amount), 0) FROM dbo.BankVoucherLines WHERE BankVoucherID = @ID);
                SELECT @BDir = Direction, @BAcc = BankAccountID FROM dbo.BankVouchers WHERE BankVoucherID = @ID;
                DECLARE @BJson NVARCHAR(MAX) = (
                    SELECT * FROM (
                        SELECT l.AccountID,
                               CASE WHEN @BDir = 'Payment' THEN l.Amount ELSE 0 END AS Debit,
                               CASE WHEN @BDir = 'Receipt' THEN l.Amount ELSE 0 END AS Credit,
                               l.Description AS Narrative,
                               l.PartyMemberID, l.PartySupplierID, l.PartyStaffID,
                               CASE WHEN l.KnockOff = 1 THEN l.BillRef END AS BillRef,
                               CASE WHEN l.KnockOff = 1 THEN l.BillDate END AS BillDate,
                               CASE WHEN l.KnockOff = 1 THEN l.DueDate END AS DueDate
                        FROM dbo.BankVoucherLines l WHERE l.BankVoucherID = @ID
                        UNION ALL
                        SELECT @BAcc AS AccountID,
                               CASE WHEN @BDir = 'Receipt' THEN @TotalB ELSE 0 END AS Debit,
                               CASE WHEN @BDir = 'Payment' THEN @TotalB ELSE 0 END AS Credit,
                               b.Narrative AS Narrative,
                               CAST(NULL AS INT), CAST(NULL AS INT), CAST(NULL AS INT),
                               CAST(NULL AS NVARCHAR(50)), CAST(NULL AS DATE), CAST(NULL AS DATE)
                        FROM (SELECT Narrative FROM dbo.BankVouchers WHERE BankVoucherID = @ID) b
                    ) x
                    FOR JSON PATH);
                DECLARE @BType INT = (SELECT VoucherTypeID FROM dbo.VoucherTypes
                                      WHERE TypeCode = CASE WHEN @BDir = 'Receipt' THEN 'BRV' ELSE 'BPV' END);
                DECLARE @BBr INT = (SELECT BranchID FROM dbo.BankVouchers WHERE BankVoucherID = @ID);
                DECLARE @BDate DATE = (SELECT VoucherDate FROM dbo.BankVouchers WHERE BankVoucherID = @ID);
                DECLARE @BId INT, @BNo NVARCHAR(50);
                DECLARE @BNar NVARCHAR(500) = (SELECT Narrative FROM dbo.BankVouchers WHERE BankVoucherID = @ID);
                EXEC dbo.sp_Accounting_CreateAndPostCore @VoucherTypeID = @BType, @VoucherDate = @BDate,
                     @BranchID = @BBr, @Narrative = @BNar,
                     @SourceModule = 'BankVoucher', @SourceID = @ID, @EntriesJson = @BJson, @UserId = @UserId,
                     @NewVoucherID = @BId OUTPUT, @NewVoucherNo = @BNo OUTPUT;
                UPDATE dbo.BankVouchers SET VoucherID = @BId, VoucherNo = @BNo,
                       FinancialYearID = (SELECT FinancialYearID FROM dbo.Vouchers WHERE VoucherID = @BId),
                       Status = 'Posted', PostedBy = @UserId, PostedAt = SYSUTCDATETIME()
                 WHERE BankVoucherID = @ID;
                SET @NewVoucherNo = @BNo;
            END
        END

        COMMIT TRANSACTION;
        SELECT 'OK' AS Result, @NewVoucherNo AS VoucherNo;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
/* ================================================================== */
/* 7. KNOCK-OFF ALLOCATIONS (transactional save + reversal)           */
/* ================================================================== */
CREATE OR ALTER PROCEDURE dbo.sp_FinanceDocuments_SaveAllocations
    @Family NVARCHAR(10), @DocumentID INT, @LineID BIGINT,
    @AllocJson NVARCHAR(MAX), @UserId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF @Family NOT IN ('CASH','BANK','JOURNAL','OTB')
            THROW 51051, 'Invalid voucher family.', 1;

        DECLARE @LineAmount DECIMAL(18,2), @DocStatus NVARCHAR(20);
        IF @Family = 'CASH'
            SELECT @LineAmount = l.Amount, @DocStatus = v.Status
            FROM dbo.CashVoucherLines l JOIN dbo.CashVouchers v ON v.CashVoucherID = l.CashVoucherID
            WHERE l.CashVoucherLineID = @LineID AND v.CashVoucherID = @DocumentID;
        ELSE IF @Family = 'BANK'
            SELECT @LineAmount = l.Amount, @DocStatus = v.Status
            FROM dbo.BankVoucherLines l JOIN dbo.BankVouchers v ON v.BankVoucherID = l.BankVoucherID
            WHERE l.BankVoucherLineID = @LineID AND v.BankVoucherID = @DocumentID;
        ELSE
            THROW 51051, 'Allocations are available on cash and bank voucher lines.', 1;

        IF @LineAmount IS NULL THROW 51001, 'Voucher line not found.', 1;

        IF OBJECT_ID('tempdb..#Alloc') IS NOT NULL DROP TABLE #Alloc;
        CREATE TABLE #Alloc (BillRef NVARCHAR(50) PRIMARY KEY, Amount DECIMAL(18,2) NOT NULL);
        INSERT INTO #Alloc (BillRef, Amount)
        SELECT NULLIF(LTRIM(RTRIM(BillRef)), ''), Amount
        FROM OPENJSON(@AllocJson)
        WITH (BillRef NVARCHAR(50) '$.billRef', Amount DECIMAL(18,2) '$.amount');

        IF NOT EXISTS (SELECT 1 FROM #Alloc)
            THROW 51057, 'No allocation rows supplied.', 1;
        IF EXISTS (SELECT 1 FROM #Alloc WHERE Amount IS NULL OR Amount <= 0)
            THROW 51053, 'Every allocation amount must be greater than zero.', 1;
        IF (SELECT ISNULL(SUM(Amount), 0) FROM #Alloc) > @LineAmount
            THROW 51066, 'Total allocation exceeds the voucher line amount.', 1;

        /* per-bill outstanding check: bill net (from ledger) minus active
           allocations from OTHER lines */
        IF EXISTS (
            SELECT 1 FROM #Alloc a
            CROSS APPLY (
                SELECT ISNULL(SUM(e.Debit - e.Credit), 0) AS Net
                FROM dbo.VoucherEntries e
                JOIN dbo.Vouchers v ON v.VoucherID = e.VoucherID
                     AND v.Status IN ('Posted','Reversed') AND v.IsDeleted = 0
                WHERE e.PartyMemberID = (SELECT TOP 1 PartyMemberID FROM dbo.CashVoucherLines WHERE CashVoucherLineID = @LineID)
                  AND e.BillRef = a.BillRef
            ) b
            CROSS APPLY (
                SELECT ISNULL(SUM(al.Amount), 0) AS Allocated
                FROM dbo.FinanceLineAllocations al
                WHERE al.IsReversed = 0 AND al.BillRef = a.BillRef
                  AND NOT (al.Family = @Family AND al.DocumentID = @DocumentID AND al.LineID = @LineID)
            ) c
            WHERE a.Amount > b.Net - c.Allocated
        )
            THROW 51067, 'One or more allocations exceed the outstanding amount of the bill.', 1;

        /* replace: reverse previous allocations of this line, insert new */
        UPDATE dbo.FinanceLineAllocations SET IsReversed = 1
         WHERE Family = @Family AND DocumentID = @DocumentID AND LineID = @LineID;

        INSERT INTO dbo.FinanceLineAllocations (Family, DocumentID, LineID, BillRef, PartyMemberID, PartySupplierID, Amount, CreatedBy)
        SELECT @Family, @DocumentID, @LineID, a.BillRef,
               (SELECT TOP 1 PartyMemberID FROM dbo.CashVoucherLines WHERE CashVoucherLineID = @LineID),
               (SELECT TOP 1 PartySupplierID FROM dbo.BankVoucherLines WHERE BankVoucherLineID = @LineID),
               a.Amount, @UserId
        FROM #Alloc a;

        COMMIT TRANSACTION;
        SELECT 'OK' AS Result;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_FinanceDocuments_GetAllocations
    @Family NVARCHAR(10), @DocumentID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT AllocationID, LineID, BillRef, PartyMemberID, PartySupplierID, Amount, IsReversed
    FROM dbo.FinanceLineAllocations
    WHERE Family = @Family AND DocumentID = @DocumentID
    ORDER BY AllocationID;
END
GO

/* ================================================================== */
/* 8. DELETE update: reverse allocations too                          */
/* ================================================================== */
CREATE OR ALTER PROCEDURE dbo.sp_FinanceDocuments_Delete
    @Family NVARCHAR(10), @ID INT, @UserId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @LedgerID INT = NULL, @DocDate DATE = NULL, @DocStatus NVARCHAR(20) = NULL;

        IF @Family = 'CASH'
        BEGIN
            SELECT @LedgerID = VoucherID, @DocDate = VoucherDate, @DocStatus = Status FROM dbo.CashVouchers
            WHERE CashVoucherID = @ID AND IsDeleted = 0;
            IF @LedgerID IS NULL THROW 51001, 'Cash voucher not found.', 1;
        END
        ELSE IF @Family = 'BANK'
        BEGIN
            SELECT @LedgerID = VoucherID, @DocDate = VoucherDate, @DocStatus = Status FROM dbo.BankVouchers
            WHERE BankVoucherID = @ID AND IsDeleted = 0;
            IF @LedgerID IS NULL THROW 51001, 'Bank voucher not found.', 1;
        END
        ELSE IF @Family = 'JOURNAL'
        BEGIN
            SELECT @LedgerID = VoucherID, @DocDate = VoucherDate, @DocStatus = Status FROM dbo.JournalVouchers
            WHERE JournalVoucherID = @ID AND IsDeleted = 0;
            IF @LedgerID IS NULL THROW 51001, 'Journal voucher not found.', 1;
        END
        ELSE IF @Family = 'OTB'
        BEGIN
            SELECT @LedgerID = VoucherID, @DocDate = VoucherDate, @DocStatus = Status FROM dbo.OpeningTrialBalances
            WHERE OpeningTBID = @ID AND IsDeleted = 0;
            IF @LedgerID IS NULL THROW 51001, 'Opening trial balance not found.', 1;
        END
        ELSE
            THROW 51051, 'Invalid voucher family.', 1;

        IF @DocStatus = 'Posted' AND @LedgerID IS NOT NULL
        BEGIN
            DECLARE @RevID INT, @RevNo NVARCHAR(50);
            EXEC dbo.sp_Accounting_ReverseCore
                 @VoucherID = @LedgerID, @ReversalDate = @DocDate,
                 @UserId = @UserId, @NewVoucherID = @RevID OUTPUT, @NewVoucherNo = @RevNo OUTPUT;
        END

        UPDATE dbo.FinanceLineAllocations SET IsReversed = 1
         WHERE Family = @Family AND DocumentID = @ID AND IsReversed = 0;

        IF @Family = 'CASH'
            UPDATE dbo.CashVouchers SET IsDeleted = 1, Status = 'Reversed',
                   ReversedBy = @UserId, ReversedAt = SYSUTCDATETIME(),
                   UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @UserId
             WHERE CashVoucherID = @ID;
        ELSE IF @Family = 'BANK'
            UPDATE dbo.BankVouchers SET IsDeleted = 1, Status = 'Reversed',
                   ReversedBy = @UserId, ReversedAt = SYSUTCDATETIME(),
                   UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @UserId
             WHERE BankVoucherID = @ID;
        ELSE IF @Family = 'JOURNAL'
            UPDATE dbo.JournalVouchers SET IsDeleted = 1, Status = 'Reversed',
                   ReversedBy = @UserId, ReversedAt = SYSUTCDATETIME(),
                   UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @UserId
             WHERE JournalVoucherID = @ID;
        ELSE
            UPDATE dbo.OpeningTrialBalances SET IsDeleted = 1, Status = 'Reversed',
                   ReversedBy = @UserId, ReversedAt = SYSUTCDATETIME(),
                   UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @UserId
             WHERE OpeningTBID = @ID;

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
/* 9. LIST: Draft/Hold included + book/line account + search filters  */
/* ================================================================== */
CREATE OR ALTER PROCEDURE dbo.sp_FinanceDocuments_List
    @Family   NVARCHAR(10),
    @Page INT = 1, @PageSize INT = 15,
    @Direction NVARCHAR(10) = NULL,
    @Status NVARCHAR(20) = NULL,
    @BranchID INT = NULL,
    @FromDate DATE = NULL,
    @ToDate DATE = NULL,
    @Search NVARCHAR(100) = NULL,
    @BookAccountID INT = NULL,
    @AccountID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Offset INT = (@Page - 1) * @PageSize;

    IF @Family IN ('CASH','BANK')
    BEGIN
        DECLARE @Tbl NVARCHAR(20) = CASE WHEN @Family = 'CASH' THEN 'CashVouchers' ELSE 'BankVouchers' END;
        DECLARE @LnTbl NVARCHAR(20) = CASE WHEN @Family = 'CASH' THEN 'CashVoucherLines' ELSE 'BankVoucherLines' END;
        DECLARE @Pk NVARCHAR(20) = CASE WHEN @Family = 'CASH' THEN 'CashVoucherID' ELSE 'BankVoucherID' END;
        DECLARE @AccCol NVARCHAR(20) = CASE WHEN @Family = 'CASH' THEN 'CashAccountID' ELSE 'BankAccountID' END;

        DECLARE @Sql NVARCHAR(MAX) = N'
        SELECT  v.' + QUOTENAME(@Pk) + N' AS ID, v.VoucherNo, v.VoucherDate, v.Direction, v.Narrative,
                v.TotalAmount AS Amount, v.Status, v.BranchID, b.Name AS BranchName,
                a.Code AS MoneyAccountCode, a.Title AS MoneyAccountTitle,
                (SELECT COUNT(*) FROM dbo.' + QUOTENAME(@LnTbl) + N' l WHERE l.' + QUOTENAME(@Pk) + N' = v.' + QUOTENAME(@Pk) + N') AS LineCount,
                u.FullName AS CreatedByName, v.CreatedAt
        FROM    dbo.' + QUOTENAME(@Tbl) + N' v
        JOIN    dbo.Branches b ON b.BranchID = v.BranchID
        JOIN    dbo.Accounts a ON a.AccountID = v.' + QUOTENAME(@AccCol) + N'
        LEFT JOIN dbo.Users u ON u.UserID = v.CreatedBy
        WHERE   v.IsDeleted = 0
          AND   (@Direction IS NULL OR v.Direction = @Direction)
          AND   (@Status IS NULL OR v.Status = @Status)
          AND   (@BranchID IS NULL OR v.BranchID = @BranchID)
          AND   (@FromDate IS NULL OR v.VoucherDate >= @FromDate)
          AND   (@ToDate IS NULL OR v.VoucherDate <= @ToDate)
          AND   (@BookAccountID IS NULL OR v.' + QUOTENAME(@AccCol) + N' = @BookAccountID)
          AND   (@AccountID IS NULL OR EXISTS (SELECT 1 FROM dbo.' + QUOTENAME(@LnTbl) + N' l WHERE l.' + QUOTENAME(@Pk) + N' = v.' + QUOTENAME(@Pk) + N' AND l.AccountID = @AccountID))
          AND   (@Search IS NULL OR v.VoucherNo LIKE N''%'' + @Search + N''%'' OR v.Narrative LIKE N''%'' + @Search + N''%'')
        ORDER BY v.VoucherDate DESC, v.' + QUOTENAME(@Pk) + N' DESC
        OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;

        SELECT COUNT(*) AS Total, ISNULL(SUM(v.TotalAmount), 0) AS TotalAmount
        FROM    dbo.' + QUOTENAME(@Tbl) + N' v
        WHERE   v.IsDeleted = 0
          AND   (@Direction IS NULL OR v.Direction = @Direction)
          AND   (@Status IS NULL OR v.Status = @Status)
          AND   (@BranchID IS NULL OR v.BranchID = @BranchID)
          AND   (@FromDate IS NULL OR v.VoucherDate >= @FromDate)
          AND   (@ToDate IS NULL OR v.VoucherDate <= @ToDate)
          AND   (@BookAccountID IS NULL OR v.' + QUOTENAME(@AccCol) + N' = @BookAccountID)
          AND   (@AccountID IS NULL OR EXISTS (SELECT 1 FROM dbo.' + QUOTENAME(@LnTbl) + N' l WHERE l.' + QUOTENAME(@Pk) + N' = v.' + QUOTENAME(@Pk) + N' AND l.AccountID = @AccountID))
          AND   (@Search IS NULL OR v.VoucherNo LIKE N''%'' + @Search + N''%'' OR v.Narrative LIKE N''%'' + @Search + N''%'');';

        EXEC sp_executesql @Sql,
            N'@Offset INT, @PageSize INT, @Direction NVARCHAR(10), @Status NVARCHAR(20),
              @BranchID INT, @FromDate DATE, @ToDate DATE, @Search NVARCHAR(100),
              @BookAccountID INT, @AccountID INT',
            @Offset, @PageSize, @Direction, @Status, @BranchID, @FromDate, @ToDate, @Search,
            @BookAccountID, @AccountID;
    END
    ELSE
    BEGIN
        DECLARE @Tbl2 NVARCHAR(20) = CASE WHEN @Family = 'JOURNAL' THEN 'JournalVouchers' ELSE 'OpeningTrialBalances' END;
        DECLARE @Pk2 NVARCHAR(20) = CASE WHEN @Family = 'JOURNAL' THEN 'JournalVoucherID' ELSE 'OpeningTBID' END;
        DECLARE @Ln2 NVARCHAR(20) = CASE WHEN @Family = 'JOURNAL' THEN 'JournalVoucherLines' ELSE 'OpeningTBLines' END;
        DECLARE @Sql2 NVARCHAR(MAX) = N'
        SELECT  v.' + QUOTENAME(@Pk2) + N' AS ID, v.VoucherNo, v.VoucherDate, CAST(NULL AS NVARCHAR(10)) AS Direction, v.Narrative,
                v.DebitTotal AS Amount, v.Status, v.BranchID, b.Name AS BranchName,
                CAST(NULL AS NVARCHAR(20)) AS MoneyAccountCode, CAST(NULL AS NVARCHAR(150)) AS MoneyAccountTitle,
                (SELECT COUNT(*) FROM dbo.' + QUOTENAME(@Ln2) + N' l WHERE l.' + QUOTENAME(@Pk2) + N' = v.' + QUOTENAME(@Pk2) + N') AS LineCount,
                u.FullName AS CreatedByName, v.CreatedAt
        FROM    dbo.' + QUOTENAME(@Tbl2) + N' v
        JOIN    dbo.Branches b ON b.BranchID = v.BranchID
        LEFT JOIN dbo.Users u ON u.UserID = v.CreatedBy
        WHERE   v.IsDeleted = 0
          AND   (@Status IS NULL OR v.Status = @Status)
          AND   (@BranchID IS NULL OR v.BranchID = @BranchID)
          AND   (@FromDate IS NULL OR v.VoucherDate >= @FromDate)
          AND   (@ToDate IS NULL OR v.VoucherDate <= @ToDate)
          AND   (@BookAccountID IS NULL OR 1 = 0)
          AND   (@AccountID IS NULL OR EXISTS (SELECT 1 FROM dbo.' + QUOTENAME(@Ln2) + N' l WHERE l.' + QUOTENAME(@Pk2) + N' = v.' + QUOTENAME(@Pk2) + N' AND l.AccountID = @AccountID))
          AND   (@Search IS NULL OR v.VoucherNo LIKE N''%'' + @Search + N''%'' OR v.Narrative LIKE N''%'' + @Search + N''%'')
        ORDER BY v.VoucherDate DESC, v.' + QUOTENAME(@Pk2) + N' DESC
        OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;

        SELECT COUNT(*) AS Total, ISNULL(SUM(v.DebitTotal), 0) AS TotalAmount
        FROM    dbo.' + QUOTENAME(@Tbl2) + N' v
        WHERE   v.IsDeleted = 0
          AND   (@Status IS NULL OR v.Status = @Status)
          AND   (@BranchID IS NULL OR v.BranchID = @BranchID)
          AND   (@FromDate IS NULL OR v.VoucherDate >= @FromDate)
          AND   (@ToDate IS NULL OR v.VoucherDate <= @ToDate)
          AND   (@BookAccountID IS NULL OR 1 = 0)
          AND   (@AccountID IS NULL OR EXISTS (SELECT 1 FROM dbo.' + QUOTENAME(@Ln2) + N' l WHERE l.' + QUOTENAME(@Pk2) + N' = v.' + QUOTENAME(@Pk2) + N' AND l.AccountID = @AccountID))
          AND   (@Search IS NULL OR v.VoucherNo LIKE N''%'' + @Search + N''%'' OR v.Narrative LIKE N''%'' + @Search + N''%'');';

        EXEC sp_executesql @Sql2,
            N'@Offset INT, @PageSize INT, @Status NVARCHAR(20), @BranchID INT,
              @FromDate DATE, @ToDate DATE, @Search NVARCHAR(100),
              @BookAccountID INT, @AccountID INT',
            @Offset, @PageSize, @Status, @BranchID, @FromDate, @ToDate, @Search,
            @BookAccountID, @AccountID;
    END
END
GO
/* ================================================================== */
/* 10. GET: full line details (tax/cheque/ref) + allocations          */
/* ================================================================== */
CREATE OR ALTER PROCEDURE dbo.sp_FinanceDocuments_Get
    @Family NVARCHAR(10), @ID INT
AS
BEGIN
    SET NOCOUNT ON;

    IF @Family = 'CASH'
    BEGIN
        SELECT  v.CashVoucherID AS ID, v.VoucherNo, v.VoucherDate, v.Direction, v.Narrative,
                v.TotalAmount AS Amount, v.TotalAmount AS DebitTotal, v.TotalAmount AS CreditTotal,
                v.Status, v.BranchID, b.Name AS BranchName,
                v.CashAccountID AS MoneyAccountID, a.Code AS MoneyAccountCode, a.Title AS MoneyAccountTitle,
                lv.VoucherNo AS LedgerVoucherNo, lv.Status AS LedgerStatus, v.ReversedAt,
                u.FullName AS CreatedByName, v.CreatedAt
        FROM dbo.CashVouchers v
        JOIN dbo.Branches b ON b.BranchID = v.BranchID
        JOIN dbo.Accounts a ON a.AccountID = v.CashAccountID
        LEFT JOIN dbo.Vouchers lv ON lv.VoucherID = v.VoucherID
        LEFT JOIN dbo.Users u ON u.UserID = v.CreatedBy
        WHERE v.CashVoucherID = @ID AND v.IsDeleted = 0;

        SELECT  l.CashVoucherLineID AS LineID, l.AccountID, a.Code AS AccountCode, a.Title AS AccountTitle,
                l.Description, l.Amount,
                CAST(NULL AS DECIMAL(18,2)) AS Debit, CAST(NULL AS DECIMAL(18,2)) AS Credit,
                l.TaxHeadID, l.TaxAccountID, ta.Code AS TaxAccountCode, ta.Title AS TaxAccountTitle,
                l.TaxPercent, l.TaxAmount,
                l.ChequeNo, l.ChequeStatus, l.ChequeTitle, l.ReferenceNo,
                l.KnockOff, l.BillRef, l.BillDate, l.DueDate,
                l.PartyMemberID, m.FullName AS PartyMemberName,
                l.PartySupplierID, s.Name AS PartySupplierName,
                l.PartyStaffID, st.FullName AS PartyStaffName
        FROM dbo.CashVoucherLines l
        JOIN dbo.Accounts a ON a.AccountID = l.AccountID
        LEFT JOIN dbo.Accounts ta ON ta.AccountID = l.TaxAccountID
        LEFT JOIN dbo.Members m ON m.MemberID = l.PartyMemberID
        LEFT JOIN dbo.Suppliers s ON s.SupplierID = l.PartySupplierID
        LEFT JOIN dbo.Staff st ON st.StaffID = l.PartyStaffID
        WHERE l.CashVoucherID = @ID
        ORDER BY l.CashVoucherLineID;

        SELECT AllocationID, LineID, BillRef, PartyMemberID, PartySupplierID, Amount, IsReversed
        FROM dbo.FinanceLineAllocations
        WHERE Family = 'CASH' AND DocumentID = @ID
        ORDER BY AllocationID;
    END
    ELSE IF @Family = 'BANK'
    BEGIN
        SELECT  v.BankVoucherID AS ID, v.VoucherNo, v.VoucherDate, v.Direction, v.Narrative,
                v.TotalAmount AS Amount, v.TotalAmount AS DebitTotal, v.TotalAmount AS CreditTotal,
                v.Status, v.BranchID, b.Name AS BranchName,
                v.BankAccountID AS MoneyAccountID, a.Code AS MoneyAccountCode, a.Title AS MoneyAccountTitle,
                lv.VoucherNo AS LedgerVoucherNo, lv.Status AS LedgerStatus, v.ReversedAt,
                u.FullName AS CreatedByName, v.CreatedAt
        FROM dbo.BankVouchers v
        JOIN dbo.Branches b ON b.BranchID = v.BranchID
        JOIN dbo.Accounts a ON a.AccountID = v.BankAccountID
        LEFT JOIN dbo.Vouchers lv ON lv.VoucherID = v.VoucherID
        LEFT JOIN dbo.Users u ON u.UserID = v.CreatedBy
        WHERE v.BankVoucherID = @ID AND v.IsDeleted = 0;

        SELECT  l.BankVoucherLineID AS LineID, l.AccountID, a.Code AS AccountCode, a.Title AS AccountTitle,
                l.Description, l.Amount,
                CAST(NULL AS DECIMAL(18,2)) AS Debit, CAST(NULL AS DECIMAL(18,2)) AS Credit,
                l.TaxHeadID, l.TaxAccountID, ta.Code AS TaxAccountCode, ta.Title AS TaxAccountTitle,
                l.TaxPercent, l.TaxAmount,
                l.ChequeNo, l.ChequeStatus, l.ChequeTitle, l.ReferenceNo,
                l.KnockOff, l.BillRef, l.BillDate, l.DueDate,
                l.PartyMemberID, m.FullName AS PartyMemberName,
                l.PartySupplierID, s.Name AS PartySupplierName,
                l.PartyStaffID, st.FullName AS PartyStaffName
        FROM dbo.BankVoucherLines l
        JOIN dbo.Accounts a ON a.AccountID = l.AccountID
        LEFT JOIN dbo.Accounts ta ON ta.AccountID = l.TaxAccountID
        LEFT JOIN dbo.Members m ON m.MemberID = l.PartyMemberID
        LEFT JOIN dbo.Suppliers s ON s.SupplierID = l.PartySupplierID
        LEFT JOIN dbo.Staff st ON st.StaffID = l.PartyStaffID
        WHERE l.BankVoucherID = @ID
        ORDER BY l.BankVoucherLineID;

        SELECT AllocationID, LineID, BillRef, PartyMemberID, PartySupplierID, Amount, IsReversed
        FROM dbo.FinanceLineAllocations
        WHERE Family = 'BANK' AND DocumentID = @ID
        ORDER BY AllocationID;
    END
    ELSE IF @Family = 'JOURNAL'
    BEGIN
        SELECT  v.JournalVoucherID AS ID, v.VoucherNo, v.VoucherDate, CAST(NULL AS NVARCHAR(10)) AS Direction,
                v.Narrative, v.DebitTotal AS Amount, v.DebitTotal AS DebitTotal, v.CreditTotal AS CreditTotal,
                v.Status, v.BranchID, b.Name AS BranchName,
                CAST(NULL AS INT) AS MoneyAccountID, CAST(NULL AS NVARCHAR(20)) AS MoneyAccountCode,
                CAST(NULL AS NVARCHAR(150)) AS MoneyAccountTitle,
                lv.VoucherNo AS LedgerVoucherNo, lv.Status AS LedgerStatus, v.ReversedAt,
                u.FullName AS CreatedByName, v.CreatedAt
        FROM dbo.JournalVouchers v
        JOIN dbo.Branches b ON b.BranchID = v.BranchID
        LEFT JOIN dbo.Vouchers lv ON lv.VoucherID = v.VoucherID
        LEFT JOIN dbo.Users u ON u.UserID = v.CreatedBy
        WHERE v.JournalVoucherID = @ID AND v.IsDeleted = 0;

        SELECT  l.JournalVoucherLineID AS LineID, l.AccountID, a.Code AS AccountCode, a.Title AS AccountTitle,
                l.Description, CAST(NULL AS DECIMAL(18,2)) AS Amount, l.Debit, l.Credit,
                CAST(NULL AS INT) AS TaxHeadID, CAST(NULL AS INT) AS TaxAccountID,
                CAST(NULL AS NVARCHAR(20)) AS TaxAccountCode, CAST(NULL AS NVARCHAR(150)) AS TaxAccountTitle,
                CAST(NULL AS DECIMAL(9,4)) AS TaxPercent, CAST(NULL AS DECIMAL(18,2)) AS TaxAmount,
                CAST(NULL AS NVARCHAR(50)) AS ChequeNo, CAST(NULL AS NVARCHAR(20)) AS ChequeStatus,
                CAST(NULL AS NVARCHAR(150)) AS ChequeTitle, CAST(NULL AS NVARCHAR(50)) AS ReferenceNo,
                CAST(0 AS BIT) AS KnockOff, CAST(NULL AS NVARCHAR(50)) AS BillRef,
                CAST(NULL AS DATE) AS BillDate, CAST(NULL AS DATE) AS DueDate,
                CAST(NULL AS INT) AS PartyMemberID, CAST(NULL AS INT) AS PartySupplierID, CAST(NULL AS INT) AS PartyStaffID
        FROM dbo.JournalVoucherLines l
        JOIN dbo.Accounts a ON a.AccountID = l.AccountID
        WHERE l.JournalVoucherID = @ID
        ORDER BY l.JournalVoucherLineID;

        SELECT CAST(NULL AS BIGINT) AS AllocationID, CAST(NULL AS BIGINT) AS LineID,
               CAST(NULL AS NVARCHAR(50)) AS BillRef, CAST(NULL AS INT) AS PartyMemberID,
               CAST(NULL AS INT) AS PartySupplierID, CAST(NULL AS DECIMAL(18,2)) AS Amount,
               CAST(NULL AS BIT) AS IsReversed
        WHERE 1 = 0;
    END
    ELSE IF @Family = 'OTB'
    BEGIN
        SELECT  v.OpeningTBID AS ID, v.VoucherNo, v.VoucherDate, CAST(NULL AS NVARCHAR(10)) AS Direction,
                v.Narrative, v.DebitTotal AS Amount, v.DebitTotal AS DebitTotal, v.CreditTotal AS CreditTotal,
                v.Status, v.BranchID, b.Name AS BranchName,
                CAST(NULL AS INT) AS MoneyAccountID, CAST(NULL AS NVARCHAR(20)) AS MoneyAccountCode,
                CAST(NULL AS NVARCHAR(150)) AS MoneyAccountTitle,
                lv.VoucherNo AS LedgerVoucherNo, lv.Status AS LedgerStatus, v.ReversedAt,
                u.FullName AS CreatedByName, v.CreatedAt
        FROM dbo.OpeningTrialBalances v
        JOIN dbo.Branches b ON b.BranchID = v.BranchID
        LEFT JOIN dbo.Vouchers lv ON lv.VoucherID = v.VoucherID
        LEFT JOIN dbo.Users u ON u.UserID = v.CreatedBy
        WHERE v.OpeningTBID = @ID AND v.IsDeleted = 0;

        SELECT  l.OpeningTBLineID AS LineID, l.AccountID, a.Code AS AccountCode, a.Title AS AccountTitle,
                l.Description, CAST(NULL AS DECIMAL(18,2)) AS Amount, l.Debit, l.Credit,
                CAST(NULL AS INT) AS TaxHeadID, CAST(NULL AS INT) AS TaxAccountID,
                CAST(NULL AS NVARCHAR(20)) AS TaxAccountCode, CAST(NULL AS NVARCHAR(150)) AS TaxAccountTitle,
                CAST(NULL AS DECIMAL(9,4)) AS TaxPercent, CAST(NULL AS DECIMAL(18,2)) AS TaxAmount,
                CAST(NULL AS NVARCHAR(50)) AS ChequeNo, CAST(NULL AS NVARCHAR(20)) AS ChequeStatus,
                CAST(NULL AS NVARCHAR(150)) AS ChequeTitle, CAST(NULL AS NVARCHAR(50)) AS ReferenceNo,
                CAST(0 AS BIT) AS KnockOff, CAST(NULL AS NVARCHAR(50)) AS BillRef,
                CAST(NULL AS DATE) AS BillDate, CAST(NULL AS DATE) AS DueDate,
                CAST(NULL AS INT) AS PartyMemberID, CAST(NULL AS INT) AS PartySupplierID, CAST(NULL AS INT) AS PartyStaffID
        FROM dbo.OpeningTBLines l
        JOIN dbo.Accounts a ON a.AccountID = l.AccountID
        WHERE l.OpeningTBID = @ID
        ORDER BY l.OpeningTBLineID;

        SELECT CAST(NULL AS BIGINT) AS AllocationID, CAST(NULL AS BIGINT) AS LineID,
               CAST(NULL AS NVARCHAR(50)) AS BillRef, CAST(NULL AS INT) AS PartyMemberID,
               CAST(NULL AS INT) AS PartySupplierID, CAST(NULL AS DECIMAL(18,2)) AS Amount,
               CAST(NULL AS BIT) AS IsReversed
        WHERE 1 = 0;
    END
    ELSE
        THROW 51051, 'Invalid voucher family.', 1;
END
GO

PRINT '=== 16_vouchers_upgrade.sql (procedures) applied. ===';
GO

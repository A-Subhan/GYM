/* ============================================================================
   CONTOURA LABS — GYM MANAGEMENT SYSTEM
   FINANCE & ACCOUNTING MODULE — STORED PROCEDURES (12_finance_procedures.sql)
   ----------------------------------------------------------------------------
   Idempotent (all CREATE OR ALTER). Run AFTER 11_finance_schema.sql,
   BEFORE 13_finance_permissions_defaults.sql.

   Sections:
     1. COA structure + accounts + tags
     2. Financial years + accounting periods
     3. Voucher types
     4. Voucher CRUD + CENTRAL POSTING ENGINE + reversal
     5. Reports (Ledger, TB, OTB, BS, P&L, Register, Aging, Bank Statement)
     6. Bank reconciliation
     7. Mappings, user report formats, dashboard

   Error numbers (THROW) — mapped to friendly messages in the backend:
     51001 voucher not found          51002 voucher not a draft
     51003 voucher already posted     51004 debit <> credit
     51005 fewer than 2 entries       51006 debit total <= 0
     51007 control/inactive account   51008 account not found
     51010 invalid COA config         51011 duplicate account code
     51012 invalid code/level/parent  51013 account has children
     51014 account has transactions   51015 no FY for date
     51016 FY locked/closed           51017 period closed / not found
     51018 invalid branch             51019 party reference invalid
     51020 prefix locked              51021 voucher type invalid
     51022 already reversed           51023 draft cannot be reversed
     51024 reversal period closed     51025 overlapping financial year
     51026 FY name conflict           51027 retained earnings not configured
     51028 invalid retained earnings  51029 structure change invalidates codes
     51030 cannot change used prefix  51031 entry side invalid
     51032 account tag missing        51033 recon run invalid
     51034 cannot edit posted voucher 51035 cannot delete posted voucher
     51036 cannot close FY (drafts)   51037 financial year not found
     51038 period not found           51039 tender (cash/bank) tag rule
     51040 FY already closed          51041 report filter invalid
   ============================================================================ */

/* ================================================================== */
/* SECTION 1 — COA STRUCTURE, ACCOUNTS, TAGS                          */
/* ================================================================== */

CREATE OR ALTER PROCEDURE dbo.sp_FinanceCoaLevels_Get
AS
BEGIN
    SET NOCOUNT ON;
    SELECT LevelNo, Digits,
           (SELECT SUM(Digits) FROM dbo.FinanceCoaLevels l2 WHERE l2.LevelNo <= l.LevelNo) AS CumDigits
    FROM dbo.FinanceCoaLevels l
    ORDER BY LevelNo;

    SELECT CASE WHEN EXISTS (SELECT 1 FROM dbo.Accounts) THEN 1 ELSE 0 END AS HasAccounts,
           (SELECT COUNT(*) FROM dbo.Accounts) AS AccountCount;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_FinanceCoaLevels_Set
    @LevelsJson NVARCHAR(MAX),
    @UpdatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        -- Parse a digits-per-level array, e.g. "[1,2,2,3]" (level = index + 1)
        IF OBJECT_ID('tempdb..#NewLevels') IS NOT NULL DROP TABLE #NewLevels;
        CREATE TABLE #NewLevels (LevelNo INT PRIMARY KEY, Digits INT NOT NULL);

        INSERT INTO #NewLevels (LevelNo, Digits)
        SELECT CAST([key] AS INT) + 1, CAST(CAST([value] AS NVARCHAR(10)) AS INT)
        FROM OPENJSON(@LevelsJson)
        WHERE ISNUMERIC(CAST([value] AS NVARCHAR(10))) = 1;

        DECLARE @Count INT = (SELECT COUNT(*) FROM #NewLevels);
        DECLARE @MaxDigits INT = (SELECT ISNULL(MAX(Digits),0) FROM #NewLevels);
        DECLARE @TotalDigits INT = (SELECT ISNULL(SUM(Digits),0) FROM #NewLevels);
        DECLARE @MinLevel INT = (SELECT ISNULL(MIN(LevelNo),1) FROM #NewLevels);
        DECLARE @MaxLevel INT = (SELECT ISNULL(MAX(LevelNo),1) FROM #NewLevels);

        IF @Count < 1 OR @Count > 7
            THROW 51010, 'COA structure must define between 1 and 7 levels.', 1;
        IF @MinLevel <> 1 OR @MaxLevel <> @Count
            THROW 51010, 'COA structure levels must be consecutive starting at 1.', 1;
        IF EXISTS (SELECT 1 FROM #NewLevels WHERE Digits < 1 OR Digits > 12)
            THROW 51010, 'Each level must use between 1 and 12 digits.', 1;
        IF @TotalDigits > 12
            THROW 51010, 'COA structure cannot exceed 12 total code digits.', 1;
        IF @MaxDigits > 6
            THROW 51010, 'A single level cannot use more than 6 digits.', 1;

        -- Validate that every existing account still conforms to the new structure
        IF OBJECT_ID('tempdb..#PrefixSums') IS NOT NULL DROP TABLE #PrefixSums;
        CREATE TABLE #PrefixSums (LevelNo INT PRIMARY KEY, CumDigits INT);
        INSERT INTO #PrefixSums (LevelNo, CumDigits)
        SELECT LevelNo, (SELECT SUM(Digits) FROM #NewLevels n2 WHERE n2.LevelNo <= n.LevelNo)
        FROM #NewLevels n;

        IF EXISTS (
            SELECT 1
            FROM dbo.Accounts a
            LEFT JOIN #PrefixSums p ON p.LevelNo = a.LevelNo
            WHERE a.IsDeleted = 0
              AND (p.CumDigits IS NULL OR LEN(a.Code) <> p.CumDigits)
        )
            THROW 51029, 'COA structure is locked: the new configuration would invalidate existing account codes.', 1;

        MERGE dbo.FinanceCoaLevels AS t
        USING #NewLevels AS s ON t.LevelNo = s.LevelNo
        WHEN MATCHED THEN UPDATE SET Digits = s.Digits, UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @UpdatedBy
        WHEN NOT MATCHED THEN INSERT (LevelNo, Digits, UpdatedBy) VALUES (s.LevelNo, s.Digits, @UpdatedBy);

        -- Remove levels that no longer exist (possible only when no accounts are stored)
        DELETE l FROM dbo.FinanceCoaLevels l
        WHERE NOT EXISTS (SELECT 1 FROM #NewLevels n WHERE n.LevelNo = l.LevelNo);

        COMMIT TRANSACTION;
        SELECT 'OK' AS Result;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

/* ---------------- Accounts list (flat, with parent info + tags) --- */

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
            a.LevelNo, a.IsControl, a.IsActive, a.IsDeleted, a.CreatedAt, a.UpdatedAt,
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

/* ---------------- Account create ---------------------------------- */

CREATE OR ALTER PROCEDURE dbo.sp_FinanceAccounts_Create
    @Code        NVARCHAR(12),
    @Title       NVARCHAR(150),
    @AccountType NVARCHAR(20),
    @ParentAccountID INT = NULL,
    @IsControl   BIT = 1,
    @TagsJson    NVARCHAR(MAX) = NULL,   -- ["Customer","Bank", ...]
    @CreatedBy   INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @C NVARCHAR(12) = LTRIM(RTRIM(@Code));

        -- code must be digits only, within max length
        IF @C IS NULL OR @C NOT LIKE '[0-9]%' OR @C LIKE '%[^0-9]%'
            THROW 51012, 'Account code must contain digits only.', 1;
        IF LEN(@C) > 12
            THROW 51012, 'Account code cannot exceed 12 digits.', 1;

        -- duplicate code
        IF EXISTS (SELECT 1 FROM dbo.Accounts WHERE Code = @C AND IsDeleted = 0)
            THROW 51011, 'An account with this code already exists.', 1;

        IF @AccountType NOT IN ('Asset','Liability','Capital','Revenue','Expense')
            THROW 51012, 'Invalid account type.', 1;

        -- derive level from the configured structure
        DECLARE @LevelNo INT = NULL;
        SELECT @LevelNo = p.LevelNo
        FROM dbo.FinanceCoaLevels l
        JOIN (SELECT l3.LevelNo, (SELECT SUM(Digits) FROM dbo.FinanceCoaLevels l4 WHERE l4.LevelNo <= l3.LevelNo) AS Cum
              FROM dbo.FinanceCoaLevels l3) p ON p.LevelNo = l.LevelNo
        WHERE p.Cum = LEN(@C);

        IF @LevelNo IS NULL
            THROW 51012, 'Account code length does not match any configured COA level. Review the COA structure in Finance Defaults.', 1;

        -- parent validation
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

        INSERT INTO dbo.Accounts (Code, Title, AccountType, ParentAccountID, LevelNo, IsControl, CreatedBy)
        VALUES (@C, LTRIM(RTRIM(@Title)), @AccountType, @ParentAccountID, @LevelNo, @IsControl, @CreatedBy);

        DECLARE @NewID INT = CAST(SCOPE_IDENTITY() AS INT);

        -- tags
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

        UPDATE dbo.Accounts SET Title = LTRIM(RTRIM(@Title)), UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @UpdatedBy
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

CREATE OR ALTER PROCEDURE dbo.sp_FinanceAccounts_SetStatus
    @AccountID INT, @IsActive BIT, @UpdatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM dbo.Accounts WHERE AccountID = @AccountID AND IsDeleted = 0)
            THROW 51008, 'Account not found.', 1;

        IF @IsActive = 0 AND EXISTS (
            SELECT 1 FROM dbo.Accounts c
            WHERE c.ParentAccountID = @AccountID AND c.IsDeleted = 0 AND c.IsActive = 1)
            THROW 51013, 'Account has active child accounts. Deactivate the children first.', 1;

        UPDATE dbo.Accounts SET IsActive = @IsActive, UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @UpdatedBy
        WHERE AccountID = @AccountID;
        SELECT 'OK' AS Result;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_FinanceAccounts_Delete
    @AccountID INT, @DeletedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        IF NOT EXISTS (SELECT 1 FROM dbo.Accounts WHERE AccountID = @AccountID AND IsDeleted = 0)
            THROW 51008, 'Account not found.', 1;

        IF EXISTS (SELECT 1 FROM dbo.Accounts c WHERE c.ParentAccountID = @AccountID AND c.IsDeleted = 0)
            THROW 51013, 'Account has child accounts and cannot be deleted.', 1;

        IF EXISTS (SELECT 1 FROM dbo.VoucherEntries WHERE AccountID = @AccountID)
            THROW 51014, 'Account has posted transactions and cannot be deleted. Deactivate it instead.', 1;

        IF EXISTS (SELECT 1 FROM dbo.FinanceMappings WHERE AccountID = @AccountID AND IsActive = 1)
            THROW 51014, 'Account is used in Finance mappings and cannot be deleted.', 1;

        UPDATE dbo.Accounts SET IsDeleted = 1, IsActive = 0, UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @DeletedBy
        WHERE AccountID = @AccountID;
        DELETE FROM dbo.AccountTags WHERE AccountID = @AccountID;

        COMMIT TRANSACTION;
        SELECT 'OK' AS Result;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

/* ---------------- Context-sensitive account selector -------------- */
/* Returns ONLY active Detail accounts carrying the requested tag.     */

CREATE OR ALTER PROCEDURE dbo.sp_FinanceAccounts_Selector
    @Tag    NVARCHAR(30) = NULL,
    @Search NVARCHAR(100) = NULL,
    @TopN   INT = 100
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (@TopN)
           a.AccountID, a.Code, a.Title, a.AccountType,
           (SELECT COUNT(*) FROM dbo.AccountTags t2 WHERE t2.AccountID = a.AccountID) AS TagCount
    FROM dbo.Accounts a
    WHERE a.IsControl = 0 AND a.IsActive = 1 AND a.IsDeleted = 0
      AND (@Tag IS NULL OR EXISTS (SELECT 1 FROM dbo.AccountTags t WHERE t.AccountID = a.AccountID AND t.Tag = @Tag))
      AND (@Search IS NULL OR a.Code LIKE '%' + @Search + '%' OR a.Title LIKE '%' + @Search + '%')
    ORDER BY a.Code;
END
GO

/* ================================================================== */
/* SECTION 2 — FINANCIAL YEARS + ACCOUNTING PERIODS                   */
/* ================================================================== */

CREATE OR ALTER PROCEDURE dbo.sp_FinanceYears_List
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  fy.FinancialYearID, fy.Name, fy.StartDate, fy.EndDate, fy.Status,
            fy.CreatedAt, fy.UpdatedAt,
            (SELECT COUNT(*) FROM dbo.AccountingPeriods p WHERE p.FinancialYearID = fy.FinancialYearID) AS PeriodCount,
            (SELECT COUNT(*) FROM dbo.Vouchers v WHERE v.FinancialYearID = fy.FinancialYearID AND v.Status <> 'Draft' AND v.IsDeleted = 0) AS VoucherCount,
            (SELECT ISNULL(SUM(v.DebitTotal),0) FROM dbo.Vouchers v WHERE v.FinancialYearID = fy.FinancialYearID AND v.Status IN ('Posted','Reversed')) AS TotalDebit,
            (SELECT ISNULL(SUM(v.CreditTotal),0) FROM dbo.Vouchers v WHERE v.FinancialYearID = fy.FinancialYearID AND v.Status IN ('Posted','Reversed')) AS TotalCredit,
            CASE WHEN EXISTS (SELECT 1 FROM dbo.AccountingPeriods p
                              WHERE p.FinancialYearID = fy.FinancialYearID AND p.Status = 'Open')
                 THEN 0 ELSE 1 END AS AllPeriodsClosed
    FROM dbo.FinancialYears fy
    ORDER BY fy.StartDate DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_FinanceYears_Create
    @Name     NVARCHAR(50),
    @StartDate DATE,
    @EndDate   DATE,
    @CreatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        IF @EndDate < @StartDate
            THROW 51010, 'Financial year end date must be on or after the start date.', 1;
        IF EXISTS (SELECT 1 FROM dbo.FinancialYears
                   WHERE (@StartDate <= EndDate) AND (@EndDate >= StartDate))
            THROW 51025, 'The new financial year overlaps an existing financial year.', 1;
        IF EXISTS (SELECT 1 FROM dbo.FinancialYears WHERE Name = @Name)
            THROW 51026, 'A financial year with this name already exists.', 1;

        INSERT INTO dbo.FinancialYears (Name, StartDate, EndDate, Status, CreatedBy)
        VALUES (@Name, @StartDate, @EndDate, 'Open', @CreatedBy);
        DECLARE @FY INT = CAST(SCOPE_IDENTITY() AS INT);

        -- 12 monthly periods
        DECLARE @i INT = 0;
        WHILE @i < 12
        BEGIN
            DECLARE @s DATE = DATEADD(MONTH, @i, @StartDate);
            DECLARE @e DATE = CASE WHEN @i = 11 THEN @EndDate
                                   WHEN EOMONTH(@s) > @EndDate THEN @EndDate
                                   ELSE EOMONTH(@s) END;
            INSERT INTO dbo.AccountingPeriods (FinancialYearID, PeriodNo, StartDate, EndDate, Status, CreatedBy)
            VALUES (@FY, @i + 1, @s, @e, 'Open', @CreatedBy);
            SET @i = @i + 1;
        END

        COMMIT TRANSACTION;
        SELECT @FY AS FinancialYearID;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_FinancePeriods_List
    @FinancialYearID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.PeriodID, p.FinancialYearID, p.PeriodNo, p.StartDate, p.EndDate, p.Status,
           (SELECT COUNT(*) FROM dbo.Vouchers v
            WHERE v.FinancialYearID = p.FinancialYearID
              AND v.VoucherDate BETWEEN p.StartDate AND p.EndDate
              AND v.Status = 'Draft' AND v.IsDeleted = 0) AS DraftCount
    FROM dbo.AccountingPeriods p
    WHERE p.FinancialYearID = @FinancialYearID
    ORDER BY p.PeriodNo;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_FinancePeriods_SetStatus
    @PeriodID INT, @Status NVARCHAR(20), @UpdatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        DECLARE @FY INT, @FYStatus NVARCHAR(20);
        SELECT @FY = p.FinancialYearID, @FYStatus = fy.Status
        FROM dbo.AccountingPeriods p
        JOIN dbo.FinancialYears fy ON fy.FinancialYearID = p.FinancialYearID
        WHERE p.PeriodID = @PeriodID;

        IF @FY IS NULL THROW 51038, 'Accounting period not found.', 1;
        IF @Status NOT IN ('Open','Closed','Locked')
            THROW 51010, 'Invalid period status.', 1;
        IF @FYStatus = 'Closed'
            THROW 51016, 'The financial year is closed; period status cannot change.', 1;

        UPDATE dbo.AccountingPeriods SET Status = @Status, UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @UpdatedBy
        WHERE PeriodID = @PeriodID;
        SELECT 'OK' AS Result;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

/* ================================================================== */
/* SECTION 3 — VOUCHER TYPES                                          */
/* ================================================================== */

CREATE OR ALTER PROCEDURE dbo.sp_FinanceVoucherTypes_List
AS
BEGIN
    SET NOCOUNT ON;
    SELECT t.VoucherTypeID, t.TypeCode, t.Title, t.Prefix, t.PrefixLocked, t.TenderTag,
           t.Nature, t.IsActive, t.CreatedAt, t.UpdatedAt,
           (SELECT COUNT(*) FROM dbo.Vouchers v
             WHERE v.VoucherTypeID = t.VoucherTypeID AND v.Status IN ('Posted','Reversed')) AS UsedCount
    FROM dbo.VoucherTypes t
    ORDER BY t.VoucherTypeID;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_FinanceVoucherTypes_Update
    @VoucherTypeID INT,
    @Title    NVARCHAR(100) = NULL,
    @Prefix   NVARCHAR(10)  = NULL,
    @IsActive BIT = NULL,
    @UpdatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM dbo.VoucherTypes WHERE VoucherTypeID = @VoucherTypeID)
            THROW 51021, 'Voucher type not found.', 1;

        IF @Prefix IS NOT NULL
        BEGIN
            IF EXISTS (SELECT 1 FROM dbo.Vouchers v
                       WHERE v.VoucherTypeID = @VoucherTypeID AND v.Status IN ('Posted','Reversed'))
                THROW 51030, 'The prefix is locked: vouchers already exist for this voucher type.', 1;
        END

        UPDATE dbo.VoucherTypes SET
            Title = COALESCE(@Title, Title),
            Prefix = COALESCE(@Prefix, Prefix),
            IsActive = COALESCE(@IsActive, IsActive),
            UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @UpdatedBy
        WHERE VoucherTypeID = @VoucherTypeID;

        SELECT 'OK' AS Result;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

/* ================================================================== */
/* SECTION 4 — VOUCHERS + CENTRAL POSTING ENGINE                      */
/* ================================================================== */

/* ---------------- Preview next voucher number (no side effects) --- */

CREATE OR ALTER PROCEDURE dbo.sp_FinanceVouchers_NextNo
    @VoucherTypeID INT, @BranchID INT, @VoucherDate DATE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @FY INT = (SELECT FinancialYearID FROM dbo.FinancialYears
                       WHERE @VoucherDate BETWEEN StartDate AND EndDate);
    DECLARE @Prefix NVARCHAR(10) = (SELECT Prefix FROM dbo.VoucherTypes WHERE VoucherTypeID = @VoucherTypeID);
    DECLARE @Seq INT = 1;
    IF @FY IS NOT NULL
    BEGIN
        DECLARE @Scope NVARCHAR(60) = 'VT' + CAST(@VoucherTypeID AS NVARCHAR(10)) + '-BR' + CAST(@BranchID AS NVARCHAR(10)) + '-FY' + CAST(@FY AS NVARCHAR(10));
        SELECT @Seq = NextSeq FROM dbo.FinanceSequences WHERE ScopeKey = @Scope;
        IF @Seq IS NULL SET @Seq = 1;
    END
    DECLARE @SeqDigits INT = 4, @DateFmt NVARCHAR(20) = 'ddMMyyyy', @Cfg NVARCHAR(MAX);
    SELECT @Cfg = Value FROM dbo.Settings WHERE [Key] = 'FinanceVoucherNumbering';
    IF @Cfg IS NOT NULL
    BEGIN
        SET @SeqDigits = ISNULL(TRY_CAST(JSON_VALUE(@Cfg, '$.seqDigits') AS INT), 4);
        SET @DateFmt   = ISNULL(JSON_VALUE(@Cfg, '$.dateFormat'), 'ddMMyyyy');
    END
    SELECT @Prefix + '-' + FORMAT(@VoucherDate, @DateFmt) + RIGHT(REPLICATE('0', 10) + CAST(@Seq AS NVARCHAR(10)), @SeqDigits) AS NextNo;
END
GO

/* ---------------- Paged voucher list ------------------------------ */

CREATE OR ALTER PROCEDURE dbo.sp_FinanceVouchers_List
    @Page INT = 1, @PageSize INT = 20,
    @VoucherTypeID INT = NULL,
    @Status NVARCHAR(20) = NULL,
    @BranchID INT = NULL,
    @FromDate DATE = NULL,
    @ToDate DATE = NULL,
    @AccountID INT = NULL,
    @Search NVARCHAR(100) = NULL,
    @CreatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Offset INT = (@Page - 1) * @PageSize;

    SELECT  v.VoucherID, v.VoucherNo, v.VoucherTypeID, t.TypeCode, t.Title AS TypeTitle, t.Nature,
            v.VoucherDate, v.BranchID, b.Name AS BranchName, fy.Name AS FinancialYearName,
            v.Narrative, v.Status, v.DebitTotal, v.CreditTotal,
            v.SourceModule, v.SourceID, v.ReversalOfVoucherID,
            u.FullName AS CreatedByName, pu.FullName AS PostedByName,
            v.CreatedAt, v.PostedAt
    FROM    dbo.Vouchers v
    JOIN    dbo.VoucherTypes t ON t.VoucherTypeID = v.VoucherTypeID
    JOIN    dbo.Branches b ON b.BranchID = v.BranchID
    LEFT JOIN dbo.FinancialYears fy ON fy.FinancialYearID = v.FinancialYearID
    LEFT JOIN dbo.Users u ON u.UserID = v.CreatedBy
    LEFT JOIN dbo.Users pu ON pu.UserID = v.PostedBy
    WHERE   v.IsDeleted = 0
      AND   (@VoucherTypeID IS NULL OR v.VoucherTypeID = @VoucherTypeID)
      AND   (@Status IS NULL OR v.Status = @Status)
      AND   (@BranchID IS NULL OR v.BranchID = @BranchID)
      AND   (@FromDate IS NULL OR v.VoucherDate >= @FromDate)
      AND   (@ToDate IS NULL OR v.VoucherDate <= @ToDate)
      AND   (@CreatedBy IS NULL OR v.CreatedBy = @CreatedBy)
      AND   (@AccountID IS NULL OR EXISTS (SELECT 1 FROM dbo.VoucherEntries e WHERE e.VoucherID = v.VoucherID AND e.AccountID = @AccountID))
      AND   (@Search IS NULL OR v.VoucherNo LIKE '%' + @Search + '%' OR v.Narrative LIKE '%' + @Search + '%')
    ORDER BY v.VoucherDate DESC, v.VoucherID DESC
    OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT  COUNT(*) AS Total,
            ISNULL(SUM(CASE WHEN v.Status IN ('Posted','Reversed') THEN v.DebitTotal ELSE 0 END), 0) AS TotalDebit,
            ISNULL(SUM(CASE WHEN v.Status IN ('Posted','Reversed') THEN v.CreditTotal ELSE 0 END), 0) AS TotalCredit
    FROM    dbo.Vouchers v
    WHERE   v.IsDeleted = 0
      AND   (@VoucherTypeID IS NULL OR v.VoucherTypeID = @VoucherTypeID)
      AND   (@Status IS NULL OR v.Status = @Status)
      AND   (@BranchID IS NULL OR v.BranchID = @BranchID)
      AND   (@FromDate IS NULL OR v.VoucherDate >= @FromDate)
      AND   (@ToDate IS NULL OR v.VoucherDate <= @ToDate)
      AND   (@CreatedBy IS NULL OR v.CreatedBy = @CreatedBy)
      AND   (@AccountID IS NULL OR EXISTS (SELECT 1 FROM dbo.VoucherEntries e WHERE e.VoucherID = v.VoucherID AND e.AccountID = @AccountID))
      AND   (@Search IS NULL OR v.VoucherNo LIKE '%' + @Search + '%' OR v.Narrative LIKE '%' + @Search + '%');
END
GO

/* ---------------- Voucher get (header + entries) ------------------ */

CREATE OR ALTER PROCEDURE dbo.sp_FinanceVouchers_Get
    @VoucherID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  v.VoucherID, v.VoucherNo, v.VoucherTypeID, t.TypeCode, t.Title AS TypeTitle,
            t.Nature, t.TenderTag, t.Prefix,
            v.VoucherDate, v.BranchID, b.Name AS BranchName,
            v.FinancialYearID, fy.Name AS FinancialYearName,
            v.Narrative, v.Status, v.DebitTotal, v.CreditTotal,
            v.SourceModule, v.SourceID, v.ReversalOfVoucherID,
            rv.VoucherNo AS ReversalOfVoucherNo,
            v.PostedBy, pu.FullName AS PostedByName, v.PostedAt,
            v.ReversedBy, ru.FullName AS ReversedByName, v.ReversedAt,
            v.CreatedBy, cu.FullName AS CreatedByName, v.CreatedAt, v.UpdatedAt
    FROM dbo.Vouchers v
    JOIN dbo.VoucherTypes t ON t.VoucherTypeID = v.VoucherTypeID
    JOIN dbo.Branches b ON b.BranchID = v.BranchID
    LEFT JOIN dbo.FinancialYears fy ON fy.FinancialYearID = v.FinancialYearID
    LEFT JOIN dbo.Vouchers rv ON rv.VoucherID = v.ReversalOfVoucherID
    LEFT JOIN dbo.Users pu ON pu.UserID = v.PostedBy
    LEFT JOIN dbo.Users ru ON ru.UserID = v.ReversedBy
    LEFT JOIN dbo.Users cu ON cu.UserID = v.CreatedBy
    WHERE v.VoucherID = @VoucherID AND v.IsDeleted = 0;

    SELECT  e.EntryID, e.AccountID, a.Code AS AccountCode, a.Title AS AccountTitle, a.AccountType,
            e.Debit, e.Credit, e.Narrative,
            e.PartyMemberID, m.FullName AS PartyMemberName, m.Code AS PartyMemberCode,
            e.PartySupplierID, s.Name AS PartySupplierName,
            e.PartyStaffID, st.FullName AS PartyStaffName,
            e.BillRef, e.BillDate, e.DueDate
    FROM dbo.VoucherEntries e
    JOIN dbo.Accounts a ON a.AccountID = e.AccountID
    LEFT JOIN dbo.Members m ON m.MemberID = e.PartyMemberID
    LEFT JOIN dbo.Suppliers s ON s.SupplierID = e.PartySupplierID
    LEFT JOIN dbo.Staff st ON st.StaffID = e.PartyStaffID
    WHERE e.VoucherID = @VoucherID
    ORDER BY e.EntryID;
END
GO

/* ---------------- Delete draft (soft) ------------------------------ */

CREATE OR ALTER PROCEDURE dbo.sp_FinanceVouchers_DeleteDraft
    @VoucherID INT, @DeletedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        DECLARE @Status NVARCHAR(20);
        SELECT @Status = Status FROM dbo.Vouchers WHERE VoucherID = @VoucherID AND IsDeleted = 0;
        IF @Status IS NULL THROW 51001, 'Voucher not found.', 1;
        IF @Status <> 'Draft'
            THROW 51035, 'Posted vouchers cannot be deleted. Reverse the voucher instead.', 1;

        UPDATE dbo.Vouchers SET IsDeleted = 1, UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @DeletedBy
        WHERE VoucherID = @VoucherID;
        SELECT 'OK' AS Result;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

/* ================================================================== */
/* SECTION 2b — FINANCIAL YEAR STATUS + CLOSING                       */
/* ================================================================== */

CREATE OR ALTER PROCEDURE dbo.sp_FinanceYears_SetStatus
    @FinancialYearID INT, @Status NVARCHAR(20), @UpdatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        DECLARE @Current NVARCHAR(20);
        SELECT @Current = Status FROM dbo.FinancialYears WHERE FinancialYearID = @FinancialYearID;
        IF @Current IS NULL THROW 51037, 'Financial year not found.', 1;
        IF @Status NOT IN ('Open','Locked')
            THROW 51010, 'Use Close to close a financial year.', 1;
        IF @Current = 'Closed'
            THROW 51040, 'A closed financial year cannot be reopened.', 1;

        UPDATE dbo.FinancialYears SET Status = @Status, UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @UpdatedBy
        WHERE FinancialYearID = @FinancialYearID;
        SELECT 'OK' AS Result;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

/* ================================================================== */
/* SECTION 5 — REPORTS                                                */
/* ================================================================== */

/* ---------------- General Ledger ----------------------------------- */

CREATE OR ALTER PROCEDURE dbo.sp_FinanceReports_Ledger
    @AccountID       INT = NULL,
    @GroupAccountID  INT = NULL,     -- include all detail descendants of a control account
    @FromDate        DATE = NULL,
    @ToDate          DATE = NULL,
    @BranchID        INT = NULL,
    @VoucherTypeID   INT = NULL,
    @VoucherNo       NVARCHAR(50) = NULL,
    @PartyMemberID   INT = NULL,
    @PartySupplierID INT = NULL,
    @PartyStaffID    INT = NULL,
    @RequireTag      NVARCHAR(30) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('tempdb..#Accts') IS NOT NULL DROP TABLE #Accts;
    CREATE TABLE #Accts (AccountID INT PRIMARY KEY);

    IF @AccountID IS NOT NULL
        INSERT INTO #Accts VALUES (@AccountID);
    ELSE IF @GroupAccountID IS NOT NULL
    BEGIN
        INSERT INTO #Accts VALUES (@GroupAccountID);
        ;WITH tree AS (
            SELECT AccountID FROM dbo.Accounts WHERE ParentAccountID = @GroupAccountID
            UNION ALL
            SELECT c.AccountID FROM dbo.Accounts c JOIN tree t ON c.ParentAccountID = t.AccountID
        )
        INSERT INTO #Accts SELECT AccountID FROM tree;
    END
    ELSE
        THROW 51041, 'Select an account or an account group for the ledger.', 1;

    IF @RequireTag IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM #Accts a JOIN dbo.AccountTags t ON t.AccountID = a.AccountID AND t.Tag = @RequireTag)
        THROW 51032, 'The selected account does not carry the required tag.', 1;

    IF @ToDate IS NULL SET @ToDate = CAST(GETDATE() AS DATE);

    DECLARE @Opening DECIMAL(18,2);
    SELECT @Opening = ISNULL(SUM(e.Debit - e.Credit), 0)
    FROM dbo.VoucherEntries e
    JOIN dbo.Vouchers v ON v.VoucherID = e.VoucherID
    WHERE e.AccountID IN (SELECT AccountID FROM #Accts)
      AND v.Status IN ('Posted','Reversed') AND v.IsDeleted = 0
      AND v.VoucherDate < @FromDate
      AND (@BranchID IS NULL OR v.BranchID = @BranchID)
      AND (@VoucherTypeID IS NULL OR v.VoucherTypeID = @VoucherTypeID)
      AND (@VoucherNo IS NULL OR v.VoucherNo LIKE '%' + @VoucherNo + '%')
      AND (@PartyMemberID IS NULL OR e.PartyMemberID = @PartyMemberID)
      AND (@PartySupplierID IS NULL OR e.PartySupplierID = @PartySupplierID)
      AND (@PartyStaffID IS NULL OR e.PartyStaffID = @PartyStaffID);

    IF OBJECT_ID('tempdb..#LedgerLines') IS NOT NULL DROP TABLE #LedgerLines;
    SELECT  e.EntryID, v.VoucherID, v.VoucherNo, v.VoucherDate, t.TypeCode, t.Title AS VoucherType,
                v.BranchID, b.Name AS BranchName,
                a.AccountID, a.Code AS AccountCode, a.Title AS AccountTitle,
                e.Debit, e.Credit, e.Narrative,
                e.PartyMemberID, m.FullName AS PartyMemberName,
                e.PartySupplierID, s.Name AS PartySupplierName,
                e.PartyStaffID, st.FullName AS PartyStaffName,
                u.FullName AS CreatedBy,
                v.Status,
                @Opening + SUM(e.Debit - e.Credit) OVER (ORDER BY v.VoucherDate, e.EntryID
                                ROWS UNBOUNDED PRECEDING) AS RunningBalance
        INTO #LedgerLines
        FROM dbo.VoucherEntries e
        JOIN dbo.Vouchers v ON v.VoucherID = e.VoucherID
        JOIN dbo.VoucherTypes t ON t.VoucherTypeID = v.VoucherTypeID
        JOIN dbo.Branches b ON b.BranchID = v.BranchID
        JOIN dbo.Accounts a ON a.AccountID = e.AccountID
        LEFT JOIN dbo.Members m ON m.MemberID = e.PartyMemberID
        LEFT JOIN dbo.Suppliers s ON s.SupplierID = e.PartySupplierID
        LEFT JOIN dbo.Staff st ON st.StaffID = e.PartyStaffID
        LEFT JOIN dbo.Users u ON u.UserID = v.CreatedBy
        WHERE e.AccountID IN (SELECT AccountID FROM #Accts)
          AND v.Status IN ('Posted','Reversed') AND v.IsDeleted = 0
          AND v.VoucherDate >= @FromDate AND v.VoucherDate <= @ToDate
          AND (@BranchID IS NULL OR v.BranchID = @BranchID)
          AND (@VoucherTypeID IS NULL OR v.VoucherTypeID = @VoucherTypeID)
          AND (@VoucherNo IS NULL OR v.VoucherNo LIKE '%' + @VoucherNo + '%')
          AND (@PartyMemberID IS NULL OR e.PartyMemberID = @PartyMemberID)
          AND (@PartySupplierID IS NULL OR e.PartySupplierID = @PartySupplierID)
          AND (@PartyStaffID IS NULL OR e.PartyStaffID = @PartyStaffID)
    SELECT @Opening AS OpeningBalance,
           ISNULL(SUM(Debit), 0) AS TotalDebit,
           ISNULL(SUM(Credit), 0) AS TotalCredit,
           @Opening + ISNULL(SUM(Debit - Credit), 0) AS ClosingBalance
    FROM #LedgerLines;

    SELECT * FROM #LedgerLines ORDER BY VoucherDate, EntryID;
END
GO

/* ---------------- Trial Balance ------------------------------------ */

CREATE OR ALTER PROCEDURE dbo.sp_FinanceReports_TrialBalance
    @FromDate DATE = NULL,
    @ToDate   DATE = NULL,
    @BranchID INT = NULL,
    @RollupLevel INT = NULL      -- NULL = per detail account; N = roll up to level N
AS
BEGIN
    SET NOCOUNT ON;
    IF @ToDate IS NULL SET @ToDate = CAST(GETDATE() AS DATE);
    IF @FromDate IS NULL SET @FromDate = DATEADD(YEAR, -1, @ToDate);

    IF OBJECT_ID('tempdb..#TB') IS NOT NULL DROP TABLE #TB;
    CREATE TABLE #TB (
        AccountID INT PRIMARY KEY, Code NVARCHAR(12), Title NVARCHAR(150), AccountType NVARCHAR(20),
        LevelNo INT, ParentAccountID INT,
        OpeningDebit DECIMAL(18,2), OpeningCredit DECIMAL(18,2),
        PeriodDebit DECIMAL(18,2), PeriodCredit DECIMAL(18,2));

    INSERT INTO #TB (AccountID, Code, Title, AccountType, LevelNo, ParentAccountID,
                     OpeningDebit, OpeningCredit, PeriodDebit, PeriodCredit)
    SELECT a.AccountID, a.Code, a.Title, a.AccountType, a.LevelNo, a.ParentAccountID,
           ISNULL(SUM(CASE WHEN v.VoucherDate < @FromDate THEN e.Debit ELSE 0 END), 0),
           ISNULL(SUM(CASE WHEN v.VoucherDate < @FromDate THEN e.Credit ELSE 0 END), 0),
           ISNULL(SUM(CASE WHEN v.VoucherDate BETWEEN @FromDate AND @ToDate THEN e.Debit ELSE 0 END), 0),
           ISNULL(SUM(CASE WHEN v.VoucherDate BETWEEN @FromDate AND @ToDate THEN e.Credit ELSE 0 END), 0)
    FROM dbo.Accounts a
    JOIN dbo.VoucherEntries e ON e.AccountID = a.AccountID
    JOIN dbo.Vouchers v ON v.VoucherID = e.VoucherID
         AND v.Status IN ('Posted','Reversed') AND v.IsDeleted = 0
         AND (@BranchID IS NULL OR v.BranchID = @BranchID)
         AND v.VoucherDate <= @ToDate
    WHERE a.IsControl = 0
    GROUP BY a.AccountID, a.Code, a.Title, a.AccountType, a.LevelNo, a.ParentAccountID;

    IF @RollupLevel IS NULL
    BEGIN
        SELECT AccountID, Code, Title, AccountType, LevelNo, ParentAccountID,
               CASE WHEN (OpeningDebit - OpeningCredit) > 0 THEN OpeningDebit - OpeningCredit ELSE 0 END AS OpeningDebit,
               CASE WHEN (OpeningCredit - OpeningDebit) > 0 THEN OpeningCredit - OpeningDebit ELSE 0 END AS OpeningCredit,
               PeriodDebit, PeriodCredit,
               CASE WHEN (OpeningDebit + PeriodDebit - OpeningCredit - PeriodCredit) > 0
                    THEN OpeningDebit + PeriodDebit - OpeningCredit - PeriodCredit ELSE 0 END AS ClosingDebit,
               CASE WHEN (OpeningCredit + PeriodCredit - OpeningDebit - PeriodDebit) > 0
                    THEN OpeningCredit + PeriodCredit - OpeningDebit - PeriodDebit ELSE 0 END AS ClosingCredit
        FROM #TB
        ORDER BY Code;
    END
    ELSE
    BEGIN
        ;WITH ancestry AS (
            SELECT a.AccountID, a.AccountID AS AncestorID, a.LevelNo
            FROM dbo.Accounts a WHERE a.IsDeleted = 0
            UNION ALL
            SELECT ac.AccountID, p.ParentAccountID, p.LevelNo
            FROM ancestry ac
            JOIN dbo.Accounts p ON p.AccountID = ac.AncestorID
            WHERE p.ParentAccountID IS NOT NULL
        ),
        rollup AS (
            SELECT t.Code + ' *' AS Code, an.AncestorID AS AccountID, anc.Title,
                   anc.AccountType, anc.LevelNo, anc.ParentAccountID,
                   SUM(t.OpeningDebit) OpeningDebit, SUM(t.OpeningCredit) OpeningCredit,
                   SUM(t.PeriodDebit) PeriodDebit, SUM(t.PeriodCredit) PeriodCredit
            FROM #TB t
            JOIN ancestry an ON an.AccountID = t.AccountID AND an.LevelNo = @RollupLevel
            JOIN dbo.Accounts anc ON anc.AccountID = an.AncestorID
            GROUP BY t.Code, an.AncestorID, anc.Title, anc.AccountType, anc.LevelNo, anc.ParentAccountID
        )
        SELECT AccountID, Code, Title, AccountType, LevelNo, ParentAccountID,
               CASE WHEN (OpeningDebit - OpeningCredit) > 0 THEN OpeningDebit - OpeningCredit ELSE 0 END AS OpeningDebit,
               CASE WHEN (OpeningCredit - OpeningDebit) > 0 THEN OpeningCredit - OpeningDebit ELSE 0 END AS OpeningCredit,
               PeriodDebit, PeriodCredit,
               CASE WHEN (OpeningDebit + PeriodDebit - OpeningCredit - PeriodCredit) > 0
                    THEN OpeningDebit + PeriodDebit - OpeningCredit - PeriodCredit ELSE 0 END AS ClosingDebit,
               CASE WHEN (OpeningCredit + PeriodCredit - OpeningDebit - PeriodDebit) > 0
                    THEN OpeningCredit + PeriodCredit - OpeningDebit - PeriodDebit ELSE 0 END AS ClosingCredit
        FROM rollup
        ORDER BY Code;
    END

    SELECT  ISNULL(SUM(CASE WHEN (OpeningDebit - OpeningCredit) > 0 THEN OpeningDebit - OpeningCredit ELSE 0 END), 0) AS TotalOpeningDebit,
            ISNULL(SUM(CASE WHEN (OpeningCredit - OpeningDebit) > 0 THEN OpeningCredit - OpeningDebit ELSE 0 END), 0) AS TotalOpeningCredit,
            ISNULL(SUM(PeriodDebit), 0) AS TotalPeriodDebit,
            ISNULL(SUM(PeriodCredit), 0) AS TotalPeriodCredit,
            ISNULL(SUM(CASE WHEN (OpeningDebit + PeriodDebit - OpeningCredit - PeriodCredit) > 0
                            THEN OpeningDebit + PeriodDebit - OpeningCredit - PeriodCredit ELSE 0 END), 0) AS TotalClosingDebit,
            ISNULL(SUM(CASE WHEN (OpeningCredit + PeriodCredit - OpeningDebit - PeriodDebit) > 0
                            THEN OpeningCredit + PeriodCredit - OpeningDebit - PeriodDebit ELSE 0 END), 0) AS TotalClosingCredit
    FROM #TB;
END
GO

/* ---------------- Opening Trial Balance report --------------------- */

CREATE OR ALTER PROCEDURE dbo.sp_FinanceReports_OpeningTB
    @FinancialYearID INT,
    @BranchID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Start DATE = (SELECT StartDate FROM dbo.FinancialYears WHERE FinancialYearID = @FinancialYearID);
    IF @Start IS NULL THROW 51037, 'Financial year not found.', 1;

    SELECT  a.AccountID, a.Code, a.Title, a.AccountType, a.LevelNo, a.ParentAccountID,
            CASE WHEN (ISNULL(SUM(e.Debit),0) - ISNULL(SUM(e.Credit),0)) > 0
                 THEN ISNULL(SUM(e.Debit),0) - ISNULL(SUM(e.Credit),0) ELSE 0 END AS OpeningDebit,
            CASE WHEN (ISNULL(SUM(e.Credit),0) - ISNULL(SUM(e.Debit),0)) > 0
                 THEN ISNULL(SUM(e.Credit),0) - ISNULL(SUM(e.Debit),0) ELSE 0 END AS OpeningCredit
    FROM dbo.Accounts a
    JOIN dbo.VoucherEntries e ON e.AccountID = a.AccountID
    JOIN dbo.Vouchers v ON v.VoucherID = e.VoucherID
         AND v.Status IN ('Posted','Reversed') AND v.IsDeleted = 0
         AND v.VoucherDate < @Start
         AND (@BranchID IS NULL OR v.BranchID = @BranchID)
    WHERE a.IsControl = 0
    GROUP BY a.AccountID, a.Code, a.Title, a.AccountType, a.LevelNo, a.ParentAccountID
    HAVING ISNULL(SUM(e.Debit), 0) <> ISNULL(SUM(e.Credit), 0)
    ORDER BY a.Code;

    SELECT  ISNULL(SUM(CASE WHEN Net > 0 THEN Net ELSE 0 END), 0) AS TotalOpeningDebit,
            ISNULL(SUM(CASE WHEN Net < 0 THEN -Net ELSE 0 END), 0) AS TotalOpeningCredit
    FROM (
        SELECT SUM(e.Debit - e.Credit) AS Net
        FROM dbo.Accounts a
        JOIN dbo.VoucherEntries e ON e.AccountID = a.AccountID
        JOIN dbo.Vouchers v ON v.VoucherID = e.VoucherID
             AND v.Status IN ('Posted','Reversed') AND v.IsDeleted = 0
             AND v.VoucherDate < @Start
             AND (@BranchID IS NULL OR v.BranchID = @BranchID)
        WHERE a.IsControl = 0
        GROUP BY a.AccountID
    ) x;
END
GO

/* ---------------- Balance Sheet ------------------------------------ */

CREATE OR ALTER PROCEDURE dbo.sp_FinanceReports_BalanceSheet
    @AsOf DATE = NULL,
    @BranchID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @AsOf IS NULL SET @AsOf = CAST(GETDATE() AS DATE);

    SELECT  a.AccountID, a.Code, a.Title, a.AccountType, a.LevelNo, a.ParentAccountID,
            ISNULL(SUM(e.Debit), 0) AS TotalDebit,
            ISNULL(SUM(e.Credit), 0) AS TotalCredit,
            ISNULL(SUM(e.Debit - e.Credit), 0) AS Balance   -- debit-positive
    FROM dbo.Accounts a
    JOIN dbo.VoucherEntries e ON e.AccountID = a.AccountID
    JOIN dbo.Vouchers v ON v.VoucherID = e.VoucherID
         AND v.Status IN ('Posted','Reversed') AND v.IsDeleted = 0
         AND v.VoucherDate <= @AsOf
         AND (@BranchID IS NULL OR v.BranchID = @BranchID)
    WHERE a.IsControl = 0 AND a.AccountType IN ('Asset','Liability','Capital')
    GROUP BY a.AccountID, a.Code, a.Title, a.AccountType, a.LevelNo, a.ParentAccountID
    HAVING ISNULL(SUM(e.Debit), 0) <> 0 OR ISNULL(SUM(e.Credit), 0) <> 0
    ORDER BY a.Code;

    DECLARE @Assets DECIMAL(18,2), @Liabilities DECIMAL(18,2), @Capital DECIMAL(18,2),
            @Revenue DECIMAL(18,2), @Expense DECIMAL(18,2);
    SELECT @Assets = ISNULL(SUM(CASE WHEN a.AccountType = 'Asset' THEN e.Debit - e.Credit ELSE 0 END), 0),
           @Liabilities = ISNULL(SUM(CASE WHEN a.AccountType = 'Liability' THEN e.Credit - e.Debit ELSE 0 END), 0),
           @Capital = ISNULL(SUM(CASE WHEN a.AccountType = 'Capital' THEN e.Credit - e.Debit ELSE 0 END), 0),
           @Revenue = ISNULL(SUM(CASE WHEN a.AccountType = 'Revenue' THEN e.Credit - e.Debit ELSE 0 END), 0),
           @Expense = ISNULL(SUM(CASE WHEN a.AccountType = 'Expense' THEN e.Debit - e.Credit ELSE 0 END), 0)
    FROM dbo.Accounts a
    JOIN dbo.VoucherEntries e ON e.AccountID = a.AccountID
    JOIN dbo.Vouchers v ON v.VoucherID = e.VoucherID
         AND v.Status IN ('Posted','Reversed') AND v.IsDeleted = 0
         AND v.VoucherDate <= @AsOf
         AND (@BranchID IS NULL OR v.BranchID = @BranchID)
    WHERE a.IsControl = 0;

    DECLARE @NetProfit DECIMAL(18,2) = @Revenue - @Expense;
    SELECT @Assets AS AssetsTotal, @Liabilities AS LiabilitiesTotal,
           @Capital AS CapitalTotal, @Revenue AS RevenueTotal, @Expense AS ExpenseTotal,
           @NetProfit AS NetProfit,
           @Capital + @NetProfit AS EquityTotal,
           @Assets - (@Liabilities + @Capital + @NetProfit) AS Difference;
END
GO

/* ---------------- Profit & Loss (account based) -------------------- */

CREATE OR ALTER PROCEDURE dbo.sp_FinanceReports_ProfitLoss
    @FromDate DATE = NULL,
    @ToDate   DATE = NULL,
    @BranchID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @ToDate IS NULL SET @ToDate = CAST(GETDATE() AS DATE);
    IF @FromDate IS NULL SET @FromDate = DATEADD(MONTH, -1, @ToDate);

    SELECT  a.AccountID, a.Code, a.Title, a.AccountType, a.LevelNo, a.ParentAccountID,
            CASE WHEN a.AccountType = 'Revenue'
                 THEN ISNULL(SUM(e.Credit - e.Debit), 0)
                 ELSE ISNULL(SUM(e.Debit - e.Credit), 0) END AS Amount
    FROM dbo.Accounts a
    JOIN dbo.VoucherEntries e ON e.AccountID = a.AccountID
    JOIN dbo.Vouchers v ON v.VoucherID = e.VoucherID
         AND v.Status IN ('Posted','Reversed') AND v.IsDeleted = 0
         AND v.VoucherDate BETWEEN @FromDate AND @ToDate
         AND (@BranchID IS NULL OR v.BranchID = @BranchID)
    WHERE a.IsControl = 0 AND a.AccountType IN ('Revenue','Expense')
    GROUP BY a.AccountID, a.Code, a.Title, a.AccountType, a.LevelNo, a.ParentAccountID
    ORDER BY a.Code;

    DECLARE @Revenue DECIMAL(18,2), @Expense DECIMAL(18,2);
    SELECT @Revenue = ISNULL(SUM(CASE WHEN a.AccountType = 'Revenue' THEN e.Credit - e.Debit ELSE 0 END), 0),
           @Expense = ISNULL(SUM(CASE WHEN a.AccountType = 'Expense' THEN e.Debit - e.Credit ELSE 0 END), 0)
    FROM dbo.Accounts a
    JOIN dbo.VoucherEntries e ON e.AccountID = a.AccountID
    JOIN dbo.Vouchers v ON v.VoucherID = e.VoucherID
         AND v.Status IN ('Posted','Reversed') AND v.IsDeleted = 0
         AND v.VoucherDate BETWEEN @FromDate AND @ToDate
         AND (@BranchID IS NULL OR v.BranchID = @BranchID)
    WHERE a.IsControl = 0 AND a.AccountType IN ('Revenue','Expense');

    SELECT @Revenue AS RevenueTotal, @Expense AS ExpenseTotal, @Revenue - @Expense AS NetProfit,
           @FromDate AS FromDate, @ToDate AS ToDate;
END
GO

/* ---------------- Aging (shared core for customer / vendor) -------- */
/* Mode 'BillWise': outstanding per (party, bill reference).            */
/* Mode 'FIFO': credits knock off the oldest documents first.           */

CREATE OR ALTER PROCEDURE dbo.sp_FinanceReports_Aging
    @PartyKind NVARCHAR(10),      -- 'Customer' | 'Vendor'
    @AsOf DATE = NULL,
    @BranchID INT = NULL,
    @PartyID INT = NULL,
    @Mode NVARCHAR(10) = NULL     -- NULL = read from Finance Defaults
AS
BEGIN
    SET NOCOUNT ON;
    IF @AsOf IS NULL SET @AsOf = CAST(GETDATE() AS DATE);
    IF @PartyKind NOT IN ('Customer','Vendor')
        THROW 51041, 'Invalid aging party kind.', 1;

    IF @Mode IS NULL OR @Mode NOT IN ('BillWise','FIFO')
    BEGIN
        DECLARE @Cfg NVARCHAR(MAX) = (SELECT Value FROM dbo.Settings WHERE [Key] = 'FinanceAccounting');
        DECLARE @BillWise INT = ISNULL(TRY_CAST(JSON_VALUE(@Cfg, '$.billWise') AS INT), 1);
        SET @Mode = CASE WHEN @BillWise = 1 THEN 'BillWise' ELSE 'FIFO' END;
    END

    DECLARE @Tag NVARCHAR(30) = @PartyKind;

    IF OBJECT_ID('tempdb..#Lines') IS NOT NULL DROP TABLE #Lines;
    CREATE TABLE #Lines (
        EntryID BIGINT, VoucherID INT, VoucherNo NVARCHAR(50), VoucherDate DATE,
        AccountID INT, Debit DECIMAL(18,2), Credit DECIMAL(18,2),
        PartyID INT, BillRef NVARCHAR(50), BillDate DATE, DueDate DATE, Narrative NVARCHAR(500),
        BranchID INT, BranchName NVARCHAR(150));

    INSERT INTO #Lines (EntryID, VoucherID, VoucherNo, VoucherDate, AccountID, Debit, Credit,
                        PartyID, BillRef, BillDate, DueDate, Narrative, BranchID, BranchName)
    SELECT e.EntryID, v.VoucherID, v.VoucherNo, v.VoucherDate, e.AccountID, e.Debit, e.Credit,
           CASE WHEN @PartyKind = 'Customer' THEN e.PartyMemberID ELSE e.PartySupplierID END,
           e.BillRef, e.BillDate, e.DueDate, e.Narrative, v.BranchID, b.Name
    FROM dbo.VoucherEntries e
    JOIN dbo.Vouchers v ON v.VoucherID = e.VoucherID
         AND v.Status IN ('Posted','Reversed') AND v.IsDeleted = 0
         AND v.VoucherDate <= @AsOf
         AND (@BranchID IS NULL OR v.BranchID = @BranchID)
    JOIN dbo.AccountTags tg ON tg.AccountID = e.AccountID AND tg.Tag = @Tag
    JOIN dbo.Branches b ON b.BranchID = v.BranchID
    WHERE CASE WHEN @PartyKind = 'Customer' THEN e.PartyMemberID ELSE e.PartySupplierID END IS NOT NULL
      AND (@PartyID IS NULL OR CASE WHEN @PartyKind = 'Customer' THEN e.PartyMemberID ELSE e.PartySupplierID END = @PartyID);

    IF @Mode = 'BillWise'
    BEGIN
        ;WITH keyed AS (
            SELECT *,
                   COALESCE(NULLIF(BillRef, ''), 'V-' + CAST(VoucherID AS NVARCHAR(20))) AS BillKey
            FROM #Lines
        ),
        bills AS (
            SELECT PartyID, BillKey,
                   MIN(COALESCE(BillDate, VoucherDate)) AS BillDate,
                   MAX(DueDate) AS DueDate,
                   SUM(Debit) AS Dr, SUM(Credit) AS Cr,
                   MIN(BranchName) AS BranchName
            FROM keyed
            GROUP BY PartyID, BillKey
        )
        SELECT  PartyID,
                PartyName, PartyCode, BillKey AS BillRef, BillDate, DueDate,
                OriginalAmount, AdjustedAmount, RemainingAmount, AgeDays, Bucket, BranchName, VoucherNo
        FROM (
            SELECT bl.PartyID,
                   CASE WHEN @PartyKind = 'Customer' THEN m.FullName ELSE s.Name END AS PartyName,
                   CASE WHEN @PartyKind = 'Customer' THEN m.Code ELSE CAST(s.SupplierID AS NVARCHAR(30)) END AS PartyCode,
                   bl.BillKey, bl.BillDate, bl.DueDate,
                   CASE WHEN @PartyKind = 'Customer' THEN bl.Dr ELSE bl.Cr END AS OriginalAmount,
                   CASE WHEN @PartyKind = 'Customer' THEN bl.Cr ELSE bl.Dr END AS AdjustedAmount,
                   CASE WHEN @PartyKind = 'Customer' THEN bl.Dr - bl.Cr ELSE bl.Cr - bl.Dr END AS RemainingAmount,
                   DATEDIFF(DAY, COALESCE(bl.DueDate, bl.BillDate), @AsOf) AS AgeDays,
                   CASE
                     WHEN DATEDIFF(DAY, COALESCE(bl.DueDate, bl.BillDate), @AsOf) <= 0 THEN 'Current'
                     WHEN DATEDIFF(DAY, COALESCE(bl.DueDate, bl.BillDate), @AsOf) <= 30 THEN '1-30'
                     WHEN DATEDIFF(DAY, COALESCE(bl.DueDate, bl.BillDate), @AsOf) <= 60 THEN '31-60'
                     WHEN DATEDIFF(DAY, COALESCE(bl.DueDate, bl.BillDate), @AsOf) <= 90 THEN '61-90'
                     ELSE '90+' END AS Bucket,
                   bl.BranchName,
                   (SELECT TOP 1 l.VoucherNo FROM #Lines l
                    WHERE l.PartyID = bl.PartyID AND COALESCE(NULLIF(l.BillRef,''), 'V-' + CAST(l.VoucherID AS NVARCHAR(20))) = bl.BillKey
                    ORDER BY l.VoucherDate) AS VoucherNo
            FROM bills bl
            LEFT JOIN dbo.Members m ON @PartyKind = 'Customer' AND m.MemberID = bl.PartyID
            LEFT JOIN dbo.Suppliers s ON @PartyKind = 'Vendor' AND s.SupplierID = bl.PartyID
        ) x
        WHERE RemainingAmount > 0
        ORDER BY PartyName, BillDate;
    END
    ELSE
    BEGIN
        ;WITH docs AS (
            SELECT PartyID, VoucherID AS DocVoucherID, MIN(VoucherNo) AS VoucherNo,
                   MIN(COALESCE(BillRef,'')) AS BillRef,
                   MIN(COALESCE(BillDate, VoucherDate)) AS BillDate, MAX(DueDate) AS DueDate,
                   CASE WHEN @PartyKind = 'Customer' THEN SUM(Debit) ELSE SUM(Credit) END AS DocAmount,
                   ROW_NUMBER() OVER (PARTITION BY PartyID ORDER BY MIN(VoucherDate), MIN(EntryID)) AS rn
            FROM #Lines
            WHERE CASE WHEN @PartyKind = 'Customer' THEN Debit ELSE Credit END > 0
            GROUP BY PartyID, VoucherID
        ),
        credits AS (
            SELECT PartyID,
                   CASE WHEN @PartyKind = 'Customer' THEN SUM(Credit) ELSE SUM(Debit) END AS TotalSettled
            FROM #Lines
            GROUP BY PartyID
        ),
        calc AS (
            SELECT d.PartyID, d.DocVoucherID, d.VoucherNo, d.BillRef, d.BillDate, d.DueDate, d.DocAmount,
                   c.TotalSettled,
                   SUM(d.DocAmount) OVER (PARTITION BY d.PartyID ORDER BY d.rn ROWS UNBOUNDED PRECEDING) AS CumAmount
            FROM docs d
            JOIN credits c ON c.PartyID = d.PartyID
        )
        SELECT PartyID, PartyName, PartyCode, BillRef, BillDate, DueDate,
               OriginalAmount, AdjustedAmount, RemainingAmount, AgeDays, Bucket, BranchName, VoucherNo
        FROM (
            SELECT x.PartyID,
                   CASE WHEN @PartyKind = 'Customer' THEN m.FullName ELSE s.Name END AS PartyName,
                   CASE WHEN @PartyKind = 'Customer' THEN m.Code ELSE CAST(s.SupplierID AS NVARCHAR(30)) END AS PartyCode,
                   x.BillRef, x.BillDate, x.DueDate,
                   x.DocAmount AS OriginalAmount,
                   CASE WHEN x.TotalSettled >= x.DocAmount THEN x.DocAmount
                        WHEN x.TotalSettled <= x.CumAmount - x.DocAmount THEN 0
                        ELSE x.TotalSettled - (x.CumAmount - x.DocAmount) END AS AdjustedAmount,
                   CASE WHEN x.TotalSettled >= x.DocAmount THEN 0
                        WHEN x.TotalSettled <= x.CumAmount - x.DocAmount THEN x.DocAmount
                        ELSE x.DocAmount - (x.TotalSettled - (x.CumAmount - x.DocAmount)) END AS RemainingAmount,
                   DATEDIFF(DAY, COALESCE(x.DueDate, x.BillDate), @AsOf) AS AgeDays,
                   CASE
                     WHEN DATEDIFF(DAY, COALESCE(x.DueDate, x.BillDate), @AsOf) <= 0 THEN 'Current'
                     WHEN DATEDIFF(DAY, COALESCE(x.DueDate, x.BillDate), @AsOf) <= 30 THEN '1-30'
                     WHEN DATEDIFF(DAY, COALESCE(x.DueDate, x.BillDate), @AsOf) <= 60 THEN '31-60'
                     WHEN DATEDIFF(DAY, COALESCE(x.DueDate, x.BillDate), @AsOf) <= 90 THEN '61-90'
                     ELSE '90+' END AS Bucket,
                   (SELECT TOP 1 l.BranchName FROM #Lines l WHERE l.PartyID = x.PartyID ORDER BY l.VoucherDate) AS BranchName,
                   x.VoucherNo
            FROM calc x
            LEFT JOIN dbo.Members m ON @PartyKind = 'Customer' AND m.MemberID = x.PartyID
            LEFT JOIN dbo.Suppliers s ON @PartyKind = 'Vendor' AND s.SupplierID = x.PartyID
        ) y
        WHERE RemainingAmount > 0
        ORDER BY PartyName, BillDate;
    END
END
GO

/* ---------------- Bank Statement (ledger for a Bank-tagged account) */

CREATE OR ALTER PROCEDURE dbo.sp_FinanceReports_BankStatement
    @AccountID INT,
    @FromDate DATE = NULL,
    @ToDate DATE = NULL,
    @BranchID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    -- the ledger SP streams both recordsets (summary + lines) through this EXEC
    EXEC dbo.sp_FinanceReports_Ledger
         @AccountID = @AccountID, @FromDate = @FromDate, @ToDate = @ToDate,
         @BranchID = @BranchID, @RequireTag = 'Bank';
END
GO

/* ---------------- Finance dashboard -------------------------------- */

CREATE OR ALTER PROCEDURE dbo.sp_FinanceDashboard_Stats
    @AsOf DATE = NULL,
    @BranchID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @AsOf IS NULL SET @AsOf = CAST(GETDATE() AS DATE);

    DECLARE @Cash DECIMAL(18,2), @Bank DECIMAL(18,2), @Receivables DECIMAL(18,2), @Payables DECIMAL(18,2),
            @MonthRevenue DECIMAL(18,2), @MonthExpense DECIMAL(18,2), @FYRevenue DECIMAL(18,2), @FYExpense DECIMAL(18,2);

    SELECT @Cash = ISNULL(SUM(e.Debit - e.Credit), 0)
    FROM dbo.VoucherEntries e
    JOIN dbo.Vouchers v ON v.VoucherID = e.VoucherID AND v.Status IN ('Posted','Reversed') AND v.IsDeleted = 0 AND v.VoucherDate <= @AsOf AND (@BranchID IS NULL OR v.BranchID = @BranchID)
    JOIN dbo.AccountTags t ON t.AccountID = e.AccountID AND t.Tag = 'Cash';

    SELECT @Bank = ISNULL(SUM(e.Debit - e.Credit), 0)
    FROM dbo.VoucherEntries e
    JOIN dbo.Vouchers v ON v.VoucherID = e.VoucherID AND v.Status IN ('Posted','Reversed') AND v.IsDeleted = 0 AND v.VoucherDate <= @AsOf AND (@BranchID IS NULL OR v.BranchID = @BranchID)
    JOIN dbo.AccountTags t ON t.AccountID = e.AccountID AND t.Tag = 'Bank';

    SELECT @Receivables = ISNULL(SUM(e.Debit - e.Credit), 0)
    FROM dbo.VoucherEntries e
    JOIN dbo.Vouchers v ON v.VoucherID = e.VoucherID AND v.Status IN ('Posted','Reversed') AND v.IsDeleted = 0 AND v.VoucherDate <= @AsOf AND (@BranchID IS NULL OR v.BranchID = @BranchID)
    JOIN dbo.AccountTags t ON t.AccountID = e.AccountID AND t.Tag = 'Customer';

    SELECT @Payables = ISNULL(SUM(e.Credit - e.Debit), 0)
    FROM dbo.VoucherEntries e
    JOIN dbo.Vouchers v ON v.VoucherID = e.VoucherID AND v.Status IN ('Posted','Reversed') AND v.IsDeleted = 0 AND v.VoucherDate <= @AsOf AND (@BranchID IS NULL OR v.BranchID = @BranchID)
    JOIN dbo.AccountTags t ON t.AccountID = e.AccountID AND t.Tag = 'Vendor';

    DECLARE @MS DATE = DATEFROMPARTS(YEAR(@AsOf), MONTH(@AsOf), 1);
    SELECT @MonthRevenue = ISNULL(SUM(CASE WHEN a.AccountType='Revenue' THEN e.Credit - e.Debit ELSE 0 END), 0),
           @MonthExpense = ISNULL(SUM(CASE WHEN a.AccountType='Expense' THEN e.Debit - e.Credit ELSE 0 END), 0)
    FROM dbo.VoucherEntries e
    JOIN dbo.Vouchers v ON v.VoucherID = e.VoucherID AND v.Status IN ('Posted','Reversed') AND v.IsDeleted = 0
         AND v.VoucherDate BETWEEN @MS AND @AsOf AND (@BranchID IS NULL OR v.BranchID = @BranchID)
    JOIN dbo.Accounts a ON a.AccountID = e.AccountID AND a.IsControl = 0 AND a.AccountType IN ('Revenue','Expense');

    SELECT @FYRevenue = ISNULL(SUM(CASE WHEN a.AccountType='Revenue' THEN e.Credit - e.Debit ELSE 0 END), 0),
           @FYExpense = ISNULL(SUM(CASE WHEN a.AccountType='Expense' THEN e.Debit - e.Credit ELSE 0 END), 0)
    FROM dbo.VoucherEntries e
    JOIN dbo.Vouchers v ON v.VoucherID = e.VoucherID AND v.Status IN ('Posted','Reversed') AND v.IsDeleted = 0
         AND v.VoucherDate <= @AsOf AND (@BranchID IS NULL OR v.BranchID = @BranchID)
    JOIN dbo.Accounts a ON a.AccountID = e.AccountID AND a.IsControl = 0 AND a.AccountType IN ('Revenue','Expense');

    DECLARE @PendingCustomerBills INT, @PendingVendorBills INT;
    ;WITH cl AS (
        SELECT e.PartyMemberID AS PartyID, SUM(e.Debit - e.Credit) AS Out_
        FROM dbo.VoucherEntries e
        JOIN dbo.Vouchers v ON v.VoucherID = e.VoucherID AND v.Status IN ('Posted','Reversed') AND v.IsDeleted = 0 AND v.VoucherDate <= @AsOf AND (@BranchID IS NULL OR v.BranchID = @BranchID)
        JOIN dbo.AccountTags t ON t.AccountID = e.AccountID AND t.Tag = 'Customer'
        WHERE e.PartyMemberID IS NOT NULL
        GROUP BY e.PartyMemberID HAVING SUM(e.Debit - e.Credit) > 0
    )
    SELECT @PendingCustomerBills = COUNT(*) FROM cl;
    ;WITH vl AS (
        SELECT e.PartySupplierID AS PartyID, SUM(e.Credit - e.Debit) AS Out_
        FROM dbo.VoucherEntries e
        JOIN dbo.Vouchers v ON v.VoucherID = e.VoucherID AND v.Status IN ('Posted','Reversed') AND v.IsDeleted = 0 AND v.VoucherDate <= @AsOf AND (@BranchID IS NULL OR v.BranchID = @BranchID)
        JOIN dbo.AccountTags t ON t.AccountID = e.AccountID AND t.Tag = 'Vendor'
        WHERE e.PartySupplierID IS NOT NULL
        GROUP BY e.PartySupplierID HAVING SUM(e.Credit - e.Debit) > 0
    )
    SELECT @PendingVendorBills = COUNT(*) FROM vl;

    SELECT @Cash AS CashBalance, @Bank AS BankBalance, @Receivables AS Receivables, @Payables AS Payables,
           @MonthRevenue AS MonthRevenue, @MonthExpense AS MonthExpense,
           @MonthRevenue - @MonthExpense AS MonthNetProfit,
           @FYRevenue AS YearRevenue, @FYExpense AS YearExpense,
           @FYRevenue - @FYExpense AS YearNetProfit,
           @PendingCustomerBills AS PendingCustomerBills, @PendingVendorBills AS PendingVendorBills,
           @AsOf AS AsOf;
END
GO

/* ================================================================== */
/* SECTION 6 — BANK RECONCILIATION                                    */
/* ================================================================== */

CREATE OR ALTER PROCEDURE dbo.sp_FinanceRecon_CreateRun
    @AccountID INT,
    @StatementDate DATE,
    @StatementOpeningBalance DECIMAL(18,2) = 0,
    @StatementClosingBalance DECIMAL(18,2) = 0,
    @BranchID INT = NULL,
    @Notes NVARCHAR(500) = NULL,
    @CreatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM dbo.Accounts a
                       JOIN dbo.AccountTags t ON t.AccountID = a.AccountID AND t.Tag = 'Bank'
                       WHERE a.AccountID = @AccountID AND a.IsControl = 0 AND a.IsActive = 1 AND a.IsDeleted = 0)
            THROW 51032, 'Select an active Detail bank account (tagged Bank).', 1;

        IF EXISTS (SELECT 1 FROM dbo.BankReconciliationRuns WHERE AccountID = @AccountID AND Status = 'Open')
            THROW 51033, 'An open reconciliation already exists for this bank account. Complete or discard it first.', 1;

        INSERT INTO dbo.BankReconciliationRuns
            (AccountID, BranchID, StatementDate, StatementOpeningBalance, StatementClosingBalance, Notes, CreatedBy)
        VALUES (@AccountID, @BranchID, @StatementDate, @StatementOpeningBalance, @StatementClosingBalance, @Notes, @CreatedBy);
        DECLARE @ReconID INT = CAST(SCOPE_IDENTITY() AS INT);

        -- snapshot the not-yet-reconciled system entries up to the statement date
        INSERT INTO dbo.BankReconciliationLines (ReconID, VoucherEntryID)
        SELECT @ReconID, e.EntryID
        FROM dbo.VoucherEntries e
        JOIN dbo.Vouchers v ON v.VoucherID = e.VoucherID AND v.Status IN ('Posted','Reversed') AND v.IsDeleted = 0
        WHERE e.AccountID = @AccountID
          AND v.VoucherDate <= @StatementDate
          AND (@BranchID IS NULL OR v.BranchID = @BranchID)
          AND NOT EXISTS (SELECT 1 FROM dbo.BankReconciliationLines l WHERE l.VoucherEntryID = e.EntryID);

        DECLARE @Snapshots INT = @@ROWCOUNT;

        COMMIT TRANSACTION;
        SELECT @ReconID AS ReconID, @Snapshots AS SnapshotCount;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_FinanceRecon_ListRuns
    @AccountID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT r.ReconID, r.AccountID, a.Code AS AccountCode, a.Title AS AccountTitle,
           r.BranchID, b.Name AS BranchName,
           r.StatementDate, r.StatementOpeningBalance, r.StatementClosingBalance, r.Status, r.Notes,
           r.CreatedAt, u.FullName AS CreatedByName, r.CompletedAt, cu.FullName AS CompletedByName,
           (SELECT COUNT(*) FROM dbo.BankReconciliationLines l WHERE l.ReconID = r.ReconID) AS TotalLines,
           (SELECT COUNT(*) FROM dbo.BankReconciliationLines l WHERE l.ReconID = r.ReconID AND l.IsReconciled = 1) AS MatchedLines,
           (SELECT ISNULL(SUM(e.Debit - e.Credit), 0)
            FROM dbo.VoucherEntries e JOIN dbo.Vouchers v ON v.VoucherID = e.VoucherID
                 AND v.Status IN ('Posted','Reversed') AND v.IsDeleted = 0
            WHERE e.AccountID = r.AccountID AND v.VoucherDate <= r.StatementDate) AS SystemClosingBalance
    FROM dbo.BankReconciliationRuns r
    JOIN dbo.Accounts a ON a.AccountID = r.AccountID
    LEFT JOIN dbo.Branches b ON b.BranchID = r.BranchID
    LEFT JOIN dbo.Users u ON u.UserID = r.CreatedBy
    LEFT JOIN dbo.Users cu ON cu.UserID = r.CompletedBy
    WHERE (@AccountID IS NULL OR r.AccountID = @AccountID)
    ORDER BY r.StatementDate DESC, r.ReconID DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_FinanceRecon_GetRun
    @ReconID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT r.ReconID, r.AccountID, a.Code AS AccountCode, a.Title AS AccountTitle,
           r.BranchID, r.StatementDate, r.StatementOpeningBalance, r.StatementClosingBalance,
           r.Status, r.Notes, r.CreatedAt, r.CompletedAt,
           (SELECT ISNULL(SUM(e.Debit - e.Credit), 0)
            FROM dbo.VoucherEntries e JOIN dbo.Vouchers v ON v.VoucherID = e.VoucherID
                 AND v.Status IN ('Posted','Reversed') AND v.IsDeleted = 0
            WHERE e.AccountID = r.AccountID AND v.VoucherDate <= r.StatementDate) AS SystemClosingBalance
    FROM dbo.BankReconciliationRuns r
    JOIN dbo.Accounts a ON a.AccountID = r.AccountID
    WHERE r.ReconID = @ReconID;

    SELECT l.LineID, l.VoucherEntryID, l.IsReconciled, l.ReconciledAt, ru.FullName AS ReconciledByName,
           v.VoucherDate, v.VoucherNo, t.TypeCode, e.Debit, e.Credit, e.Narrative,
           v.Status, b.Name AS BranchName
    FROM dbo.BankReconciliationLines l
    JOIN dbo.VoucherEntries e ON e.EntryID = l.VoucherEntryID
    JOIN dbo.Vouchers v ON v.VoucherID = e.VoucherID
    JOIN dbo.VoucherTypes t ON t.VoucherTypeID = v.VoucherTypeID
    JOIN dbo.Branches b ON b.BranchID = v.BranchID
    LEFT JOIN dbo.Users ru ON ru.UserID = l.ReconciledBy
    WHERE l.ReconID = @ReconID
    ORDER BY v.VoucherDate, e.EntryID;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_FinanceRecon_SetLine
    @LineID INT, @IsReconciled BIT, @UserId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        DECLARE @ReconID INT;
        SELECT @ReconID = l.ReconID
        FROM dbo.BankReconciliationLines l
        WHERE l.LineID = @LineID;

        IF @ReconID IS NULL THROW 51033, 'Reconciliation line not found.', 1;
        IF (SELECT Status FROM dbo.BankReconciliationRuns WHERE ReconID = @ReconID) <> 'Open'
            THROW 51033, 'This reconciliation run is completed and can no longer change.', 1;

        UPDATE dbo.BankReconciliationLines
           SET IsReconciled = @IsReconciled,
               ReconciledAt = CASE WHEN @IsReconciled = 1 THEN SYSUTCDATETIME() ELSE NULL END,
               ReconciledBy = CASE WHEN @IsReconciled = 1 THEN @UserId ELSE NULL END
         WHERE LineID = @LineID;
        SELECT 'OK' AS Result;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_FinanceRecon_CompleteRun
    @ReconID INT, @UserId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        DECLARE @Status NVARCHAR(20);
        SELECT @Status = Status FROM dbo.BankReconciliationRuns WHERE ReconID = @ReconID;
        IF @Status IS NULL THROW 51033, 'Reconciliation run not found.', 1;
        IF @Status = 'Completed' THROW 51033, 'Reconciliation run is already completed.', 1;

        UPDATE dbo.BankReconciliationRuns
           SET Status = 'Completed', CompletedAt = SYSUTCDATETIME(), CompletedBy = @UserId
         WHERE ReconID = @ReconID;
        SELECT 'OK' AS Result;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_FinanceRecon_DeleteRun
    @ReconID INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        DECLARE @Status NVARCHAR(20);
        SELECT @Status = Status FROM dbo.BankReconciliationRuns WHERE ReconID = @ReconID;
        IF @Status IS NULL THROW 51033, 'Reconciliation run not found.', 1;
        IF @Status = 'Completed' THROW 51033, 'A completed reconciliation run cannot be deleted.', 1;

        DELETE FROM dbo.BankReconciliationLines WHERE ReconID = @ReconID;
        DELETE FROM dbo.BankReconciliationRuns WHERE ReconID = @ReconID;
        SELECT 'OK' AS Result;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

/* ================================================================== */
/* SECTION 7 — MAPPINGS, USER REPORT FORMATS                          */
/* ================================================================== */

CREATE OR ALTER PROCEDURE dbo.sp_FinanceMappings_List
    @MappingType NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT m.MappingID, m.MappingType, m.SourceKey, m.AccountID,
           a.Code AS AccountCode, a.Title AS AccountTitle, a.AccountType,
           m.IsActive, m.UpdatedAt
    FROM dbo.FinanceMappings m
    JOIN dbo.Accounts a ON a.AccountID = m.AccountID
    WHERE (@MappingType IS NULL OR m.MappingType = @MappingType)
    ORDER BY m.MappingType, m.SourceKey;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_FinanceMappings_Set
    @MappingType NVARCHAR(50),
    @SourceKey NVARCHAR(50) = NULL,
    @AccountID INT,
    @UserId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM dbo.Accounts
                       WHERE AccountID = @AccountID AND IsControl = 0 AND IsActive = 1 AND IsDeleted = 0)
            THROW 51008, 'Mappings must target an active Detail account.', 1;

        IF @SourceKey IS NULL
        BEGIN
            -- singleton mapping (e.g. DefaultCash): keep exactly one row per type
            IF EXISTS (SELECT 1 FROM dbo.FinanceMappings WHERE MappingType = @MappingType AND SourceKey IS NULL AND AccountID <> @AccountID)
                UPDATE dbo.FinanceMappings SET AccountID = @AccountID, UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @UserId
                WHERE MappingType = @MappingType AND SourceKey IS NULL;
            ELSE IF NOT EXISTS (SELECT 1 FROM dbo.FinanceMappings WHERE MappingType = @MappingType AND SourceKey IS NULL)
                INSERT INTO dbo.FinanceMappings (MappingType, SourceKey, AccountID, UpdatedBy)
                VALUES (@MappingType, NULL, @AccountID, @UserId);
        END
        ELSE
        BEGIN
            IF EXISTS (SELECT 1 FROM dbo.FinanceMappings WHERE MappingType = @MappingType AND SourceKey = @SourceKey)
                UPDATE dbo.FinanceMappings SET AccountID = @AccountID, IsActive = 1,
                       UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @UserId
                 WHERE MappingType = @MappingType AND SourceKey = @SourceKey;
            ELSE
                INSERT INTO dbo.FinanceMappings (MappingType, SourceKey, AccountID, UpdatedBy)
                VALUES (@MappingType, @SourceKey, @AccountID, @UserId);
        END
        SELECT 'OK' AS Result;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_FinanceMappings_Delete
    @MappingID INT
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM dbo.FinanceMappings WHERE MappingID = @MappingID;
    SELECT 'OK' AS Result;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_FinanceUserFormats_List
    @UserID INT, @ReportKey NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT FormatID, UserID, ReportKey, FormatName, ColumnsJson, IsDefault, CreatedAt, UpdatedAt
    FROM dbo.UserReportFormats
    WHERE UserID = @UserID AND (@ReportKey IS NULL OR ReportKey = @ReportKey)
    ORDER BY ReportKey, FormatName;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_FinanceUserFormats_Save
    @FormatID INT = NULL,
    @UserID INT,
    @ReportKey NVARCHAR(50),
    @FormatName NVARCHAR(100),
    @ColumnsJson NVARCHAR(MAX),
    @IsDefault BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        IF @FormatID IS NULL
        BEGIN
            SELECT @FormatID = FormatID FROM dbo.UserReportFormats
            WHERE UserID = @UserID AND ReportKey = @ReportKey AND FormatName = @FormatName;
        END
        ELSE IF NOT EXISTS (SELECT 1 FROM dbo.UserReportFormats WHERE FormatID = @FormatID AND UserID = @UserID)
            THROW 51033, 'Report format not found.', 1;

        IF @FormatID IS NULL
        BEGIN
            INSERT INTO dbo.UserReportFormats (UserID, ReportKey, FormatName, ColumnsJson, IsDefault)
            VALUES (@UserID, @ReportKey, @FormatName, @ColumnsJson, @IsDefault);
            SET @FormatID = CAST(SCOPE_IDENTITY() AS INT);
        END
        ELSE
        BEGIN
            UPDATE dbo.UserReportFormats
               SET FormatName = @FormatName, ColumnsJson = @ColumnsJson, IsDefault = @IsDefault, UpdatedAt = SYSUTCDATETIME()
             WHERE FormatID = @FormatID;
        END

        IF @IsDefault = 1
            UPDATE dbo.UserReportFormats SET IsDefault = 0
            WHERE UserID = @UserID AND ReportKey = @ReportKey AND FormatID <> @FormatID;

        COMMIT TRANSACTION;
        SELECT @FormatID AS FormatID;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_FinanceUserFormats_Delete
    @FormatID INT, @UserID INT
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM dbo.UserReportFormats WHERE FormatID = @FormatID AND UserID = @UserID;
    SELECT 'OK' AS Result;
END
GO

PRINT '=== 12_finance_procedures.sql applied successfully. ===';
GO
/* ================================================================== */
/* SECTION 4b — ENGINE v2 (supersedes the earlier definitions above)  */
/* ------------------------------------------------------------------ */
/* The earlier sp_Accounting_* procs used INSERT...EXEC composition,  */
/* which fails with "Cannot use ROLLBACK within INSERT-EXEC" when a   */
/* business rule throws. v2 splits every operation into:              */
/*   *Core proc  — pure logic, NO transaction statements, THROWs      */
/*                 propagate to the caller (XACT_ABORT rolls back).   */
/*   *Wrapper    — owns BEGIN TRAN / TRY / CATCH / ROLLBACK, calls    */
/*                 the core, returns the result set.                  */
/* CREATE OR ALTER below overrides the earlier definitions.           */
/* ================================================================== */

/* ---------------- Save draft CORE (no transaction) ----------------- */

CREATE OR ALTER PROCEDURE dbo.sp_FinanceVouchers_SaveDraftCore
    @VoucherID     INT OUTPUT,
    @VoucherTypeID INT,
    @VoucherDate   DATE,
    @BranchID      INT,
    @Narrative     NVARCHAR(500) = NULL,
    @EntriesJson   NVARCHAR(MAX),
    @UserId        INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ExistingStatus NVARCHAR(20) = NULL, @ExistingType INT = NULL;
    IF @VoucherID IS NOT NULL
        SELECT @ExistingStatus = Status, @ExistingType = VoucherTypeID
        FROM dbo.Vouchers WHERE VoucherID = @VoucherID AND IsDeleted = 0;

    IF @VoucherID IS NOT NULL AND @ExistingStatus IS NULL
        THROW 51001, 'Voucher not found.', 1;
    IF @ExistingStatus IS NOT NULL AND @ExistingStatus <> 'Draft'
        THROW 51034, 'Posted vouchers cannot be edited. Reverse and re-post instead.', 1;
    IF @ExistingType IS NOT NULL AND @ExistingType <> @VoucherTypeID
        THROW 51021, 'The voucher type of a draft cannot be changed.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.VoucherTypes WHERE VoucherTypeID = @VoucherTypeID AND IsActive = 1)
        THROW 51021, 'Voucher type not found or inactive.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Branches WHERE BranchID = @BranchID AND IsActive = 1 AND IsDeleted = 0)
        THROW 51018, 'Invalid or inactive branch.', 1;

    IF OBJECT_ID('tempdb..#Lines') IS NOT NULL DROP TABLE #Lines;
    CREATE TABLE #Lines (
        RowNum INT IDENTITY(1,1) PRIMARY KEY,
        AccountID INT, Debit DECIMAL(18,2), Credit DECIMAL(18,2),
        Narrative NVARCHAR(500), PartyMemberID INT, PartySupplierID INT, PartyStaffID INT,
        BillRef NVARCHAR(50), BillDate DATE, DueDate DATE);

    INSERT INTO #Lines (AccountID, Debit, Credit, Narrative, PartyMemberID, PartySupplierID, PartyStaffID, BillRef, BillDate, DueDate)
    SELECT AccountID, Debit, Credit, Narrative, PartyMemberID, PartySupplierID, PartyStaffID, BillRef, BillDate, DueDate
    FROM OPENJSON(@EntriesJson)
    WITH (
        AccountID      INT           '$.AccountID',
        Debit          DECIMAL(18,2) '$.Debit',
        Credit         DECIMAL(18,2) '$.Credit',
        Narrative      NVARCHAR(500) '$.Narrative',
        PartyMemberID  INT           '$.PartyMemberID',
        PartySupplierID INT          '$.PartySupplierID',
        PartyStaffID   INT           '$.PartyStaffID',
        BillRef        NVARCHAR(50)  '$.BillRef',
        BillDate       DATE          '$.BillDate',
        DueDate        DATE          '$.DueDate'
    );

    IF NOT EXISTS (SELECT 1 FROM #Lines)
        THROW 51005, 'A voucher needs at least one entry line.', 1;
    IF EXISTS (SELECT 1 FROM #Lines WHERE AccountID IS NULL)
        THROW 51008, 'Every line must reference an account.', 1;
    IF EXISTS (SELECT 1 FROM #Lines WHERE Debit < 0 OR Credit < 0)
        THROW 51031, 'Debit and credit amounts must be zero or positive numbers.', 1;
    IF EXISTS (SELECT 1 FROM #Lines WHERE ISNULL(Debit, 0) > 0 AND ISNULL(Credit, 0) > 0)
        THROW 51031, 'A line cannot have both debit and credit amounts.', 1;
    IF EXISTS (SELECT 1 FROM #Lines WHERE ISNULL(Debit, 0) = 0 AND ISNULL(Credit, 0) = 0)
        THROW 51031, 'A line must have either a debit or a credit amount.', 1;

    IF EXISTS (SELECT 1 FROM #Lines l LEFT JOIN dbo.Accounts a ON a.AccountID = l.AccountID
               WHERE a.AccountID IS NULL)
        THROW 51008, 'One or more selected accounts do not exist.', 1;
    IF EXISTS (SELECT 1 FROM #Lines l JOIN dbo.Accounts a ON a.AccountID = l.AccountID
               WHERE a.IsControl = 1)
        THROW 51007, 'Control accounts cannot receive postings. Select a Detail account.', 1;
    IF EXISTS (SELECT 1 FROM #Lines l JOIN dbo.Accounts a ON a.AccountID = l.AccountID
               WHERE a.IsActive = 0 OR a.IsDeleted = 1)
        THROW 51008, 'One or more selected accounts are inactive or deleted.', 1;

    IF EXISTS (SELECT 1 FROM #Lines l LEFT JOIN dbo.Members m ON m.MemberID = l.PartyMemberID
               WHERE l.PartyMemberID IS NOT NULL AND m.MemberID IS NULL)
        THROW 51019, 'Invalid customer reference.', 1;
    IF EXISTS (SELECT 1 FROM #Lines l LEFT JOIN dbo.Suppliers s ON s.SupplierID = l.PartySupplierID
               WHERE l.PartySupplierID IS NOT NULL AND s.SupplierID IS NULL)
        THROW 51019, 'Invalid vendor reference.', 1;
    IF EXISTS (SELECT 1 FROM #Lines l LEFT JOIN dbo.Staff st ON st.StaffID = l.PartyStaffID
               WHERE l.PartyStaffID IS NOT NULL AND st.StaffID IS NULL)
        THROW 51019, 'Invalid employee reference.', 1;

    IF @VoucherID IS NULL
    BEGIN
        INSERT INTO dbo.Vouchers (VoucherTypeID, VoucherDate, BranchID, Narrative, Status, CreatedBy)
        VALUES (@VoucherTypeID, @VoucherDate, @BranchID, @Narrative, 'Draft', @UserId);
        SET @VoucherID = CAST(SCOPE_IDENTITY() AS INT);
    END
    ELSE
    BEGIN
        UPDATE dbo.Vouchers SET VoucherDate = @VoucherDate, BranchID = @BranchID,
               Narrative = @Narrative, UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @UserId
        WHERE VoucherID = @VoucherID;
        DELETE FROM dbo.VoucherEntries WHERE VoucherID = @VoucherID;
    END

    INSERT INTO dbo.VoucherEntries (VoucherID, AccountID, Debit, Credit, Narrative,
                                    PartyMemberID, PartySupplierID, PartyStaffID,
                                    BillRef, BillDate, DueDate, CreatedBy)
    SELECT @VoucherID, AccountID, ISNULL(Debit, 0), ISNULL(Credit, 0), Narrative,
           PartyMemberID, PartySupplierID, PartyStaffID,
           NULLIF(LTRIM(RTRIM(BillRef)), ''), BillDate, DueDate, @UserId
    FROM #Lines;
END
GO

/* ---------------- Save draft wrapper (owns the transaction) -------- */

CREATE OR ALTER PROCEDURE dbo.sp_FinanceVouchers_SaveDraft
    @VoucherID     INT = NULL,
    @VoucherTypeID INT,
    @VoucherDate   DATE,
    @BranchID      INT,
    @Narrative     NVARCHAR(500) = NULL,
    @EntriesJson   NVARCHAR(MAX),
    @UserId        INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @OutID INT = @VoucherID; -- NULL = create new draft
        EXEC dbo.sp_FinanceVouchers_SaveDraftCore
             @VoucherID = @OutID OUTPUT,
             @VoucherTypeID = @VoucherTypeID, @VoucherDate = @VoucherDate,
             @BranchID = @BranchID, @Narrative = @Narrative,
             @EntriesJson = @EntriesJson, @UserId = @UserId;
        COMMIT TRANSACTION;
        SELECT @OutID AS VoucherID;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

/* ---------------- Posting engine CORE (no transaction) ------------- */

CREATE OR ALTER PROCEDURE dbo.sp_Accounting_PostCore
    @VoucherID INT,
    @PostedBy  INT,
    @VoucherNo NVARCHAR(50) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Type INT, @Nature NVARCHAR(20), @TenderTag NVARCHAR(30), @Status NVARCHAR(20),
            @VDate DATE, @BranchID INT, @Prefix NVARCHAR(10), @RevOf INT;

    SELECT  @Type = v.VoucherTypeID, @Nature = t.Nature, @TenderTag = t.TenderTag,
            @Status = v.Status, @VDate = v.VoucherDate, @BranchID = v.BranchID, @Prefix = t.Prefix,
            @RevOf = v.ReversalOfVoucherID,
            @RevOf = v.ReversalOfVoucherID
    FROM    dbo.Vouchers v WITH (UPDLOCK, HOLDLOCK)
    JOIN    dbo.VoucherTypes t ON t.VoucherTypeID = v.VoucherTypeID
    WHERE   v.VoucherID = @VoucherID AND v.IsDeleted = 0;

    IF @Type IS NULL  THROW 51001, 'Voucher not found.', 1;
    IF @Status <> 'Draft'
        THROW 51003, 'Voucher is already posted or reversed.', 1;

    DECLARE @Lines INT, @Dr DECIMAL(18,2), @Cr DECIMAL(18,2);
    SELECT @Lines = COUNT(*), @Dr = ISNULL(SUM(Debit), 0), @Cr = ISNULL(SUM(Credit), 0)
    FROM dbo.VoucherEntries WHERE VoucherID = @VoucherID;

    IF @Lines < 2
        THROW 51005, 'A posted voucher must contain at least two entries.', 1;
    IF @Dr <> @Cr
        THROW 51004, 'Debit and credit totals do not match.', 1;
    IF @Dr <= 0
        THROW 51006, 'Debit total must be greater than zero.', 1;

    DECLARE @FYID INT;
    SELECT @FYID = FinancialYearID FROM dbo.FinancialYears
    WHERE @VDate BETWEEN StartDate AND EndDate;
    IF @FYID IS NULL
        THROW 51015, 'No financial year covers the voucher date. Create the financial year first.', 1;
    IF (SELECT Status FROM dbo.FinancialYears WHERE FinancialYearID = @FYID) <> 'Open'
        THROW 51016, 'The financial year is locked or closed.', 1;

    DECLARE @PeriodID INT;
    SELECT @PeriodID = PeriodID
    FROM dbo.AccountingPeriods
    WHERE FinancialYearID = @FYID AND @VDate BETWEEN StartDate AND EndDate;
    IF @PeriodID IS NULL
        THROW 51017, 'No accounting period covers the voucher date.', 1;
    IF (SELECT Status FROM dbo.AccountingPeriods WHERE PeriodID = @PeriodID) <> 'Open'
        THROW 51017, 'The accounting period is closed or locked.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Branches WHERE BranchID = @BranchID AND IsActive = 1 AND IsDeleted = 0)
        THROW 51018, 'Invalid or inactive branch.', 1;

    IF EXISTS (SELECT 1 FROM dbo.VoucherEntries e
               JOIN dbo.Accounts a ON a.AccountID = e.AccountID
               WHERE e.VoucherID = @VoucherID AND (a.IsControl = 1 OR a.IsActive = 0 OR a.IsDeleted = 1))
        THROW 51007, 'All entries must target active Detail accounts (control and inactive accounts cannot receive postings).', 1;

    IF @Nature = 'Receipt' AND @TenderTag IS NOT NULL AND @RevOf IS NULL
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM dbo.VoucherEntries e
                       JOIN dbo.AccountTags tg ON tg.AccountID = e.AccountID AND tg.Tag = @TenderTag
                       WHERE e.VoucherID = @VoucherID AND e.Debit > 0)
            THROW 51039, 'The receipt side (debit) must include an account tagged Cash or Bank for this voucher type.', 1;
        IF EXISTS (SELECT 1 FROM dbo.VoucherEntries e
                   JOIN dbo.Accounts a ON a.AccountID = e.AccountID
                   WHERE e.VoucherID = @VoucherID AND e.Debit > 0
                     AND NOT EXISTS (SELECT 1 FROM dbo.AccountTags tg WHERE tg.AccountID = a.AccountID AND tg.Tag = @TenderTag))
            THROW 51039, 'Every debit account of this voucher type must be tagged Cash or Bank.', 1;
    END
    IF @Nature = 'Payment' AND @TenderTag IS NOT NULL AND @RevOf IS NULL
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM dbo.VoucherEntries e
                       JOIN dbo.AccountTags tg ON tg.AccountID = e.AccountID AND tg.Tag = @TenderTag
                       WHERE e.VoucherID = @VoucherID AND e.Credit > 0)
            THROW 51039, 'The payment side (credit) must include an account tagged Cash or Bank for this voucher type.', 1;
        IF EXISTS (SELECT 1 FROM dbo.VoucherEntries e
                   JOIN dbo.Accounts a ON a.AccountID = e.AccountID
                   WHERE e.VoucherID = @VoucherID AND e.Credit > 0
                     AND NOT EXISTS (SELECT 1 FROM dbo.AccountTags tg WHERE tg.AccountID = a.AccountID AND tg.Tag = @TenderTag))
            THROW 51039, 'Every credit account of this voucher type must be tagged Cash or Bank.', 1;
    END

    SELECT @VoucherNo = VoucherNo FROM dbo.Vouchers WHERE VoucherID = @VoucherID;
    IF @VoucherNo IS NULL
    BEGIN
        DECLARE @Scope NVARCHAR(60) =
            'VT' + CAST(@Type AS NVARCHAR(10)) + '-BR' + CAST(@BranchID AS NVARCHAR(10)) + '-FY' + CAST(@FYID AS NVARCHAR(10));
        DECLARE @Seq INT = NULL;

        UPDATE s SET @Seq = s.NextSeq, s.NextSeq = s.NextSeq + 1, s.UpdatedAt = SYSUTCDATETIME()
        FROM dbo.FinanceSequences s WITH (UPDLOCK, HOLDLOCK)
        WHERE s.ScopeKey = @Scope;

        IF @Seq IS NULL
        BEGIN
            INSERT INTO dbo.FinanceSequences (ScopeKey, NextSeq) VALUES (@Scope, 2);
            SET @Seq = 1;
        END

        DECLARE @SeqDigits INT = 4, @DateFmt NVARCHAR(20) = 'ddMMyyyy', @Cfg NVARCHAR(MAX);
        SELECT @Cfg = Value FROM dbo.Settings WHERE [Key] = 'FinanceVoucherNumbering';
        IF @Cfg IS NOT NULL
        BEGIN
            SET @SeqDigits = ISNULL(TRY_CAST(JSON_VALUE(@Cfg, '$.seqDigits') AS INT), 4);
            SET @DateFmt   = ISNULL(JSON_VALUE(@Cfg, '$.dateFormat'), 'ddMMyyyy');
        END

        DECLARE @NewNo NVARCHAR(50) = @Prefix + '-' + FORMAT(@VDate, @DateFmt)
                     + RIGHT(REPLICATE('0', 10) + CAST(@Seq AS NVARCHAR(10)), @SeqDigits);

        IF EXISTS (SELECT 1 FROM dbo.Vouchers WHERE VoucherNo = @NewNo)
            THROW 51001, 'Generated voucher number already exists.', 1;

        UPDATE dbo.Vouchers SET VoucherNo = @NewNo WHERE VoucherID = @VoucherID;
        SET @VoucherNo = @NewNo;
    END

    IF EXISTS (SELECT 1 FROM dbo.Vouchers v2
               WHERE v2.VoucherTypeID = @Type AND v2.Status IN ('Posted','Reversed') AND v2.VoucherID <> @VoucherID)
        UPDATE dbo.VoucherTypes SET PrefixLocked = 1 WHERE VoucherTypeID = @Type AND PrefixLocked = 0;

    UPDATE dbo.Vouchers
       SET Status = 'Posted', FinancialYearID = @FYID,
           DebitTotal = @Dr, CreditTotal = @Cr,
           PostedBy = @PostedBy, PostedAt = SYSUTCDATETIME(),
           UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @PostedBy
     WHERE VoucherID = @VoucherID;

    -- the prefix locks as soon as the type has been used
    UPDATE dbo.VoucherTypes SET PrefixLocked = 1
     WHERE VoucherTypeID = @Type AND PrefixLocked = 0
       AND EXISTS (SELECT 1 FROM dbo.Vouchers v2
                    WHERE v2.VoucherTypeID = @Type AND v2.Status IN ('Posted','Reversed'));

    DECLARE @PeriodNo INT = (SELECT PeriodNo FROM dbo.AccountingPeriods WHERE PeriodID = @PeriodID);
    ;WITH agg AS (
        SELECT AccountID, SUM(Debit) AS D, SUM(Credit) AS C
        FROM dbo.VoucherEntries
        WHERE VoucherID = @VoucherID
        GROUP BY AccountID
    )
    MERGE dbo.AccountBalances WITH (HOLDLOCK) AS t
    USING agg AS s ON t.AccountID = s.AccountID AND t.FinancialYearID = @FYID AND t.PeriodNo = @PeriodNo
    WHEN MATCHED THEN
        UPDATE SET DebitTotal = t.DebitTotal + s.D, CreditTotal = t.CreditTotal + s.C, UpdatedAt = SYSUTCDATETIME()
    WHEN NOT MATCHED THEN
        INSERT (AccountID, FinancialYearID, PeriodNo, DebitTotal, CreditTotal)
        VALUES (s.AccountID, @FYID, @PeriodNo, s.D, s.C);
END
GO

/* ---------------- Post wrapper (owns the transaction) --------------- */

CREATE OR ALTER PROCEDURE dbo.sp_Accounting_PostVoucher
    @VoucherID INT,
    @PostedBy  INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @No NVARCHAR(50);
        EXEC dbo.sp_Accounting_PostCore @VoucherID = @VoucherID, @PostedBy = @PostedBy, @VoucherNo = @No OUTPUT;
        COMMIT TRANSACTION;
        DECLARE @FY INT = (SELECT FinancialYearID FROM dbo.Vouchers WHERE VoucherID = @VoucherID);
        SELECT @VoucherID AS VoucherID, @No AS VoucherNo, @FY AS FinancialYearID;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

/* ---------------- Create + post wrapper ----------------------------- */

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

        DECLARE @NewID INT = NULL; -- NULL = create new draft
        EXEC dbo.sp_FinanceVouchers_SaveDraftCore
             @VoucherID = @NewID OUTPUT,
             @VoucherTypeID = @VoucherTypeID, @VoucherDate = @VoucherDate,
             @BranchID = @BranchID, @Narrative = @Narrative,
             @EntriesJson = @EntriesJson, @UserId = @UserId;

        UPDATE dbo.Vouchers
           SET SourceModule = @SourceModule, SourceID = @SourceID,
               ReversalOfVoucherID = @ReversalOfVoucherID
         WHERE VoucherID = @NewID;

        DECLARE @No NVARCHAR(50);
        EXEC dbo.sp_Accounting_PostCore @VoucherID = @NewID, @PostedBy = @UserId, @VoucherNo = @No OUTPUT;

        DECLARE @FY INT = (SELECT FinancialYearID FROM dbo.Vouchers WHERE VoucherID = @NewID);

        COMMIT TRANSACTION;
        SELECT @NewID AS VoucherID, @No AS VoucherNo, @FY AS FinancialYearID;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

/* ---------------- Reversal (via cores, no INSERT-EXEC) --------------- */

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

        DECLARE @Type INT, @BranchID INT, @Status NVARCHAR(20), @OrigNo NVARCHAR(50);
        SELECT @Type = VoucherTypeID, @BranchID = BranchID, @Status = Status, @OrigNo = VoucherNo
        FROM dbo.Vouchers WITH (UPDLOCK, HOLDLOCK)
        WHERE VoucherID = @VoucherID AND IsDeleted = 0;

        IF @Type IS NULL THROW 51001, 'Voucher not found.', 1;
        IF @Status = 'Draft' THROW 51023, 'A draft voucher cannot be reversed — delete it instead.', 1;
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

        DECLARE @NewID INT = NULL; -- NULL = create new draft
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

        DECLARE @FY INT = (SELECT FinancialYearID FROM dbo.Vouchers WHERE VoucherID = @NewID);

        COMMIT TRANSACTION;
        SELECT @NewID AS VoucherID, @No AS VoucherNo, @FY AS FinancialYearID;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

/* ---------------- Year close (via cores, no INSERT-EXEC) ------------- */

CREATE OR ALTER PROCEDURE dbo.sp_FinanceYears_Close
    @FinancialYearID INT,
    @ClosedBy INT = NULL,
    @RetainedEarningsAccountID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @Start DATE, @End DATE, @Status NVARCHAR(20), @Name NVARCHAR(50);
        SELECT @Start = StartDate, @End = EndDate, @Status = Status, @Name = Name
        FROM dbo.FinancialYears WITH (UPDLOCK, HOLDLOCK)
        WHERE FinancialYearID = @FinancialYearID;

        IF @Start IS NULL THROW 51037, 'Financial year not found.', 1;
        IF @Status = 'Closed' THROW 51040, 'Financial year is already closed.', 1;

        IF EXISTS (SELECT 1 FROM dbo.Vouchers
                   WHERE FinancialYearID = @FinancialYearID AND Status = 'Draft' AND IsDeleted = 0)
            THROW 51036, 'Draft vouchers exist in this financial year. Post or delete them before closing.', 1;

        IF @RetainedEarningsAccountID IS NULL
        BEGIN
            DECLARE @Cfg NVARCHAR(MAX) = (SELECT Value FROM dbo.Settings WHERE [Key] = 'FinanceAccounting');
            IF @Cfg IS NOT NULL
                SET @RetainedEarningsAccountID = TRY_CAST(JSON_VALUE(@Cfg, '$.retainedEarningsAccountId') AS INT);
        END
        IF @RetainedEarningsAccountID IS NULL
            THROW 51027, 'Retained earnings account is not configured (Finance Defaults - Accounting).', 1;

        DECLARE @REType NVARCHAR(20), @REIsControl BIT, @REActive BIT;
        SELECT @REType = AccountType, @REIsControl = IsControl, @REActive = IsActive
        FROM dbo.Accounts WHERE AccountID = @RetainedEarningsAccountID AND IsDeleted = 0;
        IF @REType IS NULL
            THROW 51028, 'Retained earnings account not found.', 1;
        IF @REIsControl = 1 OR @REType <> 'Capital' OR @REActive = 0
            THROW 51028, 'Retained earnings must be an active Detail account of type Capital.', 1;

        DECLARE @ClosePeriodID INT, @ClosePeriodStatus NVARCHAR(20);
        SELECT @ClosePeriodID = PeriodID, @ClosePeriodStatus = Status
        FROM dbo.AccountingPeriods
        WHERE FinancialYearID = @FinancialYearID AND @End BETWEEN StartDate AND EndDate;
        IF @ClosePeriodID IS NULL
            THROW 51017, 'No accounting period covers the financial year end date.', 1;
        IF @ClosePeriodStatus <> 'Open'
            UPDATE dbo.AccountingPeriods SET Status = 'Open' WHERE PeriodID = @ClosePeriodID;

        IF OBJECT_ID('tempdb..#CloseLines') IS NOT NULL DROP TABLE #CloseLines;
        CREATE TABLE #CloseLines (AccountID INT, Debit DECIMAL(18,2), Credit DECIMAL(18,2), Narrative NVARCHAR(500));

        ;WITH nets AS (
            SELECT a.AccountID, a.AccountType,
                   SUM(e.Debit) AS Dr, SUM(e.Credit) AS Cr
            FROM dbo.VoucherEntries e
            JOIN dbo.Vouchers v ON v.VoucherID = e.VoucherID AND v.Status IN ('Posted','Reversed') AND v.IsDeleted = 0
            JOIN dbo.Accounts a ON a.AccountID = e.AccountID AND a.IsControl = 0
            WHERE v.VoucherDate <= @End AND a.AccountType IN ('Revenue','Expense')
            GROUP BY a.AccountID, a.AccountType
        )
        INSERT INTO #CloseLines (AccountID, Debit, Credit, Narrative)
        SELECT AccountID,
               CASE WHEN AccountType = 'Revenue' THEN Cr - Dr ELSE 0 END,
               CASE WHEN AccountType = 'Expense' THEN Dr - Cr ELSE 0 END,
               CASE WHEN AccountType = 'Revenue' THEN 'Close revenue to retained earnings'
                    ELSE 'Close expense to retained earnings' END
        FROM nets
        WHERE CASE WHEN AccountType = 'Revenue' THEN Cr - Dr ELSE Dr - Cr END <> 0;

        DECLARE @TotalDebit DECIMAL(18,2) = ISNULL((SELECT SUM(Debit) FROM #CloseLines), 0);
        DECLARE @TotalCredit DECIMAL(18,2) = ISNULL((SELECT SUM(Credit) FROM #CloseLines), 0);
        DECLARE @NetProfit DECIMAL(18,2) = @TotalDebit - @TotalCredit;

        DECLARE @CloseVoucherID INT = NULL;
        IF @TotalDebit <> 0 OR @TotalCredit <> 0
        BEGIN
            IF @NetProfit > 0
                INSERT INTO #CloseLines (AccountID, Debit, Credit, Narrative)
                VALUES (@RetainedEarningsAccountID, 0, @NetProfit, 'Net profit transferred to retained earnings');
            ELSE IF @NetProfit < 0
                INSERT INTO #CloseLines (AccountID, Debit, Credit, Narrative)
                VALUES (@RetainedEarningsAccountID, -@NetProfit, 0, 'Net loss transferred to retained earnings');

            DECLARE @JPV INT = (SELECT VoucherTypeID FROM dbo.VoucherTypes WHERE TypeCode = 'JPV' AND IsActive = 1);
            IF @JPV IS NULL
                THROW 51021, 'The Journal Voucher type is required for year closing.', 1;

            DECLARE @BranchID INT = (SELECT TOP 1 BranchID FROM dbo.Branches
                                     WHERE IsActive = 1 AND IsDeleted = 0 ORDER BY BranchID);
            IF @BranchID IS NULL THROW 51018, 'No active branch available for the closing voucher.', 1;

            DECLARE @Json NVARCHAR(MAX) =
                (SELECT AccountID, Debit, Credit, Narrative
                 FROM #CloseLines
                 WHERE (Debit <> 0 OR Credit <> 0)
                 FOR JSON PATH);

            DECLARE @CloseNarrative NVARCHAR(500) = CONCAT('Year closing entries - ', @Name);

            DECLARE @NewID INT = NULL; -- NULL = create new draft
            EXEC dbo.sp_FinanceVouchers_SaveDraftCore
                 @VoucherID = @NewID OUTPUT,
                 @VoucherTypeID = @JPV, @VoucherDate = @End, @BranchID = @BranchID,
                 @Narrative = @CloseNarrative, @EntriesJson = @Json, @UserId = @ClosedBy;

            UPDATE dbo.Vouchers SET SourceModule = 'YearClose', SourceID = @FinancialYearID
            WHERE VoucherID = @NewID;

            DECLARE @No NVARCHAR(50);
            EXEC dbo.sp_Accounting_PostCore @VoucherID = @NewID, @PostedBy = @ClosedBy, @VoucherNo = @No OUTPUT;

            SET @CloseVoucherID = @NewID;
        END

        IF @ClosePeriodStatus <> 'Open'
            UPDATE dbo.AccountingPeriods SET Status = @ClosePeriodStatus WHERE PeriodID = @ClosePeriodID;

        DECLARE @NS DATE = DATEADD(DAY, 1, @End);
        DECLARE @NE DATE = DATEADD(DAY, -1, DATEADD(YEAR, 1, @NS));
        DECLARE @NextFY INT = (SELECT TOP 1 FinancialYearID FROM dbo.FinancialYears
                               WHERE (@NS <= EndDate) AND (@NE >= StartDate) ORDER BY FinancialYearID);
        IF @NextFY IS NULL
        BEGIN
            DECLARE @NextName NVARCHAR(50) = 'FY ' + CAST(YEAR(@NS) AS NVARCHAR(10));
            IF EXISTS (SELECT 1 FROM dbo.FinancialYears WHERE Name = @NextName)
                SET @NextName = @NextName + ' (' + CONVERT(NVARCHAR(10), @NS, 23) + ')';
            INSERT INTO dbo.FinancialYears (Name, StartDate, EndDate, Status, CreatedBy)
            VALUES (@NextName, @NS, @NE, 'Open', @ClosedBy);
            SET @NextFY = CAST(SCOPE_IDENTITY() AS INT);

            DECLARE @i INT = 0;
            WHILE @i < 12
            BEGIN
                DECLARE @ps DATE = DATEADD(MONTH, @i, @NS);
                DECLARE @pe DATE = CASE WHEN @i = 11 THEN @NE
                                        WHEN EOMONTH(@ps) > @NE THEN @NE
                                        ELSE EOMONTH(@ps) END;
                INSERT INTO dbo.AccountingPeriods (FinancialYearID, PeriodNo, StartDate, EndDate, Status, CreatedBy)
                VALUES (@NextFY, @i + 1, @ps, @pe, 'Open', @ClosedBy);
                SET @i = @i + 1;
            END
        END

        INSERT INTO dbo.AccountBalances (AccountID, FinancialYearID, PeriodNo, DebitTotal, CreditTotal)
        SELECT e.AccountID, @NextFY, 0, SUM(e.Debit), SUM(e.Credit)
        FROM dbo.VoucherEntries e
        JOIN dbo.Vouchers v ON v.VoucherID = e.VoucherID AND v.Status IN ('Posted','Reversed') AND v.IsDeleted = 0
        WHERE v.VoucherDate <= @End
        GROUP BY e.AccountID
        HAVING SUM(e.Debit) <> SUM(e.Credit);

        UPDATE dbo.FinancialYears SET Status = 'Closed', UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @ClosedBy
        WHERE FinancialYearID = @FinancialYearID;

        COMMIT TRANSACTION;
        SELECT @CloseVoucherID AS ClosingVoucherID, @NextFY AS NextFinancialYearID, @NetProfit AS NetProfit;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

PRINT '=== 12_finance_procedures.sql (v2 engine) applied. ===';
GO

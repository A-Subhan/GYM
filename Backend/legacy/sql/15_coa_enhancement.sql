/* ============================================================================
   CONTOURA LABS — GYM MANAGEMENT SYSTEM
   COA ENHANCEMENT (15_coa_enhancement.sql)
   ----------------------------------------------------------------------------
   Idempotent. Run AFTER 14_finance_rework.sql.

   - New account columns: book type, branch assignment, description,
     reference no, contact info, identification info, bank info, photo.
   - sp_FinanceAccounts_Create: AUTOMATIC account code generation from the
     parent account (users never type a code). Codes respect the configured
     COA level widths; codes of soft-deleted accounts keep their sequence
     slot, so a code with accounting history is never reused.
   - sp_FinanceAccounts_Update: editable profile/book/branch fields; parent
     and code are intentionally immutable (code stability).
   - sp_FinanceAccounts_Selector: Book Type + branch availability filtering
     (drives the voucher Book Account dropdowns).
   - sp_FinanceAccounts_NextCode / sp_FinanceAccounts_SetPhoto.
   ============================================================================ */

/* ------------------------------------------------------------------ */
/* NEW COLUMNS                                                         */
/* ------------------------------------------------------------------ */
IF COL_LENGTH('dbo.Accounts', 'Description') IS NULL        ALTER TABLE dbo.Accounts ADD Description NVARCHAR(500) NULL;
GO
IF COL_LENGTH('dbo.Accounts', 'ReferenceNo') IS NULL        ALTER TABLE dbo.Accounts ADD ReferenceNo NVARCHAR(50) NULL;
GO
IF COL_LENGTH('dbo.Accounts', 'Address') IS NULL            ALTER TABLE dbo.Accounts ADD Address NVARCHAR(500) NULL;
GO
IF COL_LENGTH('dbo.Accounts', 'Phone') IS NULL              ALTER TABLE dbo.Accounts ADD Phone NVARCHAR(30) NULL;
GO
IF COL_LENGTH('dbo.Accounts', 'WhatsApp') IS NULL           ALTER TABLE dbo.Accounts ADD WhatsApp NVARCHAR(30) NULL;
GO
IF COL_LENGTH('dbo.Accounts', 'Telephone') IS NULL          ALTER TABLE dbo.Accounts ADD Telephone NVARCHAR(30) NULL;
GO
IF COL_LENGTH('dbo.Accounts', 'Fax') IS NULL                ALTER TABLE dbo.Accounts ADD Fax NVARCHAR(30) NULL;
GO
IF COL_LENGTH('dbo.Accounts', 'Email') IS NULL              ALTER TABLE dbo.Accounts ADD Email NVARCHAR(150) NULL;
GO
IF COL_LENGTH('dbo.Accounts', 'CNIC') IS NULL               ALTER TABLE dbo.Accounts ADD CNIC NVARCHAR(20) NULL;
GO
IF COL_LENGTH('dbo.Accounts', 'NTN') IS NULL                ALTER TABLE dbo.Accounts ADD NTN NVARCHAR(20) NULL;
GO
IF COL_LENGTH('dbo.Accounts', 'STRN') IS NULL               ALTER TABLE dbo.Accounts ADD STRN NVARCHAR(20) NULL;
GO
IF COL_LENGTH('dbo.Accounts', 'Photo') IS NULL              ALTER TABLE dbo.Accounts ADD Photo VARBINARY(MAX) NULL;
GO
IF COL_LENGTH('dbo.Accounts', 'BankName') IS NULL           ALTER TABLE dbo.Accounts ADD BankName NVARCHAR(150) NULL;
GO
IF COL_LENGTH('dbo.Accounts', 'BankAccountTitle') IS NULL   ALTER TABLE dbo.Accounts ADD BankAccountTitle NVARCHAR(150) NULL;
GO
IF COL_LENGTH('dbo.Accounts', 'BankAccountNo') IS NULL      ALTER TABLE dbo.Accounts ADD BankAccountNo NVARCHAR(50) NULL;
GO
IF COL_LENGTH('dbo.Accounts', 'IBAN') IS NULL               ALTER TABLE dbo.Accounts ADD IBAN NVARCHAR(50) NULL;
GO
IF COL_LENGTH('dbo.Accounts', 'BankBranch') IS NULL         ALTER TABLE dbo.Accounts ADD BankBranch NVARCHAR(150) NULL;
GO
IF COL_LENGTH('dbo.Accounts', 'BookType') IS NULL
    ALTER TABLE dbo.Accounts ADD BookType NVARCHAR(10) NULL
        CHECK (BookType IN (N'Cash Book', N'Bank Book'));
GO
IF COL_LENGTH('dbo.Accounts', 'BranchID') IS NULL
    ALTER TABLE dbo.Accounts ADD BranchID INT NULL
        FOREIGN KEY REFERENCES dbo.Branches(BranchID);
GO

/* ------------------------------------------------------------------ */
/* CREATE — automatic code generation from the parent account          */
/* ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE dbo.sp_FinanceAccounts_Create
    @Title       NVARCHAR(150),
    @ParentAccountID INT,
    @IsControl   BIT = 0,
    @KnockOff    BIT = 0,
    @BookType    NVARCHAR(10) = NULL,
    @BranchID    INT = NULL,
    @IsActive    BIT = 1,
    @Description NVARCHAR(500) = NULL,
    @ReferenceNo NVARCHAR(50) = NULL,
    @Address     NVARCHAR(500) = NULL,
    @Phone       NVARCHAR(30) = NULL,
    @WhatsApp    NVARCHAR(30) = NULL,
    @Telephone   NVARCHAR(30) = NULL,
    @Fax         NVARCHAR(30) = NULL,
    @Email       NVARCHAR(150) = NULL,
    @CNIC        NVARCHAR(20) = NULL,
    @NTN         NVARCHAR(20) = NULL,
    @STRN        NVARCHAR(20) = NULL,
    @BankName           NVARCHAR(150) = NULL,
    @BankAccountTitle   NVARCHAR(150) = NULL,
    @BankAccountNo      NVARCHAR(50) = NULL,
    @IBAN               NVARCHAR(50) = NULL,
    @BankBranch         NVARCHAR(150) = NULL,
    @TagsJson    NVARCHAR(MAX) = NULL,
    @CreatedBy   INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF LTRIM(RTRIM(@Title)) IS NULL
            THROW 51012, 'Account name is required.', 1;
        IF @ParentAccountID IS NULL
            THROW 51012, 'Select a parent account - the code is generated from the parent.', 1;
        IF @BookType IS NOT NULL AND @BookType NOT IN (N'Cash Book', N'Bank Book')
            THROW 51012, 'Book Type must be Cash Book or Bank Book.', 1;
        IF @BookType IS NOT NULL AND @IsControl = 1
            THROW 51012, 'Book Type applies to Detail (posting) accounts only.', 1;
        IF @KnockOff = 1 AND @IsControl = 1
            THROW 51012, 'Knock Off applies to Detail (posting) accounts only.', 1;
        IF @BranchID IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.Branches WHERE BranchID = @BranchID AND IsDeleted = 0)
            THROW 51018, 'Invalid branch.', 1;

        DECLARE @ParentLevel INT, @ParentType NVARCHAR(20), @ParentCode NVARCHAR(12), @ParentIsControl BIT;
        SELECT @ParentLevel = a.LevelNo, @ParentType = a.AccountType, @ParentCode = a.Code, @ParentIsControl = a.IsControl
        FROM dbo.Accounts a WITH (UPDLOCK, HOLDLOCK)
        WHERE a.AccountID = @ParentAccountID AND a.IsDeleted = 0;

        IF @ParentCode IS NULL
            THROW 51008, 'Parent account not found.', 1;
        IF @ParentIsControl = 0
            THROW 51012, 'Cannot create a child account under a Detail (posting) account.', 1;

        -- child level width from the configured COA structure
        DECLARE @ChildLevel INT = @ParentLevel + 1;
        DECLARE @Width INT = (SELECT Digits FROM dbo.FinanceCoaLevels WHERE LevelNo = @ChildLevel);
        IF @Width IS NULL
            THROW 51012, 'The parent account is already at the deepest configured COA level - no child account can be added under it.', 1;

        -- next sequence: counts ALL children incl. soft-deleted, so a code
        -- whose account has accounting history is never reused
        DECLARE @Next INT;
        SELECT @Next = ISNULL(MAX(TRY_CONVERT(INT, RIGHT(Code, @Width))), 0) + 1
        FROM dbo.Accounts WITH (UPDLOCK, HOLDLOCK)
        WHERE ParentAccountID = @ParentAccountID;

        DECLARE @Code NVARCHAR(12) = @ParentCode + RIGHT(REPLICATE('0', 12) + CAST(@Next AS NVARCHAR(12)), @Width);

        IF EXISTS (SELECT 1 FROM dbo.Accounts WHERE Code = @Code)
            THROW 51011, 'Generated account code already exists.', 1;

        INSERT INTO dbo.Accounts (Code, Title, AccountType, ParentAccountID, LevelNo, IsControl, KnockOff,
                                  BookType, BranchID, IsActive,
                                  Description, ReferenceNo, Address, Phone, WhatsApp, Telephone, Fax, Email,
                                  CNIC, NTN, STRN,
                                  BankName, BankAccountTitle, BankAccountNo, IBAN, BankBranch, CreatedBy)
        VALUES (@Code, LTRIM(RTRIM(@Title)), @ParentType, @ParentAccountID, @ChildLevel, @IsControl, @KnockOff,
                @BookType, @BranchID, @IsActive,
                @Description, @ReferenceNo, @Address, @Phone, @WhatsApp, @Telephone, @Fax, @Email,
                @CNIC, @NTN, @STRN,
                @BankName, @BankAccountTitle, @BankAccountNo, @IBAN, @BankBranch, @CreatedBy);

        DECLARE @NewID INT = CAST(SCOPE_IDENTITY() AS INT);

        IF @TagsJson IS NOT NULL
            INSERT INTO dbo.AccountTags (AccountID, Tag)
            SELECT DISTINCT @NewID, LTRIM(RTRIM(CAST([value] AS NVARCHAR(30))))
            FROM OPENJSON(@TagsJson)
            WHERE LTRIM(RTRIM(CAST([value] AS NVARCHAR(30)))) <> '';

        COMMIT TRANSACTION;
        SELECT @NewID AS AccountID, @Code AS Code, @ChildLevel AS LevelNo;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

/* Preview of the code the system will generate (no side effects) */
CREATE OR ALTER PROCEDURE dbo.sp_FinanceAccounts_NextCode
    @ParentAccountID INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ParentLevel INT, @ParentCode NVARCHAR(12), @ParentIsControl BIT;
    SELECT @ParentLevel = LevelNo, @ParentCode = Code, @ParentIsControl = IsControl
    FROM dbo.Accounts WHERE AccountID = @ParentAccountID AND IsDeleted = 0;

    IF @ParentCode IS NULL THROW 51008, 'Parent account not found.', 1;

    DECLARE @ChildLevel INT = @ParentLevel + 1;
    DECLARE @Width INT = (SELECT Digits FROM dbo.FinanceCoaLevels WHERE LevelNo = @ChildLevel);
    IF @Width IS NULL
        SELECT CAST(0 AS INT) AS CanAddChild, CAST(NULL AS NVARCHAR(12)) AS NextCode;
    ELSE
    BEGIN
        DECLARE @Next INT;
        SELECT @Next = ISNULL(MAX(TRY_CONVERT(INT, RIGHT(Code, @Width))), 0) + 1
        FROM dbo.Accounts
        WHERE ParentAccountID = @ParentAccountID;

        SELECT CAST(1 AS INT) AS CanAddChild,
               @ParentCode + RIGHT(REPLICATE('0', 12) + CAST(@Next AS NVARCHAR(12)), @Width) AS NextCode;
    END
END
GO

/* ------------------------------------------------------------------ */
/* UPDATE — profile fields only (parent and code are immutable)        */
/* ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE dbo.sp_FinanceAccounts_Update
    @AccountID INT,
    @Title     NVARCHAR(150),
    @KnockOff  BIT = NULL,
    @BookType  NVARCHAR(10) = NULL,
    @BranchID  INT = NULL,
    @IsActive  BIT = NULL,
    @Description NVARCHAR(500) = NULL,
    @ReferenceNo NVARCHAR(50) = NULL,
    @Address     NVARCHAR(500) = NULL,
    @Phone       NVARCHAR(30) = NULL,
    @WhatsApp    NVARCHAR(30) = NULL,
    @Telephone   NVARCHAR(30) = NULL,
    @Fax         NVARCHAR(30) = NULL,
    @Email       NVARCHAR(150) = NULL,
    @CNIC        NVARCHAR(20) = NULL,
    @NTN         NVARCHAR(20) = NULL,
    @STRN        NVARCHAR(20) = NULL,
    @BankName           NVARCHAR(150) = NULL,
    @BankAccountTitle   NVARCHAR(150) = NULL,
    @BankAccountNo      NVARCHAR(50) = NULL,
    @IBAN               NVARCHAR(50) = NULL,
    @BankBranch         NVARCHAR(150) = NULL,
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

        IF @BookType IS NOT NULL AND @BookType NOT IN (N'Cash Book', N'Bank Book')
            THROW 51012, 'Book Type must be Cash Book or Bank Book.', 1;
        IF @BookType IS NOT NULL
           AND EXISTS (SELECT 1 FROM dbo.Accounts WHERE AccountID = @AccountID AND IsControl = 1)
            THROW 51012, 'Book Type applies to Detail (posting) accounts only.', 1;
        IF @KnockOff = 1
           AND EXISTS (SELECT 1 FROM dbo.Accounts WHERE AccountID = @AccountID AND IsControl = 1)
            THROW 51012, 'Knock Off applies to Detail (posting) accounts only.', 1;
        IF @BranchID IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.Branches WHERE BranchID = @BranchID AND IsDeleted = 0)
            THROW 51018, 'Invalid branch.', 1;
        IF @IsActive = 0
           AND EXISTS (SELECT 1 FROM dbo.Accounts c
                       WHERE c.ParentAccountID = @AccountID AND c.IsDeleted = 0 AND c.IsActive = 1)
            THROW 51013, 'Account has active child accounts. Deactivate the children first.', 1;

        UPDATE dbo.Accounts
           SET Title = LTRIM(RTRIM(@Title)),
               KnockOff = COALESCE(@KnockOff, KnockOff),
               BookType = CASE WHEN @BookType = '' THEN NULL ELSE COALESCE(@BookType, BookType) END,
               BranchID = CASE WHEN @BranchID IS NULL THEN BranchID ELSE @BranchID END,
               IsActive = COALESCE(@IsActive, IsActive),
               Description = @Description,
               ReferenceNo = @ReferenceNo,
               Address = @Address, Phone = @Phone, WhatsApp = @WhatsApp,
               Telephone = @Telephone, Fax = @Fax, Email = @Email,
               CNIC = @CNIC, NTN = @NTN, STRN = @STRN,
               BankName = @BankName, BankAccountTitle = @BankAccountTitle,
               BankAccountNo = @BankAccountNo, IBAN = @IBAN, BankBranch = @BankBranch,
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

/* ------------------------------------------------------------------ */
/* LIST — grid + global search fields (no photo payload)               */
/* ------------------------------------------------------------------ */
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
            a.BookType, a.BranchID, b.Name AS BranchName,
            a.Description, a.ReferenceNo,
            a.Email, a.Phone,
            a.CreatedAt, a.UpdatedAt,
            STUFF((SELECT ',' + t.Tag FROM dbo.AccountTags t
                   WHERE t.AccountID = a.AccountID ORDER BY t.Tag FOR XML PATH('')), 1, 1, '') AS Tags,
            CASE WHEN EXISTS (SELECT 1 FROM dbo.VoucherEntries e WHERE e.AccountID = a.AccountID)
                 THEN 1 ELSE 0 END AS HasTransactions,
            (SELECT COUNT(*) FROM dbo.Accounts c WHERE c.ParentAccountID = a.AccountID AND c.IsDeleted = 0) AS ChildCount
    FROM    dbo.Accounts a
    LEFT JOIN dbo.Accounts p ON p.AccountID = a.ParentAccountID
    LEFT JOIN dbo.Branches b ON b.BranchID = a.BranchID
    WHERE   (@IncludeDeleted = 1 OR a.IsDeleted = 0)
      AND   (@Search IS NULL OR a.Code LIKE '%' + @Search + '%' OR a.Title LIKE '%' + @Search + '%'
              OR a.Description LIKE '%' + @Search + '%' OR a.ReferenceNo LIKE '%' + @Search + '%')
      AND   (@AccountType IS NULL OR a.AccountType = @AccountType)
      AND   (@IsControl IS NULL OR a.IsControl = @IsControl)
      AND   (@IsActive IS NULL OR a.IsActive = @IsActive)
      AND   (@Tag IS NULL OR EXISTS (SELECT 1 FROM dbo.AccountTags t WHERE t.AccountID = a.AccountID AND t.Tag = @Tag))
    ORDER BY a.Code;
END
GO

/* ------------------------------------------------------------------ */
/* GET — complete account details incl. photo (base64 by the model)    */
/* ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE dbo.sp_FinanceAccounts_Get
    @AccountID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  a.AccountID, a.Code, a.Title, a.AccountType, a.ParentAccountID,
            p.Code AS ParentCode, p.Title AS ParentTitle,
            a.LevelNo, a.IsControl, a.IsActive, a.IsDeleted,
            ISNULL(a.KnockOff, 0) AS KnockOff,
            a.BookType, a.BranchID, b.Name AS BranchName,
            a.Description, a.ReferenceNo,
            a.Address, a.Phone, a.WhatsApp, a.Telephone, a.Fax, a.Email,
            a.CNIC, a.NTN, a.STRN,
            a.BankName, a.BankAccountTitle, a.BankAccountNo, a.IBAN, a.BankBranch,
            a.CreatedAt, a.UpdatedAt,
            CASE WHEN EXISTS (SELECT 1 FROM dbo.VoucherEntries e WHERE e.AccountID = a.AccountID)
                 THEN 1 ELSE 0 END AS HasTransactions
    FROM dbo.Accounts a
    LEFT JOIN dbo.Accounts p ON p.AccountID = a.ParentAccountID
    LEFT JOIN dbo.Branches b ON b.BranchID = a.BranchID
    WHERE a.AccountID = @AccountID;

    SELECT Tag FROM dbo.AccountTags WHERE AccountID = @AccountID ORDER BY Tag;

    SELECT c.AccountID, c.Code, c.Title, c.AccountType, c.IsControl, c.IsActive
    FROM dbo.Accounts c
    WHERE c.ParentAccountID = @AccountID AND c.IsDeleted = 0
    ORDER BY c.Code;
END
GO

/* ------------------------------------------------------------------ */
/* SELECTOR — voucher Book Account / line account filtering            */
/* Book Type drives cash/bank voucher Book Accounts; branch            */
/* availability: NULL BranchID = all branches.                         */
/* ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE dbo.sp_FinanceAccounts_Selector
    @Tag    NVARCHAR(30) = NULL,
    @BookType NVARCHAR(10) = NULL,
    @BranchID INT = NULL,
    @Search NVARCHAR(100) = NULL,
    @TopN   INT = 100
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (@TopN)
           a.AccountID, a.Code, a.Title, a.AccountType, a.BookType, a.BranchID
    FROM dbo.Accounts a
    WHERE a.IsControl = 0 AND a.IsActive = 1 AND a.IsDeleted = 0
      AND (@Tag IS NULL OR EXISTS (SELECT 1 FROM dbo.AccountTags t WHERE t.AccountID = a.AccountID AND t.Tag = @Tag))
      AND (@BookType IS NULL OR a.BookType = @BookType)
      AND (@BranchID IS NULL OR a.BranchID IS NULL OR a.BranchID = @BranchID)
      AND (@Search IS NULL OR a.Code LIKE '%' + @Search + '%' OR a.Title LIKE '%' + @Search + '%')
    ORDER BY a.Code;
END
GO

/* ------------------------------------------------------------------ */
/* PHOTO                                                               */
/* ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE dbo.sp_FinanceAccounts_SetPhoto
    @AccountID INT, @Photo VARBINARY(MAX), @UpdatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.Accounts WHERE AccountID = @AccountID AND IsDeleted = 0)
        THROW 51008, 'Account not found.', 1;
    UPDATE dbo.Accounts SET Photo = @Photo, UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @UpdatedBy
    WHERE AccountID = @AccountID;
    SELECT 'OK' AS Result;
END
GO

PRINT '=== 15_coa_enhancement.sql applied successfully. ===';
GO

/* ------------------------------------------------------------------ */
/* Fix in NextCode: MAX over ALL children incl. soft-deleted           */
/* (keeps freed codes of accounts with history from being reused)      */
/* ------------------------------------------------------------------ */

/* Book Type defaults for the seeded cash/bank accounts (idempotent) */
UPDATE dbo.Accounts SET BookType = N'Cash Book'
WHERE Code = N'10102001' AND BookType IS NULL;
GO
UPDATE dbo.Accounts SET BookType = N'Bank Book'
WHERE Code IN (N'10103001', N'10103002') AND BookType IS NULL;
GO

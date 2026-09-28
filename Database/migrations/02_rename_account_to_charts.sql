-- ============================================================================
-- Contoura Gym ERP — Migration 02: RENAME Account -> charts + new columns
-- ============================================================================
-- 1. Renames [dbo].[Account] to [dbo].[charts] (dependent FKs stay valid,
--    sp_rename keeps them bound to the object).
-- 2. Archives openingBalance / openingBalanceType into
--    zz_backup_charts_opening_<yyyymmdd> (nothing is lost; migration 03 folds
--    the archive into the new OpenTB book), then removes both columns using
--    dynamic dependency cleanup (default constraints / indexes / FKs are
--    looked up in the catalog, never hardcoded).
-- 3. Adds the new finance columns
--    (strn, fbr, otherName, referenceNumber, faxNumber, city, country,
--     website, paymentTerms, registrationNumber).
-- 4. Merges parentId into a single NOT NULL parentCode column (children hold
--    the parent's account code; the tree root(s) get the documented sentinel
--    value 'ROOT'), then drops parentId.
--
-- The charts PK is NOT touched here — migration 05 rebuilds it so that
-- charts.id becomes the account code.
-- ============================================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET LANGUAGE us_english;
GO

DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'01_bootstrap_history', @self = N'02_rename_account_to_charts', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    02 already applied, skipping.'; RETURN; END
BEGIN TRY
    BEGIN TRAN;

    -- 1. Rename Account -> charts
    IF OBJECT_ID('dbo.Account') IS NOT NULL AND OBJECT_ID('dbo.charts') IS NULL
    BEGIN
        EXEC sp_rename 'dbo.Account', 'charts';
        PRINT '  table Account renamed to charts';
    END
    IF OBJECT_ID('dbo.Account') IS NULL AND OBJECT_ID('dbo.charts') IS NOT NULL
        PRINT '  charts already present - rename skipped';

    -- 2. Archive opening balance values BEFORE dropping the columns
    IF COL_LENGTH('dbo.charts', 'openingBalance') IS NOT NULL
       AND OBJECT_ID('dbo.zz_backup_charts_opening') IS NULL
    BEGIN
        DECLARE @rowc int = (SELECT COUNT(*) FROM dbo.charts);
        DECLARE @bak sysname = N'zz_backup_charts_opening_' + CONVERT(varchar(8), GETDATE(), 112);
        IF OBJECT_ID('dbo.' + @bak) IS NULL
        BEGIN
            EXEC (N'SELECT id, code, name, branchId, openingBalance, openingBalanceType,
                            SYSDATETIME() AS archivedAt
                     INTO dbo.' + QUOTENAME(@bak) + N'
                     FROM dbo.charts;');
            PRINT '  archived ' + CAST(@rowc AS varchar(10)) + ' charts rows (opening balances) into dbo.' + @bak;
        END
    END
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'02_rename_account_to_charts';
    THROW;
END CATCH
GO

-- 3. Add the new finance columns (each in its own guarded statement)
DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'01_bootstrap_history', @self = N'02_rename_account_to_charts', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    02 already applied, skipping.'; RETURN; END
BEGIN TRY
    IF OBJECT_ID('dbo.charts') IS NULL THROW 51010, 'dbo.charts does not exist — run from batch 1 failed?', 1;

    IF COL_LENGTH('dbo.charts','strn') IS NULL
        ALTER TABLE dbo.charts ADD [strn] NVARCHAR(255) NULL;
    IF COL_LENGTH('dbo.charts','fbr') IS NULL
        ALTER TABLE dbo.charts ADD [fbr] NVARCHAR(255) NULL;
    IF COL_LENGTH('dbo.charts','otherName') IS NULL
        ALTER TABLE dbo.charts ADD [otherName] NVARCHAR(255) NULL;
    IF COL_LENGTH('dbo.charts','referenceNumber') IS NULL
        ALTER TABLE dbo.charts ADD [referenceNumber] NVARCHAR(255) NULL;
    IF COL_LENGTH('dbo.charts','faxNumber') IS NULL
        ALTER TABLE dbo.charts ADD [faxNumber] NVARCHAR(255) NULL;
    IF COL_LENGTH('dbo.charts','city') IS NULL
        ALTER TABLE dbo.charts ADD [city] NVARCHAR(255) NULL;
    IF COL_LENGTH('dbo.charts','country') IS NULL
        ALTER TABLE dbo.charts ADD [country] NVARCHAR(255) NULL;
    IF COL_LENGTH('dbo.charts','website') IS NULL
        ALTER TABLE dbo.charts ADD [website] NVARCHAR(255) NULL;
    IF COL_LENGTH('dbo.charts','paymentTerms') IS NULL
        ALTER TABLE dbo.charts ADD [paymentTerms] NVARCHAR(255) NULL;
    IF COL_LENGTH('dbo.charts','registrationNumber') IS NULL
        ALTER TABLE dbo.charts ADD [registrationNumber] NVARCHAR(255) NULL;
    PRINT '  new finance columns present on charts';
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'02_rename_account_to_charts';
    THROW;
END CATCH
GO

-- 4. parentCode: one hierarchical column, backfilled from parentId
DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'01_bootstrap_history', @self = N'02_rename_account_to_charts', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    02 already applied, skipping.'; RETURN; END
BEGIN TRY
    IF COL_LENGTH('dbo.charts','parentCode') IS NULL
        ALTER TABLE dbo.charts ADD [parentCode] NVARCHAR(50) NULL;
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'02_rename_account_to_charts';
    THROW;
END CATCH
GO

-- 5. Backfill parentCode (separate batch: references the new column)
DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'01_bootstrap_history', @self = N'02_rename_account_to_charts', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    02 already applied, skipping.'; RETURN; END
BEGIN TRY
    UPDATE c SET c.parentCode = p.code
    FROM dbo.charts c
    JOIN dbo.charts p ON p.id = c.parentId
    WHERE c.parentCode IS NULL AND c.parentId IS NOT NULL;

    UPDATE dbo.charts SET parentCode = 'ROOT'
    WHERE parentCode IS NULL AND parentId IS NULL;

    -- any row still without a parent link (dangling parentId) -> root
    UPDATE c SET c.parentCode = 'ROOT'
    FROM dbo.charts c
    WHERE c.parentCode IS NULL;

    DECLARE @nulls int = (SELECT COUNT(*) FROM dbo.charts WHERE parentCode IS NULL);
    IF @nulls > 0 THROW 51011, 'parentCode backfill left NULL rows — aborting.', 1;

    ALTER TABLE dbo.charts ALTER COLUMN [parentCode] NVARCHAR(50) NOT NULL;
    PRINT '  parentCode populated and set NOT NULL (root = ''ROOT'')';
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'02_rename_account_to_charts';
    THROW;
END CATCH
GO

-- 6. Drop parentId and opening-balance columns with dynamic dependency cleanup
DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'01_bootstrap_history', @self = N'02_rename_account_to_charts', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    02 already applied, skipping.'; RETURN; END
BEGIN TRY
    IF COL_LENGTH('dbo.charts','openingBalance') IS NOT NULL
    BEGIN
        DECLARE @rc int = (SELECT COUNT(*) FROM dbo.charts);
        PRINT '  dropping charts.openingBalance (table has ' + CAST(@rc AS varchar(10)) + ' rows; values archived)';
        EXEC dbo.__mig_DropColumn @table = 'dbo.charts', @column = 'openingBalance';
    END
    IF COL_LENGTH('dbo.charts','openingBalanceType') IS NOT NULL
    BEGIN
        DECLARE @rc2 int = (SELECT COUNT(*) FROM dbo.charts);
        PRINT '  dropping charts.openingBalanceType (table has ' + CAST(@rc2 AS varchar(10)) + ' rows; values archived)';
        EXEC dbo.__mig_DropColumn @table = 'dbo.charts', @column = 'openingBalanceType';
    END
    IF COL_LENGTH('dbo.charts','parentId') IS NOT NULL
    BEGIN
        DECLARE @rc3 int = (SELECT COUNT(*) FROM dbo.charts);
        PRINT '  dropping charts.parentId (table has ' + CAST(@rc3 AS varchar(10)) + ' rows; replaced by parentCode)';
        EXEC dbo.__mig_DropColumn @table = 'dbo.charts', @column = 'parentId';
    END
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'02_rename_account_to_charts';
    THROW;
END CATCH
GO

-- 7. Verify end state, mark Success, commit
DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'01_bootstrap_history', @self = N'02_rename_account_to_charts', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    02 already applied, skipping.'; RETURN; END
BEGIN TRY
    IF OBJECT_ID('dbo.charts') IS NULL THROW 51012, 'verification failed: dbo.charts missing', 1;
    IF COL_LENGTH('dbo.charts','openingBalance') IS NOT NULL
        THROW 51012, 'verification failed: openingBalance still present', 1;
    IF COL_LENGTH('dbo.charts','parentCode') IS NULL
        THROW 51012, 'verification failed: parentCode missing', 1;
    IF EXISTS (SELECT 1 FROM dbo.charts WHERE parentCode IS NULL)
        THROW 51012, 'verification failed: parentCode has NULLs', 1;

    EXEC dbo.__mig_Done @self = N'02_rename_account_to_charts';
    IF @@TRANCOUNT > 0 COMMIT TRAN;
    PRINT '=== 02 done ===';
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'02_rename_account_to_charts';
    THROW;
END CATCH
GO

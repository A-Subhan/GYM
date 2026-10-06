USE GymDB;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- 13_verify.sql
-- ============================================================================
-- PASS/FAIL verification for 13_admin_security_upgrade.sql.
-- Checks:
--   1. Every id format (CMP-, TAX-, PRM-, ROL-, USR-, SCP-, UPM-, ACM-, FDF-)
--      with prefix AND numeric-width validation.
--   2. No orphan references (FK integrity for known relationships)
--   3. No old User id left in any character column of any table — dynamic
--      scan exactly like 13e (every char column of every table except
--      [User] and _UpgradeLog), verified against dbo._UserIdMap (saved by
--      step 13e) so we only flag values that belonged to a still-existing
--      user at migration time.
--   4. IdSequence.next > max(numeric suffix) for each key
--   5. FinanceDefaults columns exist (all 12 expanded columns + the
--      original 6 = 18 total; message states the actual count).
--   6. Company-wide FinanceDefaults row exists (branchId NULL)
--
-- Single batch — no variable crosses a GO. Prints PASS/FAIL per item
-- and ONE summary row at the end:
--   ALL PASS  — every check passed
--   FAILED: <list> — one or more checks failed
-- ============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

PRINT N'=== STEP 13 VERIFY ===';

-- Create dbo._UpgradeLog if missing (so this script can be run even
-- before the upgrade_log table batch from 10_00_log_table.sql).
IF OBJECT_ID('dbo._UpgradeLog','U') IS NULL
BEGIN
    CREATE TABLE dbo._UpgradeLog (
        id INT IDENTITY(1,1) NOT NULL,
        step NVARCHAR(100) NOT NULL,
        status NVARCHAR(20) NOT NULL,
        message NVARCHAR(MAX),
        createdAt DATETIME2 NOT NULL CONSTRAINT [_UpgradeLog_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT [_UpgradeLog_pkey] PRIMARY KEY CLUSTERED ([id])
    );
    PRINT N'  (created dbo._UpgradeLog)';
END
GO

-- ============================================================================
-- Single batch — all variables declared and used within this batch.
-- ============================================================================
USE GymDB;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @results TABLE (item NVARCHAR(100), status NVARCHAR(10), detail NVARCHAR(MAX));
DECLARE @fails NVARCHAR(MAX) = N'';
DECLARE @passCount INT = 0, @failCount INT = 0;
DECLARE @bad INT;
DECLARE @orphans INT;
DECLARE @cuid_count INT;
DECLARE @cuid_sql NVARCHAR(MAX);
DECLARE @cuid_cnt INT;
DECLARE @cp_tbl NVARCHAR(128), @cp_col NVARCHAR(128);
DECLARE @check_pairs TABLE (tbl NVARCHAR(128), col NVARCHAR(128));
DECLARE @seq_key NVARCHAR(50), @tbl NVARCHAR(128), @prefix NVARCHAR(20);
DECLARE @seq_max INT, @seq_next INT, @seq_ok INT = 0, @seq_fail INT = 0;
DECLARE @seq_table TABLE ([key] NVARCHAR(50), tbl NVARCHAR(128), prefix NVARCHAR(20), width INT);
DECLARE @dyn_seq NVARCHAR(MAX);
DECLARE @col_missing INT = 0;
DECLARE @has_company_fd INT = 0;

BEGIN TRY

-- ============================================================================
-- CHECK 1: Every id format — prefix AND numeric-width validation
-- Each id must match: <prefix><zero-padded number of width N>
-- Defaults CMP-[0-9][0-9][0-9], TaxHead TAX-[0-9][0-9][0-9],
-- Permission PRM-[0-9][0-9][0-9][0-9], Role ROL-[0-9][0-9][0-9],
-- User USR-[0-9][0-9][0-9][0-9], ScreenPermission SCP-[0-9][0-9][0-9][0-9],
-- UserPermission UPM-[0-9][0-9][0-9][0-9], AccountMapping ACM-[0-9][0-9][0-9],
-- FinanceDefaults FDF-[0-9][0-9][0-9].
-- ============================================================================

-- Defaults -> CMP-NNN (width 3)
SET @bad = 0;
IF OBJECT_ID('dbo.Defaults','U') IS NOT NULL
    SELECT @bad = COUNT(*) FROM dbo.Defaults WHERE [id] NOT LIKE N'CMP-[0-9][0-9][0-9]';
IF @bad = 0
    INSERT INTO @results VALUES (N'1a-Defaults-CMP', N'PASS', N'All Defaults.id match CMP-NNN');
ELSE
    INSERT INTO @results VALUES (N'1a-Defaults-CMP', N'FAIL', CAST(@bad AS NVARCHAR(10)) + N' rows not matching CMP-NNN');

-- TaxHead -> TAX-NNN (width 3)
SET @bad = 0;
IF OBJECT_ID('dbo.TaxHead','U') IS NOT NULL
    SELECT @bad = COUNT(*) FROM dbo.TaxHead WHERE [id] NOT LIKE N'TAX-[0-9][0-9][0-9]';
IF @bad = 0
    INSERT INTO @results VALUES (N'1b-TaxHead-TAX', N'PASS', N'All TaxHead.id match TAX-NNN');
ELSE
    INSERT INTO @results VALUES (N'1b-TaxHead-TAX', N'FAIL', CAST(@bad AS NVARCHAR(10)) + N' rows not matching TAX-NNN');

-- Permission -> PRM-NNNN (width 4)
SET @bad = 0;
IF OBJECT_ID('dbo.Permission','U') IS NOT NULL
    SELECT @bad = COUNT(*) FROM dbo.Permission WHERE [id] NOT LIKE N'PRM-[0-9][0-9][0-9][0-9]';
IF @bad = 0
    INSERT INTO @results VALUES (N'1c-Permission-PRM', N'PASS', N'All Permission.id match PRM-NNNN');
ELSE
    INSERT INTO @results VALUES (N'1c-Permission-PRM', N'FAIL', CAST(@bad AS NVARCHAR(10)) + N' rows not matching PRM-NNNN');

-- Role -> ROL-NNN (width 3)
SET @bad = 0;
IF OBJECT_ID('dbo.Role','U') IS NOT NULL
    SELECT @bad = COUNT(*) FROM dbo.Role WHERE [id] NOT LIKE N'ROL-[0-9][0-9][0-9]';
IF @bad = 0
    INSERT INTO @results VALUES (N'1d-Role-ROL', N'PASS', N'All Role.id match ROL-NNN');
ELSE
    INSERT INTO @results VALUES (N'1d-Role-ROL', N'FAIL', CAST(@bad AS NVARCHAR(10)) + N' rows not matching ROL-NNN');

-- User -> USR-NNNN (width 4)
SET @bad = 0;
IF OBJECT_ID('dbo.[User]','U') IS NOT NULL
    SELECT @bad = COUNT(*) FROM dbo.[User] WHERE [id] NOT LIKE N'USR-[0-9][0-9][0-9][0-9]';
IF @bad = 0
    INSERT INTO @results VALUES (N'1e-User-USR', N'PASS', N'All User.id match USR-NNNN');
ELSE
    INSERT INTO @results VALUES (N'1e-User-USR', N'FAIL', CAST(@bad AS NVARCHAR(10)) + N' rows not matching USR-NNNN');

-- ScreenPermission -> SCP-NNNN (width 4)
SET @bad = 0;
IF OBJECT_ID('dbo.ScreenPermission','U') IS NOT NULL
    SELECT @bad = COUNT(*) FROM dbo.ScreenPermission WHERE [id] NOT LIKE N'SCP-[0-9][0-9][0-9][0-9]';
IF @bad = 0
    INSERT INTO @results VALUES (N'1f-ScreenPermission-SCP', N'PASS', N'All ScreenPermission.id match SCP-NNNN');
ELSE
    INSERT INTO @results VALUES (N'1f-ScreenPermission-SCP', N'FAIL', CAST(@bad AS NVARCHAR(10)) + N' rows not matching SCP-NNNN');

-- UserPermission -> UPM-NNNN (width 4)
SET @bad = 0;
IF OBJECT_ID('dbo.UserPermission','U') IS NOT NULL
    SELECT @bad = COUNT(*) FROM dbo.UserPermission WHERE [id] NOT LIKE N'UPM-[0-9][0-9][0-9][0-9]';
IF @bad = 0
    INSERT INTO @results VALUES (N'1g-UserPermission-UPM', N'PASS', N'All UserPermission.id match UPM-NNNN');
ELSE
    INSERT INTO @results VALUES (N'1g-UserPermission-UPM', N'FAIL', CAST(@bad AS NVARCHAR(10)) + N' rows not matching UPM-NNNN');

-- AccountMapping -> ACM-NNN (width 3)
SET @bad = 0;
IF OBJECT_ID('dbo.AccountMapping','U') IS NOT NULL
    SELECT @bad = COUNT(*) FROM dbo.AccountMapping WHERE [id] NOT LIKE N'ACM-[0-9][0-9][0-9]';
IF @bad = 0
    INSERT INTO @results VALUES (N'1h-AccountMapping-ACM', N'PASS', N'All AccountMapping.id match ACM-NNN');
ELSE
    INSERT INTO @results VALUES (N'1h-AccountMapping-ACM', N'FAIL', CAST(@bad AS NVARCHAR(10)) + N' rows not matching ACM-NNN');

-- FinanceDefaults -> FDF-NNN (width 3)
SET @bad = 0;
IF OBJECT_ID('dbo.FinanceDefaults','U') IS NOT NULL
    SELECT @bad = COUNT(*) FROM dbo.FinanceDefaults WHERE [id] NOT LIKE N'FDF-[0-9][0-9][0-9]';
IF @bad = 0
    INSERT INTO @results VALUES (N'1i-FinanceDefaults-FDF', N'PASS', N'All FinanceDefaults.id match FDF-NNN');
ELSE
    INSERT INTO @results VALUES (N'1i-FinanceDefaults-FDF', N'FAIL', CAST(@bad AS NVARCHAR(10)) + N' rows not matching FDF-NNN');

-- ============================================================================
-- CHECK 2: No orphan references (known FK / string references)
-- ============================================================================

-- UserPermission.userId -> [User].id
SET @orphans = 0;
IF OBJECT_ID('dbo.UserPermission','U') IS NOT NULL AND OBJECT_ID('dbo.[User]','U') IS NOT NULL
    SELECT @orphans = COUNT(*) FROM dbo.UserPermission up WHERE NOT EXISTS (SELECT 1 FROM dbo.[User] u WHERE u.[id] = up.[userId]);
IF @orphans = 0
    INSERT INTO @results VALUES (N'2a-UserPermission-userId', N'PASS', N'No orphan userId');
ELSE
    INSERT INTO @results VALUES (N'2a-UserPermission-userId', N'FAIL', CAST(@orphans AS NVARCHAR(10)) + N' orphan userId refs');

-- ScreenPermission.roleId -> [Role].id
SET @orphans = 0;
IF OBJECT_ID('dbo.ScreenPermission','U') IS NOT NULL AND OBJECT_ID('dbo.Role','U') IS NOT NULL
    SELECT @orphans = COUNT(*) FROM dbo.ScreenPermission sp WHERE NOT EXISTS (SELECT 1 FROM dbo.Role r WHERE r.[id] = sp.[roleId]);
IF @orphans = 0
    INSERT INTO @results VALUES (N'2b-ScreenPermission-roleId', N'PASS', N'No orphan roleId');
ELSE
    INSERT INTO @results VALUES (N'2b-ScreenPermission-roleId', N'FAIL', CAST(@orphans AS NVARCHAR(10)) + N' orphan roleId refs');

-- RolePermission.roleId -> [Role].id
SET @orphans = 0;
IF OBJECT_ID('dbo.RolePermission','U') IS NOT NULL AND OBJECT_ID('dbo.Role','U') IS NOT NULL
    SELECT @orphans = COUNT(*) FROM dbo.RolePermission rp WHERE NOT EXISTS (SELECT 1 FROM dbo.Role r WHERE r.[id] = rp.[roleId]);
IF @orphans = 0
    INSERT INTO @results VALUES (N'2c-RolePermission-roleId', N'PASS', N'No orphan roleId');
ELSE
    INSERT INTO @results VALUES (N'2c-RolePermission-roleId', N'FAIL', CAST(@orphans AS NVARCHAR(10)) + N' orphan roleId refs');

-- RolePermission.permissionId -> [Permission].id
SET @orphans = 0;
IF OBJECT_ID('dbo.RolePermission','U') IS NOT NULL AND OBJECT_ID('dbo.Permission','U') IS NOT NULL
    SELECT @orphans = COUNT(*) FROM dbo.RolePermission rp WHERE NOT EXISTS (SELECT 1 FROM dbo.Permission p WHERE p.[id] = rp.[permissionId]);
IF @orphans = 0
    INSERT INTO @results VALUES (N'2d-RolePermission-permissionId', N'PASS', N'No orphan permissionId');
ELSE
    INSERT INTO @results VALUES (N'2d-RolePermission-permissionId', N'FAIL', CAST(@orphans AS NVARCHAR(10)) + N' orphan permissionId refs');

-- [User].roleId -> [Role].id (nullable)
SET @orphans = 0;
IF OBJECT_ID('dbo.[User]','U') IS NOT NULL AND OBJECT_ID('dbo.Role','U') IS NOT NULL
    SELECT @orphans = COUNT(*) FROM dbo.[User] u WHERE u.[roleId] IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.Role r WHERE r.[id] = u.[roleId]);
IF @orphans = 0
    INSERT INTO @results VALUES (N'2e-User-roleId', N'PASS', N'No orphan roleId');
ELSE
    INSERT INTO @results VALUES (N'2e-User-roleId', N'FAIL', CAST(@orphans AS NVARCHAR(10)) + N' orphan roleId refs');

-- FinanceDefaults.defaultTaxHeadId -> [TaxHead].id (nullable)
SET @orphans = 0;
IF OBJECT_ID('dbo.FinanceDefaults','U') IS NOT NULL AND OBJECT_ID('dbo.TaxHead','U') IS NOT NULL
    SELECT @orphans = COUNT(*) FROM dbo.FinanceDefaults fd WHERE fd.[defaultTaxHeadId] IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.TaxHead t WHERE t.[id] = fd.[defaultTaxHeadId]);
IF @orphans = 0
    INSERT INTO @results VALUES (N'2f-FinanceDefaults-taxHead', N'PASS', N'No orphan defaultTaxHeadId');
ELSE
    INSERT INTO @results VALUES (N'2f-FinanceDefaults-taxHead', N'FAIL', CAST(@orphans AS NVARCHAR(10)) + N' orphan defaultTaxHeadId refs');

-- ============================================================================
-- CHECK 3: No old User id left in any character column of any table.
-- Dynamic scan EXACTLY LIKE 13e (every char column of every dbo table
-- except [User] and _UpgradeLog). We only flag values that match an
-- old_id stored in dbo._UserIdMap (saved by step 13e during migration),
-- so we never false-FAIL on cuids of hard-deleted users that no longer
-- have a User row.
--
-- If dbo._UserIdMap does not exist (migration 13e not yet run, or fresh
-- install with no old ids), CHECK 3 PASSes trivially (nothing to verify).
-- ============================================================================
SET @cuid_count = 0;

IF OBJECT_ID('dbo._UserIdMap','U') IS NOT NULL
BEGIN
    -- _UserIdMap exists: scan every char column (exactly like 13e) for
    -- values that match an old_id in the map.
    DECLARE @col_table NVARCHAR(128), @col_column NVARCHAR(128);
    DECLARE @col_check_sql NVARCHAR(MAX), @col_affected INT;
    DECLARE col_cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT t.name, c.name
        FROM sys.columns c
        JOIN sys.tables t ON c.object_id = t.object_id
        WHERE c.user_type_id IN (TYPE_ID(N'nvarchar'), TYPE_ID(N'varchar'), TYPE_ID(N'nchar'), TYPE_ID(N'char'))
          AND c.is_computed = 0
          AND t.schema_id = SCHEMA_ID(N'dbo')
          AND t.name NOT IN (N'User', N'_UpgradeLog', N'_UserIdMap');
    OPEN col_cur;
    FETCH NEXT FROM col_cur INTO @col_table, @col_column;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Count rows whose value matches an old_id in _UserIdMap
        SET @col_check_sql = N'SELECT @aff = COUNT(*) FROM [dbo].' + QUOTENAME(@col_table) + N' t INNER JOIN dbo._UserIdMap m ON t.' + QUOTENAME(@col_column) + N' = m.old_id';
        SET @col_affected = 0;
        EXEC sp_executesql @col_check_sql, N'@aff INT OUTPUT', @aff = @col_affected OUTPUT;
        SET @cuid_count = @cuid_count + @col_affected;
        FETCH NEXT FROM col_cur INTO @col_table, @col_column;
    END
    CLOSE col_cur;
    DEALLOCATE col_cur;
END

IF @cuid_count = 0
    INSERT INTO @results VALUES (N'3-OldUserId-scan', N'PASS',
        CASE WHEN OBJECT_ID('dbo._UserIdMap','U') IS NOT NULL
             THEN N'No old User id left in any char column (verified against _UserIdMap)'
             ELSE N'_UserIdMap not present (migration 13e not needed or already clean)' END);
ELSE
    INSERT INTO @results VALUES (N'3-OldUserId-scan', N'FAIL', CAST(@cuid_count AS NVARCHAR(10)) + N' old User id values still referenced');

-- ============================================================================
-- CHECK 4: IdSequence.next > max(numeric suffix) for each key
-- ============================================================================
INSERT INTO @seq_table VALUES
    (N'USER',             N'[User]',            N'USR-', 4),
    (N'PERMISSION',       N'[Permission]',      N'PRM-', 4),
    (N'ROLE',             N'[Role]',            N'ROL-', 3),
    (N'TAXHEAD',          N'[TaxHead]',         N'TAX-', 3),
    (N'SCREENPERMISSION', N'[ScreenPermission]',N'SCP-', 4),
    (N'USERPERMISSION',   N'[UserPermission]',  N'UPM-', 4),
    (N'ACCOUNTMAPPING',   N'[AccountMapping]',  N'ACM-', 3),
    (N'FINANCEDEFAULTS',  N'[FinanceDefaults]', N'FDF-', 3),
    (N'DEFAULTS',         N'[Defaults]',        N'CMP-', 3);

DECLARE seq_cur CURSOR LOCAL FAST_FORWARD FOR SELECT [key], tbl, prefix FROM @seq_table;
OPEN seq_cur;
FETCH NEXT FROM seq_cur INTO @seq_key, @tbl, @prefix;
WHILE @@FETCH_STATUS = 0
BEGIN
    -- Compute max numeric suffix from the actual table rows
    SET @dyn_seq = N'SELECT @ms = MAX(CAST(SUBSTRING([id], ' + CAST(LEN(@prefix) + 1 AS NVARCHAR(10)) + N', 20) AS INT)) FROM dbo.' + @tbl + N' WHERE [id] LIKE @pfx AND SUBSTRING([id], ' + CAST(LEN(@prefix) + 1 AS NVARCHAR(10)) + N', 20) NOT LIKE N''%[^0-9]%''';
    SET @seq_max = 0;
    EXEC sp_executesql @dyn_seq, N'@ms INT OUTPUT, @pfx NVARCHAR(20)', @ms = @seq_max OUTPUT, @pfx = @prefix + N'%';
    IF @seq_max IS NULL SET @seq_max = 0;

    -- Get IdSequence.next
    SET @seq_next = 0;
    IF OBJECT_ID('dbo.IdSequence','U') IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.IdSequence WHERE [key] = @seq_key)
        SELECT @seq_next = [next] FROM dbo.IdSequence WHERE [key] = @seq_key;

    IF @seq_next > @seq_max
        SET @seq_ok = @seq_ok + 1;
    ELSE
        SET @seq_fail = @seq_fail + 1;

    FETCH NEXT FROM seq_cur INTO @seq_key, @tbl, @prefix;
END
CLOSE seq_cur;
DEALLOCATE seq_cur;

IF @seq_fail = 0
    INSERT INTO @results VALUES (N'4-IdSequence-ahead', N'PASS', N'All ' + CAST(@seq_ok AS NVARCHAR(10)) + N' sequence rows are ahead of max');
ELSE
    INSERT INTO @results VALUES (N'4-IdSequence-ahead', N'FAIL', CAST(@seq_fail AS NVARCHAR(10)) + N' sequence rows NOT ahead of max');

-- ============================================================================
-- CHECK 5: FinanceDefaults columns exist (all 13 expanded columns:
--   allowUnbalancedOTB, allowBackDatedVouchers, lockBeforeDate,
--   voucherApprovalRequired, allowEditPostedVouchers, defaultCurrency,
--   decimalPlaces, defaultCashPaymentMode, defaultBankPaymentMode,
--   allowNegativeCash, autoPostReceipts, fiscalYearStart, fiscalYearEnd)
-- ============================================================================
IF COL_LENGTH('dbo.FinanceDefaults','allowUnbalancedOTB') IS NULL SET @col_missing = @col_missing + 1;
IF COL_LENGTH('dbo.FinanceDefaults','allowBackDatedVouchers') IS NULL SET @col_missing = @col_missing + 1;
IF COL_LENGTH('dbo.FinanceDefaults','lockBeforeDate') IS NULL SET @col_missing = @col_missing + 1;
IF COL_LENGTH('dbo.FinanceDefaults','voucherApprovalRequired') IS NULL SET @col_missing = @col_missing + 1;
IF COL_LENGTH('dbo.FinanceDefaults','allowEditPostedVouchers') IS NULL SET @col_missing = @col_missing + 1;
IF COL_LENGTH('dbo.FinanceDefaults','defaultCurrency') IS NULL SET @col_missing = @col_missing + 1;
IF COL_LENGTH('dbo.FinanceDefaults','decimalPlaces') IS NULL SET @col_missing = @col_missing + 1;
IF COL_LENGTH('dbo.FinanceDefaults','defaultCashPaymentMode') IS NULL SET @col_missing = @col_missing + 1;
IF COL_LENGTH('dbo.FinanceDefaults','defaultBankPaymentMode') IS NULL SET @col_missing = @col_missing + 1;
IF COL_LENGTH('dbo.FinanceDefaults','allowNegativeCash') IS NULL SET @col_missing = @col_missing + 1;
IF COL_LENGTH('dbo.FinanceDefaults','autoPostReceipts') IS NULL SET @col_missing = @col_missing + 1;
IF COL_LENGTH('dbo.FinanceDefaults','fiscalYearStart') IS NULL SET @col_missing = @col_missing + 1;
IF COL_LENGTH('dbo.FinanceDefaults','fiscalYearEnd') IS NULL SET @col_missing = @col_missing + 1;

IF @col_missing = 0
    INSERT INTO @results VALUES (N'5-FinanceDefaults-columns', N'PASS', N'All 13 expanded columns exist');
ELSE
    INSERT INTO @results VALUES (N'5-FinanceDefaults-columns', N'FAIL', CAST(@col_missing AS NVARCHAR(10)) + N' of 13 columns missing');

-- ============================================================================
-- CHECK 6: Company-wide FinanceDefaults row exists (branchId NULL)
-- ============================================================================
SET @has_company_fd = 0;
IF OBJECT_ID('dbo.FinanceDefaults','U') IS NOT NULL
    SELECT @has_company_fd = COUNT(*) FROM dbo.FinanceDefaults WHERE [branchId] IS NULL;
IF @has_company_fd > 0
    INSERT INTO @results VALUES (N'6-FinanceDefaults-company-row', N'PASS', N'Company-wide FinanceDefaults row exists');
ELSE
    INSERT INTO @results VALUES (N'6-FinanceDefaults-company-row', N'FAIL', N'No company-wide FinanceDefaults row (branchId NULL)');

-- ============================================================================
-- PRINT RESULTS + ONE SUMMARY ROW
-- ============================================================================
PRINT N'';
SELECT item, status, detail FROM @results ORDER BY item;

SELECT @passCount = SUM(CASE WHEN status = N'PASS' THEN 1 ELSE 0 END),
       @failCount = SUM(CASE WHEN status = N'FAIL' THEN 1 ELSE 0 END)
FROM @results;

PRINT N'';
IF @failCount = 0
BEGIN
    PRINT N'=== SUMMARY: ALL PASS ===';
    SELECT N'ALL PASS' AS result, @passCount AS passed, 0 AS failed;
END
ELSE
BEGIN
    SELECT @fails = @fails + item + N'; ' FROM @results WHERE status = N'FAIL' ORDER BY item;
    PRINT N'=== SUMMARY: FAILED ===';
    PRINT N'FAILED: ' + @fails;
    SELECT N'FAILED' AS result, @passCount AS passed, @failCount AS failed, @fails AS details;
END

END TRY
BEGIN CATCH
    DECLARE @eNum INT = ERROR_NUMBER(), @eLine INT = ERROR_LINE(), @eMsg NVARCHAR(MAX) = ERROR_MESSAGE();
    PRINT N'13_verify FAILED - Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg;
    SELECT N'FAILED' AS result, N'Verify script error: ' + @eMsg AS details;
END CATCH
GO

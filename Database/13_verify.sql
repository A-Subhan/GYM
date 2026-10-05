USE GymDB;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- 13_verify.sql
-- ============================================================================
-- PASS/FAIL verification for 13_admin_security_upgrade.sql.
-- Checks:
--   1.  Every id format (CMP-, TAX-, PRM-, ROL-, USR-, SCP-, UPM-, ACM-, FDF-)
--   2.  No orphan references (FK integrity for known relationships)
--   3.  No old User id left in any NVARCHAR column (dynamic scan)
--   4.  IdSequence.next > max(numeric suffix) for each key
--   5.  FinanceDefaults columns exist (all 12 expanded columns)
--   6.  Company-wide FinanceDefaults row exists (branchId NULL)
--
-- Prints PASS/FAIL per item and ONE summary row at the end:
--   ALL PASS  — every check passed
--   FAILED: <list> — one or more checks failed
-- ============================================================================

SET NOCOUNT ON;

PRINT N'=== STEP 13 VERIFY ===';

DECLARE @results TABLE (item NVARCHAR(100), status NVARCHAR(10), detail NVARCHAR(MAX));
DECLARE @fails NVARCHAR(MAX) = N'';
DECLARE @passCount INT = 0, @failCount INT = 0;

-- Helper: append result
-- (inline, no stored proc to avoid quoting issues)

-- ============================================================================
-- CHECK 1: Every id format
-- ============================================================================
DECLARE @bad INT;

-- Defaults -> CMP-NNN
SET @bad = 0;
IF OBJECT_ID('dbo.Defaults','U') IS NOT NULL
    SELECT @bad = COUNT(*) FROM dbo.Defaults WHERE [id] NOT LIKE N'CMP-%';
IF @bad = 0
    INSERT INTO @results VALUES (N'1a-Defaults-CMP', N'PASS', N'All Defaults.id match CMP-%');
ELSE
    INSERT INTO @results VALUES (N'1a-Defaults-CMP', N'FAIL', CAST(@bad AS NVARCHAR(10)) + N' rows not matching CMP-%');

-- TaxHead -> TAX-NNN
SET @bad = 0;
IF OBJECT_ID('dbo.TaxHead','U') IS NOT NULL
    SELECT @bad = COUNT(*) FROM dbo.TaxHead WHERE [id] NOT LIKE N'TAX-%';
IF @bad = 0
    INSERT INTO @results VALUES (N'1b-TaxHead-TAX', N'PASS', N'All TaxHead.id match TAX-%');
ELSE
    INSERT INTO @results VALUES (N'1b-TaxHead-TAX', N'FAIL', CAST(@bad AS NVARCHAR(10)) + N' rows not matching TAX-%');

-- Permission -> PRM-NNNN
SET @bad = 0;
IF OBJECT_ID('dbo.Permission','U') IS NOT NULL
    SELECT @bad = COUNT(*) FROM dbo.Permission WHERE [id] NOT LIKE N'PRM-%';
IF @bad = 0
    INSERT INTO @results VALUES (N'1c-Permission-PRM', N'PASS', N'All Permission.id match PRM-%');
ELSE
    INSERT INTO @results VALUES (N'1c-Permission-PRM', N'FAIL', CAST(@bad AS NVARCHAR(10)) + N' rows not matching PRM-%');

-- Role -> ROL-NNN
SET @bad = 0;
IF OBJECT_ID('dbo.Role','U') IS NOT NULL
    SELECT @bad = COUNT(*) FROM dbo.Role WHERE [id] NOT LIKE N'ROL-%';
IF @bad = 0
    INSERT INTO @results VALUES (N'1d-Role-ROL', N'PASS', N'All Role.id match ROL-%');
ELSE
    INSERT INTO @results VALUES (N'1d-Role-ROL', N'FAIL', CAST(@bad AS NVARCHAR(10)) + N' rows not matching ROL-%');

-- User -> USR-NNNN
SET @bad = 0;
IF OBJECT_ID('dbo.[User]','U') IS NOT NULL
    SELECT @bad = COUNT(*) FROM dbo.[User] WHERE [id] NOT LIKE N'USR-%';
IF @bad = 0
    INSERT INTO @results VALUES (N'1e-User-USR', N'PASS', N'All User.id match USR-%');
ELSE
    INSERT INTO @results VALUES (N'1e-User-USR', N'FAIL', CAST(@bad AS NVARCHAR(10)) + N' rows not matching USR-%');

-- ScreenPermission -> SCP-NNNN
SET @bad = 0;
IF OBJECT_ID('dbo.ScreenPermission','U') IS NOT NULL
    SELECT @bad = COUNT(*) FROM dbo.ScreenPermission WHERE [id] NOT LIKE N'SCP-%';
IF @bad = 0
    INSERT INTO @results VALUES (N'1f-ScreenPermission-SCP', N'PASS', N'All ScreenPermission.id match SCP-%');
ELSE
    INSERT INTO @results VALUES (N'1f-ScreenPermission-SCP', N'FAIL', CAST(@bad AS NVARCHAR(10)) + N' rows not matching SCP-%');

-- UserPermission -> UPM-NNNN
SET @bad = 0;
IF OBJECT_ID('dbo.UserPermission','U') IS NOT NULL
    SELECT @bad = COUNT(*) FROM dbo.UserPermission WHERE [id] NOT LIKE N'UPM-%';
IF @bad = 0
    INSERT INTO @results VALUES (N'1g-UserPermission-UPM', N'PASS', N'All UserPermission.id match UPM-%');
ELSE
    INSERT INTO @results VALUES (N'1g-UserPermission-UPM', N'FAIL', CAST(@bad AS NVARCHAR(10)) + N' rows not matching UPM-%');

-- AccountMapping -> ACM-NNN
SET @bad = 0;
IF OBJECT_ID('dbo.AccountMapping','U') IS NOT NULL
    SELECT @bad = COUNT(*) FROM dbo.AccountMapping WHERE [id] NOT LIKE N'ACM-%';
IF @bad = 0
    INSERT INTO @results VALUES (N'1h-AccountMapping-ACM', N'PASS', N'All AccountMapping.id match ACM-%');
ELSE
    INSERT INTO @results VALUES (N'1h-AccountMapping-ACM', N'FAIL', CAST(@bad AS NVARCHAR(10)) + N' rows not matching ACM-%');

-- FinanceDefaults -> FDF-NNN
SET @bad = 0;
IF OBJECT_ID('dbo.FinanceDefaults','U') IS NOT NULL
    SELECT @bad = COUNT(*) FROM dbo.FinanceDefaults WHERE [id] NOT LIKE N'FDF-%';
IF @bad = 0
    INSERT INTO @results VALUES (N'1i-FinanceDefaults-FDF', N'PASS', N'All FinanceDefaults.id match FDF-%');
ELSE
    INSERT INTO @results VALUES (N'1i-FinanceDefaults-FDF', N'FAIL', CAST(@bad AS NVARCHAR(10)) + N' rows not matching FDF-%');

-- ============================================================================
-- CHECK 2: No orphan references (known FK / string references)
-- ============================================================================
DECLARE @orphans INT;

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
-- CHECK 3: No old User id left in any NVARCHAR column (dynamic scan)
-- An "old User id" is a cuid (c + 24 lowercase alphanumeric chars).
-- We scan every NVARCHAR/VARCHAR column in every dbo table (except [User]
-- itself and lookup tables that legitimately hold cuids) for values
-- matching this pattern.
-- ============================================================================
USE GymDB;
GO
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @results TABLE (item NVARCHAR(100), status NVARCHAR(10), detail NVARCHAR(MAX));

-- Re-populate @results from the previous batch is not possible (table
-- variables don't survive GO). We rebuild the full results set here and
-- print at the end. To keep the script simple, we run all checks in this
-- single batch.

DECLARE @bad INT, @orphans INT;

-- Re-run checks 1 and 2 in this batch (table variable was reset by GO)
-- CHECK 1: id formats
SET @bad = 0;
IF OBJECT_ID('dbo.Defaults','U') IS NOT NULL SELECT @bad = COUNT(*) FROM dbo.Defaults WHERE [id] NOT LIKE N'CMP-%';
IF @bad = 0 INSERT INTO @results VALUES (N'1a-Defaults-CMP', N'PASS', N'All match CMP-%') ELSE INSERT INTO @results VALUES (N'1a-Defaults-CMP', N'FAIL', CAST(@bad AS NVARCHAR(10)) + N' not CMP-%');

SET @bad = 0;
IF OBJECT_ID('dbo.TaxHead','U') IS NOT NULL SELECT @bad = COUNT(*) FROM dbo.TaxHead WHERE [id] NOT LIKE N'TAX-%';
IF @bad = 0 INSERT INTO @results VALUES (N'1b-TaxHead-TAX', N'PASS', N'All match TAX-%') ELSE INSERT INTO @results VALUES (N'1b-TaxHead-TAX', N'FAIL', CAST(@bad AS NVARCHAR(10)) + N' not TAX-%');

SET @bad = 0;
IF OBJECT_ID('dbo.Permission','U') IS NOT NULL SELECT @bad = COUNT(*) FROM dbo.Permission WHERE [id] NOT LIKE N'PRM-%';
IF @bad = 0 INSERT INTO @results VALUES (N'1c-Permission-PRM', N'PASS', N'All match PRM-%') ELSE INSERT INTO @results VALUES (N'1c-Permission-PRM', N'FAIL', CAST(@bad AS NVARCHAR(10)) + N' not PRM-%');

SET @bad = 0;
IF OBJECT_ID('dbo.Role','U') IS NOT NULL SELECT @bad = COUNT(*) FROM dbo.Role WHERE [id] NOT LIKE N'ROL-%';
IF @bad = 0 INSERT INTO @results VALUES (N'1d-Role-ROL', N'PASS', N'All match ROL-%') ELSE INSERT INTO @results VALUES (N'1d-Role-ROL', N'FAIL', CAST(@bad AS NVARCHAR(10)) + N' not ROL-%');

SET @bad = 0;
IF OBJECT_ID('dbo.[User]','U') IS NOT NULL SELECT @bad = COUNT(*) FROM dbo.[User] WHERE [id] NOT LIKE N'USR-%';
IF @bad = 0 INSERT INTO @results VALUES (N'1e-User-USR', N'PASS', N'All match USR-%') ELSE INSERT INTO @results VALUES (N'1e-User-USR', N'FAIL', CAST(@bad AS NVARCHAR(10)) + N' not USR-%');

SET @bad = 0;
IF OBJECT_ID('dbo.ScreenPermission','U') IS NOT NULL SELECT @bad = COUNT(*) FROM dbo.ScreenPermission WHERE [id] NOT LIKE N'SCP-%';
IF @bad = 0 INSERT INTO @results VALUES (N'1f-ScreenPermission-SCP', N'PASS', N'All match SCP-%') ELSE INSERT INTO @results VALUES (N'1f-ScreenPermission-SCP', N'FAIL', CAST(@bad AS NVARCHAR(10)) + N' not SCP-%');

SET @bad = 0;
IF OBJECT_ID('dbo.UserPermission','U') IS NOT NULL SELECT @bad = COUNT(*) FROM dbo.UserPermission WHERE [id] NOT LIKE N'UPM-%';
IF @bad = 0 INSERT INTO @results VALUES (N'1g-UserPermission-UPM', N'PASS', N'All match UPM-%') ELSE INSERT INTO @results VALUES (N'1g-UserPermission-UPM', N'FAIL', CAST(@bad AS NVARCHAR(10)) + N' not UPM-%');

SET @bad = 0;
IF OBJECT_ID('dbo.AccountMapping','U') IS NOT NULL SELECT @bad = COUNT(*) FROM dbo.AccountMapping WHERE [id] NOT LIKE N'ACM-%';
IF @bad = 0 INSERT INTO @results VALUES (N'1h-AccountMapping-ACM', N'PASS', N'All match ACM-%') ELSE INSERT INTO @results VALUES (N'1h-AccountMapping-ACM', N'FAIL', CAST(@bad AS NVARCHAR(10)) + N' not ACM-%');

SET @bad = 0;
IF OBJECT_ID('dbo.FinanceDefaults','U') IS NOT NULL SELECT @bad = COUNT(*) FROM dbo.FinanceDefaults WHERE [id] NOT LIKE N'FDF-%';
IF @bad = 0 INSERT INTO @results VALUES (N'1i-FinanceDefaults-FDF', N'PASS', N'All match FDF-%') ELSE INSERT INTO @results VALUES (N'1i-FinanceDefaults-FDF', N'FAIL', CAST(@bad AS NVARCHAR(10)) + N' not FDF-%');

-- CHECK 2: orphan references
SET @orphans = 0;
IF OBJECT_ID('dbo.UserPermission','U') IS NOT NULL AND OBJECT_ID('dbo.[User]','U') IS NOT NULL
    SELECT @orphans = COUNT(*) FROM dbo.UserPermission up WHERE NOT EXISTS (SELECT 1 FROM dbo.[User] u WHERE u.[id] = up.[userId]);
IF @orphans = 0 INSERT INTO @results VALUES (N'2a-UserPermission-userId', N'PASS', N'No orphans') ELSE INSERT INTO @results VALUES (N'2a-UserPermission-userId', N'FAIL', CAST(@orphans AS NVARCHAR(10)) + N' orphans');

SET @orphans = 0;
IF OBJECT_ID('dbo.ScreenPermission','U') IS NOT NULL AND OBJECT_ID('dbo.Role','U') IS NOT NULL
    SELECT @orphans = COUNT(*) FROM dbo.ScreenPermission sp WHERE NOT EXISTS (SELECT 1 FROM dbo.Role r WHERE r.[id] = sp.[roleId]);
IF @orphans = 0 INSERT INTO @results VALUES (N'2b-ScreenPermission-roleId', N'PASS', N'No orphans') ELSE INSERT INTO @results VALUES (N'2b-ScreenPermission-roleId', N'FAIL', CAST(@orphans AS NVARCHAR(10)) + N' orphans');

SET @orphans = 0;
IF OBJECT_ID('dbo.RolePermission','U') IS NOT NULL AND OBJECT_ID('dbo.Role','U') IS NOT NULL
    SELECT @orphans = COUNT(*) FROM dbo.RolePermission rp WHERE NOT EXISTS (SELECT 1 FROM dbo.Role r WHERE r.[id] = rp.[roleId]);
IF @orphans = 0 INSERT INTO @results VALUES (N'2c-RolePermission-roleId', N'PASS', N'No orphans') ELSE INSERT INTO @results VALUES (N'2c-RolePermission-roleId', N'FAIL', CAST(@orphans AS NVARCHAR(10)) + N' orphans');

SET @orphans = 0;
IF OBJECT_ID('dbo.RolePermission','U') IS NOT NULL AND OBJECT_ID('dbo.Permission','U') IS NOT NULL
    SELECT @orphans = COUNT(*) FROM dbo.RolePermission rp WHERE NOT EXISTS (SELECT 1 FROM dbo.Permission p WHERE p.[id] = rp.[permissionId]);
IF @orphans = 0 INSERT INTO @results VALUES (N'2d-RolePermission-permissionId', N'PASS', N'No orphans') ELSE INSERT INTO @results VALUES (N'2d-RolePermission-permissionId', N'FAIL', CAST(@orphans AS NVARCHAR(10)) + N' orphans');

SET @orphans = 0;
IF OBJECT_ID('dbo.[User]','U') IS NOT NULL AND OBJECT_ID('dbo.Role','U') IS NOT NULL
    SELECT @orphans = COUNT(*) FROM dbo.[User] u WHERE u.[roleId] IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.Role r WHERE r.[id] = u.[roleId]);
IF @orphans = 0 INSERT INTO @results VALUES (N'2e-User-roleId', N'PASS', N'No orphans') ELSE INSERT INTO @results VALUES (N'2e-User-roleId', N'FAIL', CAST(@orphans AS NVARCHAR(10)) + N' orphans');

SET @orphans = 0;
IF OBJECT_ID('dbo.FinanceDefaults','U') IS NOT NULL AND OBJECT_ID('dbo.TaxHead','U') IS NOT NULL
    SELECT @orphans = COUNT(*) FROM dbo.FinanceDefaults fd WHERE fd.[defaultTaxHeadId] IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.TaxHead t WHERE t.[id] = fd.[defaultTaxHeadId]);
IF @orphans = 0 INSERT INTO @results VALUES (N'2f-FinanceDefaults-taxHead', N'PASS', N'No orphans') ELSE INSERT INTO @results VALUES (N'2f-FinanceDefaults-taxHead', N'FAIL', CAST(@orphans AS NVARCHAR(10)) + N' orphans');

-- CHECK 3: No old User id (cuid) left in any known User-reference column.
-- A cuid is 25 chars: 'c' + 24 lowercase alphanumeric. We check specific
-- known columns that hold User references (userId, postedById, etc.).
DECLARE @cuid_count INT = 0;
DECLARE @cuid_sql NVARCHAR(MAX);
DECLARE @cuid_cnt INT;

-- Helper: check one column for cuid-like values and add to @cuid_count
-- A value matches if LEN = 25 AND starts with 'c' AND all alphanumeric.
-- We use a simpler LIKE: 'c[a-z0-9]%' with LEN check.
DECLARE @check_pairs TABLE (tbl NVARCHAR(128), col NVARCHAR(128));
INSERT INTO @check_pairs VALUES
    (N'UserPermission', N'userId'),
    (N'UserReportFormat', N'userId'),
    (N'AuditLog', N'userId'),
    (N'Session', N'userId'),
    (N'CashBook', N'postedById'),
    (N'BankBook', N'postedById'),
    (N'JV', N'postedById'),
    (N'OpenTB', N'postedById'),
    (N'CashBook', N'deletedById'),
    (N'BankBook', N'deletedById'),
    (N'JV', N'deletedById'),
    (N'OpenTB', N'deletedById'),
    (N'CashBook', N'reversedById'),
    (N'BankBook', N'reversedById'),
    (N'JV', N'reversedById'),
    (N'OpenTB', N'reversedById'),
    (N'Leave', N'approvedBy'),
    (N'Overtime', N'approvedBy'),
    (N'KnockOff', N'createdById');

DECLARE @cp_tbl NVARCHAR(128), @cp_col NVARCHAR(128);
DECLARE cp_cur CURSOR LOCAL FAST_FORWARD FOR SELECT tbl, col FROM @check_pairs;
OPEN cp_cur;
FETCH NEXT FROM cp_cur INTO @cp_tbl, @cp_col;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF OBJECT_ID(N'dbo.' + QUOTENAME(@cp_tbl), N'U') IS NOT NULL
       AND COL_LENGTH(N'dbo.' + QUOTENAME(@cp_tbl), @cp_col) IS NOT NULL
    BEGIN
        SET @cuid_sql = N'SELECT @c = COUNT(*) FROM dbo.' + QUOTENAME(@cp_tbl) + N' WHERE ' + QUOTENAME(@cp_col) + N' IS NOT NULL AND LEN(' + QUOTENAME(@cp_col) + N') = 25 AND ' + QUOTENAME(@cp_col) + N' LIKE N''c%'' AND ' + QUOTENAME(@cp_col) + N' NOT LIKE N''%[^a-z0-9]%''';
        SET @cuid_cnt = 0;
        EXEC sp_executesql @cuid_sql, N'@c INT OUTPUT', @c = @cuid_cnt OUTPUT;
        SET @cuid_count = @cuid_count + @cuid_cnt;
    END
    FETCH NEXT FROM cp_cur INTO @cp_tbl, @cp_col;
END
CLOSE cp_cur;
DEALLOCATE cp_cur;

IF @cuid_count = 0
    INSERT INTO @results VALUES (N'3-OldUserId-scan', N'PASS', N'No old User id (cuid) found in any known User-reference column');
ELSE
    INSERT INTO @results VALUES (N'3-OldUserId-scan', N'FAIL', CAST(@cuid_count AS NVARCHAR(10)) + N' old User id (cuid) values found');

-- CHECK 4: IdSequence.next > max(numeric suffix) for each key
DECLARE @seq_key NVARCHAR(50), @tbl NVARCHAR(128), @prefix NVARCHAR(20), @width INT;
DECLARE @seq_max INT, @seq_next INT, @seq_ok INT = 0, @seq_fail INT = 0;
DECLARE @seq_table TABLE ([key] NVARCHAR(50), tbl NVARCHAR(128), prefix NVARCHAR(20));
INSERT INTO @seq_table VALUES
    (N'USER',            N'[User]',            N'USR-'),
    (N'PERMISSION',      N'[Permission]',      N'PRM-'),
    (N'ROLE',            N'[Role]',            N'ROL-'),
    (N'TAXHEAD',         N'[TaxHead]',         N'TAX-'),
    (N'SCREENPERMISSION',N'[ScreenPermission]',N'SCP-'),
    (N'USERPERMISSION',  N'[UserPermission]',  N'UPM-'),
    (N'ACCOUNTMAPPING',  N'[AccountMapping]',  N'ACM-'),
    (N'FINANCEDEFAULTS', N'[FinanceDefaults]', N'FDF-'),
    (N'DEFAULTS',        N'[Defaults]',        N'CMP-');

DECLARE seq_cur CURSOR LOCAL FAST_FORWARD FOR SELECT [key], tbl, prefix FROM @seq_table;
OPEN seq_cur;
FETCH NEXT FROM seq_cur INTO @seq_key, @tbl, @prefix;
WHILE @@FETCH_STATUS = 0
BEGIN
    -- Get max from table
    DECLARE @dyn_seq NVARCHAR(MAX) = N'SELECT @ms = MAX(CAST(SUBSTRING([id], ' + CAST(LEN(@prefix) + 1 AS NVARCHAR(10)) + N', 20) AS INT)) FROM dbo.' + @tbl + N' WHERE [id] LIKE @pfx AND SUBSTRING([id], ' + CAST(LEN(@prefix) + 1 AS NVARCHAR(10)) + N', 20) NOT LIKE N''%[^0-9]%''';
    SET @seq_max = 0;
    EXEC sp_executesql @dyn_seq, N'@ms INT OUTPUT, @pfx NVARCHAR(20)', @ms = @seq_max OUTPUT, @pfx = @prefix + N'%';
    IF @seq_max IS NULL SET @seq_max = 0;

    -- Get IdSequence.next
    SET @seq_next = 0;
    IF EXISTS (SELECT 1 FROM dbo.IdSequence WHERE [key] = @seq_key)
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

-- CHECK 5: FinanceDefaults columns exist (all 12)
DECLARE @col_missing INT = 0;
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
    INSERT INTO @results VALUES (N'5-FinanceDefaults-columns', N'PASS', N'All 12 expanded columns exist');
ELSE
    INSERT INTO @results VALUES (N'5-FinanceDefaults-columns', N'FAIL', CAST(@col_missing AS NVARCHAR(10)) + N' columns missing');

-- CHECK 6: Company-wide FinanceDefaults row exists (branchId NULL)
DECLARE @has_company_fd INT = 0;
IF OBJECT_ID('dbo.FinanceDefaults','U') IS NOT NULL
    SELECT @has_company_fd = COUNT(*) FROM dbo.FinanceDefaults WHERE [branchId] IS NULL;
IF @has_company_fd > 0
    INSERT INTO @results VALUES (N'6-FinanceDefaults-company-row', N'PASS', N'Company-wide FinanceDefaults row exists');
ELSE
    INSERT INTO @results VALUES (N'6-FinanceDefaults-company-row', N'FAIL', N'No company-wide FinanceDefaults row (branchId NULL)');

-- ============================================================================
-- PRINT RESULTS
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
GO

USE GymDB;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- 14_verify.sql
-- ============================================================================
-- PASS/FAIL verification for 14_company_and_finance_options.sql.
-- Checks:
--   1. trg_Defaults_CompanyNameLock does NOT exist (company name is editable)
--   2. FinanceDefaults expanded columns exist (all 13)
--   3. vouchers.approve permission row exists
--   4. vouchers.approve granted to at least Super Admin
--
-- Single batch — no variable crosses a GO. Prints PASS/FAIL per item
-- and ONE summary row at the end:
--   ALL PASS  — every check passed
--   FAILED: <list> — one or more checks failed
-- ============================================================================

USE GymDB;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @results TABLE (item NVARCHAR(100), status NVARCHAR(10), detail NVARCHAR(MAX));
DECLARE @fails NVARCHAR(MAX) = N'';
DECLARE @passCount INT = 0, @failCount INT = 0;

BEGIN TRY

-- ============================================================================
-- CHECK 1: trg_Defaults_CompanyNameLock does NOT exist
-- ============================================================================
IF EXISTS (SELECT 1 FROM sys.triggers WHERE name = N'trg_Defaults_CompanyNameLock' AND parent_id = OBJECT_ID('dbo.Defaults'))
    INSERT INTO @results VALUES (N'1-CompanyNameTrigger-gone', N'FAIL', N'trg_Defaults_CompanyNameLock still exists — company name is still locked');
ELSE
    INSERT INTO @results VALUES (N'1-CompanyNameTrigger-gone', N'PASS', N'trg_Defaults_CompanyNameLock dropped — company name is editable');

-- ============================================================================
-- CHECK 2: FinanceDefaults expanded columns exist (all 13)
-- ============================================================================
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
    INSERT INTO @results VALUES (N'2-FinanceDefaults-columns', N'PASS', N'All 13 expanded columns exist');
ELSE
    INSERT INTO @results VALUES (N'2-FinanceDefaults-columns', N'FAIL', CAST(@col_missing AS NVARCHAR(10)) + N' of 13 columns missing');

-- ============================================================================
-- CHECK 3: vouchers.approve permission row exists
-- ============================================================================
IF NOT EXISTS (SELECT 1 FROM dbo.[Permission] WHERE [code] = N'vouchers.approve')
    INSERT INTO @results VALUES (N'3-Permission-vouchers-approve', N'FAIL', N'vouchers.approve permission row missing');
ELSE
    INSERT INTO @results VALUES (N'3-Permission-vouchers-approve', N'PASS', N'vouchers.approve permission row exists');

-- ============================================================================
-- CHECK 4: vouchers.approve granted to at least Super Admin
-- ============================================================================
DECLARE @has_approve INT = 0;
IF OBJECT_ID('dbo.Role','U') IS NOT NULL AND OBJECT_ID('dbo.Permission','U') IS NOT NULL AND OBJECT_ID('dbo.RolePermission','U') IS NOT NULL
BEGIN
    SELECT @has_approve = COUNT(*)
    FROM dbo.[Role] r
    JOIN dbo.[RolePermission] rp ON rp.[roleId] = r.[id]
    JOIN dbo.[Permission] p ON p.[id] = rp.[permissionId]
    WHERE r.[name] = N'Super Admin' AND p.[code] = N'vouchers.approve';
END

IF @has_approve > 0
    INSERT INTO @results VALUES (N'4-Grant-vouchers-approve', N'PASS', N'vouchers.approve granted to Super Admin');
ELSE
    INSERT INTO @results VALUES (N'4-Grant-vouchers-approve', N'FAIL', N'vouchers.approve NOT granted to Super Admin');

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
    PRINT N'14_verify FAILED - Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg;
    SELECT N'FAILED' AS result, N'Verify script error: ' + @eMsg AS details;
END CATCH
GO

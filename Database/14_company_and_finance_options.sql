USE GymDB;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- 14_company_and_finance_options.sql
-- ============================================================================
-- Database changes for the company & finance options task.
--
-- The only schema-level change is dropping the trg_Defaults_CompanyNameLock
-- trigger so the company name can be changed via direct SQL or the API.
-- The expanded FinanceDefaults columns (allowBackDatedVouchers,
-- lockBeforeDate, voucherApprovalRequired, etc.) already exist from
-- 13_admin_security_upgrade.sql / 02_schema_tables.sql — no new columns.
--
-- Idempotent. Each step in TRY/CATCH: capture error, then
-- IF XACT_STATE() <> 0 ROLLBACK, then log. No variable or #temp crosses
-- a GO. No column used in the same batch that creates it.
-- ============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

PRINT N'=== STEP 14: Company & Finance Options ===';

-- ============================================================================
-- STEP 14a: Drop trg_Defaults_CompanyNameLock
-- ============================================================================
USE GymDB;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);

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
END
GO

USE GymDB;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);

BEGIN TRY
    IF EXISTS (SELECT 1 FROM sys.triggers WHERE name = N'trg_Defaults_CompanyNameLock' AND parent_id = OBJECT_ID('dbo.Defaults'))
    BEGIN
        DROP TRIGGER dbo.trg_Defaults_CompanyNameLock;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'14a-DropCompanyNameTrigger', N'OK', N'Dropped trg_Defaults_CompanyNameLock — company name is now editable');
        PRINT N'  14a-DropCompanyNameTrigger: OK';
    END
    ELSE
    BEGIN
        BEGIN TRY
            INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'14a-DropCompanyNameTrigger', N'SKIPPED', N'Trigger not found — already dropped');
            PRINT N'  14a-DropCompanyNameTrigger: SKIPPED';
        END TRY
        BEGIN CATCH
            PRINT N'  14a-DropCompanyNameTrigger: SKIPPED (log failed)';
        END CATCH
    END
END TRY
BEGIN CATCH
    SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
    IF XACT_STATE() <> 0 ROLLBACK TRAN;
    BEGIN TRY
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'14a-DropCompanyNameTrigger', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
    END TRY
    BEGIN CATCH
        PRINT N'  14a-DropCompanyNameTrigger: FAILED (log also failed)';
    END CATCH
    PRINT N'  14a-DropCompanyNameTrigger: FAILED - ' + @eMsg;
END CATCH
GO

-- ============================================================================
-- STEP 14b: Ensure FinanceDefaults expanded columns exist
-- (already present from 02 or 13; this is a safety net for DBs that ran
--  an older 02 before the columns were added. Idempotent — ALTER ADD
--  only when the column is missing.)
-- ============================================================================
USE GymDB;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);

IF OBJECT_ID('dbo.FinanceDefaults','U') IS NOT NULL
BEGIN
    BEGIN TRY
        BEGIN TRAN;

        IF COL_LENGTH('dbo.FinanceDefaults','allowUnbalancedOTB') IS NULL
            ALTER TABLE dbo.FinanceDefaults ADD [allowUnbalancedOTB] BIT NOT NULL CONSTRAINT [FinanceDefaults_allowUnbalancedOTB_df] DEFAULT 1;
        IF COL_LENGTH('dbo.FinanceDefaults','allowBackDatedVouchers') IS NULL
            ALTER TABLE dbo.FinanceDefaults ADD [allowBackDatedVouchers] BIT NOT NULL CONSTRAINT [FinanceDefaults_allowBackDatedVouchers_df] DEFAULT 1;
        IF COL_LENGTH('dbo.FinanceDefaults','lockBeforeDate') IS NULL
            ALTER TABLE dbo.FinanceDefaults ADD [lockBeforeDate] DATETIME2;
        IF COL_LENGTH('dbo.FinanceDefaults','voucherApprovalRequired') IS NULL
            ALTER TABLE dbo.FinanceDefaults ADD [voucherApprovalRequired] BIT NOT NULL CONSTRAINT [FinanceDefaults_voucherApprovalRequired_df] DEFAULT 0;
        IF COL_LENGTH('dbo.FinanceDefaults','allowEditPostedVouchers') IS NULL
            ALTER TABLE dbo.FinanceDefaults ADD [allowEditPostedVouchers] BIT NOT NULL CONSTRAINT [FinanceDefaults_allowEditPostedVouchers_df] DEFAULT 1;
        IF COL_LENGTH('dbo.FinanceDefaults','defaultCurrency') IS NULL
            ALTER TABLE dbo.FinanceDefaults ADD [defaultCurrency] NVARCHAR(50);
        IF COL_LENGTH('dbo.FinanceDefaults','decimalPlaces') IS NULL
            ALTER TABLE dbo.FinanceDefaults ADD [decimalPlaces] INT NOT NULL CONSTRAINT [FinanceDefaults_decimalPlaces_df] DEFAULT 2;
        IF COL_LENGTH('dbo.FinanceDefaults','defaultCashPaymentMode') IS NULL
            ALTER TABLE dbo.FinanceDefaults ADD [defaultCashPaymentMode] NVARCHAR(50);
        IF COL_LENGTH('dbo.FinanceDefaults','defaultBankPaymentMode') IS NULL
            ALTER TABLE dbo.FinanceDefaults ADD [defaultBankPaymentMode] NVARCHAR(50);
        IF COL_LENGTH('dbo.FinanceDefaults','allowNegativeCash') IS NULL
            ALTER TABLE dbo.FinanceDefaults ADD [allowNegativeCash] BIT NOT NULL CONSTRAINT [FinanceDefaults_allowNegativeCash_df] DEFAULT 0;
        IF COL_LENGTH('dbo.FinanceDefaults','autoPostReceipts') IS NULL
            ALTER TABLE dbo.FinanceDefaults ADD [autoPostReceipts] BIT NOT NULL CONSTRAINT [FinanceDefaults_autoPostReceipts_df] DEFAULT 1;
        IF COL_LENGTH('dbo.FinanceDefaults','fiscalYearStart') IS NULL
            ALTER TABLE dbo.FinanceDefaults ADD [fiscalYearStart] DATETIME2;
        IF COL_LENGTH('dbo.FinanceDefaults','fiscalYearEnd') IS NULL
            ALTER TABLE dbo.FinanceDefaults ADD [fiscalYearEnd] DATETIME2;

        COMMIT TRAN;
        BEGIN TRY
            INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'14b-FinanceDefaults-columns', N'OK', N'All expanded FinanceDefaults columns present');
        END TRY
        BEGIN CATCH
            PRINT N'  14b-FinanceDefaults-columns: OK (log failed)';
        END CATCH
        PRINT N'  14b-FinanceDefaults-columns: OK';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        BEGIN TRY
            INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'14b-FinanceDefaults-columns', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        END TRY
        BEGIN CATCH
            PRINT N'  14b-FinanceDefaults-columns: FAILED (log also failed)';
        END CATCH
        PRINT N'  14b-FinanceDefaults-columns: FAILED - ' + @eMsg;
    END CATCH
END
ELSE
BEGIN
    BEGIN TRY
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'14b-FinanceDefaults-columns', N'SKIPPED', N'FinanceDefaults table not found');
        PRINT N'  14b-FinanceDefaults-columns: SKIPPED';
    END TRY
    BEGIN CATCH
        PRINT N'  14b-FinanceDefaults-columns: SKIPPED (log failed)';
    END CATCH
END
GO

-- ============================================================================
-- STEP 14c: Add vouchers.approve permission row if missing
-- (The permission code is added to the app's PERMISSIONS array; this
--  step ensures the dbo.Permission row exists with the next free PRM-
--  id so RolePermission grants can reference it.)
-- ============================================================================
USE GymDB;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);

IF OBJECT_ID('dbo.Permission','U') IS NOT NULL
BEGIN
    BEGIN TRY
        BEGIN TRAN;

        IF NOT EXISTS (SELECT 1 FROM dbo.[Permission] WHERE [code] = N'vouchers.approve')
        BEGIN
            DECLARE @prm_max INT = 0;
            SELECT @prm_max = MAX(CAST(SUBSTRING([id], 5, 20) AS INT))
            FROM dbo.[Permission]
            WHERE [id] LIKE N'PRM-%' AND SUBSTRING([id], 5, 20) NOT LIKE N'%[^0-9]%';
            IF @prm_max IS NULL SET @prm_max = 0;

            DECLARE @new_prm_id NVARCHAR(50) = N'PRM-' + RIGHT(N'000' + CAST(@prm_max + 1 AS NVARCHAR(10)), 4);
            INSERT INTO dbo.[Permission] ([id], [module], [action], [code], [description])
            VALUES (@new_prm_id, N'vouchers', N'approve', N'vouchers.approve', N'Approve pending vouchers');
        END

        COMMIT TRAN;
        BEGIN TRY
            INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'14c-Permission-vouchers-approve', N'OK', N'vouchers.approve permission row ensured');
        END TRY
        BEGIN CATCH
            PRINT N'  14c-Permission-vouchers-approve: OK (log failed)';
        END CATCH
        PRINT N'  14c-Permission-vouchers-approve: OK';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        BEGIN TRY
            INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'14c-Permission-vouchers-approve', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        END TRY
        BEGIN CATCH
            PRINT N'  14c-Permission-vouchers-approve: FAILED (log also failed)';
        END CATCH
        PRINT N'  14c-Permission-vouchers-approve: FAILED - ' + @eMsg;
    END CATCH
END
ELSE
BEGIN
    BEGIN TRY
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'14c-Permission-vouchers-approve', N'SKIPPED', N'Permission table not found');
        PRINT N'  14c-Permission-vouchers-approve: SKIPPED';
    END TRY
    BEGIN CATCH
        PRINT N'  14c-Permission-vouchers-approve: SKIPPED (log failed)';
    END CATCH
END
GO

-- ============================================================================
-- STEP 14d: Grant vouchers.approve to Super Admin and Accountant roles
-- (looked up by name so this works on fresh installs and live DBs)
-- ============================================================================
USE GymDB;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);

IF OBJECT_ID('dbo.Role','U') IS NOT NULL AND OBJECT_ID('dbo.Permission','U') IS NOT NULL AND OBJECT_ID('dbo.RolePermission','U') IS NOT NULL
BEGIN
    BEGIN TRY
        BEGIN TRAN;

        DECLARE @approve_perm_id NVARCHAR(50);
        SELECT @approve_perm_id = [id] FROM dbo.[Permission] WHERE [code] = N'vouchers.approve';

        IF @approve_perm_id IS NOT NULL
        BEGIN
            -- Grant to each role by name (idempotent)
            DECLARE @role_name NVARCHAR(191), @role_id NVARCHAR(50);
            DECLARE role_cur CURSOR LOCAL FAST_FORWARD FOR
                SELECT [name], [id] FROM dbo.[Role] WHERE [name] IN (N'Super Admin', N'Owner', N'Manager', N'Accountant');
            OPEN role_cur;
            FETCH NEXT FROM role_cur INTO @role_name, @role_id;
            WHILE @@FETCH_STATUS = 0
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM dbo.[RolePermission] WHERE [roleId] = @role_id AND [permissionId] = @approve_perm_id)
                    INSERT INTO dbo.[RolePermission] ([roleId], [permissionId]) VALUES (@role_id, @approve_perm_id);
                FETCH NEXT FROM role_cur INTO @role_name, @role_id;
            END
            CLOSE role_cur;
            DEALLOCATE role_cur;
        END

        COMMIT TRAN;
        BEGIN TRY
            INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'14d-Grant-vouchers-approve', N'OK', N'vouchers.approve granted to Super Admin/Owner/Manager/Accountant');
        END TRY
        BEGIN CATCH
            PRINT N'  14d-Grant-vouchers-approve: OK (log failed)';
        END CATCH
        PRINT N'  14d-Grant-vouchers-approve: OK';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        BEGIN TRY
            INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'14d-Grant-vouchers-approve', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        END TRY
        BEGIN CATCH
            PRINT N'  14d-Grant-vouchers-approve: FAILED (log also failed)';
        END CATCH
        PRINT N'  14d-Grant-vouchers-approve: FAILED - ' + @eMsg;
    END CATCH
END
ELSE
BEGIN
    BEGIN TRY
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'14d-Grant-vouchers-approve', N'SKIPPED', N'Required tables not found');
        PRINT N'  14d-Grant-vouchers-approve: SKIPPED';
    END TRY
    BEGIN CATCH
        PRINT N'  14d-Grant-vouchers-approve: SKIPPED (log failed)';
    END CATCH
END
GO

-- ============================================================================
-- FINAL SUMMARY
-- ============================================================================
USE GymDB;
GO
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);

BEGIN TRY
    PRINT N'';
    PRINT N'=== STEP 14 SUMMARY ===';

    DECLARE @expected14 TABLE (step NVARCHAR(100) NOT NULL);
    INSERT INTO @expected14 (step) VALUES
        (N'14a-DropCompanyNameTrigger'),
        (N'14b-FinanceDefaults-columns'),
        (N'14c-Permission-vouchers-approve'),
        (N'14d-Grant-vouchers-approve');

    DECLARE @missing14 INT = 0, @failed14 INT = 0;
    SELECT @missing14 = COUNT(*) FROM @expected14 e WHERE NOT EXISTS (SELECT 1 FROM dbo._UpgradeLog l WHERE l.step = e.step);
    SELECT @failed14 = COUNT(*) FROM dbo._UpgradeLog l WHERE l.step LIKE N'14%' AND l.status = N'FAILED';

    IF @missing14 = 0 AND @failed14 = 0
    BEGIN
        PRINT N'SUCCESS';
        SELECT N'SUCCESS' AS result, COUNT(*) AS steps, SUM(CASE WHEN status=N'OK' THEN 1 ELSE 0 END) AS ok, SUM(CASE WHEN status=N'SKIPPED' THEN 1 ELSE 0 END) AS skipped, 0 AS failed
        FROM dbo._UpgradeLog WHERE step LIKE N'14%';
    END
    ELSE
    BEGIN
        DECLARE @failList14 NVARCHAR(MAX) = N'';
        SELECT @failList14 = @failList14 + step + N'; ' FROM dbo._UpgradeLog WHERE step LIKE N'14%' AND status = N'FAILED' ORDER BY step;
        SELECT @failList14 = @failList14 + N'MISSING: ' + step + N'; ' FROM @expected14 e WHERE NOT EXISTS (SELECT 1 FROM dbo._UpgradeLog l WHERE l.step = e.step) ORDER BY e.step;
        PRINT N'FAILED - ' + @failList14;
        SELECT N'FAILED' AS result, @failList14 AS details;
    END
END TRY
BEGIN CATCH
    SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
    PRINT N'  STEP 14 SUMMARY: FAILED - ' + @eMsg;
    SELECT N'FAILED' AS result, N'Summary read error: ' + @eMsg AS details;
END CATCH
GO

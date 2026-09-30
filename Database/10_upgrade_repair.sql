-- ============================================================================
-- Contoura Gym Management System — STEP 10: UPGRADE REPAIR
-- ============================================================================
-- Safe, idempotent repair script that brings a PARTIAL database to the final
-- target state defined by 02_schema_tables.sql.
--
-- WHEN TO RUN:
--   * On a database where 08_upgrade_2026_09.sql FAILED partway through
--     (e.g. Msg 207 userType, Msg 208 gymmaster).
--   * On a database where 09_upgrade_finance_hr.sql FAILED partway through
--     (e.g. Msg 102 QUOTENAME errors in Staff/Shift/CalendarDay steps).
--   * On an UNTOUCHED database built from older 02-06 scripts.
--   * On a FRESH database built from the current 02-06 (this script detects
--     everything is already in place and skips every step).
--
-- SAFETY:
--   * Every step checks IF EXISTS / IF COL_LENGTH and skips if already done.
--   * Every step is wrapped in TRY/CATCH with SET XACT_ABORT ON.
--   * Every step logs to dbo._UpgradeLog(step, status, message, at).
--   * Legacy tables are RENAMED to *_legacy_bak, never DROPPED.
--   * No data is deleted before counts are verified.
--   * Dynamic SQL uses sp_executesql (not inline EXEC('...'+...) which
--     caused Msg 102 QUOTENAME errors in the old 09 script).
--
-- FINAL OUTPUT:
--   "SUCCESS" — if zero step failures.
--   "FAILED: <step names>" — if one or more steps failed.
--
-- KNOWN PARTIAL-STATE SCENARIOS HANDLED:
--   * 08 failed at userType (Msg 207): column added+used in same batch.
--   * 08 failed at gymmaster (Msg 208): table never created.
--   * 09 failed at QUOTENAME (Msg 102): Staff merge, Shift renumber,
--     CalendarDay renumber all skipped.
--   * 09 steps 1-2 already ran: voucher soft-delete + line ids present.
-- ============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

-- ============================================================================
-- PREFLIGHT: create the log table (always needed, even if everything else
-- is already done, so we can record "already up to date" status).
-- ============================================================================
IF OBJECT_ID(N'dbo._UpgradeLog', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo]._UpgradeLog (
        [step]     NVARCHAR(100) NOT NULL,
        [status]   NVARCHAR(20)  NOT NULL,  -- 'OK' | 'SKIPPED' | 'FAILED'
        [message]  NVARCHAR(MAX),
        [at]       DATETIME2     NOT NULL CONSTRAINT [_UpgradeLog_at_df] DEFAULT CURRENT_TIMESTAMP
    );
END
GO

-- ============================================================================
-- PREFLIGHT REPORT: print the detected state of every object this script
-- touches. This runs BEFORE any changes are made.
-- ============================================================================
DECLARE @pf NVARCHAR(MAX) = N'';

-- User.userType
SET @pf = @pf + N'[User].userType: '
    + CASE WHEN COL_LENGTH('dbo.[User]','userType') IS NOT NULL THEN 'EXISTS' ELSE 'MISSING' END + NCHAR(13);
-- User.roleId nullability
SET @pf = @pf + N'[User].roleId nullable: '
    + CASE WHEN EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.[User]') AND name='roleId' AND is_nullable=1) THEN 'YES' ELSE 'NO' END + NCHAR(13);
-- ScreenPermission
SET @pf = @pf + N'ScreenPermission: '
    + CASE WHEN OBJECT_ID('dbo.ScreenPermission','U') IS NOT NULL THEN 'EXISTS' ELSE 'MISSING' END + NCHAR(13);
-- UserPermission
SET @pf = @pf + N'UserPermission: '
    + CASE WHEN OBJECT_ID('dbo.UserPermission','U') IS NOT NULL THEN 'EXISTS' ELSE 'MISSING' END + NCHAR(13);
-- Member.joiningFee
SET @pf = @pf + N'Member.joiningFee: '
    + CASE WHEN COL_LENGTH('dbo.Member','joiningFee') IS NOT NULL THEN 'EXISTS' ELSE 'MISSING' END + NCHAR(13);
-- 6 master tables
SET @pf = @pf + N'gymmaster: '
    + CASE WHEN OBJECT_ID('dbo.gymmaster','U') IS NOT NULL THEN 'EXISTS' ELSE 'MISSING' END + NCHAR(13);
SET @pf = @pf + N'gymmasterdetail: '
    + CASE WHEN OBJECT_ID('dbo.gymmasterdetail','U') IS NOT NULL THEN 'EXISTS' ELSE 'MISSING' END + NCHAR(13);
SET @pf = @pf + N'financemaster: '
    + CASE WHEN OBJECT_ID('dbo.financemaster','U') IS NOT NULL THEN 'EXISTS' ELSE 'MISSING' END + NCHAR(13);
SET @pf = @pf + N'financemasterdetail: '
    + CASE WHEN OBJECT_ID('dbo.financemasterdetail','U') IS NOT NULL THEN 'EXISTS' ELSE 'MISSING' END + NCHAR(13);
SET @pf = @pf + N'payrollmaster: '
    + CASE WHEN OBJECT_ID('dbo.payrollmaster','U') IS NOT NULL THEN 'EXISTS' ELSE 'MISSING' END + NCHAR(13);
SET @pf = @pf + N'payrollmasterdetail: '
    + CASE WHEN OBJECT_ID('dbo.payrollmasterdetail','U') IS NOT NULL THEN 'EXISTS' ELSE 'MISSING' END + NCHAR(13);
-- Exercise table (legacy, should be gone after migration)
SET @pf = @pf + N'Exercise (legacy): '
    + CASE WHEN OBJECT_ID('dbo.Exercise','U') IS NOT NULL THEN 'EXISTS' ELSE 'MISSING/GONE' END + NCHAR(13);
-- Staff.employeeId (legacy, should be gone after merge)
SET @pf = @pf + N'Staff.employeeId (legacy): '
    + CASE WHEN COL_LENGTH('dbo.Staff','employeeId') IS NOT NULL THEN 'EXISTS' ELSE 'MISSING/GONE' END + NCHAR(13);
-- Staff.isDeleted
SET @pf = @pf + N'Staff.isDeleted: '
    + CASE WHEN COL_LENGTH('dbo.Staff','isDeleted') IS NOT NULL THEN 'EXISTS' ELSE 'MISSING' END + NCHAR(13);
-- Voucher soft-delete
SET @pf = @pf + N'CashBook.isDeleted: '
    + CASE WHEN COL_LENGTH('dbo.CashBook','isDeleted') IS NOT NULL THEN 'EXISTS' ELSE 'MISSING' END + NCHAR(13);
-- Shift id format (cuid vs 3-digit)
DECLARE @shiftCuid INT = 0;
SELECT @shiftCuid = COUNT(*) FROM dbo.Shift WHERE id NOT LIKE '[0-9][0-9][0-9]';
SET @pf = @pf + N'Shift ids (non-3-digit rows): ' + CAST(@shiftCuid AS NVARCHAR(10)) + NCHAR(13);
-- CalendarDay id format
DECLARE @calCuid INT = 0;
IF OBJECT_ID('dbo.CalendarDay','U') IS NOT NULL
    SELECT @calCuid = COUNT(*) FROM dbo.CalendarDay WHERE id NOT LIKE '[0-9][0-9][0-9]';
SET @pf = @pf + N'CalendarDay ids (non-3-digit rows): ' + CAST(@calCuid AS NVARCHAR(10)) + NCHAR(13);
-- Branch.nodeType
SET @pf = @pf + N'Branch.nodeType: '
    + CASE WHEN COL_LENGTH('dbo.Branch','nodeType') IS NOT NULL THEN 'EXISTS' ELSE 'MISSING' END + NCHAR(13);
-- Gym operation tables
SET @pf = @pf + N'TrainerAvailability: '
    + CASE WHEN OBJECT_ID('dbo.TrainerAvailability','U') IS NOT NULL THEN 'EXISTS' ELSE 'MISSING' END + NCHAR(13);
SET @pf = @pf + N'TrainerSchedule: '
    + CASE WHEN OBJECT_ID('dbo.TrainerSchedule','U') IS NOT NULL THEN 'EXISTS' ELSE 'MISSING' END + NCHAR(13);
SET @pf = @pf + N'FitnessGoal: '
    + CASE WHEN OBJECT_ID('dbo.FitnessGoal','U') IS NOT NULL THEN 'EXISTS' ELSE 'MISSING' END + NCHAR(13);
SET @pf = @pf + N'PersonalTrainingSession: '
    + CASE WHEN OBJECT_ID('dbo.PersonalTrainingSession','U') IS NOT NULL THEN 'EXISTS' ELSE 'MISSING' END + NCHAR(13);
SET @pf = @pf + N'StaffDocument: '
    + CASE WHEN OBJECT_ID('dbo.StaffDocument','U') IS NOT NULL THEN 'EXISTS' ELSE 'MISSING' END + NCHAR(13);
SET @pf = @pf + N'KnockOff: '
    + CASE WHEN OBJECT_ID('dbo.KnockOff','U') IS NOT NULL THEN 'EXISTS' ELSE 'MISSING' END + NCHAR(13);

PRINT N'=== PREFLIGHT STATE ===';
PRINT @pf;
PRINT N'=== END PREFLIGHT ===';
GO

-- ============================================================================
-- Helper: log a step result
-- ============================================================================
IF OBJECT_ID(N'dbo._LogStep', N'P') IS NULL
BEGIN
    EXEC sp_executesql N'CREATE PROCEDURE dbo._LogStep
        @step NVARCHAR(100),
        @status NVARCHAR(20),
        @message NVARCHAR(MAX) = NULL
    AS
    BEGIN
        SET NOCOUNT ON;
        INSERT INTO dbo._UpgradeLog (step, status, message, at)
        VALUES (@step, @status, @message, CURRENT_TIMESTAMP);
        PRINT N'[' + @step + N'] ' + @status + N': ' + COALESCE(@message, N'');
    END';
END
GO

-- ============================================================================
-- STEP 1: User.userType + nullable roleId
-- ============================================================================
-- Fixes 08 Msg 207 (column added+used in same batch).
-- Uses GO between ALTER ADD and the UPDATE that references the new column.
-- ============================================================================

-- 1a. Add userType if missing
IF COL_LENGTH('dbo.[User]', 'userType') IS NULL
BEGIN
    BEGIN TRY
        BEGIN TRAN;
        ALTER TABLE dbo.[User] ADD [userType] NVARCHAR(255) NOT NULL CONSTRAINT [User_userType_df] DEFAULT 'User';
        COMMIT TRAN;
        EXEC dbo._LogStep N'1a-userType', N'OK', N'Added User.userType column';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        EXEC dbo._LogStep N'1a-userType', N'FAILED', ERROR_MESSAGE();
    END CATCH
END
ELSE
    EXEC dbo._LogStep N'1a-userType', N'SKIPPED', N'userType already exists';
GO

-- 1b. Make roleId nullable (separate batch — cannot alter + reference in one go)
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.[User]') AND name = 'roleId' AND is_nullable = 0
)
BEGIN
    BEGIN TRY
        BEGIN TRAN;
        ALTER TABLE dbo.[User] ALTER COLUMN [roleId] NVARCHAR(50) NULL;
        COMMIT TRAN;
        EXEC dbo._LogStep N'1b-roleId', N'OK', N'User.roleId set to nullable';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        EXEC dbo._LogStep N'1b-roleId', N'FAILED', ERROR_MESSAGE();
    END CATCH
END
ELSE
    EXEC dbo._LogStep N'1b-roleId', N'SKIPPED', N'roleId already nullable (or column missing)';
GO

-- 1c. Populate userType: 'admin' users → 'Admin', everyone else → 'User'
-- This is in a SEPARATE batch from the ALTER ADD, so the column definitely exists.
IF COL_LENGTH('dbo.[User]', 'userType') IS NOT NULL
BEGIN
    BEGIN TRY
        BEGIN TRAN;
        UPDATE dbo.[User] SET [userType] = N'User'
        WHERE [userType] IS NULL OR [userType] NOT IN (N'Admin', N'User');

        UPDATE dbo.[User] SET [userType] = N'Admin'
        WHERE [username] = N'admin' AND [userType] <> N'Admin';

        COMMIT TRAN;
        EXEC dbo._LogStep N'1c-userType-data', N'OK', N'Populated userType (admin=Admin, rest=User)';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        EXEC dbo._LogStep N'1c-userType-data', N'FAILED', ERROR_MESSAGE();
    END CATCH
END
GO

-- ============================================================================
-- STEP 2: Member.joiningFee
-- ============================================================================
IF COL_LENGTH('dbo.Member', 'joiningFee') IS NULL
BEGIN
    BEGIN TRY
        BEGIN TRAN;
        ALTER TABLE dbo.Member ADD [joiningFee] FLOAT NOT NULL CONSTRAINT [Member_joiningFee_df] DEFAULT 0;
        COMMIT TRAN;
        EXEC dbo._LogStep N'2-joiningFee', N'OK', N'Added Member.joiningFee';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        EXEC dbo._LogStep N'2-joiningFee', N'FAILED', ERROR_MESSAGE();
    END CATCH
END
ELSE
    EXEC dbo._LogStep N'2-joiningFee', N'SKIPPED', N'joiningFee already exists';
GO

-- ============================================================================
-- STEP 3: Create the 6 master/detail tables (if missing)
-- ============================================================================
-- Fixes 08 Msg 208 (gymmaster referenced but never created).
-- All three master tables have identical structure; all three detail tables
-- have identical structure. Detail code = master code + 3-digit sequence.
-- ============================================================================

-- 3a. gymmaster
IF OBJECT_ID(N'dbo.gymmaster', N'U') IS NULL
BEGIN
    BEGIN TRY
        BEGIN TRAN;
        CREATE TABLE [dbo].[gymmaster] (
            [id]          NVARCHAR(50)  NOT NULL,
            [name]        NVARCHAR(255) NOT NULL,
            [description] NVARCHAR(MAX),
            [branchId]    NVARCHAR(50),
            [isActive]    BIT NOT NULL CONSTRAINT [gymmaster_isActive_df] DEFAULT 1,
            [createdAt]   DATETIME2 NOT NULL CONSTRAINT [gymmaster_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
            [updatedAt]   DATETIME2 NOT NULL,
            CONSTRAINT [gymmaster_pkey] PRIMARY KEY CLUSTERED ([id])
        );
        COMMIT TRAN;
        EXEC dbo._LogStep N'3a-gymmaster', N'OK', N'Created gymmaster';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        EXEC dbo._LogStep N'3a-gymmaster', N'FAILED', ERROR_MESSAGE();
    END CATCH
END
ELSE
    EXEC dbo._LogStep N'3a-gymmaster', N'SKIPPED', N'gymmaster already exists';
GO

-- 3b. gymmasterdetail
IF OBJECT_ID(N'dbo.gymmasterdetail', N'U') IS NULL
BEGIN
    BEGIN TRY
        BEGIN TRAN;
        CREATE TABLE [dbo].[gymmasterdetail] (
            [id]          NVARCHAR(50)  NOT NULL,
            [masterId]    NVARCHAR(50)  NOT NULL,
            [name]        NVARCHAR(255) NOT NULL,
            [description] NVARCHAR(MAX),
            [branchId]    NVARCHAR(50),
            [isActive]    BIT NOT NULL CONSTRAINT [gymmasterdetail_isActive_df] DEFAULT 1,
            [createdAt]   DATETIME2 NOT NULL CONSTRAINT [gymmasterdetail_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
            [updatedAt]   DATETIME2 NOT NULL,
            CONSTRAINT [gymmasterdetail_pkey] PRIMARY KEY CLUSTERED ([id])
        );
        COMMIT TRAN;
        EXEC dbo._LogStep N'3b-gymmasterdetail', N'OK', N'Created gymmasterdetail';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        EXEC dbo._LogStep N'3b-gymmasterdetail', N'FAILED', ERROR_MESSAGE();
    END CATCH
END
ELSE
    EXEC dbo._LogStep N'3b-gymmasterdetail', N'SKIPPED', N'gymmasterdetail already exists';
GO

-- 3c. financemaster
IF OBJECT_ID(N'dbo.financemaster', N'U') IS NULL
BEGIN
    BEGIN TRY
        BEGIN TRAN;
        CREATE TABLE [dbo].[financemaster] (
            [id]          NVARCHAR(50)  NOT NULL,
            [name]        NVARCHAR(255) NOT NULL,
            [description] NVARCHAR(MAX),
            [branchId]    NVARCHAR(50),
            [isActive]    BIT NOT NULL CONSTRAINT [financemaster_isActive_df] DEFAULT 1,
            [createdAt]   DATETIME2 NOT NULL CONSTRAINT [financemaster_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
            [updatedAt]   DATETIME2 NOT NULL,
            CONSTRAINT [financemaster_pkey] PRIMARY KEY CLUSTERED ([id])
        );
        COMMIT TRAN;
        EXEC dbo._LogStep N'3c-financemaster', N'OK', N'Created financemaster';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        EXEC dbo._LogStep N'3c-financemaster', N'FAILED', ERROR_MESSAGE();
    END CATCH
END
ELSE
    EXEC dbo._LogStep N'3c-financemaster', N'SKIPPED', N'financemaster already exists';
GO

-- 3d. financemasterdetail
IF OBJECT_ID(N'dbo.financemasterdetail', N'U') IS NULL
BEGIN
    BEGIN TRY
        BEGIN TRAN;
        CREATE TABLE [dbo].[financemasterdetail] (
            [id]          NVARCHAR(50)  NOT NULL,
            [masterId]    NVARCHAR(50)  NOT NULL,
            [name]        NVARCHAR(255) NOT NULL,
            [description] NVARCHAR(MAX),
            [branchId]    NVARCHAR(50),
            [isActive]    BIT NOT NULL CONSTRAINT [financemasterdetail_isActive_df] DEFAULT 1,
            [createdAt]   DATETIME2 NOT NULL CONSTRAINT [financemasterdetail_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
            [updatedAt]   DATETIME2 NOT NULL,
            CONSTRAINT [financemasterdetail_pkey] PRIMARY KEY CLUSTERED ([id])
        );
        COMMIT TRAN;
        EXEC dbo._LogStep N'3d-financemasterdetail', N'OK', N'Created financemasterdetail';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        EXEC dbo._LogStep N'3d-financemasterdetail', N'FAILED', ERROR_MESSAGE();
    END CATCH
END
ELSE
    EXEC dbo._LogStep N'3d-financemasterdetail', N'SKIPPED', N'financemasterdetail already exists';
GO

-- 3e. payrollmaster
IF OBJECT_ID(N'dbo.payrollmaster', N'U') IS NULL
BEGIN
    BEGIN TRY
        BEGIN TRAN;
        CREATE TABLE [dbo].[payrollmaster] (
            [id]          NVARCHAR(50)  NOT NULL,
            [name]        NVARCHAR(255) NOT NULL,
            [description] NVARCHAR(MAX),
            [branchId]    NVARCHAR(50),
            [isActive]    BIT NOT NULL CONSTRAINT [payrollmaster_isActive_df] DEFAULT 1,
            [createdAt]   DATETIME2 NOT NULL CONSTRAINT [payrollmaster_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
            [updatedAt]   DATETIME2 NOT NULL,
            CONSTRAINT [payrollmaster_pkey] PRIMARY KEY CLUSTERED ([id])
        );
        COMMIT TRAN;
        EXEC dbo._LogStep N'3e-payrollmaster', N'OK', N'Created payrollmaster';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        EXEC dbo._LogStep N'3e-payrollmaster', N'FAILED', ERROR_MESSAGE();
    END CATCH
END
ELSE
    EXEC dbo._LogStep N'3e-payrollmaster', N'SKIPPED', N'payrollmaster already exists';
GO

-- 3f. payrollmasterdetail
IF OBJECT_ID(N'dbo.payrollmasterdetail', N'U') IS NULL
BEGIN
    BEGIN TRY
        BEGIN TRAN;
        CREATE TABLE [dbo].[payrollmasterdetail] (
            [id]          NVARCHAR(50)  NOT NULL,
            [masterId]    NVARCHAR(50)  NOT NULL,
            [name]        NVARCHAR(255) NOT NULL,
            [description] NVARCHAR(MAX),
            [branchId]    NVARCHAR(50),
            [isActive]    BIT NOT NULL CONSTRAINT [payrollmasterdetail_isActive_df] DEFAULT 1,
            [createdAt]   DATETIME2 NOT NULL CONSTRAINT [payrollmasterdetail_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
            [updatedAt]   DATETIME2 NOT NULL,
            CONSTRAINT [payrollmasterdetail_pkey] PRIMARY KEY CLUSTERED ([id])
        );
        COMMIT TRAN;
        EXEC dbo._LogStep N'3f-payrollmasterdetail', N'OK', N'Created payrollmasterdetail';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        EXEC dbo._LogStep N'3f-payrollmasterdetail', N'FAILED', ERROR_MESSAGE();
    END CATCH
END
ELSE
    EXEC dbo._LogStep N'3f-payrollmasterdetail', N'SKIPPED', N'payrollmasterdetail already exists';
GO

-- 3g. Indexes on detail tables (masterId column)
IF OBJECT_ID('dbo.gymmasterdetail','U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='gymmasterdetail_masterId_idx' AND object_id=OBJECT_ID('dbo.gymmasterdetail'))
BEGIN
    BEGIN TRY
        CREATE NONCLUSTERED INDEX [gymmasterdetail_masterId_idx] ON [dbo].[gymmasterdetail]([masterId]);
        EXEC dbo._LogStep N'3g-idx-gymmasterdetail', N'OK', N'Created index';
    END TRY
    BEGIN CATCH
        EXEC dbo._LogStep N'3g-idx-gymmasterdetail', N'FAILED', ERROR_MESSAGE();
    END CATCH
END
ELSE
    EXEC dbo._LogStep N'3g-idx-gymmasterdetail', N'SKIPPED', N'Index already exists or table missing';
GO

IF OBJECT_ID('dbo.financemasterdetail','U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='financemasterdetail_masterId_idx' AND object_id=OBJECT_ID('dbo.financemasterdetail'))
BEGIN
    BEGIN TRY
        CREATE NONCLUSTERED INDEX [financemasterdetail_masterId_idx] ON [dbo].[financemasterdetail]([masterId]);
        EXEC dbo._LogStep N'3g-idx-financemasterdetail', N'OK', N'Created index';
    END TRY
    BEGIN CATCH
        EXEC dbo._LogStep N'3g-idx-financemasterdetail', N'FAILED', ERROR_MESSAGE();
    END CATCH
END
ELSE
    EXEC dbo._LogStep N'3g-idx-financemasterdetail', N'SKIPPED', N'Index already exists or table missing';
GO

IF OBJECT_ID('dbo.payrollmasterdetail','U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='payrollmasterdetail_masterId_idx' AND object_id=OBJECT_ID('dbo.payrollmasterdetail'))
BEGIN
    BEGIN TRY
        CREATE NONCLUSTERED INDEX [payrollmasterdetail_masterId_idx] ON [dbo].[payrollmasterdetail]([masterId]);
        EXEC dbo._LogStep N'3g-idx-payrollmasterdetail', N'OK', N'Created index';
    END TRY
    BEGIN CATCH
        EXEC dbo._LogStep N'3g-idx-payrollmasterdetail', N'FAILED', ERROR_MESSAGE();
    END CATCH
END
ELSE
    EXEC dbo._LogStep N'3g-idx-payrollmasterdetail', N'SKIPPED', N'Index already exists or table missing';
GO

-- 3h. Foreign keys (detail.masterId → master.id; *.branchId → Branch.id)
-- Use dynamic SQL to avoid batch-level name resolution issues.
DECLARE @fk_sql NVARCHAR(MAX);

-- gymmasterdetail.masterId → gymmaster.id
IF OBJECT_ID('dbo.gymmasterdetail','U') IS NOT NULL
   AND OBJECT_ID('dbo.gymmaster','U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name='gymmasterdetail_masterId_fkey')
BEGIN
    SET @fk_sql = N'ALTER TABLE [dbo].[gymmasterdetail] ADD CONSTRAINT [gymmasterdetail_masterId_fkey] FOREIGN KEY ([masterId]) REFERENCES [dbo].[gymmaster]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION';
    BEGIN TRY; EXEC sp_executesql @fk_sql; EXEC dbo._LogStep N'3h-fk-gmd-master', N'OK', N'FK added'; END TRY
    BEGIN CATCH; EXEC dbo._LogStep N'3h-fk-gmd-master', N'FAILED', ERROR_MESSAGE(); END CATCH
END
ELSE
    EXEC dbo._LogStep N'3h-fk-gmd-master', N'SKIPPED', N'FK already exists or table missing';
GO

-- financemasterdetail.masterId → financemaster.id
DECLARE @fk_sql NVARCHAR(MAX);
IF OBJECT_ID('dbo.financemasterdetail','U') IS NOT NULL
   AND OBJECT_ID('dbo.financemaster','U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name='financemasterdetail_masterId_fkey')
BEGIN
    SET @fk_sql = N'ALTER TABLE [dbo].[financemasterdetail] ADD CONSTRAINT [financemasterdetail_masterId_fkey] FOREIGN KEY ([masterId]) REFERENCES [dbo].[financemaster]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION';
    BEGIN TRY; EXEC sp_executesql @fk_sql; EXEC dbo._LogStep N'3h-fk-fmd-master', N'OK', N'FK added'; END TRY
    BEGIN CATCH; EXEC dbo._LogStep N'3h-fk-fmd-master', N'FAILED', ERROR_MESSAGE(); END CATCH
END
ELSE
    EXEC dbo._LogStep N'3h-fk-fmd-master', N'SKIPPED', N'FK already exists or table missing';
GO

-- payrollmasterdetail.masterId → payrollmaster.id
DECLARE @fk_sql NVARCHAR(MAX);
IF OBJECT_ID('dbo.payrollmasterdetail','U') IS NOT NULL
   AND OBJECT_ID('dbo.payrollmaster','U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name='payrollmasterdetail_masterId_fkey')
BEGIN
    SET @fk_sql = N'ALTER TABLE [dbo].[payrollmasterdetail] ADD CONSTRAINT [payrollmasterdetail_masterId_fkey] FOREIGN KEY ([masterId]) REFERENCES [dbo].[payrollmaster]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION';
    BEGIN TRY; EXEC sp_executesql @fk_sql; EXEC dbo._LogStep N'3h-fk-pmd-master', N'OK', N'FK added'; END TRY
    BEGIN CATCH; EXEC dbo._LogStep N'3h-fk-pmd-master', N'FAILED', ERROR_MESSAGE(); END CATCH
END
ELSE
    EXEC dbo._LogStep N'3h-fk-pmd-master', N'SKIPPED', N'FK already exists or table missing';
GO

-- ============================================================================
-- STEP 4: Migrate legacy master data into the new master/detail tables
-- ============================================================================
-- 4a. Exercise → gymmaster category '001' + gymmasterdetail items.
--     Codes: 0010001, 0010002, ... ordered by old code.
--     WorkoutDayExercise.exerciseId remapped.
--     Exercise table renamed to Exercise_legacy_bak (NOT dropped).
-- ============================================================================
IF OBJECT_ID(N'dbo.Exercise', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.gymmaster', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.gymmasterdetail', N'U') IS NOT NULL
BEGIN
    BEGIN TRY
        SET XACT_ABORT ON;
        BEGIN TRAN;

        -- Insert the '001' Exercises category if missing
        IF NOT EXISTS (SELECT 1 FROM [dbo].[gymmaster] WHERE [id] = N'001')
            INSERT INTO [dbo].[gymmaster] ([id], [name], [description], [branchId], [isActive], [createdAt], [updatedAt])
            VALUES (N'001', N'Exercises', N'Exercise catalog (migrated from Exercise table)', NULL, 1, SYSDATETIME(), SYSDATETIME());

        -- Migrate exercise rows → gymmasterdetail (codes 001001, 001002, ...)
        ;WITH x AS (
            SELECT [id], [name], [instructions], [branchId], [status], [createdAt], [updatedAt],
                   ROW_NUMBER() OVER (ORDER BY [code], [id]) AS rn
            FROM [dbo].[Exercise]
        )
        INSERT INTO [dbo].[gymmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt])
        SELECT N'001' + RIGHT(N'00' + CAST(x.rn AS NVARCHAR(10)), 3),
               N'001', x.[name], x.[instructions], x.[branchId],
               CASE WHEN x.[status] = N'Active' THEN 1 ELSE 0 END, x.[createdAt], x.[updatedAt]
        FROM x
        WHERE NOT EXISTS (
            SELECT 1 FROM [dbo].[gymmasterdetail] d
            WHERE d.[id] = N'001' + RIGHT(N'00' + CAST(x.rn AS NVARCHAR(10)), 3)
        );

        -- Remap WorkoutDayExercise.exerciseId from old Exercise.id to new gymmasterdetail.id
        IF OBJECT_ID('dbo.WorkoutDayExercise','U') IS NOT NULL
        BEGIN
            ;WITH x AS (
                SELECT [id], ROW_NUMBER() OVER (ORDER BY [code], [id]) AS rn
                FROM [dbo].[Exercise]
            )
            UPDATE wde SET [exerciseId] = N'001' + RIGHT(N'00' + CAST(x.rn AS NVARCHAR(10)), 3)
            FROM [dbo].[WorkoutDayExercise] wde
            JOIN x ON wde.[exerciseId] = x.[id];
        END

        -- Retarget the FK: drop the one pointing at Exercise, add new one → gymmasterdetail
        IF OBJECT_ID('dbo.WorkoutDayExercise','U') IS NOT NULL
        BEGIN
            DECLARE @oldfk NVARCHAR(MAX);
            SELECT @oldfk = name FROM sys.foreign_keys
            WHERE parent_object_id = OBJECT_ID('dbo.WorkoutDayExercise')
              AND referenced_object_id = OBJECT_ID('dbo.Exercise');
            IF @oldfk IS NOT NULL
            BEGIN
                DECLARE @dropsql NVARCHAR(MAX) = N'ALTER TABLE [dbo].[WorkoutDayExercise] DROP CONSTRAINT [' + @oldfk + N']';
                EXEC sp_executesql @dropsql;
            END

            IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'WorkoutDayExercise_exerciseId_fkey')
            BEGIN
                DECLARE @addfk NVARCHAR(MAX) = N'ALTER TABLE [dbo].[WorkoutDayExercise] ADD CONSTRAINT [WorkoutDayExercise_exerciseId_fkey] FOREIGN KEY ([exerciseId]) REFERENCES [dbo].[gymmasterdetail]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION';
                EXEC sp_executesql @addfk;
            END
        END

        -- Rename Exercise → Exercise_legacy_bak (do NOT drop — preserve data)
        IF OBJECT_ID('dbo.Exercise_legacy_bak','U') IS NULL
            EXEC sp_rename N'dbo.Exercise', N'Exercise_legacy_bak';

        COMMIT TRAN;
        EXEC dbo._LogStep N'4a-Exercise-migrate', N'OK', N'Exercise migrated to gymmasterdetail; Exercise renamed to Exercise_legacy_bak';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        EXEC dbo._LogStep N'4a-Exercise-migrate', N'FAILED', ERROR_MESSAGE();
    END CATCH
END
ELSE IF OBJECT_ID(N'dbo.Exercise', N'U') IS NULL
    EXEC dbo._LogStep N'4a-Exercise-migrate', N'SKIPPED', N'Exercise table already migrated (gone)';
ELSE
    EXEC dbo._LogStep N'4a-Exercise-migrate', N'SKIPPED', N'Master tables not ready yet';
GO

-- 4b. MasterFile (Banks/CardTypes) → financemaster categories '001'/'002' + details
IF OBJECT_ID(N'dbo.MasterFile', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.financemaster', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.financemasterdetail', N'U') IS NOT NULL
BEGIN
    BEGIN TRY
        SET XACT_ABORT ON;
        BEGIN TRAN;

        IF NOT EXISTS (SELECT 1 FROM [dbo].[financemaster] WHERE [id] = N'001')
            INSERT INTO [dbo].[financemaster] ([id],[name],[description],[branchId],[isActive],[createdAt],[updatedAt])
            VALUES (N'001', N'Banks', N'Bank master (bank transfer payments)', NULL, 1, SYSDATETIME(), SYSDATETIME());

        IF NOT EXISTS (SELECT 1 FROM [dbo].[financemaster] WHERE [id] = N'002')
            INSERT INTO [dbo].[financemaster] ([id],[name],[description],[branchId],[isActive],[createdAt],[updatedAt])
            VALUES (N'002', N'Card Types', N'Card type master (card payments)', NULL, 1, SYSDATETIME(), SYSDATETIME());

        ;WITH src AS (
            SELECT mf.*, ROW_NUMBER() OVER (PARTITION BY mf.[masterType] ORDER BY mf.[code], mf.[name]) AS rn
            FROM [dbo].[MasterFile] mf
            WHERE mf.[masterType] IN (N'Banks', N'CardTypes') AND mf.[isActive] = 1
        )
        INSERT INTO [dbo].[financemasterdetail] ([id],[masterId],[name],[description],[branchId],[isActive],[createdAt],[updatedAt])
        SELECT CASE src.[masterType] WHEN N'Banks' THEN N'001' ELSE N'002' END + RIGHT(N'00' + CAST(src.rn AS NVARCHAR(10)), 3),
               CASE src.[masterType] WHEN N'Banks' THEN N'001' ELSE N'002' END,
               src.[name], src.[description], src.[branchId], src.[isActive], SYSDATETIME(), SYSDATETIME()
        FROM src
        WHERE NOT EXISTS (
            SELECT 1 FROM [dbo].[financemasterdetail] d
            WHERE d.[masterId] = CASE src.[masterType] WHEN N'Banks' THEN N'001' ELSE N'002' END
              AND d.[name] = src.[name]
        );

        COMMIT TRAN;
        EXEC dbo._LogStep N'4b-MasterFile-finance', N'OK', N'Banks/CardTypes copied into financemaster';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        EXEC dbo._LogStep N'4b-MasterFile-finance', N'FAILED', ERROR_MESSAGE();
    END CATCH
END
ELSE
    EXEC dbo._LogStep N'4b-MasterFile-finance', N'SKIPPED', N'MasterFile or financemaster tables missing';
GO

-- 4c. payrollmasterfile → payrollmaster categories + payrollmasterdetail items
IF OBJECT_ID(N'dbo.payrollmasterfile', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.payrollmaster', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.payrollmasterdetail', N'U') IS NOT NULL
BEGIN
    BEGIN TRY
        SET XACT_ABORT ON;
        BEGIN TRAN;

        ;WITH cats AS (
            SELECT DISTINCT [masterType], ROW_NUMBER() OVER (ORDER BY [masterType]) AS rn
            FROM [dbo].[payrollmasterfile]
        )
        INSERT INTO [dbo].[payrollmaster] ([id],[name],[description],[branchId],[isActive],[createdAt],[updatedAt])
        SELECT RIGHT(N'00' + CAST(cats.rn AS NVARCHAR(10)), 3),
               cats.[masterType], N'Migrated from payrollmasterfile', NULL, 1, SYSDATETIME(), SYSDATETIME()
        FROM cats
        WHERE NOT EXISTS (SELECT 1 FROM [dbo].[payrollmaster] m WHERE m.[name] = cats.[masterType]);

        ;WITH cats AS (
            SELECT DISTINCT [masterType], ROW_NUMBER() OVER (ORDER BY [masterType]) AS rn
            FROM [dbo].[payrollmasterfile]
        ),
        items AS (
            SELECT p.[name] AS itemName, p.[description], p.[extra], p.[branchId], p.[isActive],
                   cats.rn AS catRn, p.[masterType],
                   ROW_NUMBER() OVER (PARTITION BY p.[masterType] ORDER BY p.[name]) AS rn
            FROM [dbo].[payrollmasterfile] p
            JOIN cats ON cats.[masterType] = p.[masterType]
        )
        INSERT INTO [dbo].[payrollmasterdetail] ([id],[masterId],[name],[description],[branchId],[isActive],[createdAt],[updatedAt])
        SELECT RIGHT(N'00' + CAST(items.catRn AS NVARCHAR(10)), 3) + RIGHT(N'00' + CAST(items.rn AS NVARCHAR(10)), 3),
               RIGHT(N'00' + CAST(items.catRn AS NVARCHAR(10)), 3),
               items.[itemName], items.[description], items.[branchId], items.[isActive], SYSDATETIME(), SYSDATETIME()
        FROM items
        WHERE NOT EXISTS (
            SELECT 1 FROM [dbo].[payrollmasterdetail] d
            WHERE d.[masterId] = RIGHT(N'00' + CAST(items.catRn AS NVARCHAR(10)), 3)
              AND d.[name] = items.[itemName]
        );

        COMMIT TRAN;
        EXEC dbo._LogStep N'4c-payrollmasterfile', N'OK', N'payrollmasterfile copied into payrollmaster';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        EXEC dbo._LogStep N'4c-payrollmasterfile', N'FAILED', ERROR_MESSAGE();
    END CATCH
END
ELSE
    EXEC dbo._LogStep N'4c-payrollmasterfile', N'SKIPPED', N'payrollmasterfile or payrollmaster tables missing';
GO

-- 4d. gymmasterfile → gymmaster categories + gymmasterdetail items
IF OBJECT_ID(N'dbo.gymmasterfile', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.gymmaster', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.gymmasterdetail', N'U') IS NOT NULL
   AND COL_LENGTH('dbo.gymmasterfile','level') IS NOT NULL
BEGIN
    BEGIN TRY
        SET XACT_ABORT ON;
        BEGIN TRAN;

        -- Categories (level = 1)
        IF COL_LENGTH('dbo.gymmasterfile','parentCode') IS NOT NULL
        BEGIN
            ;WITH cats AS (
                SELECT [id] AS oldCode, [name], ROW_NUMBER() OVER (ORDER BY [id]) AS rn
                FROM [dbo].[gymmasterfile] WHERE [level] = 1
            )
            INSERT INTO [dbo].[gymmaster] ([id],[name],[description],[branchId],[isActive],[createdAt],[updatedAt])
            SELECT RIGHT(N'00' + CAST(cats.rn AS NVARCHAR(10)), 3),
                   cats.[name], N'Migrated from gymmasterfile', NULL, 1, SYSDATETIME(), SYSDATETIME()
            FROM cats
            WHERE NOT EXISTS (SELECT 1 FROM [dbo].[gymmaster] m WHERE m.[name] = cats.[name]);

            -- Items (level = 2)
            ;WITH cats2 AS (
                SELECT [id] AS oldCode, [name], ROW_NUMBER() OVER (ORDER BY [id]) AS rn
                FROM [dbo].[gymmasterfile] WHERE [level] = 1
            ),
            items AS (
                SELECT g.[name], g.[branchId], g.[isActive], g.[description],
                       cats2.rn AS catRn,
                       ROW_NUMBER() OVER (PARTITION BY g.[parentCode] ORDER BY g.[id]) AS rn
                FROM [dbo].[gymmasterfile] g
                JOIN cats2 ON cats2.[oldCode] = g.[parentCode]
                WHERE g.[level] = 2
            )
            INSERT INTO [dbo].[gymmasterdetail] ([id],[masterId],[name],[description],[branchId],[isActive],[createdAt],[updatedAt])
            SELECT RIGHT(N'00' + CAST(items.catRn AS NVARCHAR(10)), 3) + RIGHT(N'00' + CAST(items.rn AS NVARCHAR(10)), 3),
                   RIGHT(N'00' + CAST(items.catRn AS NVARCHAR(10)), 3),
                   items.[name], items.[description], items.[branchId], items.[isActive], SYSDATETIME(), SYSDATETIME()
            FROM items
            WHERE NOT EXISTS (
                SELECT 1 FROM [dbo].[gymmasterdetail] d
                WHERE d.[masterId] = RIGHT(N'00' + CAST(items.catRn AS NVARCHAR(10)), 3)
                  AND d.[name] = items.[name]
            );
        END

        COMMIT TRAN;
        EXEC dbo._LogStep N'4d-gymmasterfile', N'OK', N'gymmasterfile copied into gymmaster';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        EXEC dbo._LogStep N'4d-gymmasterfile', N'FAILED', ERROR_MESSAGE();
    END CATCH
END
ELSE
    EXEC dbo._LogStep N'4d-gymmasterfile', N'SKIPPED', N'gymmasterfile or gymmaster tables missing';
GO

-- ============================================================================
-- STEP 5: Staff merge — merge employeeId into id (id keeps EMP-xxxxx format)
-- ============================================================================
-- Fixes 09 Msg 102 (QUOTENAME inside EXEC('...'+...)).
-- Uses sp_executesql with pre-built @sql variable instead.
--
-- If Staff.employeeId does NOT exist (already merged), this step is skipped.
-- If Staff.employeeId EXISTS, we:
--   1. Drop all FKs referencing Staff (via either id or employeeId).
--   2. Drop the PK.
--   3. Copy employeeId → id where id is not in EMP-xxxxx format.
--   4. Drop the employeeId column.
--   5. Re-add the PK on id.
--   6. Re-create the FKs pointing at Staff(id).
--   7. Remap all child tables' staffId from old id → new id (EMP-xxxxx).
-- ============================================================================

IF COL_LENGTH('dbo.Staff', 'employeeId') IS NOT NULL
BEGIN
    BEGIN TRY
        SET XACT_ABORT ON;
        BEGIN TRAN;

        -- 5a. Build a temp table of old_id → new_id (employeeId)
        DECLARE @map TABLE (old_id NVARCHAR(50), new_id NVARCHAR(50));
        INSERT INTO @map (old_id, new_id)
        SELECT [id], [employeeId] FROM dbo.Staff WHERE [employeeId] IS NOT NULL AND [employeeId] <> N'';

        -- 5b. Remap all child tables BEFORE touching Staff PK/FKs
        -- Child tables: Leave, Overtime, Payroll, TrainerAvailability,
        -- TrainerSchedule, StaffDocument (all reference Staff via staffId)
        DECLARE @child TABLE (name NVARCHAR(128));
        INSERT INTO @child VALUES
            (N'Leave'), (N'Overtime'), (N'Payroll'),
            (N'TrainerAvailability'), (N'TrainerSchedule'), (N'StaffDocument');

        DECLARE @c NVARCHAR(128), @sql NVARCHAR(MAX);
        DECLARE c_cur CURSOR LOCAL FAST_FORWARD FOR SELECT name FROM @child;
        OPEN c_cur;
        FETCH NEXT FROM c_cur INTO @c;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            IF OBJECT_ID('dbo.' + @c, 'U') IS NOT NULL
               AND COL_LENGTH('dbo.' + @c, 'staffId') IS NOT NULL
            BEGIN
                -- Remap staffId from old id to new employeeId
                SET @sql = N'UPDATE t SET t.[staffId] = m.new_id
                    FROM [dbo].' + QUOTENAME(@c) + N' t
                    JOIN @mapD m ON t.[staffId] = m.old_id';
                -- Use a real temp table instead of table variable for JOIN
                SELECT * INTO #map_real FROM @map;
                DECLARE @sql2 NVARCHAR(MAX) = N'UPDATE t SET t.[staffId] = m.new_id
                    FROM [dbo].' + QUOTENAME(@c) + N' t
                    JOIN #map_real m ON t.[staffId] = m.old_id';
                EXEC sp_executesql @sql2;
                DROP TABLE #map_real;
            END
            FETCH NEXT FROM c_cur INTO @c;
        END
        CLOSE c_cur;
        DEALLOCATE c_cur;

        -- 5c. Also remap Staff.assignedTrainerId? No — that's on Member, not Staff.
        -- Remap Member.assignedTrainerId
        IF COL_LENGTH('dbo.Member', 'assignedTrainerId') IS NOT NULL
        BEGIN
            SELECT * INTO #map_real2 FROM @map;
            DECLARE @sql3 NVARCHAR(MAX) = N'UPDATE t SET t.[assignedTrainerId] = m.new_id
                FROM [dbo].[Member] t
                JOIN #map_real2 m ON t.[assignedTrainerId] = m.old_id
                WHERE t.[assignedTrainerId] IS NOT NULL';
            EXEC sp_executesql @sql3;
            DROP TABLE #map_real2;
        END

        -- 5d. Drop all FKs that reference dbo.Staff
        DECLARE @fkname NVARCHAR(256), @reftbl NVARCHAR(256);
        DECLARE fk_cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT fk.name, OBJECT_NAME(fk.parent_object_id)
            FROM sys.foreign_keys fk
            WHERE fk.referenced_object_id = OBJECT_ID('dbo.Staff');
        OPEN fk_cur;
        FETCH NEXT FROM fk_cur INTO @fkname, @reftbl;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            DECLARE @dropfk NVARCHAR(MAX) = N'ALTER TABLE [dbo].' + QUOTENAME(@reftbl) + N' DROP CONSTRAINT [' + @fkname + N']';
            EXEC sp_executesql @dropfk;
            FETCH NEXT FROM fk_cur INTO @fkname, @reftbl;
        END
        CLOSE fk_cur;
        DEALLOCATE fk_cur;

        -- 5e. Drop any unique constraints/indexes on Staff.employeeId
        DECLARE @uqname NVARCHAR(256);
        SELECT TOP 1 @uqname = i.name
        FROM sys.indexes i
        WHERE i.is_unique = 1 AND i.object_id = OBJECT_ID('dbo.Staff')
          AND EXISTS (SELECT 1 FROM sys.index_columns ic
                      JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
                      WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id
                        AND c.name = 'employeeId');
        IF @uqname IS NOT NULL
        BEGIN
            DECLARE @dropuq NVARCHAR(MAX) = N'DROP INDEX [' + @uqname + N'] ON [dbo].[Staff]';
            EXEC sp_executesql @dropuq;
        END

        -- 5f. Drop the PK on Staff.id
        DECLARE @pkname NVARCHAR(256);
        SELECT @pkname = name FROM sys.key_constraints WHERE type = 'PK' AND parent_object_id = OBJECT_ID('dbo.Staff');
        IF @pkname IS NOT NULL
        BEGIN
            DECLARE @droppk NVARCHAR(MAX) = N'ALTER TABLE [dbo].[Staff] DROP CONSTRAINT [' + @pkname + N']';
            EXEC sp_executesql @droppk;
        END

        -- 5g. Copy employeeId → id (only where employeeId is a better key, i.e. id is not EMP-xxxxx)
        UPDATE dbo.Staff SET [id] = [employeeId]
        WHERE [employeeId] IS NOT NULL AND [employeeId] <> N'' AND [id] NOT LIKE N'EMP-%';

        -- 5h. Drop the employeeId column
        ALTER TABLE dbo.Staff DROP COLUMN [employeeId];

        -- 5i. Re-add the PK on id
        IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE type='PK' AND parent_object_id=OBJECT_ID('dbo.Staff'))
            ALTER TABLE [dbo].[Staff] ADD CONSTRAINT [Staff_pkey] PRIMARY KEY CLUSTERED ([id]);

        -- 5j. Re-create the child FKs pointing at Staff(id)
        -- We know the standard set; re-create each if missing
        DECLARE @childfk TABLE (fkname NVARCHAR(256), tbl NVARCHAR(128), col NVARCHAR(128), ondel NVARCHAR(20));
        INSERT INTO @childfk VALUES
            (N'Leave_staffId_fkey',            N'Leave',                N'staffId', N'CASCADE'),
            (N'Overtime_staffId_fkey',         N'Overtime',              N'staffId', N'CASCADE'),
            (N'Payroll_staffId_fkey',          N'Payroll',               N'staffId', N'NO ACTION'),
            (N'TrainerAvailability_staffId_fkey', N'TrainerAvailability', N'staffId', N'CASCADE'),
            (N'TrainerSchedule_staffId_fkey',  N'TrainerSchedule',       N'staffId', N'CASCADE'),
            (N'StaffDocument_staffId_fkey',    N'StaffDocument',         N'staffId', N'CASCADE');

        DECLARE @fkn NVARCHAR(256), @ftbl NVARCHAR(128), @fcol NVARCHAR(128), @fon NVARCHAR(20);
        DECLARE cfk_cur CURSOR LOCAL FAST_FORWARD FOR SELECT fkname, tbl, col, ondel FROM @childfk;
        OPEN cfk_cur;
        FETCH NEXT FROM cfk_cur INTO @fkn, @ftbl, @fcol, @fon;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            IF OBJECT_ID('dbo.' + @ftbl, 'U') IS NOT NULL
               AND COL_LENGTH('dbo.' + @ftbl, @fcol) IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = @fkn)
            BEGIN
                DECLARE @addcfk NVARCHAR(MAX) = N'ALTER TABLE [dbo].' + QUOTENAME(@ftbl)
                    + N' ADD CONSTRAINT [' + @fkn + N'] FOREIGN KEY ([' + @fcol + N']) REFERENCES [dbo].[Staff]([id]) ON DELETE ' + @fon + N' ON UPDATE NO ACTION';
                EXEC sp_executesql @addcfk;
            END
            FETCH NEXT FROM cfk_cur INTO @fkn, @ftbl, @fcol, @fon;
        END
        CLOSE cfk_cur;
        DEALLOCATE cfk_cur;

        -- 5k. Re-create Staff.branchId FK
        IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name='Staff_branchId_fkey')
           AND COL_LENGTH('dbo.Staff','branchId') IS NOT NULL
        BEGIN
            DECLARE @addbfk NVARCHAR(MAX) = N'ALTER TABLE [dbo].[Staff] ADD CONSTRAINT [Staff_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION';
            EXEC sp_executesql @addbfk;
        END

        -- 5l. Re-create Staff.shiftId FK
        IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name='Staff_shiftId_fkey')
           AND COL_LENGTH('dbo.Staff','shiftId') IS NOT NULL
        BEGIN
            DECLARE @addsfk NVARCHAR(MAX) = N'ALTER TABLE [dbo].[Staff] ADD CONSTRAINT [Staff_shiftId_fkey] FOREIGN KEY ([shiftId]) REFERENCES [dbo].[Shift]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION';
            EXEC sp_executesql @addsfk;
        END

        COMMIT TRAN;
        EXEC dbo._LogStep N'5-Staff-merge', N'OK', N'Staff.employeeId merged into id; FKs recreated';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        EXEC dbo._LogStep N'5-Staff-merge', N'FAILED', ERROR_MESSAGE();
    END CATCH
END
ELSE
    EXEC dbo._LogStep N'5-Staff-merge', N'SKIPPED', N'employeeId already merged (column absent)';
GO

-- ============================================================================
-- STEP 6: Shift id renumbering — cuid/legacy ids → 001, 002, 003 ...
-- ============================================================================
-- Fixes 09 Msg 102 (QUOTENAME inside EXEC).
-- Two-phase: (a) remap Staff.shiftId via temp table, (b) renumber Shift.id.
-- ============================================================================

IF OBJECT_ID('dbo.Shift','U') IS NOT NULL
BEGIN
    BEGIN TRY
        SET XACT_ABORT ON;
        BEGIN TRAN;

        -- Check if any Shift ids are non-3-digit
        IF EXISTS (SELECT 1 FROM dbo.Shift WHERE id NOT LIKE N'[0-9][0-9][0-9]')
        BEGIN
            -- 6a. Build the old→new map
            DECLARE @shiftmap TABLE (old_id NVARCHAR(50), new_id NVARCHAR(50));
            ;WITH s AS (
                SELECT [id], ROW_NUMBER() OVER (ORDER BY [name], [id]) AS rn
                FROM dbo.Shift
            )
            INSERT INTO @shiftmap (old_id, new_id)
            SELECT [id], RIGHT(N'00' + CAST(rn AS NVARCHAR(10)), 3)
            FROM s;

            -- 6b. Remap Staff.shiftId
            IF COL_LENGTH('dbo.Staff','shiftId') IS NOT NULL
            BEGIN
                SELECT * INTO #shiftmap_real FROM @shiftmap;
                DECLARE @remapStaffShift NVARCHAR(MAX) = N'UPDATE s SET s.[shiftId] = m.new_id
                    FROM [dbo].[Staff] s
                    JOIN #shiftmap_real m ON s.[shiftId] = m.old_id
                    WHERE s.[shiftId] IS NOT NULL';
                EXEC sp_executesql @remapStaffShift;
                DROP TABLE #shiftmap_real;
            END

            -- 6c. Drop Staff_shiftId_fkey (will re-add after renumber)
            IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name='Staff_shiftId_fkey')
            BEGIN
                DECLARE @dropSFK NVARCHAR(MAX) = N'ALTER TABLE [dbo].[Staff] DROP CONSTRAINT [Staff_shiftId_fkey]';
                EXEC sp_executesql @dropSFK;
            END

            -- 6d. Renumber Shift.id via a temp table swap (cannot UPDATE PK in place with FKs)
            -- Create a temp copy with new ids
            SELECT * INTO #shift_new FROM dbo.Shift WHERE 1=0;
            INSERT INTO #shift_new
            SELECT m.new_id, s.[name], s.[timeIn], s.[timeOut], s.[workingDays],
                   s.[branchId], s.[isActive], s.[createdAt], s.[updatedAt]
            FROM dbo.Shift s JOIN @shiftmap m ON s.[id] = m.old_id;

            -- Drop the Shift table's FK to Branch (if any) so we can truncate
            IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name='Shift_branchId_fkey')
            BEGIN
                DECLARE @dropSBR NVARCHAR(MAX) = N'ALTER TABLE [dbo].[Shift] DROP CONSTRAINT [Shift_branchId_fkey]';
                EXEC sp_executesql @dropSBR;
            END

            -- Rename old Shift → Shift_legacy_bak, insert new
            IF OBJECT_ID('dbo.Shift_legacy_bak','U') IS NULL
                EXEC sp_rename N'dbo.Shift', N'Shift_legacy_bak';

            -- Create fresh Shift table (same structure)
            SELECT * INTO dbo.Shift FROM #shift_new WHERE 1=0;
            INSERT INTO dbo.Shift SELECT * FROM #shift_new;
            DROP TABLE #shift_new;

            -- Re-add PK
            ALTER TABLE [dbo].[Shift] ADD CONSTRAINT [Shift_pkey] PRIMARY KEY CLUSTERED ([id]);

            -- Re-add Shift.branchId FK
            IF COL_LENGTH('dbo.Shift','branchId') IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name='Shift_branchId_fkey')
            BEGIN
                DECLARE @addSBR NVARCHAR(MAX) = N'ALTER TABLE [dbo].[Shift] ADD CONSTRAINT [Shift_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION';
                EXEC sp_executesql @addSBR;
            END

            -- Re-add Staff.shiftId FK
            IF COL_LENGTH('dbo.Staff','shiftId') IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name='Staff_shiftId_fkey')
            BEGIN
                DECLARE @addSS NVARCHAR(MAX) = N'ALTER TABLE [dbo].[Staff] ADD CONSTRAINT [Staff_shiftId_fkey] FOREIGN KEY ([shiftId]) REFERENCES [dbo].[Shift]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION';
                EXEC sp_executesql @addSS;
            END

            EXEC dbo._LogStep N'6-Shift-renumber', N'OK', N'Shift ids renumbered to 001/002/003; old table saved as Shift_legacy_bak';
        END
        ELSE
            EXEC dbo._LogStep N'6-Shift-renumber', N'SKIPPED', N'All Shift ids already 3-digit';

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        EXEC dbo._LogStep N'6-Shift-renumber', N'FAILED', ERROR_MESSAGE();
    END CATCH
END
ELSE
    EXEC dbo._LogStep N'6-Shift-renumber', N'SKIPPED', N'Shift table missing';
GO

-- ============================================================================
-- STEP 7: CalendarDay id renumbering — cuid → 001, 002, ...
-- ============================================================================
-- CalendarDay has NO inbound FKs (nothing references it), so we can safely
-- renumber in place.
-- ============================================================================

IF OBJECT_ID('dbo.CalendarDay','U') IS NOT NULL
BEGIN
    BEGIN TRY
        SET XACT_ABORT ON;
        BEGIN TRAN;

        IF EXISTS (SELECT 1 FROM dbo.CalendarDay WHERE id NOT LIKE N'[0-9][0-9][0-9]')
        BEGIN
            -- Drop the PK and the unique date constraint
            DECLARE @cdpk NVARCHAR(256);
            SELECT @cdpk = name FROM sys.key_constraints WHERE type='PK' AND parent_object_id=OBJECT_ID('dbo.CalendarDay');
            IF @cdpk IS NOT NULL
            BEGIN
                DECLARE @dropCDPK NVARCHAR(MAX) = N'ALTER TABLE [dbo].[CalendarDay] DROP CONSTRAINT [' + @cdpk + N']';
                EXEC sp_executesql @dropCDPK;
            END

            IF EXISTS (SELECT 1 FROM sys.key_constraints WHERE name='CalendarDay_date_key' AND parent_object_id=OBJECT_ID('dbo.CalendarDay'))
            BEGIN
                DECLARE @dropCDDK NVARCHAR(MAX) = N'ALTER TABLE [dbo].[CalendarDay] DROP CONSTRAINT [CalendarDay_date_key]';
                EXEC sp_executesql @dropCDDK;
            END

            -- Drop Branch FK if any
            IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name='CalendarDay_branchId_fkey')
            BEGIN
                DECLARE @dropCDBR NVARCHAR(MAX) = N'ALTER TABLE [dbo].[CalendarDay] DROP CONSTRAINT [CalendarDay_branchId_fkey]';
                EXEC sp_executesql @dropCDBR;
            END

            -- Renumber ids
            ;WITH c AS (
                SELECT [id], ROW_NUMBER() OVER (ORDER BY [date]) AS rn
                FROM dbo.CalendarDay
            )
            UPDATE cd SET [id] = RIGHT(N'00' + CAST(c.rn AS NVARCHAR(10)), 3)
            FROM dbo.CalendarDay cd JOIN c ON cd.[id] = c.[id];

            -- Re-add PK
            ALTER TABLE [dbo].[CalendarDay] ADD CONSTRAINT [CalendarDay_pkey] PRIMARY KEY CLUSTERED ([id]);

            -- Re-add unique date constraint
            IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name='CalendarDay_date_key' AND parent_object_id=OBJECT_ID('dbo.CalendarDay'))
                ALTER TABLE [dbo].[CalendarDay] ADD CONSTRAINT [CalendarDay_date_key] UNIQUE NONCLUSTERED ([date]);

            -- Re-add Branch FK
            IF COL_LENGTH('dbo.CalendarDay','branchId') IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name='CalendarDay_branchId_fkey')
            BEGIN
                DECLARE @addCDBR NVARCHAR(MAX) = N'ALTER TABLE [dbo].[CalendarDay] ADD CONSTRAINT [CalendarDay_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION';
                EXEC sp_executesql @addCDBR;
            END

            EXEC dbo._LogStep N'7-CalendarDay-renumber', N'OK', N'CalendarDay ids renumbered to 001/002/...';
        END
        ELSE
            EXEC dbo._LogStep N'7-CalendarDay-renumber', N'SKIPPED', N'All CalendarDay ids already 3-digit';

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        EXEC dbo._LogStep N'7-CalendarDay-renumber', N'FAILED', ERROR_MESSAGE();
    END CATCH
END
ELSE
    EXEC dbo._LogStep N'7-CalendarDay-renumber', N'SKIPPED', N'CalendarDay table missing';
GO

-- ============================================================================
-- STEP 8: ScreenPermission + UserPermission tables (if missing)
-- ============================================================================
IF OBJECT_ID(N'dbo.ScreenPermission', N'U') IS NULL
BEGIN
    BEGIN TRY
        SET XACT_ABORT ON;
        BEGIN TRAN;
        CREATE TABLE [dbo].[ScreenPermission] (
            [id]        NVARCHAR(50)  NOT NULL,
            [roleId]    NVARCHAR(50)  NOT NULL,
            [screenKey] NVARCHAR(255) NOT NULL,
            [canView]   BIT NOT NULL CONSTRAINT [ScreenPermission_canView_df] DEFAULT 0,
            [canAdd]    BIT NOT NULL CONSTRAINT [ScreenPermission_canAdd_df] DEFAULT 0,
            [canEdit]   BIT NOT NULL CONSTRAINT [ScreenPermission_canEdit_df] DEFAULT 0,
            [canDelete] BIT NOT NULL CONSTRAINT [ScreenPermission_canDelete_df] DEFAULT 0,
            [canPrint]  BIT NOT NULL CONSTRAINT [ScreenPermission_canPrint_df] DEFAULT 0,
            CONSTRAINT [ScreenPermission_pkey] PRIMARY KEY CLUSTERED ([id]),
            CONSTRAINT [ScreenPermission_roleId_screenKey_key] UNIQUE NONCLUSTERED ([roleId],[screenKey])
        );
        COMMIT TRAN;
        EXEC dbo._LogStep N'8a-ScreenPermission', N'OK', N'Created ScreenPermission';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        EXEC dbo._LogStep N'8a-ScreenPermission', N'FAILED', ERROR_MESSAGE();
    END CATCH
END
ELSE
    EXEC dbo._LogStep N'8a-ScreenPermission', N'SKIPPED', N'ScreenPermission already exists';
GO

IF OBJECT_ID(N'dbo.UserPermission', N'U') IS NULL
BEGIN
    BEGIN TRY
        SET XACT_ABORT ON;
        BEGIN TRAN;
        CREATE TABLE [dbo].[UserPermission] (
            [id]        NVARCHAR(50)  NOT NULL,
            [userId]    NVARCHAR(50)  NOT NULL,
            [screenKey] NVARCHAR(255) NOT NULL,
            [canView]   BIT NOT NULL CONSTRAINT [UserPermission_canView_df] DEFAULT 0,
            [canAdd]    BIT NOT NULL CONSTRAINT [UserPermission_canAdd_df] DEFAULT 0,
            [canEdit]   BIT NOT NULL CONSTRAINT [UserPermission_canEdit_df] DEFAULT 0,
            [canDelete] BIT NOT NULL CONSTRAINT [UserPermission_canDelete_df] DEFAULT 0,
            [canPrint]  BIT NOT NULL CONSTRAINT [UserPermission_canPrint_df] DEFAULT 0,
            CONSTRAINT [UserPermission_pkey] PRIMARY KEY CLUSTERED ([id]),
            CONSTRAINT [UserPermission_userId_screenKey_key] UNIQUE NONCLUSTERED ([userId],[screenKey])
        );
        COMMIT TRAN;
        EXEC dbo._LogStep N'8b-UserPermission', N'OK', N'Created UserPermission';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        EXEC dbo._LogStep N'8b-UserPermission', N'FAILED', ERROR_MESSAGE();
    END CATCH
END
ELSE
    EXEC dbo._LogStep N'8b-UserPermission', N'SKIPPED', N'UserPermission already exists';
GO

-- ============================================================================
-- STEP 9: Gym operation tables (TrainerAvailability, TrainerSchedule,
--         FitnessGoal, PersonalTrainingSession, StaffDocument, KnockOff)
-- ============================================================================
-- These tables are defined in 02_schema_tables.sql for fresh installs.
-- This step creates them only if they are missing (e.g. on a partial upgrade).
-- ============================================================================

-- 9a. TrainerAvailability
IF OBJECT_ID(N'dbo.TrainerAvailability', N'U') IS NULL
BEGIN
    BEGIN TRY
        SET XACT_ABORT ON;
        BEGIN TRAN;
        CREATE TABLE [dbo].[TrainerAvailability] (
            [id]         NVARCHAR(50)  NOT NULL,
            [staffId]    NVARCHAR(50)  NOT NULL,
            [dayOfWeek]  NVARCHAR(255) NOT NULL,
            [startTime]   NVARCHAR(255) NOT NULL,
            [endTime]     NVARCHAR(255) NOT NULL,
            [branchId]   NVARCHAR(50),
            [status]     NVARCHAR(255) NOT NULL CONSTRAINT [TrainerAvailability_status_df] DEFAULT N'Available',
            [createdAt]  DATETIME2 NOT NULL CONSTRAINT [TrainerAvailability_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
            CONSTRAINT [TrainerAvailability_pkey] PRIMARY KEY CLUSTERED ([id])
        );
        COMMIT TRAN;
        EXEC dbo._LogStep N'9a-TrainerAvailability', N'OK', N'Created TrainerAvailability';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        EXEC dbo._LogStep N'9a-TrainerAvailability', N'FAILED', ERROR_MESSAGE();
    END CATCH
END
ELSE
    EXEC dbo._LogStep N'9a-TrainerAvailability', N'SKIPPED', N'TrainerAvailability already exists';
GO

-- 9b. TrainerSchedule
IF OBJECT_ID(N'dbo.TrainerSchedule', N'U') IS NULL
BEGIN
    BEGIN TRY
        SET XACT_ABORT ON;
        BEGIN TRAN;
        CREATE TABLE [dbo].[TrainerSchedule] (
            [id]         NVARCHAR(50)  NOT NULL,
            [staffId]    NVARCHAR(50)  NOT NULL,
            [branchId]   NVARCHAR(50),
            [date]       DATETIME2 NOT NULL,
            [dayOfWeek]  NVARCHAR(255) NOT NULL,
            [startTime]   NVARCHAR(255) NOT NULL,
            [endTime]     NVARCHAR(255) NOT NULL,
            [sessionType] NVARCHAR(255) NOT NULL,
            [memberId]   NVARCHAR(50),
            [classId]    NVARCHAR(50),
            [status]     NVARCHAR(255) NOT NULL CONSTRAINT [TrainerSchedule_status_df] DEFAULT N'Scheduled',
            [notes]      NVARCHAR(MAX),
            [createdAt]  DATETIME2 NOT NULL CONSTRAINT [TrainerSchedule_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
            CONSTRAINT [TrainerSchedule_pkey] PRIMARY KEY CLUSTERED ([id])
        );
        COMMIT TRAN;
        EXEC dbo._LogStep N'9b-TrainerSchedule', N'OK', N'Created TrainerSchedule';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        EXEC dbo._LogStep N'9b-TrainerSchedule', N'FAILED', ERROR_MESSAGE();
    END CATCH
END
ELSE
    EXEC dbo._LogStep N'9b-TrainerSchedule', N'SKIPPED', N'TrainerSchedule already exists';
GO

-- 9c. FitnessGoal
IF OBJECT_ID(N'dbo.FitnessGoal', N'U') IS NULL
BEGIN
    BEGIN TRY
        SET XACT_ABORT ON;
        BEGIN TRAN;
        CREATE TABLE [dbo].[FitnessGoal] (
            [id]           NVARCHAR(50)  NOT NULL,
            [memberId]     NVARCHAR(50)  NOT NULL,
            [goalType]     NVARCHAR(255) NOT NULL,
            [targetValue]  FLOAT(53),
            [unit]         NVARCHAR(255),
            [startDate]    DATETIME2 NOT NULL CONSTRAINT [FitnessGoal_startDate_df] DEFAULT CURRENT_TIMESTAMP,
            [targetDate]   DATETIME2,
            [status]       NVARCHAR(255) NOT NULL CONSTRAINT [FitnessGoal_status_df] DEFAULT N'Active',
            [notes]        NVARCHAR(MAX),
            [createdAt]    DATETIME2 NOT NULL CONSTRAINT [FitnessGoal_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
            [updatedAt]    DATETIME2 NOT NULL,
            CONSTRAINT [FitnessGoal_pkey] PRIMARY KEY CLUSTERED ([id])
        );
        COMMIT TRAN;
        EXEC dbo._LogStep N'9c-FitnessGoal', N'OK', N'Created FitnessGoal';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        EXEC dbo._LogStep N'9c-FitnessGoal', N'FAILED', ERROR_MESSAGE();
    END CATCH
END
ELSE
    EXEC dbo._LogStep N'9c-FitnessGoal', N'SKIPPED', N'FitnessGoal already exists';
GO

-- 9d. PersonalTrainingSession
IF OBJECT_ID(N'dbo.PersonalTrainingSession', N'U') IS NULL
BEGIN
    BEGIN TRY
        SET XACT_ABORT ON;
        BEGIN TRAN;
        CREATE TABLE [dbo].[PersonalTrainingSession] (
            [id]                NVARCHAR(50)  NOT NULL,
            [memberId]          NVARCHAR(50)  NOT NULL,
            [trainerId]         NVARCHAR(50)  NOT NULL,
            [branchId]          NVARCHAR(50),
            [sessionsPurchased] INT NOT NULL CONSTRAINT [PersonalTrainingSession_sessionsPurchased_df] DEFAULT 0,
            [sessionsUsed]      INT NOT NULL CONSTRAINT [PersonalTrainingSession_sessionsUsed_df] DEFAULT 0,
            [sessionsRemaining] INT NOT NULL CONSTRAINT [PersonalTrainingSession_sessionsRemaining_df] DEFAULT 0,
            [sessionDate]       DATETIME2,
            [sessionStatus]     NVARCHAR(255) NOT NULL CONSTRAINT [PersonalTrainingSession_sessionStatus_df] DEFAULT N'Scheduled',
            [startDate]         DATETIME2,
            [endDate]           DATETIME2,
            [notes]             NVARCHAR(MAX),
            [status]            NVARCHAR(255) NOT NULL CONSTRAINT [PersonalTrainingSession_status_df] DEFAULT N'Active',
            [createdAt]         DATETIME2 NOT NULL CONSTRAINT [PersonalTrainingSession_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
            [updatedAt]         DATETIME2 NOT NULL,
            CONSTRAINT [PersonalTrainingSession_pkey] PRIMARY KEY CLUSTERED ([id])
        );
        COMMIT TRAN;
        EXEC dbo._LogStep N'9d-PersonalTrainingSession', N'OK', N'Created PersonalTrainingSession';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        EXEC dbo._LogStep N'9d-PersonalTrainingSession', N'FAILED', ERROR_MESSAGE();
    END CATCH
END
ELSE
    EXEC dbo._LogStep N'9d-PersonalTrainingSession', N'SKIPPED', N'PersonalTrainingSession already exists';
GO

-- 9e. StaffDocument
IF OBJECT_ID(N'dbo.StaffDocument', N'U') IS NULL
BEGIN
    BEGIN TRY
        SET XACT_ABORT ON;
        BEGIN TRAN;
        CREATE TABLE [dbo].[StaffDocument] (
            [id]            NVARCHAR(50)  NOT NULL,
            [staffId]       NVARCHAR(50)  NOT NULL,
            [documentType]  NVARCHAR(255) NOT NULL,
            [documentName]  NVARCHAR(255) NOT NULL,
            [fileUrl]       NVARCHAR(255) NOT NULL,
            [issueDate]     DATETIME2,
            [expiryDate]    DATETIME2,
            [status]        NVARCHAR(255) NOT NULL CONSTRAINT [StaffDocument_status_df] DEFAULT N'Active',
            [notes]         NVARCHAR(MAX),
            [uploadedBy]    NVARCHAR(255),
            [createdAt]     DATETIME2 NOT NULL CONSTRAINT [StaffDocument_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
            [updatedAt]     DATETIME2 NOT NULL,
            CONSTRAINT [StaffDocument_pkey] PRIMARY KEY CLUSTERED ([id])
        );
        COMMIT TRAN;
        EXEC dbo._LogStep N'9e-StaffDocument', N'OK', N'Created StaffDocument';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        EXEC dbo._LogStep N'9e-StaffDocument', N'FAILED', ERROR_MESSAGE();
    END CATCH
END
ELSE
    EXEC dbo._LogStep N'9e-StaffDocument', N'SKIPPED', N'StaffDocument already exists';
GO

-- 9f. KnockOff
IF OBJECT_ID(N'dbo.KnockOff', N'U') IS NULL
BEGIN
    BEGIN TRY
        SET XACT_ABORT ON;
        BEGIN TRAN;
        CREATE TABLE [dbo].[KnockOff] (
            [id]            NVARCHAR(50)  NOT NULL,
            [billId]        NVARCHAR(50)  NOT NULL,
            [billNumber]    NVARCHAR(255),
            [referenceNumber] NVARCHAR(255),
            [billType]      NVARCHAR(255),
            [amount]        FLOAT(53) NOT NULL,
            [dcFlag]        NVARCHAR(10) NOT NULL CONSTRAINT [KnockOff_dcFlag_df] DEFAULT N'Debit',
            [referenceDate] DATETIME2,
            [dueDate]       DATETIME2,
            [description]   NVARCHAR(20),
            [accountId]     NVARCHAR(50) NOT NULL,
            [branchId]      NVARCHAR(50) NOT NULL,
            [createdById]   NVARCHAR(50),
            [createdAt]     DATETIME2 NOT NULL CONSTRAINT [KnockOff_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
            [updatedAt]     DATETIME2 NOT NULL,
            CONSTRAINT [KnockOff_pkey] PRIMARY KEY CLUSTERED ([id]),
            CONSTRAINT [KnockOff_billId_key] UNIQUE NONCLUSTERED ([billId])
        );
        COMMIT TRAN;
        EXEC dbo._LogStep N'9f-KnockOff', N'OK', N'Created KnockOff';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        EXEC dbo._LogStep N'9f-KnockOff', N'FAILED', ERROR_MESSAGE();
    END CATCH
END
ELSE
    EXEC dbo._LogStep N'9f-KnockOff', N'SKIPPED', N'KnockOff already exists';
GO

-- ============================================================================
-- STEP 10: Branch hierarchical — ensure nodeType column exists
-- ============================================================================
-- The schema uses `nodeType` (not `level`) for Control/Detail classification.
-- This step adds nodeType if missing and sets defaults.
-- ============================================================================

IF COL_LENGTH('dbo.Branch', 'nodeType') IS NULL
BEGIN
    BEGIN TRY
        SET XACT_ABORT ON;
        BEGIN TRAN;
        ALTER TABLE dbo.Branch ADD [nodeType] NVARCHAR(1000) NOT NULL CONSTRAINT [Branch_nodeType_df] DEFAULT N'Detail';
        -- Existing top-level branches (parentId IS NULL) default to 'Control'
        UPDATE dbo.Branch SET [nodeType] = N'Control' WHERE [parentId] IS NULL;
        COMMIT TRAN;
        EXEC dbo._LogStep N'10-Branch-nodeType', N'OK', N'Added Branch.nodeType; top-level set to Control';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        EXEC dbo._LogStep N'10-Branch-nodeType', N'FAILED', ERROR_MESSAGE();
    END CATCH
END
ELSE
    EXEC dbo._LogStep N'10-Branch-nodeType', N'SKIPPED', N'Branch.nodeType already exists';
GO

-- ============================================================================
-- STEP 11: Staff.isDeleted (if missing — for soft delete)
-- ============================================================================
IF COL_LENGTH('dbo.Staff', 'isDeleted') IS NULL
BEGIN
    BEGIN TRY
        SET XACT_ABORT ON;
        BEGIN TRAN;
        ALTER TABLE dbo.Staff ADD [isDeleted] BIT NOT NULL CONSTRAINT [Staff_isDeleted_df] DEFAULT 0;
        COMMIT TRAN;
        EXEC dbo._LogStep N'11-Staff-isDeleted', N'OK', N'Added Staff.isDeleted';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        EXEC dbo._LogStep N'11-Staff-isDeleted', N'FAILED', ERROR_MESSAGE();
    END CATCH
END
ELSE
    EXEC dbo._LogStep N'11-Staff-isDeleted', N'SKIPPED', N'Staff.isDeleted already exists';
GO

-- ============================================================================
-- STEP 12: Member soft-delete columns (isDeleted + deletedAt)
-- ============================================================================
IF COL_LENGTH('dbo.Member', 'isDeleted') IS NULL
BEGIN
    BEGIN TRY
        SET XACT_ABORT ON;
        BEGIN TRAN;
        ALTER TABLE dbo.Member ADD [isDeleted] BIT NOT NULL CONSTRAINT [Member_isDeleted_df] DEFAULT 0;
        ALTER TABLE dbo.Member ADD [deletedAt] DATETIME2;
        COMMIT TRAN;
        EXEC dbo._LogStep N'12-Member-softdelete', N'OK', N'Added Member.isDeleted + deletedAt';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        EXEC dbo._LogStep N'12-Member-softdelete', N'FAILED', ERROR_MESSAGE();
    END CATCH
END
ELSE IF COL_LENGTH('dbo.Member', 'deletedAt') IS NULL
BEGIN
    BEGIN TRY
        SET XACT_ABORT ON;
        BEGIN TRAN;
        ALTER TABLE dbo.Member ADD [deletedAt] DATETIME2;
        COMMIT TRAN;
        EXEC dbo._LogStep N'12-Member-softdelete', N'OK', N'Added Member.deletedAt';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        EXEC dbo._LogStep N'12-Member-softdelete', N'FAILED', ERROR_MESSAGE();
    END CATCH
END
ELSE
    EXEC dbo._LogStep N'12-Member-softdelete', N'SKIPPED', N'Member soft-delete columns already exist';
GO

-- ============================================================================
-- FINAL: summarize and print SUCCESS / FAILED
-- ============================================================================
DECLARE @failures INT = 0;
DECLARE @failedSteps NVARCHAR(MAX) = N'';
DECLARE @okCount INT = 0;
DECLARE @skipCount INT = 0;

SELECT @failures = COUNT(*) FROM dbo._UpgradeLog WHERE [status] = N'FAILED';
SELECT @okCount = COUNT(*) FROM dbo._UpgradeLog WHERE [status] = N'OK';
SELECT @skipCount = COUNT(*) FROM dbo._UpgradeLog WHERE [status] = N'SKIPPED';

IF @failures > 0
BEGIN
    SELECT @failedSteps = @failedSteps + N' ' + [step]
    FROM dbo._UpgradeLog WHERE [status] = N'FAILED'
    ORDER BY [at];
    PRINT N'';
    PRINT N'=== UPGRADE RESULT ===';
    PRINT N'FAILED:' + @failedSteps;
    PRINT N'(OK: ' + CAST(@okCount AS NVARCHAR(10)) + N', Skipped: ' + CAST(@skipCount AS NVARCHAR(10)) + N', Failed: ' + CAST(@failures AS NVARCHAR(10)) + N')';
    PRINT N'';
    PRINT N'Step details (from dbo._UpgradeLog):';
    SELECT [step], [status], [message], [at] FROM dbo._UpgradeLog ORDER BY [at];
END
ELSE
BEGIN
    PRINT N'';
    PRINT N'=== UPGRADE RESULT ===';
    PRINT N'SUCCESS';
    PRINT N'(OK: ' + CAST(@okCount AS NVARCHAR(10)) + N', Skipped: ' + CAST(@skipCount AS NVARCHAR(10)) + N', Failed: 0)';
    PRINT N'';
    PRINT N'Step details (from dbo._UpgradeLog):';
    SELECT [step], [status], [message], [at] FROM dbo._UpgradeLog ORDER BY [at];
END
GO

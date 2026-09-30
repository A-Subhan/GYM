-- ============================================================================
-- Contoura Gym Management System - STEP 8 (OPTIONAL): Upgrade an EXISTING
-- GymDB to the 2026-09 feature set. NOT needed on a fresh install
-- (02 -> 06 already builds everything).
-- ============================================================================
-- What this script does (idempotent - safe to re-run):
--   1. [User]: adds [userType] ('Admin' | 'User', default 'User'); makes
--      [roleId] nullable. The role system is replaced by User Type +
--      per-user screen permissions (dbo.UserPermission).
--   2. [Member]: adds [joiningFee] (default 0). New members' first invoice
--      = membership fee + joining fee.
--   3. Creates the three IDENTICAL master/detail pairs if missing:
--      gymmaster/gymmasterdetail, financemaster/financemasterdetail,
--      payrollmaster/payrollmasterdetail.
--   4. Migrates legacy master data:
--        - [Exercise] (code + name merged into ONE name field) -> gymmaster
--          category '001' items (001001, 001002, ...); workout day exercises
--          are remapped; the old Exercise table is then DROPPED.
--        - [MasterFile] 'Banks'/'CardTypes' -> financemaster '001'/'002'.
--        - [payrollmasterfile] masterType groups -> payrollmaster categories
--          + items (Leave Type, Education, Designation, ...).
--        - [gymmasterfile] levels -> gymmaster categories + items.
--      Legacy tables are KEPT (data preserved) except Exercise, which is
--      merged away per the new design.
--   5. [FeePayment]: no structural change; new payments get business ids
--      FP/{branchCode}/{MMMyy}/{000001} (existing cuid ids keep working).
--
-- Re-run check: exits early (with a message) when everything is already
-- in place. Run AFTER backing up the database.
-- ============================================================================

SET XACT_ABORT ON;
SET NOCOUNT ON;

DECLARE @errors TABLE (step NVARCHAR(200), message NVARCHAR(MAX));
DECLARE @already BIT = 1;

-- ---------------------------------------------------------------------------
-- Helper: only touch what is missing (re-runnable)
-- ---------------------------------------------------------------------------

-- 1) User.userType + nullable roleId --------------------------------------
IF COL_LENGTH('dbo.[User]', 'userType') IS NULL
BEGIN
    ALTER TABLE dbo.[User] ADD [userType] NVARCHAR(255) NOT NULL CONSTRAINT [User_userType_df] DEFAULT 'User';
    PRINT 'added User.userType';
    SET @already = 0;
END
ELSE
    PRINT 'User.userType already present';

IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.[User]') AND name = 'roleId' AND is_nullable = 0)
BEGIN
    ALTER TABLE dbo.[User] ALTER COLUMN [roleId] NVARCHAR(50) NULL;
    PRINT 'User.roleId set to nullable';
    SET @already = 0;
END
ELSE
    PRINT 'User.roleId already nullable';

-- Default every user to type 'User'; the admin account becomes 'Admin' below.
UPDATE dbo.[User] SET [userType] = 'User' WHERE [userType] IS NULL OR [userType] NOT IN ('Admin', 'User');
UPDATE dbo.[User] SET [userType] = 'Admin' WHERE [username] = 'admin';

-- 2) Member.joiningFee -----------------------------------------------------
IF COL_LENGTH('dbo.Member', 'joiningFee') IS NULL
BEGIN
    ALTER TABLE dbo.Member ADD [joiningFee] FLOAT NOT NULL CONSTRAINT [Member_joiningFee_df] DEFAULT 0;
    PRINT 'added Member.joiningFee';
    SET @already = 0;
END
ELSE
    PRINT 'Member.joiningFee already present';

-- 3) The three master/detail pairs ----------------------------------------
IF OBJECT_ID(N'dbo.gymmaster', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[gymmaster] (
        [id] NVARCHAR(50) NOT NULL,
        [name] NVARCHAR(255) NOT NULL,
        [description] NVARCHAR(MAX),
        [branchId] NVARCHAR(50),
        [isActive] BIT NOT NULL CONSTRAINT [gymmaster_isActive_df] DEFAULT 1,
        [createdAt] DATETIME2 NOT NULL CONSTRAINT [gymmaster_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
        [updatedAt] DATETIME2 NOT NULL,
        CONSTRAINT [gymmaster_pkey] PRIMARY KEY CLUSTERED ([id])
    );
    PRINT 'created gymmaster';
    SET @already = 0;
END
IF OBJECT_ID(N'dbo.gymmasterdetail', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[gymmasterdetail] (
        [id] NVARCHAR(50) NOT NULL,
        [masterId] NVARCHAR(50) NOT NULL,
        [name] NVARCHAR(255) NOT NULL,
        [description] NVARCHAR(MAX),
        [branchId] NVARCHAR(50),
        [isActive] BIT NOT NULL CONSTRAINT [gymmasterdetail_isActive_df] DEFAULT 1,
        [createdAt] DATETIME2 NOT NULL CONSTRAINT [gymmasterdetail_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
        [updatedAt] DATETIME2 NOT NULL,
        CONSTRAINT [gymmasterdetail_pkey] PRIMARY KEY CLUSTERED ([id])
    );
    PRINT 'created gymmasterdetail';
    SET @already = 0;
END
IF OBJECT_ID(N'dbo.financemaster', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[financemaster] (
        [id] NVARCHAR(50) NOT NULL, [name] NVARCHAR(255) NOT NULL, [description] NVARCHAR(MAX),
        [branchId] NVARCHAR(50),
        [isActive] BIT NOT NULL CONSTRAINT [financemaster_isActive_df] DEFAULT 1,
        [createdAt] DATETIME2 NOT NULL CONSTRAINT [financemaster_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
        [updatedAt] DATETIME2 NOT NULL,
        CONSTRAINT [financemaster_pkey] PRIMARY KEY CLUSTERED ([id])
    );
    PRINT 'created financemaster'; SET @already = 0;
END
IF OBJECT_ID(N'dbo.financemasterdetail', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[financemasterdetail] (
        [id] NVARCHAR(50) NOT NULL, [masterId] NVARCHAR(50) NOT NULL, [name] NVARCHAR(255) NOT NULL,
        [description] NVARCHAR(MAX), [branchId] NVARCHAR(50),
        [isActive] BIT NOT NULL CONSTRAINT [financemasterdetail_isActive_df] DEFAULT 1,
        [createdAt] DATETIME2 NOT NULL CONSTRAINT [financemasterdetail_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
        [updatedAt] DATETIME2 NOT NULL,
        CONSTRAINT [financemasterdetail_pkey] PRIMARY KEY CLUSTERED ([id])
    );
    PRINT 'created financemasterdetail'; SET @already = 0;
END
IF OBJECT_ID(N'dbo.payrollmaster', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[payrollmaster] (
        [id] NVARCHAR(50) NOT NULL, [name] NVARCHAR(255) NOT NULL, [description] NVARCHAR(MAX),
        [branchId] NVARCHAR(50),
        [isActive] BIT NOT NULL CONSTRAINT [payrollmaster_isActive_df] DEFAULT 1,
        [createdAt] DATETIME2 NOT NULL CONSTRAINT [payrollmaster_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
        [updatedAt] DATETIME2 NOT NULL,
        CONSTRAINT [payrollmaster_pkey] PRIMARY KEY CLUSTERED ([id])
    );
    PRINT 'created payrollmaster'; SET @already = 0;
END
IF OBJECT_ID(N'dbo.payrollmasterdetail', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[payrollmasterdetail] (
        [id] NVARCHAR(50) NOT NULL, [masterId] NVARCHAR(50) NOT NULL, [name] NVARCHAR(255) NOT NULL,
        [description] NVARCHAR(MAX), [branchId] NVARCHAR(50),
        [isActive] BIT NOT NULL CONSTRAINT [payrollmasterdetail_isActive_df] DEFAULT 1,
        [createdAt] DATETIME2 NOT NULL CONSTRAINT [payrollmasterdetail_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
        [updatedAt] DATETIME2 NOT NULL,
        CONSTRAINT [payrollmasterdetail_pkey] PRIMARY KEY CLUSTERED ([id])
    );
    PRINT 'created payrollmasterdetail'; SET @already = 0;
END
GO

-- Indexes -------------------------------------------------------------------
IF OBJECT_ID(N'dbo.gymmasterdetail', N'U') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'gymmasterdetail_masterId_idx' AND object_id = OBJECT_ID(N'dbo.gymmasterdetail'))
    CREATE NONCLUSTERED INDEX [gymmasterdetail_masterId_idx] ON [dbo].[gymmasterdetail]([masterId]);
IF OBJECT_ID(N'dbo.financemasterdetail', N'U') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'financemasterdetail_masterId_idx' AND object_id = OBJECT_ID(N'dbo.financemasterdetail'))
    CREATE NONCLUSTERED INDEX [financemasterdetail_masterId_idx] ON [dbo].[financemasterdetail]([masterId]);
IF OBJECT_ID(N'dbo.payrollmasterdetail', N'U') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'payrollmasterdetail_masterId_idx' AND object_id = OBJECT_ID(N'dbo.payrollmasterdetail'))
    CREATE NONCLUSTERED INDEX [payrollmasterdetail_masterId_idx] ON [dbo].[payrollmasterdetail]([masterId]);
GO

-- Foreign keys (guarded) ------------------------------------------------------
IF OBJECT_ID(N'dbo.gymmaster', N'U') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'gymmaster_branchId_fkey')
    ALTER TABLE [dbo].[gymmaster] ADD CONSTRAINT [gymmaster_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
IF OBJECT_ID(N'dbo.gymmasterdetail', N'U') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'gymmasterdetail_masterId_fkey')
    ALTER TABLE [dbo].[gymmasterdetail] ADD CONSTRAINT [gymmasterdetail_masterId_fkey] FOREIGN KEY ([masterId]) REFERENCES [dbo].[gymmaster]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
IF OBJECT_ID(N'dbo.gymmasterdetail', N'U') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'gymmasterdetail_branchId_fkey')
    ALTER TABLE [dbo].[gymmasterdetail] ADD CONSTRAINT [gymmasterdetail_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
IF OBJECT_ID(N'dbo.financemaster', N'U') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'financemaster_branchId_fkey')
    ALTER TABLE [dbo].[financemaster] ADD CONSTRAINT [financemaster_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
IF OBJECT_ID(N'dbo.financemasterdetail', N'U') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'financemasterdetail_masterId_fkey')
    ALTER TABLE [dbo].[financemasterdetail] ADD CONSTRAINT [financemasterdetail_masterId_fkey] FOREIGN KEY ([masterId]) REFERENCES [dbo].[financemaster]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
IF OBJECT_ID(N'dbo.financemasterdetail', N'U') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'financemasterdetail_branchId_fkey')
    ALTER TABLE [dbo].[financemasterdetail] ADD CONSTRAINT [financemasterdetail_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
IF OBJECT_ID(N'dbo.payrollmaster', N'U') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'payrollmaster_branchId_fkey')
    ALTER TABLE [dbo].[payrollmaster] ADD CONSTRAINT [payrollmaster_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
IF OBJECT_ID(N'dbo.payrollmasterdetail', N'U') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'payrollmasterdetail_masterId_fkey')
    ALTER TABLE [dbo].[payrollmasterdetail] ADD CONSTRAINT [payrollmasterdetail_masterId_fkey] FOREIGN KEY ([masterId]) REFERENCES [dbo].[payrollmaster]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
IF OBJECT_ID(N'dbo.payrollmasterdetail', N'U') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'payrollmasterdetail_branchId_fkey')
    ALTER TABLE [dbo].[payrollmasterdetail] ADD CONSTRAINT [payrollmasterdetail_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- ============================================================================
-- 4a) Migrate [Exercise] -> gymmaster '001' + details; remap WorkoutDayExercise;
--     then retarget the FK and DROP the Exercise table.
--     Codes: exercises become 001001, 001002, ... ordered by the old code.
-- ============================================================================
IF OBJECT_ID(N'dbo.Exercise', N'U') IS NOT NULL
BEGIN
    BEGIN TRY
        BEGIN TRAN;

        IF NOT EXISTS (SELECT 1 FROM [dbo].[gymmaster] WHERE [id] = '001')
            INSERT INTO [dbo].[gymmaster] ([id], [name], [description], [branchId], [isActive], [createdAt], [updatedAt])
            VALUES ('001', N'Exercises', N'Exercise catalog (migrated from the Exercise table)', NULL, 1, SYSDATETIME(), SYSDATETIME());

        ;WITH x AS (
            SELECT [id], [name], [instructions], [branchId], [status], [createdAt], [updatedAt],
                   ROW_NUMBER() OVER (ORDER BY [code], [id]) AS rn
            FROM [dbo].[Exercise]
        )
        INSERT INTO [dbo].[gymmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt])
        SELECT '001' + RIGHT('00' + CAST(x.rn AS NVARCHAR(10)), 3), '001', x.[name], x.[instructions], x.[branchId],
               CASE WHEN x.[status] = 'Active' THEN 1 ELSE 0 END, x.[createdAt], x.[updatedAt]
        FROM x
        WHERE NOT EXISTS (SELECT 1 FROM [dbo].[gymmasterdetail] d WHERE d.[id] = '001' + RIGHT('00' + CAST(x.rn AS NVARCHAR(10)), 3));

        ;WITH x AS (
            SELECT [id], ROW_NUMBER() OVER (ORDER BY [code], [id]) AS rn
            FROM [dbo].[Exercise]
        )
        UPDATE wde SET [exerciseId] = '001' + RIGHT('00' + CAST(x.rn AS NVARCHAR(10)), 3)
        FROM [dbo].[WorkoutDayExercise] wde
        JOIN x ON wde.[exerciseId] = x.[id];

        -- retarget the FK: drop the one pointing at Exercise, add the new one
        IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'WorkoutDayExercise_exerciseId_fkey' AND referenced_object_id = OBJECT_ID(N'dbo.Exercise'))
            ALTER TABLE [dbo].[WorkoutDayExercise] DROP CONSTRAINT [WorkoutDayExercise_exerciseId_fkey];
        IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'WorkoutDayExercise_exerciseId_fkey')
            ALTER TABLE [dbo].[WorkoutDayExercise] ADD CONSTRAINT [WorkoutDayExercise_exerciseId_fkey] FOREIGN KEY ([exerciseId]) REFERENCES [dbo].[gymmasterdetail]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

        DROP TABLE [dbo].[Exercise];
        COMMIT TRAN;
        PRINT 'Exercise migrated into gymmaster/gymmasterdetail and dropped';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        THROW 51908, N'Exercise migration failed - rolled back. Fix and re-run.', 1;
    END CATCH
END
ELSE
    PRINT 'Exercise table already migrated';

GO

-- ============================================================================
-- 4b) Copy MasterFile Banks/CardTypes -> financemaster '001'/'002' details.
--     (copy, keep legacy rows; codes 001001.. within each category)
-- ============================================================================
IF OBJECT_ID(N'dbo.MasterFile', N'U') IS NOT NULL AND OBJECT_ID(N'dbo.financemaster', N'U') IS NOT NULL
BEGIN
    IF NOT EXISTS (SELECT 1 FROM [dbo].[financemaster] WHERE [id] = '001')
        INSERT INTO [dbo].[financemaster] ([id], [name], [description], [branchId], [isActive], [createdAt], [updatedAt])
        VALUES ('001', N'Banks', N'Bank master (bank transfer payments)', NULL, 1, SYSDATETIME(), SYSDATETIME());
    IF NOT EXISTS (SELECT 1 FROM [dbo].[financemaster] WHERE [id] = '002')
        INSERT INTO [dbo].[financemaster] ([id], [name], [description], [branchId], [isActive], [createdAt], [updatedAt])
        VALUES ('002', N'Card Types', N'Card type master (card payments)', NULL, 1, SYSDATETIME(), SYSDATETIME());

    ;WITH src AS (
        SELECT mf.*, ROW_NUMBER() OVER (PARTITION BY mf.[masterType] ORDER BY mf.[code], mf.[name]) AS rn
        FROM [dbo].[MasterFile] mf
        WHERE mf.[masterType] IN ('Banks', 'CardTypes') AND mf.[isActive] = 1
    )
    INSERT INTO [dbo].[financemasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt])
    SELECT CASE src.[masterType] WHEN 'Banks' THEN '001' ELSE '002' END + RIGHT('00' + CAST(src.rn AS NVARCHAR(10)), 3),
           CASE src.[masterType] WHEN 'Banks' THEN '001' ELSE '002' END,
           src.[name], src.[description], src.[branchId], src.[isActive], SYSDATETIME(), SYSDATETIME()
    FROM src
    WHERE NOT EXISTS (
        SELECT 1 FROM [dbo].[financemasterdetail] d
        WHERE d.[masterId] = CASE src.[masterType] WHEN 'Banks' THEN '001' ELSE '002' END
          AND d.[name] = src.[name]
    );
    PRINT 'Banks/CardTypes copied into financemaster (where missing)';
END
GO

-- ============================================================================
-- 4c) Copy payrollmasterfile groups -> payrollmaster categories + items.
--     Categories numbered 001.. in name order; items {catCode}{3-digit seq}.
-- ============================================================================
IF OBJECT_ID(N'dbo.payrollmasterfile', N'U') IS NOT NULL AND OBJECT_ID(N'dbo.payrollmaster', N'U') IS NOT NULL
BEGIN
    ;WITH cats AS (
        SELECT DISTINCT [masterType], ROW_NUMBER() OVER (ORDER BY [masterType]) AS rn
        FROM [dbo].[payrollmasterfile]
    )
    INSERT INTO [dbo].[payrollmaster] ([id], [name], [description], [branchId], [isActive], [createdAt], [updatedAt])
    SELECT RIGHT('00' + CAST(cats.rn AS NVARCHAR(10)), 3), cats.[masterType], N'Migrated from payrollmasterfile', NULL, 1, SYSDATETIME(), SYSDATETIME()
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
    INSERT INTO [dbo].[payrollmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt])
    SELECT RIGHT('00' + CAST(items.catRn AS NVARCHAR(10)), 3) + RIGHT('00' + CAST(items.rn AS NVARCHAR(10)), 3),
           RIGHT('00' + CAST(items.catRn AS NVARCHAR(10)), 3),
           items.[itemName], items.[description], items.[branchId], items.[isActive], SYSDATETIME(), SYSDATETIME()
    FROM items
    WHERE NOT EXISTS (
        SELECT 1 FROM [dbo].[payrollmasterdetail] d
        WHERE d.[masterId] = RIGHT('00' + CAST(items.catRn AS NVARCHAR(10)), 3)
          AND d.[name] = items.[itemName]
    );
    PRINT 'payrollmasterfile copied into payrollmaster (where missing)';
END
GO

-- ============================================================================
-- 4d) Copy gymmasterfile levels -> gymmaster categories + items.
-- ============================================================================
IF OBJECT_ID(N'dbo.gymmasterfile', N'U') IS NOT NULL AND OBJECT_ID(N'dbo.gymmaster', N'U') IS NOT NULL
BEGIN
    ;WITH cats AS (
        SELECT [id] AS oldCode, [name], ROW_NUMBER() OVER (ORDER BY [id]) AS rn
        FROM [dbo].[gymmasterfile] WHERE [level] = 1
    )
    INSERT INTO [dbo].[gymmaster] ([id], [name], [description], [branchId], [isActive], [createdAt], [updatedAt])
    SELECT RIGHT('00' + CAST(cats.rn AS NVARCHAR(10)), 3), cats.[name], N'Migrated from gymmasterfile', NULL, 1, SYSDATETIME(), SYSDATETIME()
    FROM cats
    WHERE NOT EXISTS (SELECT 1 FROM [dbo].[gymmaster] m WHERE m.[name] = cats.[name]);

    ;WITH cats AS (
        SELECT [id] AS oldCode, [name], ROW_NUMBER() OVER (ORDER BY [id]) AS rn
        FROM [dbo].[gymmasterfile] WHERE [level] = 1
    ),
    items AS (
        SELECT g.[name], g.[branchId], g.[isActive], g.[description],
               cats.rn AS catRn,
               ROW_NUMBER() OVER (PARTITION BY g.[parentCode] ORDER BY g.[id]) AS rn
        FROM [dbo].[gymmasterfile] g
        JOIN cats ON cats.[oldCode] = g.[parentCode]
        WHERE g.[level] = 2
    )
    INSERT INTO [dbo].[gymmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt])
    SELECT RIGHT('00' + CAST(items.catRn AS NVARCHAR(10)), 3) + RIGHT('00' + CAST(items.rn AS NVARCHAR(10)), 3),
           RIGHT('00' + CAST(items.catRn AS NVARCHAR(10)), 3),
           items.[name], items.[description], items.[branchId], items.[isActive], SYSDATETIME(), SYSDATETIME()
    FROM items
    WHERE NOT EXISTS (
        SELECT 1 FROM [dbo].[gymmasterdetail] d
        WHERE d.[masterId] = RIGHT('00' + CAST(items.catRn AS NVARCHAR(10)), 3)
          AND d.[name] = items.[name]
    );
    PRINT 'gymmasterfile copied into gymmaster (where missing)';
END
GO

-- ============================================================================
-- Final gate: summary
-- ============================================================================
PRINT '---';
PRINT 'Upgrade 08 finished. Verify with:';
PRINT '  SELECT COUNT(*) FROM sys.tables;                            -- 74 tables (fresh 02-06) ';
PRINT '  SELECT [userType], COUNT(*) FROM dbo.[User] GROUP BY [userType];';
PRINT '  SELECT * FROM dbo.gymmaster;  SELECT * FROM dbo.gymmasterdetail;';
PRINT '  SELECT * FROM dbo.financemaster; SELECT * FROM dbo.payrollmaster;';

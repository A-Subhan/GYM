-- ============================================================================
-- 10d_master_data_migration.sql
-- ============================================================================
-- Step 4: Migrate legacy master data into the new master/detail tables.
-- 4a. Exercise -> gymmaster category '001' + gymmasterdetail items
--     (Exercise table renamed to Exercise_legacy_bak, NOT dropped).
-- 4b. MasterFile (Banks/CardTypes) -> financemaster '001'/'002'.
-- 4c. payrollmasterfile -> payrollmaster categories + items.
-- 4d. gymmasterfile -> gymmaster categories + items.
-- Idempotent: each block checks IF OBJECT_ID and WHERE NOT EXISTS.
-- ============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

PRINT N'=== STEP 4: master data migration ===';

-- 4a. Exercise -> gymmaster '001'
IF OBJECT_ID(N'dbo.Exercise', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.gymmaster', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.gymmasterdetail', N'U') IS NOT NULL
BEGIN
    BEGIN TRY
        BEGIN TRAN;

        -- Insert the '001' Exercises category if missing
        IF NOT EXISTS (SELECT 1 FROM [dbo].[gymmaster] WHERE [id] = N'001')
            INSERT INTO [dbo].[gymmaster] ([id], [name], [description], [branchId], [isActive], [createdAt], [updatedAt])
            VALUES (N'001', N'Exercises', N'Exercise catalog (migrated from Exercise table)', NULL, 1, SYSDATETIME(), SYSDATETIME());

        -- Migrate exercise rows -> gymmasterdetail (codes 001001, 001002, ...)
        INSERT INTO [dbo].[gymmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt])
        SELECT N'001' + RIGHT(N'00' + CAST(x.rn AS NVARCHAR(10)), 3),
               N'001', x.[name], x.[instructions], x.[branchId],
               CASE WHEN x.[status] = N'Active' THEN 1 ELSE 0 END, x.[createdAt], x.[updatedAt]
        FROM (
            SELECT [id], [name], [instructions], [branchId], [status], [createdAt], [updatedAt],
                   ROW_NUMBER() OVER (ORDER BY [code], [id]) AS rn
            FROM [dbo].[Exercise]
        ) x
        WHERE NOT EXISTS (
            SELECT 1 FROM [dbo].[gymmasterdetail] d
            WHERE d.[id] = N'001' + RIGHT(N'00' + CAST(x.rn AS NVARCHAR(10)), 3)
        );

        -- Remap WorkoutDayExercise.exerciseId
        IF OBJECT_ID('dbo.WorkoutDayExercise','U') IS NOT NULL
        BEGIN
            UPDATE wde SET [exerciseId] = N'001' + RIGHT(N'00' + CAST(x.rn AS NVARCHAR(10)), 3)
            FROM [dbo].[WorkoutDayExercise] wde
            JOIN (
                SELECT [id], ROW_NUMBER() OVER (ORDER BY [code], [id]) AS rn
                FROM [dbo].[Exercise]
            ) x ON wde.[exerciseId] = x.[id];
        END

        -- Retarget the FK: drop old (pointing at Exercise), add new (-> gymmasterdetail)
        IF OBJECT_ID('dbo.WorkoutDayExercise','U') IS NOT NULL
        BEGIN
            DECLARE @oldfk NVARCHAR(256);
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

        -- Rename Exercise -> Exercise_legacy_bak (do NOT drop)
        IF OBJECT_ID('dbo.Exercise_legacy_bak','U') IS NULL
            EXEC sp_rename N'dbo.Exercise', N'Exercise_legacy_bak';

        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'4a-Exercise-migrate', N'OK', N'Exercise migrated to gymmasterdetail; Exercise renamed to Exercise_legacy_bak');
        PRINT N'  4a-Exercise-migrate: OK - Exercise migrated to gymmasterdetail; Exercise renamed to Exercise_legacy_bak';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'4a-Exercise-migrate', N'FAILED', ERROR_MESSAGE());
        PRINT N'  4a-Exercise-migrate: FAILED - ' + ERROR_MESSAGE();
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'4a-Exercise-migrate', N'SKIPPED', N'Exercise gone or master tables not ready');
    PRINT N'  4a-Exercise-migrate: SKIPPED - Exercise gone or master tables not ready';
END
GO

-- 4b. MasterFile (Banks/CardTypes) -> financemaster
SET NOCOUNT ON; SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.MasterFile', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.financemaster', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.financemasterdetail', N'U') IS NOT NULL
BEGIN
    BEGIN TRY
        BEGIN TRAN;

        IF NOT EXISTS (SELECT 1 FROM [dbo].[financemaster] WHERE [id] = N'001')
            INSERT INTO [dbo].[financemaster] ([id],[name],[description],[branchId],[isActive],[createdAt],[updatedAt])
            VALUES (N'001', N'Banks', N'Bank master (bank transfer payments)', NULL, 1, SYSDATETIME(), SYSDATETIME());

        IF NOT EXISTS (SELECT 1 FROM [dbo].[financemaster] WHERE [id] = N'002')
            INSERT INTO [dbo].[financemaster] ([id],[name],[description],[branchId],[isActive],[createdAt],[updatedAt])
            VALUES (N'002', N'Card Types', N'Card type master (card payments)', NULL, 1, SYSDATETIME(), SYSDATETIME());

        INSERT INTO [dbo].[financemasterdetail] ([id],[masterId],[name],[description],[branchId],[isActive],[createdAt],[updatedAt])
        SELECT
            CASE src.[masterType] WHEN N'Banks' THEN N'001' ELSE N'002' END
                + RIGHT(N'00' + CAST(src.rn AS NVARCHAR(10)), 3),
            CASE src.[masterType] WHEN N'Banks' THEN N'001' ELSE N'002' END,
            src.[name], src.[description], src.[branchId], src.[isActive], SYSDATETIME(), SYSDATETIME()
        FROM (
            SELECT mf.*, ROW_NUMBER() OVER (PARTITION BY mf.[masterType] ORDER BY mf.[code], mf.[name]) AS rn
            FROM [dbo].[MasterFile] mf
            WHERE mf.[masterType] IN (N'Banks', N'CardTypes') AND mf.[isActive] = 1
        ) src
        WHERE NOT EXISTS (
            SELECT 1 FROM [dbo].[financemasterdetail] d
            WHERE d.[masterId] = CASE src.[masterType] WHEN N'Banks' THEN N'001' ELSE N'002' END
              AND d.[name] = src.[name]
        );

        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'4b-MasterFile-finance', N'OK', N'Banks/CardTypes copied into financemaster');
        PRINT N'  4b-MasterFile-finance: OK - Banks/CardTypes copied into financemaster';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'4b-MasterFile-finance', N'FAILED', ERROR_MESSAGE());
        PRINT N'  4b-MasterFile-finance: FAILED - ' + ERROR_MESSAGE();
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'4b-MasterFile-finance', N'SKIPPED', N'MasterFile or financemaster tables missing');
    PRINT N'  4b-MasterFile-finance: SKIPPED - MasterFile or financemaster tables missing';
END
GO

-- 4c. payrollmasterfile -> payrollmaster
SET NOCOUNT ON; SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.payrollmasterfile', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.payrollmaster', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.payrollmasterdetail', N'U') IS NOT NULL
BEGIN
    BEGIN TRY
        BEGIN TRAN;

        INSERT INTO [dbo].[payrollmaster] ([id],[name],[description],[branchId],[isActive],[createdAt],[updatedAt])
        SELECT RIGHT(N'00' + CAST(cats.rn AS NVARCHAR(10)), 3),
               cats.[masterType], N'Migrated from payrollmasterfile', NULL, 1, SYSDATETIME(), SYSDATETIME()
        FROM (
            SELECT DISTINCT [masterType], ROW_NUMBER() OVER (ORDER BY [masterType]) AS rn
            FROM [dbo].[payrollmasterfile]
        ) cats
        WHERE NOT EXISTS (SELECT 1 FROM [dbo].[payrollmaster] m WHERE m.[name] = cats.[masterType]);

        INSERT INTO [dbo].[payrollmasterdetail] ([id],[masterId],[name],[description],[branchId],[isActive],[createdAt],[updatedAt])
        SELECT
            RIGHT(N'00' + CAST(items.catRn AS NVARCHAR(10)), 3)
                + RIGHT(N'00' + CAST(items.rn AS NVARCHAR(10)), 3),
            RIGHT(N'00' + CAST(items.catRn AS NVARCHAR(10)), 3),
            items.[itemName], items.[description], items.[branchId], items.[isActive], SYSDATETIME(), SYSDATETIME()
        FROM (
            SELECT
                p.[name] AS itemName, p.[description], p.[branchId], p.[isActive],
                cats.rn AS catRn,
                ROW_NUMBER() OVER (PARTITION BY p.[masterType] ORDER BY p.[name]) AS rn
            FROM [dbo].[payrollmasterfile] p
            JOIN (
                SELECT DISTINCT [masterType], ROW_NUMBER() OVER (ORDER BY [masterType]) AS rn
                FROM [dbo].[payrollmasterfile]
            ) cats ON cats.[masterType] = p.[masterType]
        ) items
        WHERE NOT EXISTS (
            SELECT 1 FROM [dbo].[payrollmasterdetail] d
            WHERE d.[masterId] = RIGHT(N'00' + CAST(items.catRn AS NVARCHAR(10)), 3)
              AND d.[name] = items.[itemName]
        );

        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'4c-payrollmasterfile', N'OK', N'payrollmasterfile copied into payrollmaster');
        PRINT N'  4c-payrollmasterfile: OK - payrollmasterfile copied into payrollmaster';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'4c-payrollmasterfile', N'FAILED', ERROR_MESSAGE());
        PRINT N'  4c-payrollmasterfile: FAILED - ' + ERROR_MESSAGE();
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'4c-payrollmasterfile', N'SKIPPED', N'payrollmasterfile or payrollmaster tables missing');
    PRINT N'  4c-payrollmasterfile: SKIPPED - payrollmasterfile or payrollmaster tables missing';
END
GO

-- 4d. gymmasterfile -> gymmaster
SET NOCOUNT ON; SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.gymmasterfile', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.gymmaster', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.gymmasterdetail', N'U') IS NOT NULL
   AND COL_LENGTH('dbo.gymmasterfile','level') IS NOT NULL
   AND COL_LENGTH('dbo.gymmasterfile','parentCode') IS NOT NULL
BEGIN
    BEGIN TRY
        BEGIN TRAN;

        -- Categories (level = 1)
        INSERT INTO [dbo].[gymmaster] ([id],[name],[description],[branchId],[isActive],[createdAt],[updatedAt])
        SELECT RIGHT(N'00' + CAST(cats.rn AS NVARCHAR(10)), 3),
               cats.[name], N'Migrated from gymmasterfile', NULL, 1, SYSDATETIME(), SYSDATETIME()
        FROM (
            SELECT [id] AS oldCode, [name], ROW_NUMBER() OVER (ORDER BY [id]) AS rn
            FROM [dbo].[gymmasterfile] WHERE [level] = 1
        ) cats
        WHERE NOT EXISTS (SELECT 1 FROM [dbo].[gymmaster] m WHERE m.[name] = cats.[name]);

        -- Items (level = 2)
        INSERT INTO [dbo].[gymmasterdetail] ([id],[masterId],[name],[description],[branchId],[isActive],[createdAt],[updatedAt])
        SELECT
            RIGHT(N'00' + CAST(items.catRn AS NVARCHAR(10)), 3)
                + RIGHT(N'00' + CAST(items.rn AS NVARCHAR(10)), 3),
            RIGHT(N'00' + CAST(items.catRn AS NVARCHAR(10)), 3),
            items.[name], items.[description], items.[branchId], items.[isActive], SYSDATETIME(), SYSDATETIME()
        FROM (
            SELECT
                g.[name], g.[branchId], g.[isActive], g.[description],
                cats.rn AS catRn,
                ROW_NUMBER() OVER (PARTITION BY g.[parentCode] ORDER BY g.[id]) AS rn
            FROM [dbo].[gymmasterfile] g
            JOIN (
                SELECT [id] AS oldCode, ROW_NUMBER() OVER (ORDER BY [id]) AS rn
                FROM [dbo].[gymmasterfile] WHERE [level] = 1
            ) cats ON cats.[oldCode] = g.[parentCode]
            WHERE g.[level] = 2
        ) items
        WHERE NOT EXISTS (
            SELECT 1 FROM [dbo].[gymmasterdetail] d
            WHERE d.[masterId] = RIGHT(N'00' + CAST(items.catRn AS NVARCHAR(10)), 3)
              AND d.[name] = items.[name]
        );

        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'4d-gymmasterfile', N'OK', N'gymmasterfile copied into gymmaster');
        PRINT N'  4d-gymmasterfile: OK - gymmasterfile copied into gymmaster';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'4d-gymmasterfile', N'FAILED', ERROR_MESSAGE());
        PRINT N'  4d-gymmasterfile: FAILED - ' + ERROR_MESSAGE();
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'4d-gymmasterfile', N'SKIPPED', N'gymmasterfile or gymmaster tables missing, or level/parentCode column missing');
    PRINT N'  4d-gymmasterfile: SKIPPED - gymmasterfile or gymmaster tables missing, or level/parentCode column missing';
END
GO

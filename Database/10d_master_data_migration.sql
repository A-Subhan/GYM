USE GymDB;
GO

-- ============================================================================
-- 10d_master_data_migration.sql
-- ============================================================================
-- Step 4: Migrate legacy master data into the new master/detail tables.
-- 4a2. Exercise -> gymmaster category '001' + gymmasterdetail items
--      (Exercise table renamed to Exercise_legacy_bak, NOT dropped).
--      FIX: drop FK WorkoutDayExercise_exerciseId_fkey BEFORE updating
--      exerciseId, then add new FK to gymmasterdetail(id).
-- 4b. MasterFile (Banks/CardTypes) -> financemaster '001'/'002'.
-- 4c. payrollmasterfile -> payrollmaster categories + items.
-- 4d. gymmasterfile -> gymmaster categories + items.
-- Idempotent: each block checks IF OBJECT_ID and WHERE NOT EXISTS.
-- Step name 4a2 replaces the old 4a (which FAILED on rerun due to FK order).
-- ============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

PRINT N'=== STEP 4: master data migration ===';

-- 4a2. Exercise -> gymmaster '001'
--     Order of operations (safe):
--       1. Copy Exercise rows into gymmaster '001' + gymmasterdetail (mapping table).
--       2. Drop the FK WorkoutDayExercise_exerciseId_fkey (pointing at Exercise).
--       3. Update WorkoutDayExercise.exerciseId using the mapping.
--       4. Add new FK -> gymmasterdetail(id).
--       5. Verify row counts (Exercise count = migrated count, no orphan exerciseId).
--       6. Rename Exercise -> Exercise_legacy_bak (do NOT DROP).
IF OBJECT_ID(N'dbo.Exercise', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.gymmaster', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.gymmasterdetail', N'U') IS NOT NULL
BEGIN
    BEGIN TRY
        SET XACT_ABORT ON;
        BEGIN TRAN;

        -- Step 1: Insert the '001' Exercises category if missing
        IF NOT EXISTS (SELECT 1 FROM [dbo].[gymmaster] WHERE [id] = N'001')
            INSERT INTO [dbo].[gymmaster] ([id], [name], [description], [branchId], [isActive], [createdAt], [updatedAt])
            VALUES (N'001', N'Exercises', N'Exercise catalog (migrated from Exercise table)', NULL, 1, SYSDATETIME(), SYSDATETIME());

        -- Step 1b: Copy Exercise rows into gymmasterdetail with a mapping temp table.
        -- The mapping allows us to remap WorkoutDayExercise.exerciseId after the FK is dropped.
        IF OBJECT_ID('tempdb..#ex_map', 'U') IS NOT NULL DROP TABLE #ex_map;
        CREATE TABLE #ex_map (old_id NVARCHAR(50), new_code NVARCHAR(50));

        INSERT INTO #ex_map (old_id, new_code)
        SELECT e.[id], N'001' + RIGHT(N'00' + CAST(e.rn AS NVARCHAR(10)), 3)
        FROM (
            SELECT [id], ROW_NUMBER() OVER (ORDER BY [code], [id]) AS rn
            FROM [dbo].[Exercise]
        ) e;

        -- Insert into gymmasterdetail (skip rows that already exist from a previous partial run)
        INSERT INTO [dbo].[gymmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt])
        SELECT
            m.new_code,
            N'001',
            ex.[name],
            ex.[instructions],
            ex.[branchId],
            CASE WHEN ex.[status] = N'Active' THEN 1 ELSE 0 END,
            ex.[createdAt],
            ex.[updatedAt]
        FROM #ex_map m
        JOIN [dbo].[Exercise] ex ON ex.[id] = m.old_id
        WHERE NOT EXISTS (
            SELECT 1 FROM [dbo].[gymmasterdetail] d WHERE d.[id] = m.new_code
        );

        -- Step 2: Drop the FK WorkoutDayExercise -> Exercise (MUST happen before UPDATE)
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
                PRINT N'  4a2: dropped old FK [' + @oldfk + N']';
            END
        END

        -- Step 3: Update WorkoutDayExercise.exerciseId using the mapping
        IF OBJECT_ID('dbo.WorkoutDayExercise','U') IS NOT NULL
        BEGIN
            UPDATE wde SET [exerciseId] = m.new_code
            FROM [dbo].[WorkoutDayExercise] wde
            JOIN #ex_map m ON wde.[exerciseId] = m.old_id;
            PRINT N'  4a2: updated WorkoutDayExercise.exerciseId';
        END

        -- Step 4: Add new FK -> gymmasterdetail(id)
        IF OBJECT_ID('dbo.WorkoutDayExercise','U') IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'WorkoutDayExercise_exerciseId_fkey')
        BEGIN
            DECLARE @addfk NVARCHAR(MAX) = N'ALTER TABLE [dbo].[WorkoutDayExercise] ADD CONSTRAINT [WorkoutDayExercise_exerciseId_fkey] FOREIGN KEY ([exerciseId]) REFERENCES [dbo].[gymmasterdetail]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION';
            EXEC sp_executesql @addfk;
            PRINT N'  4a2: added new FK WorkoutDayExercise_exerciseId_fkey -> gymmasterdetail(id)';
        END

        -- Step 5: Verify row counts
        DECLARE @exCount INT, @migCount INT, @orphanCount INT;
        SELECT @exCount = COUNT(*) FROM [dbo].[Exercise];
        SELECT @migCount = COUNT(*) FROM [dbo].[gymmasterdetail] WHERE [masterId] = N'001';

        IF OBJECT_ID('dbo.WorkoutDayExercise','U') IS NOT NULL
            SELECT @orphanCount = COUNT(*) FROM [dbo].[WorkoutDayExercise] wde
            WHERE NOT EXISTS (SELECT 1 FROM [dbo].[gymmasterdetail] g WHERE g.[id] = wde.[exerciseId]);
        ELSE
            SET @orphanCount = 0;

        IF @orphanCount > 0
        BEGIN
            -- Orphaned exerciseId values - do NOT rename, rollback
            DECLARE @orphanMsg NVARCHAR(MAX) = N'Orphaned exerciseId rows: ' + CAST(@orphanCount AS NVARCHAR(10));
            RAISERROR(@orphanMsg, 16, 1);
        END

        PRINT N'  4a2: Exercise count=' + CAST(@exCount AS NVARCHAR(10)) + N', migrated count=' + CAST(@migCount AS NVARCHAR(10)) + N', orphans=' + CAST(@orphanCount AS NVARCHAR(10));

        -- Step 6: Rename Exercise -> Exercise_legacy_bak (do NOT drop)
        IF OBJECT_ID('dbo.Exercise_legacy_bak','U') IS NULL
            EXEC sp_rename N'dbo.Exercise', N'Exercise_legacy_bak';

        DROP TABLE #ex_map;

        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'4a2-Exercise-migrate', N'OK', N'Exercise migrated to gymmasterdetail; Exercise renamed to Exercise_legacy_bak (count=' + CAST(@exCount AS NVARCHAR(10)) + N', migrated=' + CAST(@migCount AS NVARCHAR(10)) + N')');
        PRINT N'  4a2-Exercise-migrate: OK - Exercise migrated to gymmasterdetail; Exercise renamed to Exercise_legacy_bak';
    END TRY
    BEGIN CATCH
        IF OBJECT_ID('tempdb..#ex_map', 'U') IS NOT NULL DROP TABLE #ex_map;
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'4a2-Exercise-migrate', N'FAILED', ERROR_MESSAGE());
        PRINT N'  4a2-Exercise-migrate: FAILED - ' + ERROR_MESSAGE();
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'4a2-Exercise-migrate', N'SKIPPED', N'Exercise gone or master tables not ready');
    PRINT N'  4a2-Exercise-migrate: SKIPPED - Exercise gone or master tables not ready';
END
GO

-- 4b. MasterFile (Banks/CardTypes) -> financemaster
USE GymDB;
GO
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
USE GymDB;
GO
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
USE GymDB;
GO
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

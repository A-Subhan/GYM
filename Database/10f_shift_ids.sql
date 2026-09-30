USE GymDB;
GO

-- ============================================================================
-- 10f_shift_ids.sql
-- ============================================================================
-- Step 6: Shift id renumbering — cuid/legacy ids -> 001, 002, 003, ...
-- Two-phase: (a) remap Staff.shiftId via temp table, (b) renumber Shift.id
-- by renaming the old table and inserting fresh rows.
-- Old Shift table saved as Shift_legacy_bak (NOT dropped).
-- Idempotent: if all ids are already 3-digit, SKIPS.
-- ============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

PRINT N'=== STEP 6: Shift id renumbering ===';

-- Preflight
IF OBJECT_ID('dbo.Shift','U') IS NOT NULL
BEGIN
    DECLARE @pf_shift_bad INT = 0;
    SELECT @pf_shift_bad = COUNT(*) FROM dbo.Shift WHERE [id] NOT LIKE N'[0-9][0-9][0-9]';
    PRINT N'  preflight: ' + CAST(@pf_shift_bad AS NVARCHAR(10)) + N' Shift rows with non-3-digit ids';
END
ELSE
    PRINT N'  preflight: Shift table MISSING';

IF OBJECT_ID('dbo.Shift','U') IS NOT NULL
BEGIN
    IF EXISTS (SELECT 1 FROM dbo.Shift WHERE [id] NOT LIKE N'[0-9][0-9][0-9]')
    BEGIN
        BEGIN TRY
            SET XACT_ABORT ON;
            BEGIN TRAN;

            -- 6a. Build the old_id -> new_id map into a temp table.
            IF OBJECT_ID('tempdb..#shift_map', 'U') IS NOT NULL DROP TABLE #shift_map;
            CREATE TABLE #shift_map (old_id NVARCHAR(50), new_id NVARCHAR(50));
            ;WITH s AS (
                SELECT [id], ROW_NUMBER() OVER (ORDER BY [name], [id]) AS rn
                FROM dbo.Shift
            )
            INSERT INTO #shift_map (old_id, new_id)
            SELECT [id], RIGHT(N'00' + CAST(rn AS NVARCHAR(10)), 3) FROM s;

            -- 6b. Remap Staff.shiftId
            IF COL_LENGTH('dbo.Staff','shiftId') IS NOT NULL
            BEGIN
                DECLARE @remap_sql NVARCHAR(MAX) = N'UPDATE s SET s.[shiftId] = m.new_id
                    FROM [dbo].[Staff] s
                    JOIN #shift_map m ON s.[shiftId] = m.old_id
                    WHERE s.[shiftId] IS NOT NULL';
                EXEC sp_executesql @remap_sql;
            END

            -- 6c. Drop Staff_shiftId_fkey (will re-add after renumber)
            IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'Staff_shiftId_fkey')
            BEGIN
                DECLARE @drop_sfk NVARCHAR(MAX) = N'ALTER TABLE [dbo].[Staff] DROP CONSTRAINT [Staff_shiftId_fkey]';
                EXEC sp_executesql @drop_sfk;
            END

            -- 6d. Drop Shift_branchId_fkey (if any) so we can rebuild Shift
            IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'Shift_branchId_fkey')
            BEGIN
                DECLARE @drop_sbr NVARCHAR(MAX) = N'ALTER TABLE [dbo].[Shift] DROP CONSTRAINT [Shift_branchId_fkey]';
                EXEC sp_executesql @drop_sbr;
            END

            -- 6e. Build the new Shift rows in a temp table.
            IF OBJECT_ID('tempdb..#shift_new', 'U') IS NOT NULL DROP TABLE #shift_new;
            SELECT m.new_id AS [id], s.[name], s.[timeIn], s.[timeOut], s.[workingDays],
                   s.[branchId], s.[isActive], s.[createdAt], s.[updatedAt]
            INTO #shift_new
            FROM dbo.Shift s JOIN #shift_map m ON s.[id] = m.old_id;

            -- 6f. Rename old Shift -> Shift_legacy_bak (do NOT drop)
            IF OBJECT_ID('dbo.Shift_legacy_bak','U') IS NULL
                EXEC sp_rename N'dbo.Shift', N'Shift_legacy_bak';

            -- 6g. Create fresh Shift table with the same structure and insert new rows.
            -- Use SELECT INTO to clone the structure of #shift_new, then rename.
            SELECT * INTO dbo.Shift FROM #shift_new WHERE 1=0;
            INSERT INTO dbo.Shift SELECT * FROM #shift_new;

            -- 6h. Re-add PK
            ALTER TABLE [dbo].[Shift] ADD CONSTRAINT [Shift_pkey] PRIMARY KEY CLUSTERED ([id]);

            -- 6i. Re-add Shift.branchId FK
            IF COL_LENGTH('dbo.Shift','branchId') IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'Shift_branchId_fkey')
            BEGIN
                DECLARE @add_sbr NVARCHAR(MAX) = N'ALTER TABLE [dbo].[Shift] ADD CONSTRAINT [Shift_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION';
                EXEC sp_executesql @add_sbr;
            END

            -- 6j. Re-add Staff.shiftId FK
            IF COL_LENGTH('dbo.Staff','shiftId') IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'Staff_shiftId_fkey')
            BEGIN
                DECLARE @add_ss NVARCHAR(MAX) = N'ALTER TABLE [dbo].[Staff] ADD CONSTRAINT [Staff_shiftId_fkey] FOREIGN KEY ([shiftId]) REFERENCES [dbo].[Shift]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION';
                EXEC sp_executesql @add_ss;
            END

            DROP TABLE #shift_map;
            DROP TABLE #shift_new;

            COMMIT TRAN;
            INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'6-Shift-renumber', N'OK', N'Shift ids renumbered to 001/002/003; old table saved as Shift_legacy_bak');
            PRINT N'  6-Shift-renumber: OK - Shift ids renumbered to 001/002/003; old table saved as Shift_legacy_bak';
        END TRY
        BEGIN CATCH
            IF OBJECT_ID('tempdb..#shift_map', 'U') IS NOT NULL DROP TABLE #shift_map;
            IF OBJECT_ID('tempdb..#shift_new', 'U') IS NOT NULL DROP TABLE #shift_new;
            IF @@TRANCOUNT > 0 ROLLBACK TRAN;
            INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'6-Shift-renumber', N'FAILED', ERROR_MESSAGE());
            PRINT N'  6-Shift-renumber: FAILED - ' + ERROR_MESSAGE();
        END CATCH
    END
    ELSE
    BEGIN
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'6-Shift-renumber', N'SKIPPED', N'All Shift ids already 3-digit');
        PRINT N'  6-Shift-renumber: SKIPPED - All Shift ids already 3-digit';
    END
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'6-Shift-renumber', N'SKIPPED', N'Shift table missing');
    PRINT N'  6-Shift-renumber: SKIPPED - Shift table missing';
END
GO

USE GymDB;
GO

-- ============================================================================
-- 10f_shift_ids.sql
-- ============================================================================
-- Step 6b: Shift id renumbering — legacy ids -> 001, 002, 003 ...
-- Old step name 6 never logged OK due to Msg 3930 in CATCH.
-- Step name: 6b-shift-ids.
--
-- Root cause of old Msg 3930 at line 115:
--   With SET XACT_ABORT ON, a doomed transaction (XACT_STATE() = -1) cannot
--   write to the log. The old CATCH used @@TRANCOUNT > 0 ROLLBACK (wrong
--   for doomed txns) then tried INSERT INTO _UpgradeLog before the rollback
--   was complete.
--   Fix: CATCH captures ERROR_NUMBER/LINE/MESSAGE first, then
--   IF XACT_STATE() <> 0 ROLLBACK TRAN, then INSERT + PRINT.
--
-- Safe order of operations:
--   a. Save FK definitions referencing Shift, then DROP them.
--   b. Build mapping old id -> new 3-digit id (ordered by createdAt, id).
--   c. Remap Staff.shiftId through the mapping (no FK enforced yet).
--   d. Build new Shift rows in #shift_new with new ids.
--   e. Rename old Shift -> Shift_legacy_bak (never DROP).
--   f. Create fresh Shift table with new ids.
--   g. Recreate PK on Shift.id.
--   h. Recreate FKs with original names and actions.
--   i. Verify: no orphan Staff.shiftId, all Shift ids are 3-digit.
--   j. COMMIT only after verification.
-- ============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

PRINT N'=== STEP 6b: Shift id renumbering ===';

-- Preflight
IF OBJECT_ID('dbo.Shift','U') IS NOT NULL
BEGIN
    DECLARE @pf_shift_bad INT = 0;
    SELECT @pf_shift_bad = COUNT(*) FROM dbo.Shift WHERE [id] NOT LIKE N'[0-9][0-9][0-9]';
    PRINT N'  preflight: ' + CAST(@pf_shift_bad AS NVARCHAR(10)) + N' Shift rows with non-3-digit ids';
END
ELSE
    PRINT N'  preflight: Shift table MISSING';

DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);

IF OBJECT_ID('dbo.Shift','U') IS NOT NULL
BEGIN
    IF EXISTS (SELECT 1 FROM dbo.Shift WHERE [id] NOT LIKE N'[0-9][0-9][0-9]')
    BEGIN
        BEGIN TRY
            SET XACT_ABORT ON;
            BEGIN TRAN;

            -- 6b-a. Save FK definitions referencing Shift, then drop them.
            IF OBJECT_ID('tempdb..#shift_fks', 'U') IS NOT NULL DROP TABLE #shift_fks;
            CREATE TABLE #shift_fks (
                fk_name NVARCHAR(256),
                parent_table NVARCHAR(128),
                parent_col NVARCHAR(128),
                on_delete NVARCHAR(20),
                on_update NVARCHAR(20)
            );

            INSERT INTO #shift_fks (fk_name, parent_table, parent_col, on_delete, on_update)
            SELECT
                fk.name,
                OBJECT_NAME(fk.parent_object_id),
                COL_NAME(fkc.parent_object_id, fkc.parent_column_id),
                fk.delete_referential_action_desc,
                fk.update_referential_action_desc
            FROM sys.foreign_keys fk
            JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
            WHERE fk.referenced_object_id = OBJECT_ID('dbo.Shift');

            DECLARE @sfk_name NVARCHAR(256), @sfk_parent NVARCHAR(128);
            DECLARE @drop_sfk_sql NVARCHAR(MAX);
            DECLARE drop_sfk_cur CURSOR LOCAL FAST_FORWARD FOR
                SELECT DISTINCT fk_name, parent_table FROM #shift_fks;

            OPEN drop_sfk_cur;
            FETCH NEXT FROM drop_sfk_cur INTO @sfk_name, @sfk_parent;
            WHILE @@FETCH_STATUS = 0
            BEGIN
                SET @drop_sfk_sql = N'ALTER TABLE [dbo].' + QUOTENAME(@sfk_parent)
                    + N' DROP CONSTRAINT [' + @sfk_name + N']';
                EXEC sp_executesql @drop_sfk_sql;
                PRINT N'  6b: dropped FK [' + @sfk_name + N'] on [' + @sfk_parent + N']';
                FETCH NEXT FROM drop_sfk_cur INTO @sfk_name, @sfk_parent;
            END
            CLOSE drop_sfk_cur;
            DEALLOCATE drop_sfk_cur;

            -- 6b-b. Build the old_id -> new_id mapping.
            IF OBJECT_ID('tempdb..#shift_map', 'U') IS NOT NULL DROP TABLE #shift_map;
            CREATE TABLE #shift_map (old_id NVARCHAR(50), new_id NVARCHAR(50));
            INSERT INTO #shift_map (old_id, new_id)
            SELECT [id], RIGHT(N'00' + CAST(rn AS NVARCHAR(10)), 3)
            FROM (
                SELECT [id], ROW_NUMBER() OVER (ORDER BY [createdAt], [id]) AS rn
                FROM dbo.Shift
            ) x;

            -- 6b-c. Remap Staff.shiftId through the mapping (FK is dropped).
            IF COL_LENGTH('dbo.Staff','shiftId') IS NOT NULL
            BEGIN
                UPDATE s SET s.[shiftId] = m.new_id
                FROM [dbo].[Staff] s
                JOIN #shift_map m ON s.[shiftId] = m.old_id
                WHERE s.[shiftId] IS NOT NULL;
                PRINT N'  6b: remapped Staff.shiftId';
            END

            -- 6b-d. Build new Shift rows.
            IF OBJECT_ID('tempdb..#shift_new', 'U') IS NOT NULL DROP TABLE #shift_new;
            SELECT m.new_id AS [id], s.[name], s.[timeIn], s.[timeOut], s.[workingDays],
                   s.[branchId], s.[isActive], s.[createdAt], s.[updatedAt]
            INTO #shift_new
            FROM dbo.Shift s JOIN #shift_map m ON s.[id] = m.old_id;

            -- 6b-e. Rename old Shift -> Shift_legacy_bak (never DROP).
            IF OBJECT_ID('dbo.Shift_legacy_bak','U') IS NULL
                EXEC sp_rename N'dbo.Shift', N'Shift_legacy_bak';

            -- 6b-f. Create fresh Shift table.
            SELECT * INTO dbo.Shift FROM #shift_new WHERE 1=0;
            INSERT INTO dbo.Shift SELECT * FROM #shift_new;

            -- 6b-g. Recreate PK.
            ALTER TABLE [dbo].[Shift] ADD CONSTRAINT [Shift_pkey] PRIMARY KEY CLUSTERED ([id]);

            -- 6b-h. Recreate FKs with original names and actions.
            DECLARE @cfk_name NVARCHAR(256), @cfk_tbl NVARCHAR(128), @cfk_col NVARCHAR(128);
            DECLARE @cfk_del NVARCHAR(20), @cfk_upd NVARCHAR(20);
            DECLARE @add_sfk_sql NVARCHAR(MAX);
            DECLARE add_sfk_cur CURSOR LOCAL FAST_FORWARD FOR
                SELECT DISTINCT fk_name, parent_table, parent_col, on_delete, on_update FROM #shift_fks;

            OPEN add_sfk_cur;
            FETCH NEXT FROM add_sfk_cur INTO @cfk_name, @cfk_tbl, @cfk_col, @cfk_del, @cfk_upd;
            WHILE @@FETCH_STATUS = 0
            BEGIN
                IF OBJECT_ID('dbo.' + QUOTENAME(@cfk_tbl), 'U') IS NOT NULL
                   AND COL_LENGTH('dbo.' + QUOTENAME(@cfk_tbl), @cfk_col) IS NOT NULL
                   AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = @cfk_name)
                BEGIN
                    DECLARE @del_action NVARCHAR(20) = REPLACE(@cfk_del, N'_', N' ');
                    DECLARE @upd_action NVARCHAR(20) = REPLACE(@cfk_upd, N'_', N' ');
                    IF @del_action = N'NO' SET @del_action = N'NO ACTION';
                    IF @upd_action = N'NO' SET @upd_action = N'NO ACTION';

                    SET @add_sfk_sql = N'ALTER TABLE [dbo].' + QUOTENAME(@cfk_tbl)
                        + N' ADD CONSTRAINT [' + @cfk_name + N'] FOREIGN KEY ([' + @cfk_col
                        + N']) REFERENCES [dbo].[Shift]([id]) ON DELETE ' + @del_action
                        + N' ON UPDATE ' + @upd_action;
                    EXEC sp_executesql @add_sfk_sql;
                    PRINT N'  6b: recreated FK [' + @cfk_name + N'] on [' + @cfk_tbl + N'].[' + @cfk_col + N']';
                END
                FETCH NEXT FROM add_sfk_cur INTO @cfk_name, @cfk_tbl, @cfk_col, @cfk_del, @cfk_upd;
            END
            CLOSE add_sfk_cur;
            DEALLOCATE add_sfk_cur;

            -- 6b-i. Verify: all Shift ids 3-digit, no orphan Staff.shiftId.
            DECLARE @v_bad_shift INT = 0;
            SELECT @v_bad_shift = COUNT(*) FROM dbo.Shift WHERE [id] NOT LIKE N'[0-9][0-9][0-9]';
            IF @v_bad_shift > 0
            BEGIN
                RAISERROR(N'Verification failed: %d Shift ids not 3-digit', 16, 1, @v_bad_shift);
            END

            IF COL_LENGTH('dbo.Staff','shiftId') IS NOT NULL
            BEGIN
                DECLARE @v_orphan_shift INT = 0;
                SELECT @v_orphan_shift = COUNT(*) FROM dbo.Staff s
                WHERE s.[shiftId] IS NOT NULL
                  AND NOT EXISTS (SELECT 1 FROM dbo.Shift sh WHERE sh.[id] = s.[shiftId]);
                IF @v_orphan_shift > 0
                BEGIN
                    RAISERROR(N'Verification failed: %d orphaned Staff.shiftId', 16, 1, @v_orphan_shift);
                END
            END

            PRINT N'  6b: verification OK (all 3-digit, no orphans)';

            DROP TABLE #shift_map;
            DROP TABLE #shift_new;
            DROP TABLE #shift_fks;

            COMMIT TRAN;
            INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'6b-shift-ids', N'OK', N'Shift ids renumbered to 001/002/003; old table saved as Shift_legacy_bak');
            PRINT N'  6b-shift-ids: OK - Shift ids renumbered to 001/002/003; old table saved as Shift_legacy_bak';
        END TRY
        BEGIN CATCH
            SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
            IF OBJECT_ID('tempdb..#shift_map', 'U') IS NOT NULL DROP TABLE #shift_map;
            IF OBJECT_ID('tempdb..#shift_new', 'U') IS NOT NULL DROP TABLE #shift_new;
            IF OBJECT_ID('tempdb..#shift_fks', 'U') IS NOT NULL DROP TABLE #shift_fks;
            IF XACT_STATE() <> 0 ROLLBACK TRAN;
            INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'6b-shift-ids', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
            PRINT N'  6b-shift-ids: FAILED - Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg;
        END CATCH
    END
    ELSE
    BEGIN
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'6b-shift-ids', N'SKIPPED', N'All Shift ids already 3-digit');
        PRINT N'  6b-shift-ids: SKIPPED - All Shift ids already 3-digit';
    END
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'6b-shift-ids', N'SKIPPED', N'Shift table missing');
    PRINT N'  6b-shift-ids: SKIPPED - Shift table missing';
END
GO

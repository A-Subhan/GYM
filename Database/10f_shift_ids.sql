USE GymDB;
GO

-- ============================================================================
-- 10f_shift_ids.sql
-- ============================================================================
-- Step 6c: Shift id renumbering — legacy ids -> 001, 002, 003 ...
-- In-place UPDATE (no table rebuild, no sp_rename).
--
-- Safe order of operations (in one transaction):
--   a. Save FK definitions referencing Shift (name, parent table, column,
--      ON DELETE/UPDATE actions) in a temp table, then DROP them.
--   b. Discover and drop the Shift PK by name.
--   c. Build mapping old id -> new 3-digit id (ORDER BY createdAt, id).
--   d. Two-phase UPDATE:
--      Phase 1: SET Shift.id = 'tmp_001', 'tmp_002', ... (unique temp values).
--      Phase 2: SET Shift.id = '001', '002', '003', ... (final values).
--   e. UPDATE Staff.shiftId and any other column referencing Shift through
--      the mapping.
--   f. ALTER COLUMN id NVARCHAR(50) NOT NULL (same type/collation).
--   g. Recreate PK with its original name.
--   h. Recreate FKs with original names and actions.
--   i. Verify: all Shift ids 3-digit, no orphan Staff.shiftId.
--   j. COMMIT only after verification.
--
-- Robust and re-runnable from ANY partial state:
--   - If FKs are already dropped (previous run failed after dropping), the
--     script discovers that and skips dropping.
--   - If PK is already dropped, skips dropping.
--   - If ids are already 3-digit, SKIPS the entire step.
--   - Uses temp values to avoid PK/FK conflicts during the UPDATE.
-- ============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

PRINT N'=== STEP 6c: Shift id renumbering ===';

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

            -- 6c-a. Save FK definitions referencing Shift, then drop them.
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
                IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = @sfk_name)
                BEGIN
                    SET @drop_sfk_sql = N'ALTER TABLE [dbo].' + QUOTENAME(@sfk_parent)
                        + N' DROP CONSTRAINT [' + @sfk_name + N']';
                    EXEC sp_executesql @drop_sfk_sql;
                    PRINT N'  6c: dropped FK [' + @sfk_name + N'] on [' + @sfk_parent + N']';
                END
                FETCH NEXT FROM drop_sfk_cur INTO @sfk_name, @sfk_parent;
            END
            CLOSE drop_sfk_cur;
            DEALLOCATE drop_sfk_cur;

            -- 6c-b. Discover and drop the Shift PK.
            DECLARE @shift_pk_name NVARCHAR(256);
            SELECT @shift_pk_name = name FROM sys.key_constraints
            WHERE type = N'PK' AND parent_object_id = OBJECT_ID('dbo.Shift');
            IF @shift_pk_name IS NOT NULL
            BEGIN
                DECLARE @drop_shift_pk NVARCHAR(MAX) = N'ALTER TABLE [dbo].[Shift] DROP CONSTRAINT [' + @shift_pk_name + N']';
                EXEC sp_executesql @drop_shift_pk;
                PRINT N'  6c: dropped PK [' + @shift_pk_name + N']';
            END
            ELSE
            BEGIN
                PRINT N'  6c: PK already absent (previous partial run?)';
                SET @shift_pk_name = N'Shift_pkey';  -- default name for recreation
            END

            -- 6c-c. Build the old_id -> new_id mapping.
            IF OBJECT_ID('tempdb..#shift_map', 'U') IS NOT NULL DROP TABLE #shift_map;
            CREATE TABLE #shift_map (old_id NVARCHAR(50), new_id NVARCHAR(50), tmp_id NVARCHAR(50));
            INSERT INTO #shift_map (old_id, new_id, tmp_id)
            SELECT
                [id],
                RIGHT(N'00' + CAST(rn AS NVARCHAR(10)), 3),
                N'tmp_' + RIGHT(N'00' + CAST(rn AS NVARCHAR(10)), 3)
            FROM (
                SELECT [id], ROW_NUMBER() OVER (ORDER BY [createdAt], [id]) AS rn
                FROM dbo.Shift
            ) x;

            -- 6c-d. Two-phase UPDATE: first to temp values, then to final.
            -- Phase 1: Update Shift.id to unique temp values (no PK to conflict with).
            UPDATE s SET s.[id] = m.tmp_id
            FROM dbo.Shift s
            JOIN #shift_map m ON s.[id] = m.old_id;
            PRINT N'  6c: phase 1 - updated Shift.id to temp values';

            -- Phase 2: Update Shift.id to final 3-digit values.
            UPDATE s SET s.[id] = m.new_id
            FROM dbo.Shift s
            JOIN #shift_map m ON s.[id] = m.tmp_id;
            PRINT N'  6c: phase 2 - updated Shift.id to final 3-digit values';

            -- 6c-e. Update Staff.shiftId and any other referencing column.
            IF COL_LENGTH('dbo.Staff','shiftId') IS NOT NULL
            BEGIN
                UPDATE st SET st.[shiftId] = m.new_id
                FROM [dbo].[Staff] st
                JOIN #shift_map m ON st.[shiftId] = m.old_id
                WHERE st.[shiftId] IS NOT NULL;
                PRINT N'  6c: remapped Staff.shiftId';
            END

            -- 6c-f. ALTER COLUMN id to NOT NULL (same type, NVARCHAR(50)).
            ALTER TABLE [dbo].[Shift] ALTER COLUMN [id] NVARCHAR(50) NOT NULL;
            PRINT N'  6c: altered Shift.id to NOT NULL';

            -- 6c-g. Recreate PK with its original name.
            IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE type=N'PK' AND parent_object_id=OBJECT_ID('dbo.Shift'))
            BEGIN
                DECLARE @add_pk_sql NVARCHAR(MAX) = N'ALTER TABLE [dbo].[Shift] ADD CONSTRAINT [' + @shift_pk_name + N'] PRIMARY KEY CLUSTERED ([id])';
                EXEC sp_executesql @add_pk_sql;
                PRINT N'  6c: recreated PK [' + @shift_pk_name + N']';
            END

            -- 6c-h. Recreate FKs with original names and actions.
            DECLARE @cfk_name NVARCHAR(256), @cfk_tbl NVARCHAR(128), @cfk_col NVARCHAR(128);
            DECLARE @cfk_del NVARCHAR(20), @cfk_upd NVARCHAR(20);
            DECLARE @add_cfk_sql NVARCHAR(MAX);
            DECLARE add_cfk_cur CURSOR LOCAL FAST_FORWARD FOR
                SELECT DISTINCT fk_name, parent_table, parent_col, on_delete, on_update FROM #shift_fks;

            OPEN add_cfk_cur;
            FETCH NEXT FROM add_cfk_cur INTO @cfk_name, @cfk_tbl, @cfk_col, @cfk_del, @cfk_upd;
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

                    SET @add_cfk_sql = N'ALTER TABLE [dbo].' + QUOTENAME(@cfk_tbl)
                        + N' ADD CONSTRAINT [' + @cfk_name + N'] FOREIGN KEY ([' + @cfk_col
                        + N']) REFERENCES [dbo].[Shift]([id]) ON DELETE ' + @del_action
                        + N' ON UPDATE ' + @upd_action;
                    EXEC sp_executesql @add_cfk_sql;
                    PRINT N'  6c: recreated FK [' + @cfk_name + N'] on [' + @cfk_tbl + N'].[' + @cfk_col + N']';
                END
                FETCH NEXT FROM add_cfk_cur INTO @cfk_name, @cfk_tbl, @cfk_col, @cfk_del, @cfk_upd;
            END
            CLOSE add_cfk_cur;
            DEALLOCATE add_cfk_cur;

            -- 6c-i. Verify: all Shift ids 3-digit, no orphan Staff.shiftId.
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

            PRINT N'  6c: verification OK (all 3-digit, no orphans)';

            DROP TABLE #shift_map;
            DROP TABLE #shift_fks;

            COMMIT TRAN;
            INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'6c-shift-ids', N'OK', N'Shift ids renumbered to 001/002/003 in-place; FKs recreated');
            PRINT N'  6c-shift-ids: OK - Shift ids renumbered to 001/002/003 in-place; FKs recreated';
        END TRY
        BEGIN CATCH
            SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
            IF OBJECT_ID('tempdb..#shift_map', 'U') IS NOT NULL DROP TABLE #shift_map;
            IF OBJECT_ID('tempdb..#shift_fks', 'U') IS NOT NULL DROP TABLE #shift_fks;
            IF XACT_STATE() <> 0 ROLLBACK TRAN;
            INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'6c-shift-ids', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
            PRINT N'  6c-shift-ids: FAILED - Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg;
        END CATCH
    END
    ELSE
    BEGIN
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'6c-shift-ids', N'SKIPPED', N'All Shift ids already 3-digit');
        PRINT N'  6c-shift-ids: SKIPPED - All Shift ids already 3-digit';
    END
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'6c-shift-ids', N'SKIPPED', N'Shift table missing');
    PRINT N'  6c-shift-ids: SKIPPED - Shift table missing';
END
GO

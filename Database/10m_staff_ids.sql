USE GymDB;
GO

-- ============================================================================
-- 10m_staff_ids.sql
-- ============================================================================
-- Step 12 (OPTIONAL): Pad existing Staff ids from 4 digits to 5 digits.
--
-- The backend (ids.ts makeEmployeeId) generates EMP-00001 (5 digits via
-- pad(seq, 5)). The seed data (06_master_data.sql) inserted EMP-0001
-- (4 digits). This script pads existing ids to 5 digits so they all
-- match the backend's format.
--
-- This script is OPTIONAL — the backend handles both 4 and 5 digit ids
-- gracefully (the maxSeq reconciliation in makeEmployeeId works with
-- any digit count). Run this only if you want all ids to be consistent.
--
-- Safe order of operations (in one transaction):
--   a. Save FK definitions referencing Staff, then DROP them.
--   b. Discover and drop Staff PK.
--   c. Build mapping old id -> new id (pad to 5 digits).
--   d. Two-phase UPDATE: old -> temp -> final.
--   e. Update child tables (Leave, Overtime, Payroll, TrainerAvailability,
--      TrainerSchedule, StaffDocument) staffId through mapping.
--   f. Update Member.assignedTrainerId through mapping.
--   g. ALTER COLUMN id NVARCHAR(50) NOT NULL.
--   h. Recreate PK with original name.
--   i. Recreate FKs with original names and actions.
--   j. Verify: no NULL ids, no duplicates, no orphans.
--   k. COMMIT.
-- ============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

PRINT N'=== STEP 12: Staff id padding (4 -> 5 digits) ===';

-- Preflight: check if any ids need padding
IF OBJECT_ID('dbo.Staff','U') IS NOT NULL
BEGIN
    DECLARE @pf_pad INT = 0;
    SELECT @pf_pad = COUNT(*) FROM dbo.Staff
    WHERE [id] LIKE N'EMP-[0-9][0-9][0-9][0-9]'
      AND [id] NOT LIKE N'EMP-[0-9][0-9][0-9][0-9][0-9]%';
    PRINT N'  preflight: ' + CAST(@pf_pad AS NVARCHAR(10)) + N' Staff ids need padding (4 digits)';

    IF @pf_pad = 0
    BEGIN
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'12-staff-ids', N'SKIPPED', N'All Staff ids already 5+ digits');
        PRINT N'  12-staff-ids: SKIPPED - All Staff ids already 5+ digits';
    END
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'12-staff-ids', N'SKIPPED', N'Staff table missing');
    PRINT N'  12-staff-ids: SKIPPED - Staff table missing';
END
GO

-- Main migration (only if there are 4-digit ids to pad)
USE GymDB;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);

IF OBJECT_ID('dbo.Staff','U') IS NOT NULL
   AND EXISTS (
       SELECT 1 FROM dbo.Staff
       WHERE [id] LIKE N'EMP-[0-9][0-9][0-9][0-9]'
         AND [id] NOT LIKE N'EMP-[0-9][0-9][0-9][0-9][0-9]%'
   )
BEGIN
    BEGIN TRY
        SET XACT_ABORT ON;
        BEGIN TRAN;

        -- 12-a. Save FK definitions referencing Staff, then DROP them.
        IF OBJECT_ID('tempdb..#staff_fks', 'U') IS NOT NULL DROP TABLE #staff_fks;
        CREATE TABLE #staff_fks (
            fk_name NVARCHAR(256),
            parent_table NVARCHAR(128),
            parent_col NVARCHAR(128),
            on_delete NVARCHAR(20),
            on_update NVARCHAR(20)
        );

        INSERT INTO #staff_fks (fk_name, parent_table, parent_col, on_delete, on_update)
        SELECT
            fk.name,
            OBJECT_NAME(fk.parent_object_id),
            COL_NAME(fkc.parent_object_id, fkc.parent_column_id),
            fk.delete_referential_action_desc,
            fk.update_referential_action_desc
        FROM sys.foreign_keys fk
        JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
        WHERE fk.referenced_object_id = OBJECT_ID('dbo.Staff')
        ORDER BY fk.name;

        DECLARE @sfk_name NVARCHAR(256), @sfk_parent NVARCHAR(128);
        DECLARE @drop_sfk_sql NVARCHAR(MAX);
        DECLARE drop_sfk_cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT DISTINCT fk_name, parent_table FROM #staff_fks;

        OPEN drop_sfk_cur;
        FETCH NEXT FROM drop_sfk_cur INTO @sfk_name, @sfk_parent;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = @sfk_name)
            BEGIN
                SET @drop_sfk_sql = N'ALTER TABLE [dbo].' + QUOTENAME(@sfk_parent)
                    + N' DROP CONSTRAINT [' + @sfk_name + N']';
                EXEC sp_executesql @drop_sfk_sql;
                PRINT N'  12: dropped FK [' + @sfk_name + N'] on [' + @sfk_parent + N']';
            END
            FETCH NEXT FROM drop_sfk_cur INTO @sfk_name, @sfk_parent;
        END
        CLOSE drop_sfk_cur;
        DEALLOCATE drop_sfk_cur;

        -- 12-b. Discover and drop Staff PK.
        DECLARE @staff_pk_name NVARCHAR(256);
        SELECT @staff_pk_name = name FROM sys.key_constraints
        WHERE type = N'PK' AND parent_object_id = OBJECT_ID('dbo.Staff');
        IF @staff_pk_name IS NOT NULL
        BEGIN
            DECLARE @drop_staff_pk NVARCHAR(MAX) = N'ALTER TABLE [dbo].[Staff] DROP CONSTRAINT [' + @staff_pk_name + N']';
            EXEC sp_executesql @drop_staff_pk;
            PRINT N'  12: dropped PK [' + @staff_pk_name + N']';
        END
        ELSE
            SET @staff_pk_name = N'Staff_pkey';

        -- 12-c. Build mapping old id -> new id (pad to 5 digits).
        IF OBJECT_ID('tempdb..#staff_pad_map', 'U') IS NOT NULL DROP TABLE #staff_pad_map;
        CREATE TABLE #staff_pad_map (old_id NVARCHAR(50), new_id NVARCHAR(50), tmp_id NVARCHAR(50));

        INSERT INTO #staff_pad_map (old_id, new_id, tmp_id)
        SELECT
            [id],
            N'EMP-' + RIGHT(N'0000' + CAST(CAST(RIGHT([id], LEN([id]) - 4) AS INT) AS NVARCHAR(10)), 5),
            N'tmp_EMP_' + RIGHT(N'0000' + CAST(CAST(RIGHT([id], LEN([id]) - 4) AS INT) AS NVARCHAR(10)), 5)
        FROM dbo.Staff
        WHERE [id] LIKE N'EMP-[0-9]%'
          AND [id] NOT LIKE N'EMP-[0-9][0-9][0-9][0-9][0-9]%';

        -- 12-d. Two-phase UPDATE: old -> temp -> final.
        -- Phase 1: Update Staff.id to temp values (no PK to conflict with).
        UPDATE s SET s.[id] = m.tmp_id
        FROM dbo.Staff s
        JOIN #staff_pad_map m ON s.[id] = m.old_id;
        PRINT N'  12: phase 1 - updated Staff.id to temp values';

        -- Phase 2: Update Staff.id to final 5-digit values.
        UPDATE s SET s.[id] = m.new_id
        FROM dbo.Staff s
        JOIN #staff_pad_map m ON s.[id] = m.tmp_id;
        PRINT N'  12: phase 2 - updated Staff.id to final 5-digit values';

        -- 12-e. Update child tables staffId through mapping.
        DECLARE @child_table NVARCHAR(128);
        DECLARE @remap_sql NVARCHAR(MAX);
        DECLARE child_cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT N'Leave' UNION ALL SELECT N'Overtime' UNION ALL
            SELECT N'Payroll' UNION ALL SELECT N'TrainerAvailability' UNION ALL
            SELECT N'TrainerSchedule' UNION ALL SELECT N'StaffDocument';

        OPEN child_cur;
        FETCH NEXT FROM child_cur INTO @child_table;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            IF OBJECT_ID('dbo.' + QUOTENAME(@child_table), 'U') IS NOT NULL
               AND COL_LENGTH('dbo.' + QUOTENAME(@child_table), 'staffId') IS NOT NULL
            BEGIN
                SET @remap_sql = N'UPDATE t SET t.[staffId] = m.new_id
                    FROM [dbo].' + QUOTENAME(@child_table) + N' t
                    JOIN #staff_pad_map m ON t.[staffId] = m.old_id';
                EXEC sp_executesql @remap_sql;
                PRINT N'  12: remapped ' + @child_table + N'.staffId';
            END
            FETCH NEXT FROM child_cur INTO @child_table;
        END
        CLOSE child_cur;
        DEALLOCATE child_cur;

        -- 12-f. Update Member.assignedTrainerId (non-FK reference, check existence).
        IF COL_LENGTH('dbo.Member', 'assignedTrainerId') IS NOT NULL
        BEGIN
            SET @remap_sql = N'UPDATE t SET t.[assignedTrainerId] = m.new_id
                FROM [dbo].[Member] t
                JOIN #staff_pad_map m ON t.[assignedTrainerId] = m.old_id
                WHERE t.[assignedTrainerId] IS NOT NULL';
            EXEC sp_executesql @remap_sql;
            PRINT N'  12: remapped Member.assignedTrainerId';
        END

        -- 12-g. ALTER COLUMN id to NOT NULL.
        ALTER TABLE [dbo].[Staff] ALTER COLUMN [id] NVARCHAR(50) NOT NULL;
        PRINT N'  12: altered Staff.id to NOT NULL';

        -- 12-h. Recreate PK with original name.
        IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE type=N'PK' AND parent_object_id=OBJECT_ID('dbo.Staff'))
        BEGIN
            DECLARE @add_pk_sql NVARCHAR(MAX) = N'ALTER TABLE [dbo].[Staff] ADD CONSTRAINT [' + @staff_pk_name + N'] PRIMARY KEY CLUSTERED ([id])';
            EXEC sp_executesql @add_pk_sql;
            PRINT N'  12: recreated PK [' + @staff_pk_name + N']';
        END

        -- 12-i. Recreate FKs with original names and actions.
        DECLARE @cfk_name NVARCHAR(256), @cfk_tbl NVARCHAR(128), @cfk_col NVARCHAR(128);
        DECLARE @cfk_del NVARCHAR(20), @cfk_upd NVARCHAR(20);
        DECLARE @add_cfk_sql NVARCHAR(MAX);
        DECLARE add_cfk_cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT DISTINCT fk_name, parent_table, parent_col, on_delete, on_update FROM #staff_fks;

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
                    + N']) REFERENCES [dbo].[Staff]([id]) ON DELETE ' + @del_action
                    + N' ON UPDATE ' + @upd_action;
                EXEC sp_executesql @add_cfk_sql;
                PRINT N'  12: recreated FK [' + @cfk_name + N'] on [' + @cfk_tbl + N'].[' + @cfk_col + N']';
            END
            FETCH NEXT FROM add_cfk_cur INTO @cfk_name, @cfk_tbl, @cfk_col, @cfk_del, @cfk_upd;
        END
        CLOSE add_cfk_cur;
        DEALLOCATE add_cfk_cur;

        -- 12-j. Verify: no NULL ids, no duplicates, no orphans.
        DECLARE @v_null_id INT = 0, @v_dup_id INT = 0, @v_orphan_count INT = 0;
        SELECT @v_null_id = COUNT(*) FROM dbo.Staff WHERE [id] IS NULL;
        SELECT @v_dup_id = COUNT(*) FROM (SELECT [id] FROM dbo.Staff GROUP BY [id] HAVING COUNT(*) > 1) x;

        -- Check orphans in known child tables using static SQL
        IF OBJECT_ID('dbo.Leave','U') IS NOT NULL AND EXISTS (
            SELECT 1 FROM dbo.Leave l WHERE NOT EXISTS (SELECT 1 FROM dbo.Staff s WHERE s.[id] = l.[staffId])
        ) SET @v_orphan_count = @v_orphan_count + 1;

        IF OBJECT_ID('dbo.Overtime','U') IS NOT NULL AND EXISTS (
            SELECT 1 FROM dbo.Overtime o WHERE NOT EXISTS (SELECT 1 FROM dbo.Staff s WHERE s.[id] = o.[staffId])
        ) SET @v_orphan_count = @v_orphan_count + 1;

        IF OBJECT_ID('dbo.Payroll','U') IS NOT NULL AND EXISTS (
            SELECT 1 FROM dbo.Payroll p WHERE NOT EXISTS (SELECT 1 FROM dbo.Staff s WHERE s.[id] = p.[staffId])
        ) SET @v_orphan_count = @v_orphan_count + 1;

        IF @v_null_id > 0 OR @v_dup_id > 0 OR @v_orphan_count > 0
        BEGIN
            DECLARE @verify_msg NVARCHAR(MAX) = N'Verification failed: nulls=' + CAST(@v_null_id AS NVARCHAR(10))
                + N', duplicates=' + CAST(@v_dup_id AS NVARCHAR(10))
                + N', orphans=' + CAST(@v_orphan_count AS NVARCHAR(10));
            RAISERROR(@verify_msg, 16, 1);
        END

        PRINT N'  12: verification OK (no nulls, no duplicates, no orphans)';

        DROP TABLE #staff_pad_map;
        DROP TABLE #staff_fks;

        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'12-staff-ids', N'OK', N'Staff ids padded from 4 to 5 digits (EMP-0001 -> EMP-00001); FKs recreated');
        PRINT N'  12-staff-ids: OK - Staff ids padded to 5 digits; FKs recreated';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF OBJECT_ID('tempdb..#staff_pad_map', 'U') IS NOT NULL DROP TABLE #staff_pad_map;
        IF OBJECT_ID('tempdb..#staff_fks', 'U') IS NOT NULL DROP TABLE #staff_fks;
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'12-staff-ids', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  12-staff-ids: FAILED - Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg;
    END CATCH
END
GO

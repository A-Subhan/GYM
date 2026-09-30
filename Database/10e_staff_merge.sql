USE GymDB;
GO

-- ============================================================================
-- 10e_staff_merge.sql
-- ============================================================================
-- Step 5b: Merge Staff.employeeId into Staff.id (id keeps EMP-xxxxx format).
--
-- SAFE ORDER OF OPERATIONS:
--   a. Save FK definitions (name, parent table, parent column, ON DELETE/UPDATE)
--      referencing Staff, then DROP them.
--   b. Drop Staff_pkey, Staff_employeeId_key, any other unique index or default
--      involving id/employeeId.
--   c. Build mapping old id -> employeeId. Set Staff.id = employeeId.
--   d. Drop the employeeId column.
--   e. ALTER Staff.id to NOT NULL (correct length/collation already NVARCHAR(50)).
--   f. Recreate PK on id.
--   g. Update every child staffId column AND non-FK reference columns
--      (Member.assignedTrainerId, etc.) using the mapping.
--   h. Recreate FKs with their original names and actions.
--   i. Verify: no NULL/duplicate ids, no orphan staffId in any child, before COMMIT.
--
-- CATCH block: capture error info FIRST, then rollback, THEN log to _UpgradeLog.
-- Step name: 5b-staff-merge (old name 5 never logged due to doomed transaction).
-- ============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

PRINT N'=== STEP 5b: Staff merge ===';

-- Preflight
IF COL_LENGTH('dbo.Staff', 'employeeId') IS NOT NULL
    PRINT N'  preflight: Staff.employeeId EXISTS - will merge'
ELSE
    PRINT N'  preflight: Staff.employeeId MISSING - will skip';

IF COL_LENGTH('dbo.Staff', 'employeeId') IS NOT NULL
BEGIN
    DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);

    BEGIN TRY
        SET XACT_ABORT ON;
        BEGIN TRAN;

        -- 5b-a. Save FK definitions referencing Staff, then drop them.
        -- Store in a temp table so we can recreate with original names/actions.
        IF OBJECT_ID('tempdb..#staff_fks', 'U') IS NOT NULL DROP TABLE #staff_fks;
        CREATE TABLE #staff_fks (
            fk_name NVARCHAR(256),
            parent_table NVARCHAR(128),
            parent_col NVARCHAR(128),
            on_delete NVARCHAR(20),
            on_update NVARCHAR(20),
            col_order INT
        );

        INSERT INTO #staff_fks (fk_name, parent_table, parent_col, on_delete, on_update, col_order)
        SELECT
            fk.name,
            OBJECT_NAME(fk.parent_object_id),
            COL_NAME(fkc.parent_object_id, fkc.parent_column_id),
            fk.delete_referential_action_desc,
            fk.update_referential_action_desc,
            fkc.constraint_column_id
        FROM sys.foreign_keys fk
        JOIN sys.foreign_key_columns fkc
            ON fkc.constraint_object_id = fk.object_id
        WHERE fk.referenced_object_id = OBJECT_ID('dbo.Staff')
        ORDER BY fk.name, fkc.constraint_column_id;

        -- Now drop each FK dynamically
        DECLARE @fk_name NVARCHAR(256);
        DECLARE @fk_parent NVARCHAR(128);
        DECLARE @drop_fk_sql NVARCHAR(MAX);
        DECLARE drop_fk_cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT DISTINCT fk_name, parent_table FROM #staff_fks;

        OPEN drop_fk_cur;
        FETCH NEXT FROM drop_fk_cur INTO @fk_name, @fk_parent;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @drop_fk_sql = N'ALTER TABLE [dbo].' + QUOTENAME(@fk_parent)
                + N' DROP CONSTRAINT [' + @fk_name + N']';
            EXEC sp_executesql @drop_fk_sql;
            PRINT N'  5b: dropped FK [' + @fk_name + N'] on [' + @fk_parent + N']';
            FETCH NEXT FROM drop_fk_cur INTO @fk_name, @fk_parent;
        END
        CLOSE drop_fk_cur;
        DEALLOCATE drop_fk_cur;

        -- 5b-b. Drop Staff_pkey, Staff_employeeId_key, and any unique index on employeeId.
        -- Drop the PK
        DECLARE @pk_name NVARCHAR(256);
        SELECT @pk_name = name FROM sys.key_constraints
        WHERE type = N'PK' AND parent_object_id = OBJECT_ID('dbo.Staff');
        IF @pk_name IS NOT NULL
        BEGIN
            DECLARE @drop_pk_sql NVARCHAR(MAX) = N'ALTER TABLE [dbo].[Staff] DROP CONSTRAINT [' + @pk_name + N']';
            EXEC sp_executesql @drop_pk_sql;
            PRINT N'  5b: dropped PK [' + @pk_name + N']';
        END

        -- Drop any UNIQUE constraint on employeeId (e.g. Staff_employeeId_key)
        DECLARE @uq_name NVARCHAR(256);
        DECLARE @drop_uq_sql NVARCHAR(MAX);
        DECLARE uq_cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT kc.name
            FROM sys.key_constraints kc
            WHERE kc.type = N'UQ' AND kc.parent_object_id = OBJECT_ID('dbo.Staff')
              AND EXISTS (
                  SELECT 1 FROM sys.index_columns ic
                  JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
                  WHERE ic.object_id = kc.parent_object_id AND ic.index_id = kc.unique_index_id
                    AND c.name = N'employeeId'
              );

        OPEN uq_cur;
        FETCH NEXT FROM uq_cur INTO @uq_name;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @drop_uq_sql = N'ALTER TABLE [dbo].[Staff] DROP CONSTRAINT [' + @uq_name + N']';
            EXEC sp_executesql @drop_uq_sql;
            PRINT N'  5b: dropped unique constraint [' + @uq_name + N']';
            FETCH NEXT FROM uq_cur INTO @uq_name;
        END
        CLOSE uq_cur;
        DEALLOCATE uq_cur;

        -- Drop any remaining unique INDEX on employeeId (not a constraint)
        DECLARE @uq_idx_name NVARCHAR(256);
        SELECT TOP 1 @uq_idx_name = i.name
        FROM sys.indexes i
        WHERE i.is_unique = 1 AND i.object_id = OBJECT_ID('dbo.Staff')
          AND i.is_primary_key = 0
          AND NOT EXISTS (SELECT 1 FROM sys.key_constraints kc WHERE kc.parent_object_id = i.object_id AND kc.unique_index_id = i.index_id)
          AND EXISTS (
              SELECT 1 FROM sys.index_columns ic
              JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
              WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id
                AND c.name = N'employeeId'
          );
        IF @uq_idx_name IS NOT NULL
        BEGIN
            SET @drop_uq_sql = N'DROP INDEX [' + @uq_idx_name + N'] ON [dbo].[Staff]';
            EXEC sp_executesql @drop_uq_sql;
            PRINT N'  5b: dropped unique index [' + @uq_idx_name + N']';
        END

        -- 5b-c. Build mapping old id -> employeeId, then SET Staff.id = employeeId.
        IF OBJECT_ID('tempdb..#staff_map', 'U') IS NOT NULL DROP TABLE #staff_map;
        CREATE TABLE #staff_map (old_id NVARCHAR(50), new_id NVARCHAR(50));
        INSERT INTO #staff_map (old_id, new_id)
        SELECT [id], [employeeId]
        FROM dbo.Staff
        WHERE [employeeId] IS NOT NULL AND [employeeId] <> N'';

        -- Set id = employeeId for all rows where employeeId is valid
        UPDATE dbo.Staff SET [id] = [employeeId]
        WHERE [employeeId] IS NOT NULL AND [employeeId] <> N'';

        PRINT N'  5b: updated Staff.id = employeeId';

        -- 5b-d. Drop the employeeId column
        ALTER TABLE dbo.Staff DROP COLUMN [employeeId];
        PRINT N'  5b: dropped column employeeId';

        -- 5b-e. Ensure id is NOT NULL (it already should be, but be safe)
        ALTER TABLE dbo.[Staff] ALTER COLUMN [id] NVARCHAR(50) NOT NULL;
        PRINT N'  5b: altered Staff.id to NOT NULL';

        -- 5b-f. Recreate PK on id
        IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE type=N'PK' AND parent_object_id=OBJECT_ID('dbo.Staff'))
            ALTER TABLE [dbo].[Staff] ADD CONSTRAINT [Staff_pkey] PRIMARY KEY CLUSTERED ([id]);
        PRINT N'  5b: recreated PK Staff_pkey on id';

        -- 5b-g. Update child tables and non-FK reference columns using the mapping.
        -- Child FK tables: Leave, Overtime, Payroll, TrainerAvailability,
        -- TrainerSchedule, StaffDocument (all have staffId).
        -- Non-FK reference: Member.assignedTrainerId (check with COL_LENGTH).
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
                    JOIN #staff_map m ON t.[staffId] = m.old_id';
                EXEC sp_executesql @remap_sql;
                PRINT N'  5b: remapped ' + @child_table + N'.staffId';
            END
            FETCH NEXT FROM child_cur INTO @child_table;
        END
        CLOSE child_cur;
        DEALLOCATE child_cur;

        -- Remap Member.assignedTrainerId (non-FK reference, check existence)
        IF COL_LENGTH('dbo.Member', 'assignedTrainerId') IS NOT NULL
        BEGIN
            SET @remap_sql = N'UPDATE t SET t.[assignedTrainerId] = m.new_id
                FROM [dbo].[Member] t
                JOIN #staff_map m ON t.[assignedTrainerId] = m.old_id
                WHERE t.[assignedTrainerId] IS NOT NULL';
            EXEC sp_executesql @remap_sql;
            PRINT N'  5b: remapped Member.assignedTrainerId';
        END

        -- 5b-h. Recreate FKs with their original names and actions.
        DECLARE @cfk_name NVARCHAR(256), @cfk_tbl NVARCHAR(128), @cfk_col NVARCHAR(128);
        DECLARE @cfk_del NVARCHAR(20), @cfk_upd NVARCHAR(20);
        DECLARE @add_cfk_sql NVARCHAR(MAX);
        DECLARE add_cfk_cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT DISTINCT fk_name, parent_table, parent_col, on_delete, on_update
            FROM #staff_fks;

        OPEN add_cfk_cur;
        FETCH NEXT FROM add_cfk_cur INTO @cfk_name, @cfk_tbl, @cfk_col, @cfk_del, @cfk_upd;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            IF OBJECT_ID('dbo.' + QUOTENAME(@cfk_tbl), 'U') IS NOT NULL
               AND COL_LENGTH('dbo.' + QUOTENAME(@cfk_tbl), @cfk_col) IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = @cfk_name)
            BEGIN
                -- Normalize ON DELETE / ON UPDATE action descriptions
                -- sys.foreign_keys.delete_referential_action_desc returns e.g. 'CASCADE', 'NO_ACTION'
                DECLARE @del_action NVARCHAR(20) = REPLACE(@cfk_del, N'_', N' ');
                DECLARE @upd_action NVARCHAR(20) = REPLACE(@cfk_upd, N'_', N' ');
                IF @del_action = N'NO' OR @del_action = N'NO ACTION' SET @del_action = N'NO ACTION';
                IF @upd_action = N'NO' OR @upd_action = N'NO ACTION' SET @upd_action = N'NO ACTION';

                SET @add_cfk_sql = N'ALTER TABLE [dbo].' + QUOTENAME(@cfk_tbl)
                    + N' ADD CONSTRAINT [' + @cfk_name + N'] FOREIGN KEY ([' + @cfk_col
                    + N']) REFERENCES [dbo].[Staff]([id]) ON DELETE ' + @del_action
                    + N' ON UPDATE ' + @upd_action;
                EXEC sp_executesql @add_cfk_sql;
                PRINT N'  5b: recreated FK [' + @cfk_name + N'] on [' + @cfk_tbl + N'].[' + @cfk_col + N']';
            END
            FETCH NEXT FROM add_cfk_cur INTO @cfk_name, @cfk_tbl, @cfk_col, @cfk_del, @cfk_upd;
        END
        CLOSE add_cfk_cur;
        DEALLOCATE add_cfk_cur;

        -- 5b-i. Verify: no NULL ids, no duplicate ids, no orphan staffId.
        DECLARE @null_id INT = 0, @dup_id INT = 0, @orphan_count INT = 0;
        SELECT @null_id = COUNT(*) FROM dbo.Staff WHERE [id] IS NULL;
        SELECT @dup_id = COUNT(*) FROM (SELECT [id] FROM dbo.Staff GROUP BY [id] HAVING COUNT(*) > 1) x;

        -- Check orphans in each child table using static SQL (no dynamic SQL needed)
        IF OBJECT_ID('dbo.Leave', 'U') IS NOT NULL
            AND EXISTS (SELECT 1 FROM dbo.Leave l WHERE NOT EXISTS (SELECT 1 FROM dbo.Staff s WHERE s.[id] = l.[staffId]))
            SET @orphan_count = @orphan_count + 1;

        IF OBJECT_ID('dbo.Overtime', 'U') IS NOT NULL
            AND EXISTS (SELECT 1 FROM dbo.Overtime o WHERE NOT EXISTS (SELECT 1 FROM dbo.Staff s WHERE s.[id] = o.[staffId]))
            SET @orphan_count = @orphan_count + 1;

        IF OBJECT_ID('dbo.Payroll', 'U') IS NOT NULL
            AND EXISTS (SELECT 1 FROM dbo.Payroll p WHERE NOT EXISTS (SELECT 1 FROM dbo.Staff s WHERE s.[id] = p.[staffId]))
            SET @orphan_count = @orphan_count + 1;

        IF OBJECT_ID('dbo.TrainerAvailability', 'U') IS NOT NULL
            AND EXISTS (SELECT 1 FROM dbo.TrainerAvailability t WHERE NOT EXISTS (SELECT 1 FROM dbo.Staff s WHERE s.[id] = t.[staffId]))
            SET @orphan_count = @orphan_count + 1;

        IF OBJECT_ID('dbo.TrainerSchedule', 'U') IS NOT NULL
            AND EXISTS (SELECT 1 FROM dbo.TrainerSchedule t WHERE NOT EXISTS (SELECT 1 FROM dbo.Staff s WHERE s.[id] = t.[staffId]))
            SET @orphan_count = @orphan_count + 1;

        IF OBJECT_ID('dbo.StaffDocument', 'U') IS NOT NULL
            AND EXISTS (SELECT 1 FROM dbo.StaffDocument d WHERE NOT EXISTS (SELECT 1 FROM dbo.Staff s WHERE s.[id] = d.[staffId]))
            SET @orphan_count = @orphan_count + 1;

        IF @null_id > 0 OR @dup_id > 0 OR @orphan_count > 0
        BEGIN
            DECLARE @verify_msg NVARCHAR(MAX) = N'Verification failed: nulls=' + CAST(@null_id AS NVARCHAR(10))
                + N', duplicates=' + CAST(@dup_id AS NVARCHAR(10))
                + N', orphans=' + CAST(@orphan_count AS NVARCHAR(10));
            RAISERROR(@verify_msg, 16, 1);
        END

        PRINT N'  5b: verification OK (nulls=0, duplicates=0, orphans=0)';

        DROP TABLE #staff_map;
        DROP TABLE #staff_fks;

        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'5b-staff-merge', N'OK', N'Staff.employeeId merged into id; FKs recreated');
        PRINT N'  5b-staff-merge: OK - Staff.employeeId merged into id; FKs recreated';
    END TRY
    BEGIN CATCH
        -- CATCH FIX: capture error info FIRST, then rollback, THEN log.
        SET @eNum = ERROR_NUMBER();
        SET @eLine = ERROR_LINE();
        SET @eMsg = ERROR_MESSAGE();

        IF OBJECT_ID('tempdb..#staff_map', 'U') IS NOT NULL DROP TABLE #staff_map;
        IF OBJECT_ID('tempdb..#staff_fks', 'U') IS NOT NULL DROP TABLE #staff_fks;
        IF XACT_STATE() <> 0 ROLLBACK TRAN;

        INSERT INTO dbo._UpgradeLog (step, status, message)
        VALUES (N'5b-staff-merge', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  5b-staff-merge: FAILED - Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg;
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'5b-staff-merge', N'SKIPPED', N'employeeId already merged (column absent)');
    PRINT N'  5b-staff-merge: SKIPPED - employeeId already merged (column absent)';
END
GO

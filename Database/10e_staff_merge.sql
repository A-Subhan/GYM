USE GymDB;
GO

-- ============================================================================
-- 10e_staff_merge.sql
-- ============================================================================
-- Step 5: Merge Staff.employeeId into Staff.id (id keeps EMP-xxxxx format).
-- Fixes 09 Msg 102 (QUOTENAME inside EXEC('...'+...)).
-- Uses sp_executesql with a prebuilt @sql NVARCHAR variable for ALL DDL.
--
-- If Staff.employeeId does NOT exist (already merged), this script is skipped.
-- If Staff.employeeId EXISTS:
--   1. Build old_id -> new_id map into a temp table.
--   2. Remap all child tables (Leave, Overtime, Payroll, TrainerAvailability,
--      TrainerSchedule, StaffDocument) staffId from old id to new employeeId.
--   3. Remap Member.assignedTrainerId.
--   4. Drop all FKs referencing Staff.
--   5. Drop any unique index on Staff.employeeId.
--   6. Drop the PK on Staff.id.
--   7. Copy employeeId -> id where id is not in EMP-xxxxx format.
--   8. Drop the employeeId column.
--   9. Re-add the PK on id.
--  10. Re-create the child FKs pointing at Staff(id).
--  11. Re-create Staff.branchId and Staff.shiftId FKs.
--
-- Idempotent: if employeeId is already gone, the whole script SKIPS.
-- ============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

PRINT N'=== STEP 5: Staff merge ===';

-- Preflight
IF COL_LENGTH('dbo.Staff', 'employeeId') IS NOT NULL
    PRINT N'  preflight: Staff.employeeId EXISTS - will merge'
ELSE
    PRINT N'  preflight: Staff.employeeId MISSING - will skip';

IF COL_LENGTH('dbo.Staff', 'employeeId') IS NOT NULL
BEGIN
    BEGIN TRY
        SET XACT_ABORT ON;
        BEGIN TRAN;

        -- 5a. Build the old_id -> new_id map into a real temp table.
        -- (Table variables can't be referenced by sp_executesql.)
        IF OBJECT_ID('tempdb..#staff_map', 'U') IS NOT NULL DROP TABLE #staff_map;
        CREATE TABLE #staff_map (old_id NVARCHAR(50), new_id NVARCHAR(50));
        INSERT INTO #staff_map (old_id, new_id)
        SELECT [id], [employeeId]
        FROM dbo.Staff
        WHERE [employeeId] IS NOT NULL AND [employeeId] <> N'';

        -- 5b. Remap child tables BEFORE touching Staff PK/FKs.
        -- Each child table has a staffId column referencing Staff.
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
            END
            FETCH NEXT FROM child_cur INTO @child_table;
        END
        CLOSE child_cur;
        DEALLOCATE child_cur;

        -- 5c. Remap Member.assignedTrainerId
        IF COL_LENGTH('dbo.Member', 'assignedTrainerId') IS NOT NULL
        BEGIN
            SET @remap_sql = N'UPDATE t SET t.[assignedTrainerId] = m.new_id
                FROM [dbo].[Member] t
                JOIN #staff_map m ON t.[assignedTrainerId] = m.old_id
                WHERE t.[assignedTrainerId] IS NOT NULL';
            EXEC sp_executesql @remap_sql;
        END

        -- 5d. Drop all FKs that reference dbo.Staff
        DECLARE @fk_name NVARCHAR(256);
        DECLARE @fk_parent NVARCHAR(256);
        DECLARE @drop_fk_sql NVARCHAR(MAX);
        DECLARE fk_cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT fk.name, OBJECT_NAME(fk.parent_object_id)
            FROM sys.foreign_keys fk
            WHERE fk.referenced_object_id = OBJECT_ID('dbo.Staff');

        OPEN fk_cur;
        FETCH NEXT FROM fk_cur INTO @fk_name, @fk_parent;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @drop_fk_sql = N'ALTER TABLE [dbo].' + QUOTENAME(@fk_parent)
                + N' DROP CONSTRAINT [' + @fk_name + N']';
            EXEC sp_executesql @drop_fk_sql;
            FETCH NEXT FROM fk_cur INTO @fk_name, @fk_parent;
        END
        CLOSE fk_cur;
        DEALLOCATE fk_cur;

        -- 5e. Drop any unique index on Staff.employeeId
        DECLARE @uq_index_name NVARCHAR(256);
        SELECT TOP 1 @uq_index_name = i.name
        FROM sys.indexes i
        WHERE i.is_unique = 1 AND i.object_id = OBJECT_ID('dbo.Staff')
          AND EXISTS (
              SELECT 1 FROM sys.index_columns ic
              JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
              WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id
                AND c.name = N'employeeId'
          );
        IF @uq_index_name IS NOT NULL
        BEGIN
            DECLARE @drop_uq_sql NVARCHAR(MAX) = N'DROP INDEX [' + @uq_index_name + N'] ON [dbo].[Staff]';
            EXEC sp_executesql @drop_uq_sql;
        END

        -- 5f. Drop the PK on Staff.id
        DECLARE @pk_name NVARCHAR(256);
        SELECT @pk_name = name FROM sys.key_constraints
        WHERE type = N'PK' AND parent_object_id = OBJECT_ID('dbo.Staff');
        IF @pk_name IS NOT NULL
        BEGIN
            DECLARE @drop_pk_sql NVARCHAR(MAX) = N'ALTER TABLE [dbo].[Staff] DROP CONSTRAINT [' + @pk_name + N']';
            EXEC sp_executesql @drop_pk_sql;
        END

        -- 5g. Copy employeeId -> id (only where id is NOT already EMP-xxxxx)
        UPDATE dbo.Staff SET [id] = [employeeId]
        WHERE [employeeId] IS NOT NULL AND [employeeId] <> N'' AND [id] NOT LIKE N'EMP-%';

        -- 5h. Drop the employeeId column
        ALTER TABLE dbo.Staff DROP COLUMN [employeeId];

        -- 5i. Re-add the PK on id
        IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE type=N'PK' AND parent_object_id=OBJECT_ID('dbo.Staff'))
            ALTER TABLE [dbo].[Staff] ADD CONSTRAINT [Staff_pkey] PRIMARY KEY CLUSTERED ([id]);

        -- 5j. Re-create the child FKs pointing at Staff(id)
        DECLARE @cfk_name NVARCHAR(256), @cfk_tbl NVARCHAR(128), @cfk_col NVARCHAR(128), @cfk_on NVARCHAR(20);
        DECLARE @add_cfk_sql NVARCHAR(MAX);
        DECLARE cfk_cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT * FROM (
                VALUES
                    (N'Leave_staffId_fkey',               N'Leave',                N'staffId', N'CASCADE'),
                    (N'Overtime_staffId_fkey',            N'Overtime',             N'staffId', N'CASCADE'),
                    (N'Payroll_staffId_fkey',             N'Payroll',              N'staffId', N'NO ACTION'),
                    (N'TrainerAvailability_staffId_fkey',  N'TrainerAvailability',  N'staffId', N'CASCADE'),
                    (N'TrainerSchedule_staffId_fkey',     N'TrainerSchedule',       N'staffId', N'CASCADE'),
                    (N'StaffDocument_staffId_fkey',      N'StaffDocument',        N'staffId', N'CASCADE')
            ) AS t(fkname, tbl, col, ondel);

        OPEN cfk_cur;
        FETCH NEXT FROM cfk_cur INTO @cfk_name, @cfk_tbl, @cfk_col, @cfk_on;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            IF OBJECT_ID('dbo.' + QUOTENAME(@cfk_tbl), 'U') IS NOT NULL
               AND COL_LENGTH('dbo.' + QUOTENAME(@cfk_tbl), @cfk_col) IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = @cfk_name)
            BEGIN
                SET @add_cfk_sql = N'ALTER TABLE [dbo].' + QUOTENAME(@cfk_tbl)
                    + N' ADD CONSTRAINT [' + @cfk_name + N'] FOREIGN KEY ([' + @cfk_col
                    + N']) REFERENCES [dbo].[Staff]([id]) ON DELETE ' + @cfk_on + N' ON UPDATE NO ACTION';
                EXEC sp_executesql @add_cfk_sql;
            END
            FETCH NEXT FROM cfk_cur INTO @cfk_name, @cfk_tbl, @cfk_col, @cfk_on;
        END
        CLOSE cfk_cur;
        DEALLOCATE cfk_cur;

        -- 5k. Re-create Staff.branchId FK
        IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'Staff_branchId_fkey')
           AND COL_LENGTH('dbo.Staff','branchId') IS NOT NULL
        BEGIN
            DECLARE @add_bfk_sql NVARCHAR(MAX) = N'ALTER TABLE [dbo].[Staff] ADD CONSTRAINT [Staff_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION';
            EXEC sp_executesql @add_bfk_sql;
        END

        -- 5l. Re-create Staff.shiftId FK
        IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'Staff_shiftId_fkey')
           AND COL_LENGTH('dbo.Staff','shiftId') IS NOT NULL
        BEGIN
            DECLARE @add_sfk_sql NVARCHAR(MAX) = N'ALTER TABLE [dbo].[Staff] ADD CONSTRAINT [Staff_shiftId_fkey] FOREIGN KEY ([shiftId]) REFERENCES [dbo].[Shift]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION';
            EXEC sp_executesql @add_sfk_sql;
        END

        DROP TABLE #staff_map;

        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'5-Staff-merge', N'OK', N'Staff.employeeId merged into id; FKs recreated');
        PRINT N'  5-Staff-merge: OK - Staff.employeeId merged into id; FKs recreated';
    END TRY
    BEGIN CATCH
        IF OBJECT_ID('tempdb..#staff_map', 'U') IS NOT NULL DROP TABLE #staff_map;
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'5-Staff-merge', N'FAILED', ERROR_MESSAGE());
        PRINT N'  5-Staff-merge: FAILED - ' + ERROR_MESSAGE();
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'5-Staff-merge', N'SKIPPED', N'employeeId already merged (column absent)');
    PRINT N'  5-Staff-merge: SKIPPED - employeeId already merged (column absent)';
END
GO

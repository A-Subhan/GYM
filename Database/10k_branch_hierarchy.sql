USE GymDB;
GO

-- ============================================================================
-- 10k_branch_hierarchy.sql
-- ============================================================================
-- Step 10b: Branch hierarchy — id = code, Control/Detail node types.
-- In-place UPDATE (no table rebuild, no sp_rename).
--
-- Target structure:
--   00 Company            (Control, parent NULL)
--   01 Head Office        (Control, parent 00)
--   01001 (former BR-001) (Detail, parent 01, keeps its details)
--   01002 (former BR-002) (Detail, parent 01, keeps its details)
--
-- Safe order of operations (in one transaction):
--   a. Save all FK definitions referencing Branch, then DROP them.
--   b. Drop Branch PK, unique code constraint, and self-ref FK.
--   c. Build mapping old id -> new id for existing branches.
--   d. Two-phase UPDATE:
--      Phase 1: SET Branch.id = 'tmp_' + new_id (unique temp values).
--      Phase 2: SET Branch.id = new_id (final values).
--   e. SET Branch.code = Branch.id (code = id for every row).
--   f. Update every table with branchId column through the mapping.
--   g. Insert Control nodes (00 Company, 01 Head Office) with NULL detail fields.
--   h. Update existing branches: set nodeType = 'Detail', parentId = '01'.
--   i. ALTER COLUMN id NVARCHAR(50) NOT NULL (same type/collation).
--   j. Recreate PK, unique code constraint, self-ref FK.
--   k. Recreate all FKs with original names and actions.
--   l. Verify: id = code, control nodes clean, no orphan branchId.
--   m. COMMIT only after verification.
-- ============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

PRINT N'=== STEP 10b: Branch hierarchy ===';

-- Preflight: skip if already migrated
IF OBJECT_ID('dbo.Branch','U') IS NOT NULL
   AND EXISTS (SELECT 1 FROM dbo.Branch WHERE [id] = N'00')
BEGIN
    PRINT N'  preflight: Branch hierarchy already migrated (id 00 exists)';
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'10b-Branch-hierarchy', N'SKIPPED', N'Already in place (id 00 exists)');
    PRINT N'  10b-Branch-hierarchy: SKIPPED - already in place';
END
GO

-- Main migration (only if not already migrated)
USE GymDB;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);

IF OBJECT_ID('dbo.Branch','U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM dbo.Branch WHERE [id] = N'00')
BEGIN
    BEGIN TRY
        SET XACT_ABORT ON;
        BEGIN TRAN;

        -- 10b-a. Save all FK definitions referencing Branch, then DROP them.
        IF OBJECT_ID('tempdb..#branch_fks', 'U') IS NOT NULL DROP TABLE #branch_fks;
        CREATE TABLE #branch_fks (
            fk_name NVARCHAR(256),
            parent_table NVARCHAR(128),
            parent_col NVARCHAR(128),
            on_delete NVARCHAR(20),
            on_update NVARCHAR(20)
        );

        INSERT INTO #branch_fks (fk_name, parent_table, parent_col, on_delete, on_update)
        SELECT
            fk.name,
            OBJECT_NAME(fk.parent_object_id),
            COL_NAME(fkc.parent_object_id, fkc.parent_column_id),
            fk.delete_referential_action_desc,
            fk.update_referential_action_desc
        FROM sys.foreign_keys fk
        JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
        WHERE fk.referenced_object_id = OBJECT_ID('dbo.Branch')
        ORDER BY fk.name;

        DECLARE @bfk_name NVARCHAR(256), @bfk_parent NVARCHAR(128);
        DECLARE @drop_bfk_sql NVARCHAR(MAX);
        DECLARE drop_bfk_cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT DISTINCT fk_name, parent_table FROM #branch_fks;

        OPEN drop_bfk_cur;
        FETCH NEXT FROM drop_bfk_cur INTO @bfk_name, @bfk_parent;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = @bfk_name)
            BEGIN
                SET @drop_bfk_sql = N'ALTER TABLE [dbo].' + QUOTENAME(@bfk_parent)
                    + N' DROP CONSTRAINT [' + @bfk_name + N']';
                EXEC sp_executesql @drop_bfk_sql;
                PRINT N'  10b: dropped FK [' + @bfk_name + N'] on [' + @bfk_parent + N']';
            END
            FETCH NEXT FROM drop_bfk_cur INTO @bfk_name, @bfk_parent;
        END
        CLOSE drop_bfk_cur;
        DEALLOCATE drop_bfk_cur;

        -- 10b-b. Drop Branch PK, unique code constraint, and self-ref FK.
        DECLARE @bpk_name NVARCHAR(256);
        SELECT @bpk_name = name FROM sys.key_constraints
        WHERE type = N'PK' AND parent_object_id = OBJECT_ID('dbo.Branch');
        IF @bpk_name IS NOT NULL
        BEGIN
            DECLARE @drop_bpk_sql NVARCHAR(MAX) = N'ALTER TABLE [dbo].[Branch] DROP CONSTRAINT [' + @bpk_name + N']';
            EXEC sp_executesql @drop_bpk_sql;
            PRINT N'  10b: dropped PK [' + @bpk_name + N']';
        END
        ELSE
            SET @bpk_name = N'Branch_pkey';

        IF EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = N'Branch_code_key' AND parent_object_id = OBJECT_ID('dbo.Branch'))
        BEGIN
            EXEC sp_executesql N'ALTER TABLE [dbo].[Branch] DROP CONSTRAINT [Branch_code_key]';
            PRINT N'  10b: dropped unique Branch_code_key';
        END

        -- 10b-c. Build mapping old id -> new id for existing branches.
        IF OBJECT_ID('tempdb..#branch_map', 'U') IS NOT NULL DROP TABLE #branch_map;
        CREATE TABLE #branch_map (old_id NVARCHAR(50), new_id NVARCHAR(50), tmp_id NVARCHAR(50));
        INSERT INTO #branch_map (old_id, new_id, tmp_id)
        SELECT
            [id],
            N'01' + RIGHT(N'00' + CAST(ROW_NUMBER() OVER (ORDER BY [code], [id]) AS NVARCHAR(10)), 3),
            N'tmp_01' + RIGHT(N'00' + CAST(ROW_NUMBER() OVER (ORDER BY [code], [id]) AS NVARCHAR(10)), 3)
        FROM dbo.Branch
        WHERE [parentId] IS NULL
        ORDER BY [code], [id];

        -- 10b-d. Two-phase UPDATE: first to temp values, then to final.
        -- Phase 1: Update Branch.id to unique temp values (no PK to conflict with).
        UPDATE b SET b.[id] = m.tmp_id
        FROM dbo.Branch b
        JOIN #branch_map m ON b.[id] = m.old_id;
        PRINT N'  10b: phase 1 - updated Branch.id to temp values';

        -- Phase 2: Update Branch.id to final values.
        UPDATE b SET b.[id] = m.new_id
        FROM dbo.Branch b
        JOIN #branch_map m ON b.[id] = m.tmp_id;
        PRINT N'  10b: phase 2 - updated Branch.id to final values';

        -- 10b-e. SET Branch.code = Branch.id (code = id for every row).
        UPDATE b SET b.[code] = b.[id]
        FROM dbo.Branch b
        JOIN #branch_map m ON b.[id] = m.new_id;
        PRINT N'  10b: updated Branch.code = id';

        -- 10b-f. Update every table with branchId through the mapping.
        DECLARE @upd_tbl NVARCHAR(128);
        DECLARE @upd_sql NVARCHAR(MAX);
        DECLARE upd_cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT t.name
            FROM sys.tables t
            JOIN sys.columns c ON c.object_id = t.object_id
            WHERE c.name = N'branchId' AND t.name <> N'Branch'
            ORDER BY t.name;

        OPEN upd_cur;
        FETCH NEXT FROM upd_cur INTO @upd_tbl;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @upd_sql = N'UPDATE t SET t.[branchId] = m.new_id
                FROM [dbo].' + QUOTENAME(@upd_tbl) + N' t
                JOIN #branch_map m ON t.[branchId] = m.old_id
                WHERE t.[branchId] IS NOT NULL';
            EXEC sp_executesql @upd_sql;
            PRINT N'  10b: remapped ' + @upd_tbl + N'.branchId';
            FETCH NEXT FROM upd_cur INTO @upd_tbl;
        END
        CLOSE upd_cur;
        DEALLOCATE upd_cur;

        -- 10b-g. Insert Control nodes (00 Company, 01 Head Office).
        DECLARE @company_name NVARCHAR(255) = N'Company';
        IF OBJECT_ID('dbo.Defaults','U') IS NOT NULL
           AND COL_LENGTH('dbo.Defaults','companyName') IS NOT NULL
        BEGIN
            SELECT TOP 1 @company_name = [companyName] FROM dbo.Defaults WHERE [companyName] IS NOT NULL;
        END
        IF @company_name IS NULL OR @company_name = N''
            SET @company_name = N'Company';

        INSERT INTO [dbo].[Branch] ([id], [code], [name], [parentId], [nodeType],
            [address], [city], [phone], [email], [strn], [ntn], [trn], [fbr], [logo],
            [isActive], [createdAt], [updatedAt], [isDeleted])
        VALUES (N'00', N'00', @company_name, NULL, N'Control',
            NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
            1, SYSDATETIME(), SYSDATETIME(), 0);

        INSERT INTO [dbo].[Branch] ([id], [code], [name], [parentId], [nodeType],
            [address], [city], [phone], [email], [strn], [ntn], [trn], [fbr], [logo],
            [isActive], [createdAt], [updatedAt], [isDeleted])
        VALUES (N'01', N'01', N'Head Office', N'00', N'Control',
            NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
            1, SYSDATETIME(), SYSDATETIME(), 0);

        PRINT N'  10b: inserted Control nodes 00 (Company) and 01 (Head Office)';

        -- 10b-h. Update existing branches: set nodeType = Detail, parentId = '01'.
        UPDATE dbo.Branch SET [nodeType] = N'Detail', [parentId] = N'01'
        WHERE [id] LIKE N'01%' AND [id] <> N'01';
        PRINT N'  10b: set existing branches to Detail with parentId 01';

        -- 10b-i. ALTER COLUMN id to NOT NULL (same type, NVARCHAR(50)).
        ALTER TABLE [dbo].[Branch] ALTER COLUMN [id] NVARCHAR(50) NOT NULL;
        PRINT N'  10b: altered Branch.id to NOT NULL';

        -- 10b-j. Recreate PK, unique code constraint, self-ref FK.
        IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE type=N'PK' AND parent_object_id=OBJECT_ID('dbo.Branch'))
        BEGIN
            DECLARE @add_bpk_sql NVARCHAR(MAX) = N'ALTER TABLE [dbo].[Branch] ADD CONSTRAINT [' + @bpk_name + N'] PRIMARY KEY CLUSTERED ([id])';
            EXEC sp_executesql @add_bpk_sql;
            PRINT N'  10b: recreated PK [' + @bpk_name + N']';
        END

        IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name=N'Branch_code_key' AND parent_object_id=OBJECT_ID('dbo.Branch'))
        BEGIN
            EXEC sp_executesql N'ALTER TABLE [dbo].[Branch] ADD CONSTRAINT [Branch_code_key] UNIQUE NONCLUSTERED ([code])';
            PRINT N'  10b: recreated unique Branch_code_key';
        END

        IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'Branch_parentId_fkey')
        BEGIN
            EXEC sp_executesql N'ALTER TABLE [dbo].[Branch] ADD CONSTRAINT [Branch_parentId_fkey] FOREIGN KEY ([parentId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION';
            PRINT N'  10b: recreated Branch_parentId_fkey';
        END

        -- 10b-k. Recreate FKs with original names and actions.
        DECLARE @rbfk_name NVARCHAR(256), @rbfk_tbl NVARCHAR(128), @rbfk_col NVARCHAR(128);
        DECLARE @rbfk_del NVARCHAR(20), @rbfk_upd NVARCHAR(20);
        DECLARE @add_rbfk_sql NVARCHAR(MAX);
        DECLARE add_rbfk_cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT DISTINCT fk_name, parent_table, parent_col, on_delete, on_update
            FROM #branch_fks
            WHERE parent_table <> N'Branch';

        OPEN add_rbfk_cur;
        FETCH NEXT FROM add_rbfk_cur INTO @rbfk_name, @rbfk_tbl, @rbfk_col, @rbfk_del, @rbfk_upd;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            IF OBJECT_ID('dbo.' + QUOTENAME(@rbfk_tbl), 'U') IS NOT NULL
               AND COL_LENGTH('dbo.' + QUOTENAME(@rbfk_tbl), @rbfk_col) IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = @rbfk_name)
            BEGIN
                DECLARE @rb_del NVARCHAR(20) = REPLACE(@rbfk_del, N'_', N' ');
                DECLARE @rb_upd NVARCHAR(20) = REPLACE(@rbfk_upd, N'_', N' ');
                IF @rb_del = N'NO' SET @rb_del = N'NO ACTION';
                IF @rb_upd = N'NO' SET @rb_upd = N'NO ACTION';

                SET @add_rbfk_sql = N'ALTER TABLE [dbo].' + QUOTENAME(@rbfk_tbl)
                    + N' ADD CONSTRAINT [' + @rbfk_name + N'] FOREIGN KEY ([' + @rbfk_col
                    + N']) REFERENCES [dbo].[Branch]([id]) ON DELETE ' + @rb_del
                    + N' ON UPDATE ' + @rb_upd;
                EXEC sp_executesql @add_rbfk_sql;
                PRINT N'  10b: recreated FK [' + @rbfk_name + N'] on [' + @rbfk_tbl + N']';
            END
            FETCH NEXT FROM add_rbfk_cur INTO @rbfk_name, @rbfk_tbl, @rbfk_col, @rbfk_del, @rbfk_upd;
        END
        CLOSE add_rbfk_cur;
        DEALLOCATE add_rbfk_cur;

        -- 10b-l. Verify: id = code, control nodes clean, no orphan branchId.
        DECLARE @v_bad_id_code INT = 0;
        SELECT @v_bad_id_code = COUNT(*) FROM dbo.Branch WHERE [id] <> [code];
        IF @v_bad_id_code > 0
            RAISERROR(N'Verification failed: %d branches where id <> code', 16, 1, @v_bad_id_code);

        DECLARE @v_control_detail INT = 0;
        SELECT @v_control_detail = COUNT(*) FROM dbo.Branch
        WHERE [nodeType] = N'Control'
          AND ([address] IS NOT NULL OR [city] IS NOT NULL OR [phone] IS NOT NULL
               OR [email] IS NOT NULL OR [strn] IS NOT NULL OR [ntn] IS NOT NULL
               OR [trn] IS NOT NULL OR [fbr] IS NOT NULL OR [logo] IS NOT NULL);
        IF @v_control_detail > 0
            RAISERROR(N'Verification failed: %d Control nodes have detail data', 16, 1, @v_control_detail);

        -- Check orphan branchId in known child tables using static SQL
        DECLARE @v_orphan_branch INT = 0;
        SELECT @v_orphan_branch = COUNT(*)
        FROM dbo.Branch b
        WHERE b.[parentId] IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM dbo.Branch p WHERE p.[id] = b.[parentId]);
        IF @v_orphan_branch > 0
            RAISERROR(N'Verification failed: orphaned parentId references', 16, 1);

        IF OBJECT_ID('dbo.Member','U') IS NOT NULL AND EXISTS (
            SELECT 1 FROM dbo.Member m WHERE m.[branchId] IS NOT NULL
            AND NOT EXISTS (SELECT 1 FROM dbo.Branch b WHERE b.[id] = m.[branchId])
        ) SET @v_orphan_branch = @v_orphan_branch + 1;

        IF OBJECT_ID('dbo.Staff','U') IS NOT NULL AND EXISTS (
            SELECT 1 FROM dbo.Staff s WHERE s.[branchId] IS NOT NULL
            AND NOT EXISTS (SELECT 1 FROM dbo.Branch b WHERE b.[id] = s.[branchId])
        ) SET @v_orphan_branch = @v_orphan_branch + 1;

        IF OBJECT_ID('dbo.[User]','U') IS NOT NULL AND EXISTS (
            SELECT 1 FROM dbo.[User] u WHERE u.[branchId] IS NOT NULL
            AND NOT EXISTS (SELECT 1 FROM dbo.Branch b WHERE b.[id] = u.[branchId])
        ) SET @v_orphan_branch = @v_orphan_branch + 1;

        IF @v_orphan_branch > 0
            RAISERROR(N'Verification failed: orphaned branchId references found', 16, 1);

        PRINT N'  10b: verification OK (id=code, control clean, no orphans)';

        DROP TABLE #branch_map;
        DROP TABLE #branch_fks;

        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'10b-Branch-hierarchy', N'OK', N'Branch hierarchy created (00 Company, 01 Head Office, 01001/01002 Detail); all branchId references remapped in-place');
        PRINT N'  10b-Branch-hierarchy: OK - Branch hierarchy created; all references remapped in-place';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF OBJECT_ID('tempdb..#branch_map', 'U') IS NOT NULL DROP TABLE #branch_map;
        IF OBJECT_ID('tempdb..#branch_fks', 'U') IS NOT NULL DROP TABLE #branch_fks;
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'10b-Branch-hierarchy', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  10b-Branch-hierarchy: FAILED - Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg;
    END CATCH
END
GO

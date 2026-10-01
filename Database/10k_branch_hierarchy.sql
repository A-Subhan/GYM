USE GymDB;
GO

-- ============================================================================
-- 10k_branch_hierarchy.sql
-- ============================================================================
-- Step 10b: Branch hierarchy — id = code, Control/Detail node types,
-- parent chain, detail fields on Detail nodes only.
--
-- Target structure:
--   00 Company            (Control, parent NULL)
--   01 Head Office        (Control, parent 00)
--   01001 (former BR-001) (Detail, parent 01, keeps its details)
--   01002 (former BR-002) (Detail, parent 01, keeps its details)
--
-- Safe order of operations:
--   a. Save all FK definitions referencing Branch, then DROP them.
--   b. Build old id -> new id mapping (old cuid/BR-xxx -> new code).
--   c. Create Control nodes '00' (Company) and '01' (Head Office).
--   d. Rename old Branch -> Branch_legacy_bak (never DROP).
--   e. Create fresh Branch table with new rows:
--      - Control nodes: id = code, nodeType = 'Control', detail fields NULL.
--      - Detail nodes: id = code (new hierarchical code), nodeType = 'Detail',
--        parentId = Control parent id, keep all detail fields.
--   f. Recreate PK on Branch.id.
--   g. Update every table with branchId column through the mapping.
--   h. Recreate FKs with original names and actions.
--   i. Verify: every branch has a valid parent chain, no orphan branchId,
--      control nodes have no detail data.
--   j. COMMIT only after verification.
-- ============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

PRINT N'=== STEP 10b: Branch hierarchy ===';

-- Preflight
IF OBJECT_ID('dbo.Branch','U') IS NOT NULL
BEGIN
    -- Check if already migrated (any branch with id = '00')
    IF EXISTS (SELECT 1 FROM dbo.Branch WHERE [id] = N'00')
    BEGIN
        PRINT N'  preflight: Branch hierarchy already migrated (id 00 exists)';
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'10b-Branch-hierarchy', N'SKIPPED', N'Branch hierarchy already in place (id 00 exists)');
        PRINT N'  10b-Branch-hierarchy: SKIPPED - already in place';
    END
    ELSE
    BEGIN
        PRINT N'  preflight: Branch hierarchy NOT yet migrated - will proceed';
        -- Show current branch data
        DECLARE @pf_count INT = 0;
        SELECT @pf_count = COUNT(*) FROM dbo.Branch;
        PRINT N'  preflight: ' + CAST(@pf_count AS NVARCHAR(10)) + N' branches exist';
    END
END
ELSE
BEGIN
    PRINT N'  preflight: Branch table MISSING';
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'10b-Branch-hierarchy', N'SKIPPED', N'Branch table missing');
    PRINT N'  10b-Branch-hierarchy: SKIPPED - Branch table missing';
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
            SET @drop_bfk_sql = N'ALTER TABLE [dbo].' + QUOTENAME(@bfk_parent)
                + N' DROP CONSTRAINT [' + @bfk_name + N']';
            EXEC sp_executesql @drop_bfk_sql;
            PRINT N'  10b: dropped FK [' + @bfk_name + N'] on [' + @bfk_parent + N']';
            FETCH NEXT FROM drop_bfk_cur INTO @bfk_name, @bfk_parent;
        END
        CLOSE drop_bfk_cur;
        DEALLOCATE drop_bfk_cur;

        -- Also drop the self-referencing FK Branch_parentId_fkey
        IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'Branch_parentId_fkey'
                   AND parent_object_id = OBJECT_ID('dbo.Branch'))
        BEGIN
            EXEC sp_executesql N'ALTER TABLE [dbo].[Branch] DROP CONSTRAINT [Branch_parentId_fkey]';
            PRINT N'  10b: dropped Branch_parentId_fkey (self-ref)';
        END

        -- Drop Branch PK and unique constraint on code
        DECLARE @bpk_name NVARCHAR(256);
        SELECT @bpk_name = name FROM sys.key_constraints
        WHERE type = N'PK' AND parent_object_id = OBJECT_ID('dbo.Branch');
        IF @bpk_name IS NOT NULL
        BEGIN
            DECLARE @drop_bpk_sql NVARCHAR(MAX) = N'ALTER TABLE [dbo].[Branch] DROP CONSTRAINT [' + @bpk_name + N']';
            EXEC sp_executesql @drop_bpk_sql;
            PRINT N'  10b: dropped PK [' + @bpk_name + N']';
        END

        IF EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = N'Branch_code_key' AND parent_object_id = OBJECT_ID('dbo.Branch'))
        BEGIN
            EXEC sp_executesql N'ALTER TABLE [dbo].[Branch] DROP CONSTRAINT [Branch_code_key]';
            PRINT N'  10b: dropped unique Branch_code_key';
        END

        -- 10b-b. Build old id -> new id mapping.
        -- Existing branches are flat (parentId = NULL, nodeType = Detail).
        -- We create:
        --   00 = Company (Control)
        --   01 = Head Office (Control, parent 00)
        --   01001 = former branch 1 (Detail, parent 01)
        --   01002 = former branch 2 (Detail, parent 01)
        IF OBJECT_ID('tempdb..#branch_map', 'U') IS NOT NULL DROP TABLE #branch_map;
        CREATE TABLE #branch_map (old_id NVARCHAR(50), new_id NVARCHAR(50));

        INSERT INTO #branch_map (old_id, new_id)
        SELECT [id], N'01' + RIGHT(N'00' + CAST(ROW_NUMBER() OVER (ORDER BY [code], [id]) AS NVARCHAR(10)), 3)
        FROM dbo.Branch
        WHERE [parentId] IS NULL
        ORDER BY [code], [id];

        -- 10b-c. Rename old Branch -> Branch_legacy_bak (never DROP).
        IF OBJECT_ID('dbo.Branch_legacy_bak','U') IS NULL
            EXEC sp_rename N'dbo.Branch', N'Branch_legacy_bak';

        -- 10b-d. Create fresh Branch table.
        CREATE TABLE [dbo].[Branch] (
            [id]        NVARCHAR(50)  NOT NULL,
            [code]      NVARCHAR(191) NOT NULL,
            [name]      NVARCHAR(255) NOT NULL,
            [parentId]  NVARCHAR(50),
            [nodeType]  NVARCHAR(1000) NOT NULL CONSTRAINT [Branch_nodeType_df] DEFAULT N'Detail',
            [address]   NVARCHAR(MAX),
            [city]      NVARCHAR(255),
            [phone]     NVARCHAR(255),
            [email]     NVARCHAR(255),
            [strn]      NVARCHAR(255),
            [ntn]       NVARCHAR(255),
            [trn]       NVARCHAR(255),
            [fbr]       NVARCHAR(255),
            [logo]      NVARCHAR(255),
            [isActive]  BIT NOT NULL DEFAULT 1,
            [createdAt] DATETIME2 NOT NULL DEFAULT CURRENT_TIMESTAMP,
            [updatedAt] DATETIME2 NOT NULL,
            [isDeleted] BIT NOT NULL DEFAULT 0,
            CONSTRAINT [Branch_pkey]     PRIMARY KEY CLUSTERED ([id]),
            CONSTRAINT [Branch_code_key] UNIQUE NONCLUSTERED ([code])
        );

        -- Insert Company node (00, Control)
        DECLARE @company_name NVARCHAR(255) = N'Company';
        -- Try to get the company name from dbo.Defaults or Company settings
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

        -- Insert Head Office node (01, Control, parent 00)
        INSERT INTO [dbo].[Branch] ([id], [code], [name], [parentId], [nodeType],
            [address], [city], [phone], [email], [strn], [ntn], [trn], [fbr], [logo],
            [isActive], [createdAt], [updatedAt], [isDeleted])
        VALUES (N'01', N'01', N'Head Office', N'00', N'Control',
            NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
            1, SYSDATETIME(), SYSDATETIME(), 0);

        -- Insert Detail nodes (former branches, parent 01, keep their details)
        INSERT INTO [dbo].[Branch] ([id], [code], [name], [parentId], [nodeType],
            [address], [city], [phone], [email], [strn], [ntn], [trn], [fbr], [logo],
            [isActive], [createdAt], [updatedAt], [isDeleted])
        SELECT
            m.new_id,
            m.new_id,
            lb.[name],
            N'01',
            N'Detail',
            lb.[address], lb.[city], lb.[phone], lb.[email],
            lb.[strn], lb.[ntn], lb.[trn], lb.[fbr], lb.[logo],
            lb.[isActive], lb.[createdAt], lb.[updatedAt], lb.[isDeleted]
        FROM #branch_map m
        JOIN [dbo].[Branch_legacy_bak] lb ON lb.[id] = m.old_id;

        -- 10b-e. Recreate the self-referencing FK (Branch_parentId_fkey).
        ALTER TABLE [dbo].[Branch] ADD CONSTRAINT [Branch_parentId_fkey]
            FOREIGN KEY ([parentId]) REFERENCES [dbo].[Branch]([id])
            ON DELETE NO ACTION ON UPDATE NO ACTION;
        PRINT N'  10b: recreated Branch_parentId_fkey';

        -- 10b-f. Update every table with branchId through the mapping.
        -- This includes FK-constrained tables AND non-FK tables that have a branchId column.
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

        -- 10b-g. Recreate FKs with original names and actions.
        DECLARE @rbfk_name NVARCHAR(256), @rbfk_tbl NVARCHAR(128), @rbfk_col NVARCHAR(128);
        DECLARE @rbfk_del NVARCHAR(20), @rbfk_upd NVARCHAR(20);
        DECLARE @add_rbfk_sql NVARCHAR(MAX);
        DECLARE add_rbfk_cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT DISTINCT fk_name, parent_table, parent_col, on_delete, on_update
            FROM #branch_fks
            WHERE parent_table <> N'Branch'; -- Skip self-ref (already done)

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

        -- 10b-h. Verify: every branch has a valid parent chain, no orphan branchId,
        --        control nodes have no detail data, id = code.
        DECLARE @v_orphan_branch INT = 0;
        DECLARE @v_bad_id_code INT = 0;
        DECLARE @v_control_has_detail INT = 0;

        -- id = code check
        SELECT @v_bad_id_code = COUNT(*) FROM dbo.Branch WHERE [id] <> [code];
        IF @v_bad_id_code > 0
            RAISERROR(N'Verification failed: %d branches where id <> code', 16, 1, @v_bad_id_code);

        -- Control nodes must have NULL detail fields
        SELECT @v_control_has_detail = COUNT(*) FROM dbo.Branch
        WHERE [nodeType] = N'Control'
          AND ([address] IS NOT NULL OR [city] IS NOT NULL OR [phone] IS NOT NULL
               OR [email] IS NOT NULL OR [strn] IS NOT NULL OR [ntn] IS NOT NULL
               OR [trn] IS NOT NULL OR [fbr] IS NOT NULL OR [logo] IS NOT NULL);
        IF @v_control_has_detail > 0
            RAISERROR(N'Verification failed: %d Control nodes have detail data', 16, 1, @v_control_has_detail);

        -- Check orphans: branches with invalid parentId
        SELECT @v_orphan_branch = COUNT(*)
        FROM [dbo].[Branch] b
        WHERE b.[parentId] IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM [dbo].[Branch] p WHERE p.[id] = b.[parentId]);

        -- Check orphan branchId in known child tables using static SQL
        IF OBJECT_ID('dbo.Member','U') IS NOT NULL AND EXISTS (
            SELECT 1 FROM dbo.Member m WHERE m.[branchId] IS NOT NULL
            AND NOT EXISTS (SELECT 1 FROM dbo.Branch b WHERE b.[id] = m.[branchId])
        ) SET @v_orphan_branch = @v_orphan_branch + 1;

        IF OBJECT_ID('dbo.Staff','U') IS NOT NULL AND EXISTS (
            SELECT 1 FROM dbo.Staff s WHERE s.[branchId] IS NOT NULL
            AND NOT EXISTS (SELECT 1 FROM dbo.Branch b WHERE b.[id] = s.[branchId])
        ) SET @v_orphan_branch = @v_orphan_branch + 1;

        IF OBJECT_ID('dbo.Attendance','U') IS NOT NULL AND EXISTS (
            SELECT 1 FROM dbo.Attendance a WHERE a.[branchId] IS NOT NULL
            AND NOT EXISTS (SELECT 1 FROM dbo.Branch b WHERE b.[id] = a.[branchId])
        ) SET @v_orphan_branch = @v_orphan_branch + 1;

        IF OBJECT_ID('dbo.Fee','U') IS NOT NULL AND EXISTS (
            SELECT 1 FROM dbo.Fee f WHERE f.[branchId] IS NOT NULL
            AND NOT EXISTS (SELECT 1 FROM dbo.Branch b WHERE b.[id] = f.[branchId])
        ) SET @v_orphan_branch = @v_orphan_branch + 1;

        IF OBJECT_ID('dbo.CashBook','U') IS NOT NULL AND EXISTS (
            SELECT 1 FROM dbo.CashBook c WHERE c.[branchId] IS NOT NULL
            AND NOT EXISTS (SELECT 1 FROM dbo.Branch b WHERE b.[id] = c.[branchId])
        ) SET @v_orphan_branch = @v_orphan_branch + 1;

        IF OBJECT_ID('dbo.BankBook','U') IS NOT NULL AND EXISTS (
            SELECT 1 FROM dbo.BankBook bk WHERE bk.[branchId] IS NOT NULL
            AND NOT EXISTS (SELECT 1 FROM dbo.Branch b WHERE b.[id] = bk.[branchId])
        ) SET @v_orphan_branch = @v_orphan_branch + 1;

        IF OBJECT_ID('dbo.[User]','U') IS NOT NULL AND EXISTS (
            SELECT 1 FROM dbo.[User] u WHERE u.[branchId] IS NOT NULL
            AND NOT EXISTS (SELECT 1 FROM dbo.Branch b WHERE b.[id] = u.[branchId])
        ) SET @v_orphan_branch = @v_orphan_branch + 1;

        IF @v_orphan_branch > 0
            RAISERROR(N'Verification failed: orphaned branchId references found', 16, 1);

        PRINT N'  10b: verification OK (id=code, control nodes clean, no orphans)';

        DROP TABLE #branch_map;
        DROP TABLE #branch_fks;

        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'10b-Branch-hierarchy', N'OK', N'Branch hierarchy created (00 Company, 01 Head Office, 01001/01002 Detail); all branchId references remapped');
        PRINT N'  10b-Branch-hierarchy: OK - Branch hierarchy created; all references remapped';
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

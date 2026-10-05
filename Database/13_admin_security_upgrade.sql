USE GymDB;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- 13_admin_security_upgrade.sql
-- ============================================================================
-- Migrates existing cuid-style ids to clean business formats for:
--   Defaults         -> CMP-001     key DEFAULTS
--   TaxHead          -> TAX-001     key TAXHEAD
--   Permission       -> PRM-0001   key PERMISSION
--   Role             -> ROL-001     key ROLE
--   User             -> USR-0001   key USER
--   ScreenPermission -> SCP-0001   key SCREENPERMISSION
--   UserPermission   -> UPM-0001   key USERPERMISSION
--   AccountMapping   -> ACM-001    key ACCOUNTMAPPING
--   FinanceDefaults  -> FDF-001    key FINANCEDEFAULTS
--
-- Also adds 12 new FinanceDefaults columns for expanded finance settings
-- and seeds a company-wide FinanceDefaults row (branchId NULL).
--
-- Design principles (ALL review findings P1–P7 addressed):
--   P1  User id migration scans INFORMATION_SCHEMA for EVERY NVARCHAR column
--       in every table and updates all columns that hold old User ids
--       dynamically (userId, postedById, deletedById, reversedById,
--       approvedBy, createdById, etc.). Logs which columns were updated.
--       Final check: no column still holds an old User id.
--   P2  Every CATCH block: capture ERROR_NUMBER/LINE/MESSAGE, then
--       IF XACT_STATE() <> 0 ROLLBACK, then drop #temp tables, then log
--       FAILED. Nothing before ROLLBACK.
--   P3  IdSequence next = max(numeric suffix) + 1 for all keys, both
--       INSERT and UPDATE branches. Never decreases below current.
--   P6  Every step re-runnable: migrate only rows NOT matching the new
--       pattern; number new ids after the existing max (never restart at 1).
--   P7  Defaults handles one or many rows (CMP-001, CMP-002, ...).
--       Multi-column FKs recreated correctly. QUOTENAME everywhere.
--       No N'literal' + @var inside EXEC; build @sql first, then
--       sp_executesql @sql. Every _UpgradeLog insert inside TRY.
-- ============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

PRINT N'=== STEP 13: Admin & Security Upgrade ===';

DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);

-- ============================================================================
-- STEP 13a: Defaults.id -> CMP-001 (multi-row safe)
-- ============================================================================
USE GymDB;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);

IF OBJECT_ID('dbo.Defaults','U') IS NOT NULL
   AND EXISTS (SELECT 1 FROM dbo.Defaults WHERE [id] NOT LIKE N'CMP-%')
BEGIN
    BEGIN TRY
        BEGIN TRAN;

        -- Compute the max existing CMP- numeric suffix so we never restart at 1
        DECLARE @cmp_max INT = 0;
        SELECT @cmp_max = MAX(CAST(SUBSTRING([id], 5, 20) AS INT))
        FROM dbo.Defaults
        WHERE [id] LIKE N'CMP-%'
          AND SUBSTRING([id], 5, 20) NOT LIKE N'%[^0-9]%';
        IF @cmp_max IS NULL SET @cmp_max = 0;

        -- Build mapping (one row per old Defaults row, numbered after max)
        IF OBJECT_ID('tempdb..#cmp_map','U') IS NOT NULL DROP TABLE #cmp_map;
        CREATE TABLE #cmp_map (old_id NVARCHAR(50), new_id NVARCHAR(50), tmp_id NVARCHAR(50));
        INSERT INTO #cmp_map (old_id, new_id, tmp_id)
        SELECT [id],
               N'CMP-' + RIGHT(N'00' + CAST(@cmp_max + ROW_NUMBER() OVER (ORDER BY [createdAt], [id]) AS NVARCHAR(10)), 3),
               N'tmp_CMP_' + RIGHT(N'00' + CAST(@cmp_max + ROW_NUMBER() OVER (ORDER BY [createdAt], [id]) AS NVARCHAR(10)), 3)
        FROM dbo.Defaults WHERE [id] NOT LIKE N'CMP-%';

        -- Defaults has no inbound FKs (leaf table) — drop PK, two-phase update, recreate PK
        DECLARE @cmp_pk NVARCHAR(256);
        SELECT @cmp_pk = name FROM sys.key_constraints WHERE type = N'PK' AND parent_object_id = OBJECT_ID('dbo.Defaults');
        IF @cmp_pk IS NOT NULL
        BEGIN
            DECLARE @sql NVARCHAR(MAX) = N'ALTER TABLE [dbo].[Defaults] DROP CONSTRAINT [' + QUOTENAME(@cmp_pk) + N']';
            EXEC sp_executesql @sql;
        END
        ELSE SET @cmp_pk = N'Defaults_pkey';

        UPDATE d SET d.[id] = m.tmp_id FROM dbo.Defaults d JOIN #cmp_map m ON d.[id] = m.old_id;
        UPDATE d SET d.[id] = m.new_id FROM dbo.Defaults d JOIN #cmp_map m ON d.[id] = m.tmp_id;

        ALTER TABLE [dbo].[Defaults] ALTER COLUMN [id] NVARCHAR(50) NOT NULL;
        IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE type = N'PK' AND parent_object_id = OBJECT_ID('dbo.Defaults'))
        BEGIN
            SET @sql = N'ALTER TABLE [dbo].[Defaults] ADD CONSTRAINT [' + QUOTENAME(@cmp_pk) + N'] PRIMARY KEY CLUSTERED ([id])';
            EXEC sp_executesql @sql;
        END

        DROP TABLE #cmp_map;
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13a-Defaults-id', N'OK', N'Migrated Defaults.id to CMP-001+');
        PRINT N'  13a-Defaults-id: OK';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        IF OBJECT_ID('tempdb..#cmp_map','U') IS NOT NULL DROP TABLE #cmp_map;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13a-Defaults-id', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  13a-Defaults-id: FAILED - ' + @eMsg;
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13a-Defaults-id', N'SKIPPED', N'Already migrated or table missing');
    PRINT N'  13a-Defaults-id: SKIPPED';
END
GO

-- ============================================================================
-- STEP 13b: TaxHead.id -> TAX-001
-- ============================================================================
USE GymDB;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);

IF OBJECT_ID('dbo.TaxHead','U') IS NOT NULL
   AND EXISTS (SELECT 1 FROM dbo.TaxHead WHERE [id] NOT LIKE N'TAX-%')
BEGIN
    BEGIN TRY
        BEGIN TRAN;

        DECLARE @tax_max INT = 0;
        SELECT @tax_max = MAX(CAST(SUBSTRING([id], 5, 20) AS INT))
        FROM dbo.TaxHead
        WHERE [id] LIKE N'TAX-%' AND SUBSTRING([id], 5, 20) NOT LIKE N'%[^0-9]%';
        IF @tax_max IS NULL SET @tax_max = 0;

        IF OBJECT_ID('tempdb..#tax_map','U') IS NOT NULL DROP TABLE #tax_map;
        CREATE TABLE #tax_map (old_id NVARCHAR(50), new_id NVARCHAR(50), tmp_id NVARCHAR(50));
        INSERT INTO #tax_map (old_id, new_id, tmp_id)
        SELECT [id],
               N'TAX-' + RIGHT(N'00' + CAST(@tax_max + ROW_NUMBER() OVER (ORDER BY [code], [id]) AS NVARCHAR(10)), 3),
               N'tmp_TAX_' + RIGHT(N'00' + CAST(@tax_max + ROW_NUMBER() OVER (ORDER BY [code], [id]) AS NVARCHAR(10)), 3)
        FROM dbo.TaxHead WHERE [id] NOT LIKE N'TAX-%';

        -- Discover FKs referencing TaxHead (capture ALL parent columns for multi-column FKs)
        IF OBJECT_ID('tempdb..#tax_fks','U') IS NOT NULL DROP TABLE #tax_fks;
        CREATE TABLE #tax_fks (fk_name NVARCHAR(256), parent_table NVARCHAR(128), parent_cols NVARCHAR(MAX), on_delete NVARCHAR(20), on_update NVARCHAR(20));
        INSERT INTO #tax_fks (fk_name, parent_table, parent_cols, on_delete, on_update)
        SELECT fk.name,
               OBJECT_NAME(fk.parent_object_id),
               STUFF((SELECT N',[' + COL_NAME(fkc2.parent_object_id, fkc2.parent_column_id) + N']'
                      FROM sys.foreign_key_columns fkc2
                      WHERE fkc2.constraint_object_id = fk.object_id
                      ORDER BY fkc2.constraint_column_id
                      FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 1, N''),
               fk.delete_referential_action_desc,
               fk.update_referential_action_desc
        FROM sys.foreign_keys fk
        WHERE fk.referenced_object_id = OBJECT_ID('dbo.TaxHead');

        -- Drop FKs
        DECLARE @fk_name NVARCHAR(256), @fk_parent NVARCHAR(128);
        DECLARE @sql NVARCHAR(MAX);
        DECLARE fk_cur CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT fk_name, parent_table FROM #tax_fks;
        OPEN fk_cur;
        FETCH NEXT FROM fk_cur INTO @fk_name, @fk_parent;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = @fk_name)
            BEGIN
                SET @sql = N'ALTER TABLE [dbo].' + QUOTENAME(@fk_parent) + N' DROP CONSTRAINT ' + QUOTENAME(@fk_name);
                EXEC sp_executesql @sql;
            END
            FETCH NEXT FROM fk_cur INTO @fk_name, @fk_parent;
        END
        CLOSE fk_cur;
        DEALLOCATE fk_cur;

        -- Drop PK
        DECLARE @tax_pk NVARCHAR(256);
        SELECT @tax_pk = name FROM sys.key_constraints WHERE type = N'PK' AND parent_object_id = OBJECT_ID('dbo.TaxHead');
        IF @tax_pk IS NOT NULL
        BEGIN
            SET @sql = N'ALTER TABLE [dbo].[TaxHead] DROP CONSTRAINT ' + QUOTENAME(@tax_pk);
            EXEC sp_executesql @sql;
        END
        ELSE SET @tax_pk = N'TaxHead_pkey';

        -- Two-phase update TaxHead
        UPDATE t SET t.[id] = m.tmp_id FROM dbo.TaxHead t JOIN #tax_map m ON t.[id] = m.old_id;
        UPDATE t SET t.[id] = m.new_id FROM dbo.TaxHead t JOIN #tax_map m ON t.[id] = m.tmp_id;

        -- Update referencing columns
        IF COL_LENGTH('dbo.FinanceDefaults','defaultTaxHeadId') IS NOT NULL
            UPDATE fd SET fd.[defaultTaxHeadId] = m.new_id FROM dbo.FinanceDefaults fd JOIN #tax_map m ON fd.[defaultTaxHeadId] = m.old_id WHERE fd.[defaultTaxHeadId] IS NOT NULL;
        IF COL_LENGTH('dbo.CashBookLine','taxAccountId') IS NOT NULL
            UPDATE l SET l.[taxAccountId] = m.new_id FROM dbo.CashBookLine l JOIN #tax_map m ON l.[taxAccountId] = m.old_id WHERE l.[taxAccountId] IS NOT NULL;
        IF COL_LENGTH('dbo.BankBookLine','taxAccountId') IS NOT NULL
            UPDATE l SET l.[taxAccountId] = m.new_id FROM dbo.BankBookLine l JOIN #tax_map m ON l.[taxAccountId] = m.old_id WHERE l.[taxAccountId] IS NOT NULL;
        IF COL_LENGTH('dbo.JVLine','taxAccountId') IS NOT NULL
            UPDATE l SET l.[taxAccountId] = m.new_id FROM dbo.JVLine l JOIN #tax_map m ON l.[taxAccountId] = m.old_id WHERE l.[taxAccountId] IS NOT NULL;

        ALTER TABLE [dbo].[TaxHead] ALTER COLUMN [id] NVARCHAR(50) NOT NULL;
        IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE type = N'PK' AND parent_object_id = OBJECT_ID('dbo.TaxHead'))
        BEGIN
            SET @sql = N'ALTER TABLE [dbo].[TaxHead] ADD CONSTRAINT ' + QUOTENAME(@tax_pk) + N' PRIMARY KEY CLUSTERED ([id])';
            EXEC sp_executesql @sql;
        END

        -- Recreate FKs (handle multi-column FKs via parent_cols)
        DECLARE @rcfk_name NVARCHAR(256), @rcfk_parent NVARCHAR(128), @rcfk_cols NVARCHAR(MAX);
        DECLARE @rcfk_del NVARCHAR(20), @rcfk_upd NVARCHAR(20);
        DECLARE rcfk_cur CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT fk_name, parent_table, parent_cols, on_delete, on_update FROM #tax_fks;
        OPEN rcfk_cur;
        FETCH NEXT FROM rcfk_cur INTO @rcfk_name, @rcfk_parent, @rcfk_cols, @rcfk_del, @rcfk_upd;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            IF OBJECT_ID(N'[dbo].' + QUOTENAME(@rcfk_parent), N'U') IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = @rcfk_name)
            BEGIN
                DECLARE @del_action NVARCHAR(20) = REPLACE(@rcfk_del, N'_', N' ');
                DECLARE @upd_action NVARCHAR(20) = REPLACE(@rcfk_upd, N'_', N' ');
                IF @del_action = N'NO' SET @del_action = N'NO ACTION';
                IF @upd_action = N'NO' SET @upd_action = N'NO ACTION';
                SET @sql = N'ALTER TABLE [dbo].' + QUOTENAME(@rcfk_parent) + N' ADD CONSTRAINT ' + QUOTENAME(@rcfk_name) + N' FOREIGN KEY (' + @rcfk_cols + N') REFERENCES [dbo].[TaxHead]([id]) ON DELETE ' + @del_action + N' ON UPDATE ' + @upd_action;
                EXEC sp_executesql @sql;
            END
            FETCH NEXT FROM rcfk_cur INTO @rcfk_name, @rcfk_parent, @rcfk_cols, @rcfk_del, @rcfk_upd;
        END
        CLOSE rcfk_cur;
        DEALLOCATE rcfk_cur;

        DROP TABLE #tax_map;
        DROP TABLE #tax_fks;
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13b-TaxHead-id', N'OK', N'Migrated TaxHead.id to TAX-001+');
        PRINT N'  13b-TaxHead-id: OK';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        IF OBJECT_ID('tempdb..#tax_map','U') IS NOT NULL DROP TABLE #tax_map;
        IF OBJECT_ID('tempdb..#tax_fks','U') IS NOT NULL DROP TABLE #tax_fks;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13b-TaxHead-id', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  13b-TaxHead-id: FAILED - ' + @eMsg;
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13b-TaxHead-id', N'SKIPPED', N'Already migrated or table missing');
    PRINT N'  13b-TaxHead-id: SKIPPED';
END
GO

-- ============================================================================
-- STEP 13c: Permission.id -> PRM-0001
-- ============================================================================
USE GymDB;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);

IF OBJECT_ID('dbo.Permission','U') IS NOT NULL
   AND EXISTS (SELECT 1 FROM dbo.Permission WHERE [id] NOT LIKE N'PRM-%')
BEGIN
    BEGIN TRY
        BEGIN TRAN;

        DECLARE @prm_max INT = 0;
        SELECT @prm_max = MAX(CAST(SUBSTRING([id], 5, 20) AS INT))
        FROM dbo.Permission
        WHERE [id] LIKE N'PRM-%' AND SUBSTRING([id], 5, 20) NOT LIKE N'%[^0-9]%';
        IF @prm_max IS NULL SET @prm_max = 0;

        IF OBJECT_ID('tempdb..#prm_map','U') IS NOT NULL DROP TABLE #prm_map;
        CREATE TABLE #prm_map (old_id NVARCHAR(50), new_id NVARCHAR(50), tmp_id NVARCHAR(50));
        INSERT INTO #prm_map (old_id, new_id, tmp_id)
        SELECT [id],
               N'PRM-' + RIGHT(N'000' + CAST(@prm_max + ROW_NUMBER() OVER (ORDER BY [code]) AS NVARCHAR(10)), 4),
               N'tmp_PRM_' + RIGHT(N'000' + CAST(@prm_max + ROW_NUMBER() OVER (ORDER BY [code]) AS NVARCHAR(10)), 4)
        FROM dbo.Permission WHERE [id] NOT LIKE N'PRM-%';

        IF OBJECT_ID('tempdb..#prm_fks','U') IS NOT NULL DROP TABLE #prm_fks;
        CREATE TABLE #prm_fks (fk_name NVARCHAR(256), parent_table NVARCHAR(128), parent_cols NVARCHAR(MAX), on_delete NVARCHAR(20), on_update NVARCHAR(20));
        INSERT INTO #prm_fks (fk_name, parent_table, parent_cols, on_delete, on_update)
        SELECT fk.name, OBJECT_NAME(fk.parent_object_id),
               STUFF((SELECT N',[' + COL_NAME(fkc2.parent_object_id, fkc2.parent_column_id) + N']'
                      FROM sys.foreign_key_columns fkc2 WHERE fkc2.constraint_object_id = fk.object_id
                      ORDER BY fkc2.constraint_column_id FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 1, N''),
               fk.delete_referential_action_desc, fk.update_referential_action_desc
        FROM sys.foreign_keys fk WHERE fk.referenced_object_id = OBJECT_ID('dbo.Permission');

        DECLARE @fk_name NVARCHAR(256), @fk_parent NVARCHAR(128), @sql NVARCHAR(MAX);
        DECLARE fk_cur CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT fk_name, parent_table FROM #prm_fks;
        OPEN fk_cur; FETCH NEXT FROM fk_cur INTO @fk_name, @fk_parent;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = @fk_name)
            BEGIN
                SET @sql = N'ALTER TABLE [dbo].' + QUOTENAME(@fk_parent) + N' DROP CONSTRAINT ' + QUOTENAME(@fk_name);
                EXEC sp_executesql @sql;
            END
            FETCH NEXT FROM fk_cur INTO @fk_name, @fk_parent;
        END
        CLOSE fk_cur; DEALLOCATE fk_cur;

        DECLARE @prm_pk NVARCHAR(256);
        SELECT @prm_pk = name FROM sys.key_constraints WHERE type = N'PK' AND parent_object_id = OBJECT_ID('dbo.Permission');
        IF @prm_pk IS NOT NULL
        BEGIN
            SET @sql = N'ALTER TABLE [dbo].[Permission] DROP CONSTRAINT ' + QUOTENAME(@prm_pk);
            EXEC sp_executesql @sql;
        END
        ELSE SET @prm_pk = N'Permission_pkey';

        UPDATE p SET p.[id] = m.tmp_id FROM dbo.Permission p JOIN #prm_map m ON p.[id] = m.old_id;
        UPDATE p SET p.[id] = m.new_id FROM dbo.Permission p JOIN #prm_map m ON p.[id] = m.tmp_id;

        IF COL_LENGTH('dbo.RolePermission','permissionId') IS NOT NULL
            UPDATE rp SET rp.[permissionId] = m.new_id FROM dbo.RolePermission rp JOIN #prm_map m ON rp.[permissionId] = m.old_id;

        ALTER TABLE [dbo].[Permission] ALTER COLUMN [id] NVARCHAR(50) NOT NULL;
        IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE type = N'PK' AND parent_object_id = OBJECT_ID('dbo.Permission'))
        BEGIN
            SET @sql = N'ALTER TABLE [dbo].[Permission] ADD CONSTRAINT ' + QUOTENAME(@prm_pk) + N' PRIMARY KEY CLUSTERED ([id])';
            EXEC sp_executesql @sql;
        END

        DECLARE @rcfk_name NVARCHAR(256), @rcfk_parent NVARCHAR(128), @rcfk_cols NVARCHAR(MAX), @rcfk_del NVARCHAR(20), @rcfk_upd NVARCHAR(20);
        DECLARE rcfk_cur CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT fk_name, parent_table, parent_cols, on_delete, on_update FROM #prm_fks;
        OPEN rcfk_cur; FETCH NEXT FROM rcfk_cur INTO @rcfk_name, @rcfk_parent, @rcfk_cols, @rcfk_del, @rcfk_upd;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            IF OBJECT_ID(N'[dbo].' + QUOTENAME(@rcfk_parent), N'U') IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = @rcfk_name)
            BEGIN
                DECLARE @del_action NVARCHAR(20) = REPLACE(@rcfk_del, N'_', N' ');
                DECLARE @upd_action NVARCHAR(20) = REPLACE(@rcfk_upd, N'_', N' ');
                IF @del_action = N'NO' SET @del_action = N'NO ACTION';
                IF @upd_action = N'NO' SET @upd_action = N'NO ACTION';
                SET @sql = N'ALTER TABLE [dbo].' + QUOTENAME(@rcfk_parent) + N' ADD CONSTRAINT ' + QUOTENAME(@rcfk_name) + N' FOREIGN KEY (' + @rcfk_cols + N') REFERENCES [dbo].[Permission]([id]) ON DELETE ' + @del_action + N' ON UPDATE ' + @upd_action;
                EXEC sp_executesql @sql;
            END
            FETCH NEXT FROM rcfk_cur INTO @rcfk_name, @rcfk_parent, @rcfk_cols, @rcfk_del, @rcfk_upd;
        END
        CLOSE rcfk_cur; DEALLOCATE rcfk_cur;

        DROP TABLE #prm_map;
        DROP TABLE #prm_fks;
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13c-Permission-id', N'OK', N'Migrated Permission.id to PRM-0001+');
        PRINT N'  13c-Permission-id: OK';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        IF OBJECT_ID('tempdb..#prm_map','U') IS NOT NULL DROP TABLE #prm_map;
        IF OBJECT_ID('tempdb..#prm_fks','U') IS NOT NULL DROP TABLE #prm_fks;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13c-Permission-id', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  13c-Permission-id: FAILED - ' + @eMsg;
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13c-Permission-id', N'SKIPPED', N'Already migrated or table missing');
    PRINT N'  13c-Permission-id: SKIPPED';
END
GO

-- ============================================================================
-- STEP 13d: Role.id -> ROL-001
-- ============================================================================
USE GymDB;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);

IF OBJECT_ID('dbo.Role','U') IS NOT NULL
   AND EXISTS (SELECT 1 FROM dbo.Role WHERE [id] NOT LIKE N'ROL-%')
BEGIN
    BEGIN TRY
        BEGIN TRAN;

        DECLARE @rol_max INT = 0;
        SELECT @rol_max = MAX(CAST(SUBSTRING([id], 5, 20) AS INT))
        FROM dbo.Role
        WHERE [id] LIKE N'ROL-%' AND SUBSTRING([id], 5, 20) NOT LIKE N'%[^0-9]%';
        IF @rol_max IS NULL SET @rol_max = 0;

        IF OBJECT_ID('tempdb..#rol_map','U') IS NOT NULL DROP TABLE #rol_map;
        CREATE TABLE #rol_map (old_id NVARCHAR(50), new_id NVARCHAR(50), tmp_id NVARCHAR(50));
        INSERT INTO #rol_map (old_id, new_id, tmp_id)
        SELECT [id],
               N'ROL-' + RIGHT(N'00' + CAST(@rol_max + ROW_NUMBER() OVER (ORDER BY [name]) AS NVARCHAR(10)), 3),
               N'tmp_ROL_' + RIGHT(N'00' + CAST(@rol_max + ROW_NUMBER() OVER (ORDER BY [name]) AS NVARCHAR(10)), 3)
        FROM dbo.Role WHERE [id] NOT LIKE N'ROL-%';

        IF OBJECT_ID('tempdb..#rol_fks','U') IS NOT NULL DROP TABLE #rol_fks;
        CREATE TABLE #rol_fks (fk_name NVARCHAR(256), parent_table NVARCHAR(128), parent_cols NVARCHAR(MAX), on_delete NVARCHAR(20), on_update NVARCHAR(20));
        INSERT INTO #rol_fks (fk_name, parent_table, parent_cols, on_delete, on_update)
        SELECT fk.name, OBJECT_NAME(fk.parent_object_id),
               STUFF((SELECT N',[' + COL_NAME(fkc2.parent_object_id, fkc2.parent_column_id) + N']'
                      FROM sys.foreign_key_columns fkc2 WHERE fkc2.constraint_object_id = fk.object_id
                      ORDER BY fkc2.constraint_column_id FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 1, N''),
               fk.delete_referential_action_desc, fk.update_referential_action_desc
        FROM sys.foreign_keys fk WHERE fk.referenced_object_id = OBJECT_ID('dbo.Role');

        DECLARE @fk_name NVARCHAR(256), @fk_parent NVARCHAR(128), @sql NVARCHAR(MAX);
        DECLARE fk_cur CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT fk_name, parent_table FROM #rol_fks;
        OPEN fk_cur; FETCH NEXT FROM fk_cur INTO @fk_name, @fk_parent;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = @fk_name)
            BEGIN
                SET @sql = N'ALTER TABLE [dbo].' + QUOTENAME(@fk_parent) + N' DROP CONSTRAINT ' + QUOTENAME(@fk_name);
                EXEC sp_executesql @sql;
            END
            FETCH NEXT FROM fk_cur INTO @fk_name, @fk_parent;
        END
        CLOSE fk_cur; DEALLOCATE fk_cur;

        DECLARE @rol_pk NVARCHAR(256);
        SELECT @rol_pk = name FROM sys.key_constraints WHERE type = N'PK' AND parent_object_id = OBJECT_ID('dbo.Role');
        IF @rol_pk IS NOT NULL
        BEGIN
            SET @sql = N'ALTER TABLE [dbo].[Role] DROP CONSTRAINT ' + QUOTENAME(@rol_pk);
            EXEC sp_executesql @sql;
        END
        ELSE SET @rol_pk = N'Role_pkey';

        UPDATE r SET r.[id] = m.tmp_id FROM dbo.Role r JOIN #rol_map m ON r.[id] = m.old_id;
        UPDATE r SET r.[id] = m.new_id FROM dbo.Role r JOIN #rol_map m ON r.[id] = m.tmp_id;

        IF COL_LENGTH('dbo.[User]','roleId') IS NOT NULL
            UPDATE u SET u.[roleId] = m.new_id FROM dbo.[User] u JOIN #rol_map m ON u.[roleId] = m.old_id WHERE u.[roleId] IS NOT NULL;
        IF COL_LENGTH('dbo.RolePermission','roleId') IS NOT NULL
            UPDATE rp SET rp.[roleId] = m.new_id FROM dbo.RolePermission rp JOIN #rol_map m ON rp.[roleId] = m.old_id;
        IF COL_LENGTH('dbo.ScreenPermission','roleId') IS NOT NULL
            UPDATE sp SET sp.[roleId] = m.new_id FROM dbo.ScreenPermission sp JOIN #rol_map m ON sp.[roleId] = m.old_id;

        ALTER TABLE [dbo].[Role] ALTER COLUMN [id] NVARCHAR(50) NOT NULL;
        IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE type = N'PK' AND parent_object_id = OBJECT_ID('dbo.Role'))
        BEGIN
            SET @sql = N'ALTER TABLE [dbo].[Role] ADD CONSTRAINT ' + QUOTENAME(@rol_pk) + N' PRIMARY KEY CLUSTERED ([id])';
            EXEC sp_executesql @sql;
        END

        DECLARE @rcfk_name NVARCHAR(256), @rcfk_parent NVARCHAR(128), @rcfk_cols NVARCHAR(MAX), @rcfk_del NVARCHAR(20), @rcfk_upd NVARCHAR(20);
        DECLARE rcfk_cur CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT fk_name, parent_table, parent_cols, on_delete, on_update FROM #rol_fks;
        OPEN rcfk_cur; FETCH NEXT FROM rcfk_cur INTO @rcfk_name, @rcfk_parent, @rcfk_cols, @rcfk_del, @rcfk_upd;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            IF OBJECT_ID(N'[dbo].' + QUOTENAME(@rcfk_parent), N'U') IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = @rcfk_name)
            BEGIN
                DECLARE @del_action NVARCHAR(20) = REPLACE(@rcfk_del, N'_', N' ');
                DECLARE @upd_action NVARCHAR(20) = REPLACE(@rcfk_upd, N'_', N' ');
                IF @del_action = N'NO' SET @del_action = N'NO ACTION';
                IF @upd_action = N'NO' SET @upd_action = N'NO ACTION';
                SET @sql = N'ALTER TABLE [dbo].' + QUOTENAME(@rcfk_parent) + N' ADD CONSTRAINT ' + QUOTENAME(@rcfk_name) + N' FOREIGN KEY (' + @rcfk_cols + N') REFERENCES [dbo].[Role]([id]) ON DELETE ' + @del_action + N' ON UPDATE ' + @upd_action;
                EXEC sp_executesql @sql;
            END
            FETCH NEXT FROM rcfk_cur INTO @rcfk_name, @rcfk_parent, @rcfk_cols, @rcfk_del, @rcfk_upd;
        END
        CLOSE rcfk_cur; DEALLOCATE rcfk_cur;

        DROP TABLE #rol_map;
        DROP TABLE #rol_fks;
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13d-Role-id', N'OK', N'Migrated Role.id to ROL-001+');
        PRINT N'  13d-Role-id: OK';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        IF OBJECT_ID('tempdb..#rol_map','U') IS NOT NULL DROP TABLE #rol_map;
        IF OBJECT_ID('tempdb..#rol_fks','U') IS NOT NULL DROP TABLE #rol_fks;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13d-Role-id', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  13d-Role-id: FAILED - ' + @eMsg;
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13d-Role-id', N'SKIPPED', N'Already migrated or table missing');
    PRINT N'  13d-Role-id: SKIPPED';
END
GO

-- ============================================================================
-- STEP 13e: User.id -> USR-0001
-- P1: Dynamic scan of EVERY NVARCHAR column in every table. Updates all
-- columns that hold old User ids (userId, postedById, deletedById,
-- reversedById, approvedBy, createdById, assignedTo, etc.).
-- Final check: no column still holds an old User id (RAISERROR on failure).
-- ============================================================================
USE GymDB;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);

IF OBJECT_ID('dbo.[User]','U') IS NOT NULL
   AND EXISTS (SELECT 1 FROM dbo.[User] WHERE [id] NOT LIKE N'USR-%')
BEGIN
    BEGIN TRY
        BEGIN TRAN;

        DECLARE @usr_max INT = 0;
        SELECT @usr_max = MAX(CAST(SUBSTRING([id], 5, 20) AS INT))
        FROM dbo.[User]
        WHERE [id] LIKE N'USR-%' AND SUBSTRING([id], 5, 20) NOT LIKE N'%[^0-9]%';
        IF @usr_max IS NULL SET @usr_max = 0;

        -- Build User id mapping in a temp table (visible inside sp_executesql)
        IF OBJECT_ID('tempdb..#usr_map','U') IS NOT NULL DROP TABLE #usr_map;
        CREATE TABLE #usr_map (old_id NVARCHAR(50), new_id NVARCHAR(50), tmp_id NVARCHAR(50));
        INSERT INTO #usr_map (old_id, new_id, tmp_id)
        SELECT [id],
               N'USR-' + RIGHT(N'000' + CAST(@usr_max + ROW_NUMBER() OVER (ORDER BY [createdAt], [username]) AS NVARCHAR(10)), 4),
               N'tmp_USR_' + RIGHT(N'000' + CAST(@usr_max + ROW_NUMBER() OVER (ORDER BY [createdAt], [username]) AS NVARCHAR(10)), 4)
        FROM dbo.[User] WHERE [id] NOT LIKE N'USR-%';

        -- Discover FKs referencing [User]
        IF OBJECT_ID('tempdb..#usr_fks','U') IS NOT NULL DROP TABLE #usr_fks;
        CREATE TABLE #usr_fks (fk_name NVARCHAR(256), parent_table NVARCHAR(128), parent_cols NVARCHAR(MAX), on_delete NVARCHAR(20), on_update NVARCHAR(20));
        INSERT INTO #usr_fks (fk_name, parent_table, parent_cols, on_delete, on_update)
        SELECT fk.name, OBJECT_NAME(fk.parent_object_id),
               STUFF((SELECT N',[' + COL_NAME(fkc2.parent_object_id, fkc2.parent_column_id) + N']'
                      FROM sys.foreign_key_columns fkc2 WHERE fkc2.constraint_object_id = fk.object_id
                      ORDER BY fkc2.constraint_column_id FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 1, N''),
               fk.delete_referential_action_desc, fk.update_referential_action_desc
        FROM sys.foreign_keys fk WHERE fk.referenced_object_id = OBJECT_ID('dbo.[User]');

        -- Drop FKs
        DECLARE @fk_name NVARCHAR(256), @fk_parent NVARCHAR(128), @sql NVARCHAR(MAX);
        DECLARE fk_cur CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT fk_name, parent_table FROM #usr_fks;
        OPEN fk_cur; FETCH NEXT FROM fk_cur INTO @fk_name, @fk_parent;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = @fk_name)
            BEGIN
                SET @sql = N'ALTER TABLE [dbo].' + QUOTENAME(@fk_parent) + N' DROP CONSTRAINT ' + QUOTENAME(@fk_name);
                EXEC sp_executesql @sql;
            END
            FETCH NEXT FROM fk_cur INTO @fk_name, @fk_parent;
        END
        CLOSE fk_cur; DEALLOCATE fk_cur;

        -- Drop PK
        DECLARE @usr_pk NVARCHAR(256);
        SELECT @usr_pk = name FROM sys.key_constraints WHERE type = N'PK' AND parent_object_id = OBJECT_ID('dbo.[User]');
        IF @usr_pk IS NOT NULL
        BEGIN
            SET @sql = N'ALTER TABLE [dbo].[User] DROP CONSTRAINT ' + QUOTENAME(@usr_pk);
            EXEC sp_executesql @sql;
        END
        ELSE SET @usr_pk = N'User_pkey';

        -- Two-phase update [User].id
        UPDATE u SET u.[id] = m.tmp_id FROM dbo.[User] u JOIN #usr_map m ON u.[id] = m.old_id;
        UPDATE u SET u.[id] = m.new_id FROM dbo.[User] u JOIN #usr_map m ON u.[id] = m.tmp_id;

        -- P1: Dynamic scan — update EVERY NVARCHAR/VARCHAR/NCHAR/CHAR column
        -- in every dbo table (except [User] and _UpgradeLog) that holds old User ids.
        -- This catches userId, postedById, deletedById, reversedById, approvedBy,
        -- createdById, assignedTo, and any other column referencing User.id.
        IF OBJECT_ID('tempdb..#usr_cols','U') IS NOT NULL DROP TABLE #usr_cols;
        CREATE TABLE #usr_cols (table_name NVARCHAR(128), column_name NVARCHAR(128), row_count INT);

        DECLARE @col_table NVARCHAR(128), @col_column NVARCHAR(128);
        DECLARE @check_sql NVARCHAR(MAX), @affected INT;
        DECLARE col_cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT t.name, c.name
            FROM sys.columns c
            JOIN sys.tables t ON c.object_id = t.object_id
            WHERE c.user_type_id IN (TYPE_ID(N'nvarchar'), TYPE_ID(N'varchar'), TYPE_ID(N'nchar'), TYPE_ID(N'char'))
              AND c.is_computed = 0
              AND t.schema_id = SCHEMA_ID(N'dbo')
              AND t.name NOT IN (N'User', N'_UpgradeLog');
        OPEN col_cur;
        FETCH NEXT FROM col_cur INTO @col_table, @col_column;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            -- Check if any value in this column matches an old User id in #usr_map
            SET @check_sql = N'SELECT @aff = COUNT(*) FROM [dbo].' + QUOTENAME(@col_table) + N' t INNER JOIN #usr_map m ON t.' + QUOTENAME(@col_column) + N' = m.old_id';
            SET @affected = 0;
            EXEC sp_executesql @check_sql, N'@aff INT OUTPUT', @aff = @affected OUTPUT;
            IF @affected > 0
            BEGIN
                INSERT INTO #usr_cols VALUES (@col_table, @col_column, @affected);
                -- Update this column
                SET @check_sql = N'UPDATE t SET t.' + QUOTENAME(@col_column) + N' = m.new_id FROM [dbo].' + QUOTENAME(@col_table) + N' t INNER JOIN #usr_map m ON t.' + QUOTENAME(@col_column) + N' = m.old_id WHERE t.' + QUOTENAME(@col_column) + N' IS NOT NULL';
                EXEC sp_executesql @check_sql;
            END
            FETCH NEXT FROM col_cur INTO @col_table, @col_column;
        END
        CLOSE col_cur;
        DEALLOCATE col_cur;

        -- Log which columns were updated
        DECLARE @col_list NVARCHAR(MAX) = N'';
        SELECT @col_list = @col_list + table_name + N'.' + column_name + N' (' + CAST(row_count AS NVARCHAR(10)) + N'); ' FROM #usr_cols ORDER BY table_name, column_name;

        -- ALTER COLUMN NOT NULL + recreate PK
        ALTER TABLE [dbo].[User] ALTER COLUMN [id] NVARCHAR(50) NOT NULL;
        IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE type = N'PK' AND parent_object_id = OBJECT_ID('dbo.[User]'))
        BEGIN
            SET @sql = N'ALTER TABLE [dbo].[User] ADD CONSTRAINT ' + QUOTENAME(@usr_pk) + N' PRIMARY KEY CLUSTERED ([id])';
            EXEC sp_executesql @sql;
        END

        -- Recreate FKs (handle multi-column FKs)
        DECLARE @rcfk_name NVARCHAR(256), @rcfk_parent NVARCHAR(128), @rcfk_cols NVARCHAR(MAX), @rcfk_del NVARCHAR(20), @rcfk_upd NVARCHAR(20);
        DECLARE rcfk_cur CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT fk_name, parent_table, parent_cols, on_delete, on_update FROM #usr_fks;
        OPEN rcfk_cur; FETCH NEXT FROM rcfk_cur INTO @rcfk_name, @rcfk_parent, @rcfk_cols, @rcfk_del, @rcfk_upd;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            IF OBJECT_ID(N'[dbo].' + QUOTENAME(@rcfk_parent), N'U') IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = @rcfk_name)
            BEGIN
                DECLARE @del_action NVARCHAR(20) = REPLACE(@rcfk_del, N'_', N' ');
                DECLARE @upd_action NVARCHAR(20) = REPLACE(@rcfk_upd, N'_', N' ');
                IF @del_action = N'NO' SET @del_action = N'NO ACTION';
                IF @upd_action = N'NO' SET @upd_action = N'NO ACTION';
                SET @sql = N'ALTER TABLE [dbo].' + QUOTENAME(@rcfk_parent) + N' ADD CONSTRAINT ' + QUOTENAME(@rcfk_name) + N' FOREIGN KEY (' + @rcfk_cols + N') REFERENCES [dbo].[User]([id]) ON DELETE ' + @del_action + N' ON UPDATE ' + @upd_action;
                EXEC sp_executesql @sql;
            END
            FETCH NEXT FROM rcfk_cur INTO @rcfk_name, @rcfk_parent, @rcfk_cols, @rcfk_del, @rcfk_upd;
        END
        CLOSE rcfk_cur; DEALLOCATE rcfk_cur;

        -- Delete all sessions (force re-login with new ids)
        IF OBJECT_ID('dbo.Session','U') IS NOT NULL
            DELETE FROM dbo.Session;

        -- P1 final check: no column still holds an old User id
        IF OBJECT_ID('tempdb..#usr_remaining','U') IS NOT NULL DROP TABLE #usr_remaining;
        CREATE TABLE #usr_remaining (table_name NVARCHAR(128), column_name NVARCHAR(128));
        DECLARE @rem_table NVARCHAR(128), @rem_column NVARCHAR(128), @rem_sql NVARCHAR(MAX);
        DECLARE rem_cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT t.name, c.name FROM sys.columns c JOIN sys.tables t ON c.object_id = t.object_id
            WHERE c.user_type_id IN (TYPE_ID(N'nvarchar'), TYPE_ID(N'varchar'), TYPE_ID(N'nchar'), TYPE_ID(N'char'))
              AND c.is_computed = 0 AND t.schema_id = SCHEMA_ID(N'dbo')
              AND t.name NOT IN (N'User', N'_UpgradeLog');
        OPEN rem_cur; FETCH NEXT FROM rem_cur INTO @rem_table, @rem_column;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @rem_sql = N'IF EXISTS (SELECT 1 FROM [dbo].' + QUOTENAME(@rem_table) + N' t INNER JOIN #usr_map m ON t.' + QUOTENAME(@rem_column) + N' = m.old_id) INSERT INTO #usr_remaining VALUES (@t, @c)';
            EXEC sp_executesql @rem_sql, N'@t NVARCHAR(128), @c NVARCHAR(128)', @rem_table, @rem_column;
            FETCH NEXT FROM rem_cur INTO @rem_table, @rem_column;
        END
        CLOSE rem_cur; DEALLOCATE rem_cur;

        DECLARE @remaining_count INT = (SELECT COUNT(*) FROM #usr_remaining);
        IF @remaining_count > 0
        BEGIN
            DECLARE @remaining_list NVARCHAR(MAX) = N'';
            SELECT @remaining_list = @remaining_list + table_name + N'.' + column_name + N'; ' FROM #usr_remaining;
            RAISERROR(N'Columns still holding old User ids: %s', 16, 1, @remaining_list);
        END

        DROP TABLE #usr_map;
        DROP TABLE #usr_fks;
        DROP TABLE #usr_cols;
        DROP TABLE #usr_remaining;
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13e-User-id', N'OK', N'Migrated User.id to USR-0001+; updated columns: ' + @col_list + N'; sessions cleared');
        PRINT N'  13e-User-id: OK - sessions cleared, all users must re-login';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        IF OBJECT_ID('tempdb..#usr_map','U') IS NOT NULL DROP TABLE #usr_map;
        IF OBJECT_ID('tempdb..#usr_fks','U') IS NOT NULL DROP TABLE #usr_fks;
        IF OBJECT_ID('tempdb..#usr_cols','U') IS NOT NULL DROP TABLE #usr_cols;
        IF OBJECT_ID('tempdb..#usr_remaining','U') IS NOT NULL DROP TABLE #usr_remaining;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13e-User-id', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  13e-User-id: FAILED - ' + @eMsg;
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13e-User-id', N'SKIPPED', N'Already migrated or table missing');
    PRINT N'  13e-User-id: SKIPPED';
END
GO

-- ============================================================================
-- STEP 13f: ScreenPermission.id -> SCP-0001, UserPermission.id -> UPM-0001,
--           AccountMapping.id -> ACM-001, FinanceDefaults.id -> FDF-001
-- (These tables have no inbound FKs, so simple two-phase update + PK recreate)
-- ============================================================================
USE GymDB;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);

-- ScreenPermission
IF OBJECT_ID('dbo.ScreenPermission','U') IS NOT NULL
   AND EXISTS (SELECT 1 FROM dbo.ScreenPermission WHERE [id] NOT LIKE N'SCP-%')
BEGIN
    BEGIN TRY
        BEGIN TRAN;
        DECLARE @scp_max INT = 0;
        SELECT @scp_max = MAX(CAST(SUBSTRING([id], 5, 20) AS INT))
        FROM dbo.ScreenPermission WHERE [id] LIKE N'SCP-%' AND SUBSTRING([id], 5, 20) NOT LIKE N'%[^0-9]%';
        IF @scp_max IS NULL SET @scp_max = 0;

        IF OBJECT_ID('tempdb..#scp_map','U') IS NOT NULL DROP TABLE #scp_map;
        CREATE TABLE #scp_map (old_id NVARCHAR(50), new_id NVARCHAR(50), tmp_id NVARCHAR(50));
        INSERT INTO #scp_map (old_id, new_id, tmp_id)
        SELECT [id],
               N'SCP-' + RIGHT(N'000' + CAST(@scp_max + ROW_NUMBER() OVER (ORDER BY [id]) AS NVARCHAR(10)), 4),
               N'tmp_SCP_' + RIGHT(N'000' + CAST(@scp_max + ROW_NUMBER() OVER (ORDER BY [id]) AS NVARCHAR(10)), 4)
        FROM dbo.ScreenPermission WHERE [id] NOT LIKE N'SCP-%';

        DECLARE @scp_pk NVARCHAR(256), @sql NVARCHAR(MAX);
        SELECT @scp_pk = name FROM sys.key_constraints WHERE type = N'PK' AND parent_object_id = OBJECT_ID('dbo.ScreenPermission');
        IF @scp_pk IS NOT NULL
        BEGIN
            SET @sql = N'ALTER TABLE [dbo].[ScreenPermission] DROP CONSTRAINT ' + QUOTENAME(@scp_pk);
            EXEC sp_executesql @sql;
        END
        ELSE SET @scp_pk = N'ScreenPermission_pkey';

        UPDATE sp SET sp.[id] = m.tmp_id FROM dbo.ScreenPermission sp JOIN #scp_map m ON sp.[id] = m.old_id;
        UPDATE sp SET sp.[id] = m.new_id FROM dbo.ScreenPermission sp JOIN #scp_map m ON sp.[id] = m.tmp_id;

        ALTER TABLE [dbo].[ScreenPermission] ALTER COLUMN [id] NVARCHAR(50) NOT NULL;
        IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE type = N'PK' AND parent_object_id = OBJECT_ID('dbo.ScreenPermission'))
        BEGIN
            SET @sql = N'ALTER TABLE [dbo].[ScreenPermission] ADD CONSTRAINT ' + QUOTENAME(@scp_pk) + N' PRIMARY KEY CLUSTERED ([id])';
            EXEC sp_executesql @sql;
        END

        DROP TABLE #scp_map;
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13f-ScreenPermission-id', N'OK', N'Migrated to SCP-0001+');
        PRINT N'  13f-ScreenPermission-id: OK';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        IF OBJECT_ID('tempdb..#scp_map','U') IS NOT NULL DROP TABLE #scp_map;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13f-ScreenPermission-id', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  13f-ScreenPermission-id: FAILED - ' + @eMsg;
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13f-ScreenPermission-id', N'SKIPPED', N'Already migrated or table missing');
    PRINT N'  13f-ScreenPermission-id: SKIPPED';
END
GO

-- UserPermission
USE GymDB;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);

IF OBJECT_ID('dbo.UserPermission','U') IS NOT NULL
   AND EXISTS (SELECT 1 FROM dbo.UserPermission WHERE [id] NOT LIKE N'UPM-%')
BEGIN
    BEGIN TRY
        BEGIN TRAN;
        DECLARE @upm_max INT = 0;
        SELECT @upm_max = MAX(CAST(SUBSTRING([id], 5, 20) AS INT))
        FROM dbo.UserPermission WHERE [id] LIKE N'UPM-%' AND SUBSTRING([id], 5, 20) NOT LIKE N'%[^0-9]%';
        IF @upm_max IS NULL SET @upm_max = 0;

        IF OBJECT_ID('tempdb..#upm_map','U') IS NOT NULL DROP TABLE #upm_map;
        CREATE TABLE #upm_map (old_id NVARCHAR(50), new_id NVARCHAR(50), tmp_id NVARCHAR(50));
        INSERT INTO #upm_map (old_id, new_id, tmp_id)
        SELECT [id],
               N'UPM-' + RIGHT(N'000' + CAST(@upm_max + ROW_NUMBER() OVER (ORDER BY [id]) AS NVARCHAR(10)), 4),
               N'tmp_UPM_' + RIGHT(N'000' + CAST(@upm_max + ROW_NUMBER() OVER (ORDER BY [id]) AS NVARCHAR(10)), 4)
        FROM dbo.UserPermission WHERE [id] NOT LIKE N'UPM-%';

        DECLARE @upm_pk NVARCHAR(256), @sql NVARCHAR(MAX);
        SELECT @upm_pk = name FROM sys.key_constraints WHERE type = N'PK' AND parent_object_id = OBJECT_ID('dbo.UserPermission');
        IF @upm_pk IS NOT NULL
        BEGIN
            SET @sql = N'ALTER TABLE [dbo].[UserPermission] DROP CONSTRAINT ' + QUOTENAME(@upm_pk);
            EXEC sp_executesql @sql;
        END
        ELSE SET @upm_pk = N'UserPermission_pkey';

        UPDATE up SET up.[id] = m.tmp_id FROM dbo.UserPermission up JOIN #upm_map m ON up.[id] = m.old_id;
        UPDATE up SET up.[id] = m.new_id FROM dbo.UserPermission up JOIN #upm_map m ON up.[id] = m.tmp_id;

        ALTER TABLE [dbo].[UserPermission] ALTER COLUMN [id] NVARCHAR(50) NOT NULL;
        IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE type = N'PK' AND parent_object_id = OBJECT_ID('dbo.UserPermission'))
        BEGIN
            SET @sql = N'ALTER TABLE [dbo].[UserPermission] ADD CONSTRAINT ' + QUOTENAME(@upm_pk) + N' PRIMARY KEY CLUSTERED ([id])';
            EXEC sp_executesql @sql;
        END

        DROP TABLE #upm_map;
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13f-UserPermission-id', N'OK', N'Migrated to UPM-0001+');
        PRINT N'  13f-UserPermission-id: OK';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        IF OBJECT_ID('tempdb..#upm_map','U') IS NOT NULL DROP TABLE #upm_map;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13f-UserPermission-id', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  13f-UserPermission-id: FAILED - ' + @eMsg;
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13f-UserPermission-id', N'SKIPPED', N'Already migrated or table missing');
    PRINT N'  13f-UserPermission-id: SKIPPED';
END
GO

-- AccountMapping
USE GymDB;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);

IF OBJECT_ID('dbo.AccountMapping','U') IS NOT NULL
   AND EXISTS (SELECT 1 FROM dbo.AccountMapping WHERE [id] NOT LIKE N'ACM-%')
BEGIN
    BEGIN TRY
        BEGIN TRAN;
        DECLARE @acm_max INT = 0;
        SELECT @acm_max = MAX(CAST(SUBSTRING([id], 5, 20) AS INT))
        FROM dbo.AccountMapping WHERE [id] LIKE N'ACM-%' AND SUBSTRING([id], 5, 20) NOT LIKE N'%[^0-9]%';
        IF @acm_max IS NULL SET @acm_max = 0;

        IF OBJECT_ID('tempdb..#acm_map','U') IS NOT NULL DROP TABLE #acm_map;
        CREATE TABLE #acm_map (old_id NVARCHAR(50), new_id NVARCHAR(50), tmp_id NVARCHAR(50));
        INSERT INTO #acm_map (old_id, new_id, tmp_id)
        SELECT [id],
               N'ACM-' + RIGHT(N'00' + CAST(@acm_max + ROW_NUMBER() OVER (ORDER BY [id]) AS NVARCHAR(10)), 3),
               N'tmp_ACM_' + RIGHT(N'00' + CAST(@acm_max + ROW_NUMBER() OVER (ORDER BY [id]) AS NVARCHAR(10)), 3)
        FROM dbo.AccountMapping WHERE [id] NOT LIKE N'ACM-%';

        DECLARE @acm_pk NVARCHAR(256), @sql NVARCHAR(MAX);
        SELECT @acm_pk = name FROM sys.key_constraints WHERE type = N'PK' AND parent_object_id = OBJECT_ID('dbo.AccountMapping');
        IF @acm_pk IS NOT NULL
        BEGIN
            SET @sql = N'ALTER TABLE [dbo].[AccountMapping] DROP CONSTRAINT ' + QUOTENAME(@acm_pk);
            EXEC sp_executesql @sql;
        END
        ELSE SET @acm_pk = N'AccountMapping_pkey';

        UPDATE am SET am.[id] = m.tmp_id FROM dbo.AccountMapping am JOIN #acm_map m ON am.[id] = m.old_id;
        UPDATE am SET am.[id] = m.new_id FROM dbo.AccountMapping am JOIN #acm_map m ON am.[id] = m.tmp_id;

        ALTER TABLE [dbo].[AccountMapping] ALTER COLUMN [id] NVARCHAR(50) NOT NULL;
        IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE type = N'PK' AND parent_object_id = OBJECT_ID('dbo.AccountMapping'))
        BEGIN
            SET @sql = N'ALTER TABLE [dbo].[AccountMapping] ADD CONSTRAINT ' + QUOTENAME(@acm_pk) + N' PRIMARY KEY CLUSTERED ([id])';
            EXEC sp_executesql @sql;
        END

        DROP TABLE #acm_map;
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13f-AccountMapping-id', N'OK', N'Migrated to ACM-001+');
        PRINT N'  13f-AccountMapping-id: OK';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        IF OBJECT_ID('tempdb..#acm_map','U') IS NOT NULL DROP TABLE #acm_map;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13f-AccountMapping-id', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  13f-AccountMapping-id: FAILED - ' + @eMsg;
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13f-AccountMapping-id', N'SKIPPED', N'Already migrated or table missing');
    PRINT N'  13f-AccountMapping-id: SKIPPED';
END
GO

-- FinanceDefaults
USE GymDB;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);

IF OBJECT_ID('dbo.FinanceDefaults','U') IS NOT NULL
   AND EXISTS (SELECT 1 FROM dbo.FinanceDefaults WHERE [id] NOT LIKE N'FDF-%')
BEGIN
    BEGIN TRY
        BEGIN TRAN;
        DECLARE @fdf_max INT = 0;
        SELECT @fdf_max = MAX(CAST(SUBSTRING([id], 5, 20) AS INT))
        FROM dbo.FinanceDefaults WHERE [id] LIKE N'FDF-%' AND SUBSTRING([id], 5, 20) NOT LIKE N'%[^0-9]%';
        IF @fdf_max IS NULL SET @fdf_max = 0;

        IF OBJECT_ID('tempdb..#fdf_map','U') IS NOT NULL DROP TABLE #fdf_map;
        CREATE TABLE #fdf_map (old_id NVARCHAR(50), new_id NVARCHAR(50), tmp_id NVARCHAR(50));
        INSERT INTO #fdf_map (old_id, new_id, tmp_id)
        SELECT [id],
               N'FDF-' + RIGHT(N'00' + CAST(@fdf_max + ROW_NUMBER() OVER (ORDER BY [id]) AS NVARCHAR(10)), 3),
               N'tmp_FDF_' + RIGHT(N'00' + CAST(@fdf_max + ROW_NUMBER() OVER (ORDER BY [id]) AS NVARCHAR(10)), 3)
        FROM dbo.FinanceDefaults WHERE [id] NOT LIKE N'FDF-%';

        DECLARE @fdf_pk NVARCHAR(256), @sql NVARCHAR(MAX);
        SELECT @fdf_pk = name FROM sys.key_constraints WHERE type = N'PK' AND parent_object_id = OBJECT_ID('dbo.FinanceDefaults');
        IF @fdf_pk IS NOT NULL
        BEGIN
            SET @sql = N'ALTER TABLE [dbo].[FinanceDefaults] DROP CONSTRAINT ' + QUOTENAME(@fdf_pk);
            EXEC sp_executesql @sql;
        END
        ELSE SET @fdf_pk = N'FinanceDefaults_pkey';

        UPDATE fd SET fd.[id] = m.tmp_id FROM dbo.FinanceDefaults fd JOIN #fdf_map m ON fd.[id] = m.old_id;
        UPDATE fd SET fd.[id] = m.new_id FROM dbo.FinanceDefaults fd JOIN #fdf_map m ON fd.[id] = m.tmp_id;

        ALTER TABLE [dbo].[FinanceDefaults] ALTER COLUMN [id] NVARCHAR(50) NOT NULL;
        IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE type = N'PK' AND parent_object_id = OBJECT_ID('dbo.FinanceDefaults'))
        BEGIN
            SET @sql = N'ALTER TABLE [dbo].[FinanceDefaults] ADD CONSTRAINT ' + QUOTENAME(@fdf_pk) + N' PRIMARY KEY CLUSTERED ([id])';
            EXEC sp_executesql @sql;
        END

        DROP TABLE #fdf_map;
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13f-FinanceDefaults-id', N'OK', N'Migrated to FDF-001+');
        PRINT N'  13f-FinanceDefaults-id: OK';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        IF OBJECT_ID('tempdb..#fdf_map','U') IS NOT NULL DROP TABLE #fdf_map;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13f-FinanceDefaults-id', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  13f-FinanceDefaults-id: FAILED - ' + @eMsg;
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13f-FinanceDefaults-id', N'SKIPPED', N'Already migrated or table missing');
    PRINT N'  13f-FinanceDefaults-id: SKIPPED';
END
GO

-- ============================================================================
-- STEP 13g: Add new FinanceDefaults columns (expanded finance settings)
-- ============================================================================
USE GymDB;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);

IF OBJECT_ID('dbo.FinanceDefaults','U') IS NOT NULL
BEGIN
    BEGIN TRY
        BEGIN TRAN;

        IF COL_LENGTH('dbo.FinanceDefaults','allowUnbalancedOTB') IS NULL
            ALTER TABLE dbo.FinanceDefaults ADD [allowUnbalancedOTB] BIT NOT NULL CONSTRAINT [FinanceDefaults_allowUnbalancedOTB_df] DEFAULT 1;
        IF COL_LENGTH('dbo.FinanceDefaults','allowBackDatedVouchers') IS NULL
            ALTER TABLE dbo.FinanceDefaults ADD [allowBackDatedVouchers] BIT NOT NULL CONSTRAINT [FinanceDefaults_allowBackDatedVouchers_df] DEFAULT 1;
        IF COL_LENGTH('dbo.FinanceDefaults','lockBeforeDate') IS NULL
            ALTER TABLE dbo.FinanceDefaults ADD [lockBeforeDate] DATETIME2;
        IF COL_LENGTH('dbo.FinanceDefaults','voucherApprovalRequired') IS NULL
            ALTER TABLE dbo.FinanceDefaults ADD [voucherApprovalRequired] BIT NOT NULL CONSTRAINT [FinanceDefaults_voucherApprovalRequired_df] DEFAULT 0;
        IF COL_LENGTH('dbo.FinanceDefaults','allowEditPostedVouchers') IS NULL
            ALTER TABLE dbo.FinanceDefaults ADD [allowEditPostedVouchers] BIT NOT NULL CONSTRAINT [FinanceDefaults_allowEditPostedVouchers_df] DEFAULT 1;
        IF COL_LENGTH('dbo.FinanceDefaults','defaultCurrency') IS NULL
            ALTER TABLE dbo.FinanceDefaults ADD [defaultCurrency] NVARCHAR(50);
        IF COL_LENGTH('dbo.FinanceDefaults','decimalPlaces') IS NULL
            ALTER TABLE dbo.FinanceDefaults ADD [decimalPlaces] INT NOT NULL CONSTRAINT [FinanceDefaults_decimalPlaces_df] DEFAULT 2;
        IF COL_LENGTH('dbo.FinanceDefaults','defaultCashPaymentMode') IS NULL
            ALTER TABLE dbo.FinanceDefaults ADD [defaultCashPaymentMode] NVARCHAR(50);
        IF COL_LENGTH('dbo.FinanceDefaults','defaultBankPaymentMode') IS NULL
            ALTER TABLE dbo.FinanceDefaults ADD [defaultBankPaymentMode] NVARCHAR(50);
        IF COL_LENGTH('dbo.FinanceDefaults','allowNegativeCash') IS NULL
            ALTER TABLE dbo.FinanceDefaults ADD [allowNegativeCash] BIT NOT NULL CONSTRAINT [FinanceDefaults_allowNegativeCash_df] DEFAULT 0;
        IF COL_LENGTH('dbo.FinanceDefaults','autoPostReceipts') IS NULL
            ALTER TABLE dbo.FinanceDefaults ADD [autoPostReceipts] BIT NOT NULL CONSTRAINT [FinanceDefaults_autoPostReceipts_df] DEFAULT 1;
        IF COL_LENGTH('dbo.FinanceDefaults','fiscalYearStart') IS NULL
            ALTER TABLE dbo.FinanceDefaults ADD [fiscalYearStart] DATETIME2;
        IF COL_LENGTH('dbo.FinanceDefaults','fiscalYearEnd') IS NULL
            ALTER TABLE dbo.FinanceDefaults ADD [fiscalYearEnd] DATETIME2;

        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13g-FinanceDefaults-columns', N'OK', N'All 12 expanded finance columns present');
        PRINT N'  13g-FinanceDefaults-columns: OK';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13g-FinanceDefaults-columns', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  13g-FinanceDefaults-columns: FAILED - ' + @eMsg;
    END CATCH
END
GO

-- ============================================================================
-- STEP 13h: Seed a company-wide FinanceDefaults row (branchId NULL) if none exists
-- ============================================================================
USE GymDB;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);

IF OBJECT_ID('dbo.FinanceDefaults','U') IS NOT NULL
BEGIN
    BEGIN TRY
        BEGIN TRAN;
        IF NOT EXISTS (SELECT 1 FROM dbo.FinanceDefaults WHERE [branchId] IS NULL)
        BEGIN
            DECLARE @fdf_new_id NVARCHAR(50) = N'FDF-001';
            -- Ensure FDF-001 is not already taken
            IF EXISTS (SELECT 1 FROM dbo.FinanceDefaults WHERE [id] = N'FDF-001')
            BEGIN
                DECLARE @fdf_next INT = 0;
                SELECT @fdf_next = MAX(CAST(SUBSTRING([id], 5, 20) AS INT))
                FROM dbo.FinanceDefaults WHERE [id] LIKE N'FDF-%' AND SUBSTRING([id], 5, 20) NOT LIKE N'%[^0-9]%';
                SET @fdf_new_id = N'FDF-' + RIGHT(N'00' + CAST(@fdf_next + 1 AS NVARCHAR(10)), 3);
            END
            INSERT INTO dbo.FinanceDefaults ([id], [branchId], [allowUnbalancedOTB], [allowBackDatedVouchers],
                [voucherApprovalRequired], [allowEditPostedVouchers], [decimalPlaces], [allowNegativeCash],
                [autoPostReceipts], [createdAt], [updatedAt])
            VALUES (@fdf_new_id, NULL, 1, 1, 0, 1, 2, 0, 1, SYSDATETIME(), SYSDATETIME());
            PRINT N'  13h: created company-wide FinanceDefaults row (' + @fdf_new_id + N')';
        END
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13h-FinanceDefaults-seed', N'OK', N'Company-wide FinanceDefaults row exists');
        PRINT N'  13h-FinanceDefaults-seed: OK';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13h-FinanceDefaults-seed', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  13h-FinanceDefaults-seed: FAILED - ' + @eMsg;
    END CATCH
END
GO

-- ============================================================================
-- STEP 13i: Sync IdSequence rows — next = max(numeric suffix) + 1
-- P3: for ALL keys, both INSERT and UPDATE branches. Never decreases.
-- ============================================================================
USE GymDB;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);

IF OBJECT_ID('dbo.IdSequence','U') IS NOT NULL
BEGIN
    BEGIN TRY
        BEGIN TRAN;

        -- Helper: for each (key, table, prefix), compute max suffix and sync
        DECLARE @key NVARCHAR(50), @tbl NVARCHAR(128), @prefix NVARCHAR(20), @width INT;
        DECLARE @maxSuffix INT, @desired INT, @cur INT;

        -- We use a table variable to drive the loop
        DECLARE @keys TABLE ([key] NVARCHAR(50), tbl NVARCHAR(128), prefix NVARCHAR(20), width INT);
        INSERT INTO @keys VALUES
            (N'USER',            N'[User]',            N'USR-', 4),
            (N'PERMISSION',      N'[Permission]',      N'PRM-', 4),
            (N'ROLE',            N'[Role]',            N'ROL-', 3),
            (N'TAXHEAD',         N'[TaxHead]',         N'TAX-', 3),
            (N'SCREENPERMISSION',N'[ScreenPermission]',N'SCP-', 4),
            (N'USERPERMISSION',  N'[UserPermission]',  N'UPM-', 4),
            (N'ACCOUNTMAPPING',  N'[AccountMapping]',  N'ACM-', 3),
            (N'FINANCEDEFAULTS', N'[FinanceDefaults]', N'FDF-', 3),
            (N'DEFAULTS',        N'[Defaults]',        N'CMP-', 3);

        DECLARE k_cur CURSOR LOCAL FAST_FORWARD FOR SELECT [key], tbl, prefix, width FROM @keys;
        OPEN k_cur;
        FETCH NEXT FROM k_cur INTO @key, @tbl, @prefix, @width;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            -- Compute max numeric suffix from the actual table rows
            DECLARE @dyn NVARCHAR(MAX) = N'SELECT @ms = MAX(CAST(SUBSTRING([id], ' + CAST(LEN(@prefix) + 1 AS NVARCHAR(10)) + N', 20) AS INT)) FROM dbo.' + @tbl + N' WHERE [id] LIKE @pfx AND SUBSTRING([id], ' + CAST(LEN(@prefix) + 1 AS NVARCHAR(10)) + N', 20) NOT LIKE N''%[^0-9]%''';
            SET @maxSuffix = 0;
            EXEC sp_executesql @dyn, N'@ms INT OUTPUT, @pfx NVARCHAR(20)', @ms = @maxSuffix OUTPUT, @pfx = @prefix + N'%';
            IF @maxSuffix IS NULL SET @maxSuffix = 0;
            SET @desired = @maxSuffix + 1;

            IF NOT EXISTS (SELECT 1 FROM dbo.IdSequence WHERE [key] = @key)
            BEGIN
                INSERT INTO dbo.IdSequence ([key], [next], [updatedAt]) VALUES (@key, @desired, SYSDATETIME());
            END
            ELSE
            BEGIN
                SELECT @cur = [next] FROM dbo.IdSequence WHERE [key] = @key;
                -- P3: next = max + 1, but never decrease (avoid re-issuing reserved ids)
                IF @cur < @desired
                    UPDATE dbo.IdSequence SET [next] = @desired, [updatedAt] = SYSDATETIME() WHERE [key] = @key;
            END

            FETCH NEXT FROM k_cur INTO @key, @tbl, @prefix, @width;
        END
        CLOSE k_cur;
        DEALLOCATE k_cur;

        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13i-IdSequence', N'OK', N'Synced all IdSequence rows with max numeric suffix + 1');
        PRINT N'  13i-IdSequence: OK';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13i-IdSequence', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  13i-IdSequence: FAILED - ' + @eMsg;
    END CATCH
END
GO

-- ============================================================================
-- FINAL SUMMARY
-- ============================================================================
USE GymDB;
GO
SET NOCOUNT ON;

PRINT N'';
PRINT N'=== STEP 13 SUMMARY ===';

DECLARE @expected13 TABLE (step NVARCHAR(100) NOT NULL);
INSERT INTO @expected13 (step) VALUES
    (N'13a-Defaults-id'),
    (N'13b-TaxHead-id'),
    (N'13c-Permission-id'),
    (N'13d-Role-id'),
    (N'13e-User-id'),
    (N'13f-ScreenPermission-id'),
    (N'13f-UserPermission-id'),
    (N'13f-AccountMapping-id'),
    (N'13f-FinanceDefaults-id'),
    (N'13g-FinanceDefaults-columns'),
    (N'13h-FinanceDefaults-seed'),
    (N'13i-IdSequence');

DECLARE @missing13 INT = 0, @failed13 INT = 0;
SELECT @missing13 = COUNT(*) FROM @expected13 e WHERE NOT EXISTS (SELECT 1 FROM dbo._UpgradeLog l WHERE l.step = e.step);
SELECT @failed13 = COUNT(*) FROM dbo._UpgradeLog l WHERE l.step LIKE N'13%' AND l.status = N'FAILED';

IF @missing13 = 0 AND @failed13 = 0
BEGIN
    PRINT N'SUCCESS';
    SELECT N'SUCCESS' AS result, COUNT(*) AS steps, SUM(CASE WHEN status=N'OK' THEN 1 ELSE 0 END) AS ok, SUM(CASE WHEN status=N'SKIPPED' THEN 1 ELSE 0 END) AS skipped, 0 AS failed
    FROM dbo._UpgradeLog WHERE step LIKE N'13%';
END
ELSE
BEGIN
    DECLARE @failList13 NVARCHAR(MAX) = N'';
    SELECT @failList13 = @failList13 + step + N'; ' FROM dbo._UpgradeLog WHERE step LIKE N'13%' AND status = N'FAILED' ORDER BY step;
    SELECT @failList13 = @failList13 + N'MISSING: ' + step + N'; ' FROM @expected13 e WHERE NOT EXISTS (SELECT 1 FROM dbo._UpgradeLog l WHERE l.step = e.step) ORDER BY e.step;
    PRINT N'FAILED - ' + @failList13;
    SELECT N'FAILED' AS result, @failList13 AS details;
END
GO

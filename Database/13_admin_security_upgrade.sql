USE GymDB;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- 13_admin_security_upgrade.sql
-- ============================================================================
-- Migrates existing cuid ids to clean business formats for:
--   User: USR-0001
--   Permission: PRM-0001
--   Role: ROL-001
--   ScreenPermission: SCP-0001
--   UserPermission: UPM-0001
--   AccountMapping: ACM-001
--   FinanceDefaults: FDF-001
--   Defaults (company): CMP-001
--   TaxHead: TAX-001
--
-- Also adds new FinanceDefaults columns for the expanded finance settings.
-- Idempotent: checks if already migrated and skips.
-- Each step in its own TRY/CATCH with XACT_STATE() check.
-- ============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

PRINT N'=== STEP 13: Admin & Security Upgrade ===';

-- Helper: log function (inline, no stored proc to avoid quoting issues)
DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);

-- ============================================================================
-- STEP 13a: Defaults.id -> CMP-001
-- ============================================================================
IF OBJECT_ID('dbo.Defaults','U') IS NOT NULL
BEGIN
    IF NOT EXISTS (SELECT 1 FROM dbo.Defaults WHERE [id] LIKE N'CMP-%')
    BEGIN
        BEGIN TRY
            BEGIN TRAN;
            -- Defaults has no inbound FKs (leaf table)
            UPDATE dbo.Defaults SET [id] = N'CMP-001'
            WHERE [id] NOT LIKE N'CMP-%';
            COMMIT TRAN;
            INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13a-Defaults-id', N'OK', N'Migrated Defaults.id to CMP-001');
            PRINT N'  13a-Defaults-id: OK';
        END TRY
        BEGIN CATCH
            SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
            IF XACT_STATE() <> 0 ROLLBACK TRAN;
            INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13a-Defaults-id', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
            PRINT N'  13a-Defaults-id: FAILED - ' + @eMsg;
        END CATCH
    END
    ELSE
    BEGIN
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13a-Defaults-id', N'SKIPPED', N'Already migrated');
        PRINT N'  13a-Defaults-id: SKIPPED';
    END
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

        -- Build mapping
        IF OBJECT_ID('tempdb..#th_map', 'U') IS NOT NULL DROP TABLE #th_map;
        CREATE TABLE #th_map (old_id NVARCHAR(50), new_id NVARCHAR(50), tmp_id NVARCHAR(50));
        INSERT INTO #th_map (old_id, new_id, tmp_id)
        SELECT [id],
               N'TAX-' + RIGHT(N'000' + CAST(ROW_NUMBER() OVER (ORDER BY [code], [id]) AS NVARCHAR(10)), 3),
               N'tmp_TAX_' + RIGHT(N'000' + CAST(ROW_NUMBER() OVER (ORDER BY [code], [id]) AS NVARCHAR(10)), 3)
        FROM dbo.TaxHead WHERE [id] NOT LIKE N'TAX-%';

        -- Discover and drop FKs referencing TaxHead
        IF OBJECT_ID('tempdb..#th_fks', 'U') IS NOT NULL DROP TABLE #th_fks;
        CREATE TABLE #th_fks (fk_name NVARCHAR(256), parent_table NVARCHAR(128), parent_col NVARCHAR(128), on_delete NVARCHAR(20), on_update NVARCHAR(20));
        INSERT INTO #th_fks (fk_name, parent_table, parent_col, on_delete, on_update)
        SELECT fk.name, OBJECT_NAME(fk.parent_object_id), COL_NAME(fkc.parent_object_id, fkc.parent_column_id),
               fk.delete_referential_action_desc, fk.update_referential_action_desc
        FROM sys.foreign_keys fk
        JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
        WHERE fk.referenced_object_id = OBJECT_ID('dbo.TaxHead');

        DECLARE @thfk_name NVARCHAR(256), @thfk_parent NVARCHAR(128);
        DECLARE @drop_thfk NVARCHAR(MAX);
        DECLARE thfk_cur CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT fk_name, parent_table FROM #th_fks;
        OPEN thfk_cur;
        FETCH NEXT FROM thfk_cur INTO @thfk_name, @thfk_parent;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = @thfk_name)
            BEGIN
                SET @drop_thfk = N'ALTER TABLE [dbo].' + QUOTENAME(@thfk_parent) + N' DROP CONSTRAINT [' + @thfk_name + N']';
                EXEC sp_executesql @drop_thfk;
            END
            FETCH NEXT FROM thfk_cur INTO @thfk_name, @thfk_parent;
        END
        CLOSE thfk_cur;
        DEALLOCATE thfk_cur;

        -- Drop PK
        DECLARE @th_pk NVARCHAR(256);
        SELECT @th_pk = name FROM sys.key_constraints WHERE type = N'PK' AND parent_object_id = OBJECT_ID('dbo.TaxHead');
        IF @th_pk IS NOT NULL
        BEGIN
            DECLARE @drop_thpk NVARCHAR(MAX) = N'ALTER TABLE [dbo].[TaxHead] DROP CONSTRAINT [' + @th_pk + N']';
            EXEC sp_executesql @drop_thpk;
        END
        ELSE SET @th_pk = N'TaxHead_pkey';

        -- Two-phase update
        UPDATE t SET t.[id] = m.tmp_id FROM dbo.TaxHead t JOIN #th_map m ON t.[id] = m.old_id;
        UPDATE t SET t.[id] = m.new_id FROM dbo.TaxHead t JOIN #th_map m ON t.[id] = m.tmp_id;

        -- Update FinanceDefaults.defaultTaxHeadId
        IF COL_LENGTH('dbo.FinanceDefaults','defaultTaxHeadId') IS NOT NULL
        BEGIN
            UPDATE fd SET fd.[defaultTaxHeadId] = m.new_id
            FROM dbo.FinanceDefaults fd JOIN #th_map m ON fd.[defaultTaxHeadId] = m.old_id
            WHERE fd.[defaultTaxHeadId] IS NOT NULL;
        END

        -- Update CashBookLine.taxAccountId, BankBookLine.taxAccountId, JVLine.taxAccountId
        IF COL_LENGTH('dbo.CashBookLine','taxAccountId') IS NOT NULL
            UPDATE l SET l.[taxAccountId] = m.new_id FROM dbo.CashBookLine l JOIN #th_map m ON l.[taxAccountId] = m.old_id WHERE l.[taxAccountId] IS NOT NULL;
        IF COL_LENGTH('dbo.BankBookLine','taxAccountId') IS NOT NULL
            UPDATE l SET l.[taxAccountId] = m.new_id FROM dbo.BankBookLine l JOIN #th_map m ON l.[taxAccountId] = m.old_id WHERE l.[taxAccountId] IS NOT NULL;
        IF COL_LENGTH('dbo.JVLine','taxAccountId') IS NOT NULL
            UPDATE l SET l.[taxAccountId] = m.new_id FROM dbo.JVLine l JOIN #th_map m ON l.[taxAccountId] = m.old_id WHERE l.[taxAccountId] IS NOT NULL;

        -- ALTER COLUMN NOT NULL + recreate PK
        ALTER TABLE [dbo].[TaxHead] ALTER COLUMN [id] NVARCHAR(50) NOT NULL;
        IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE type=N'PK' AND parent_object_id=OBJECT_ID('dbo.TaxHead'))
        BEGIN
            DECLARE @add_thpk NVARCHAR(MAX) = N'ALTER TABLE [dbo].[TaxHead] ADD CONSTRAINT [' + @th_pk + N'] PRIMARY KEY CLUSTERED ([id])';
            EXEC sp_executesql @add_thpk;
        END

        -- Recreate FKs
        DECLARE @thcfk_name NVARCHAR(256), @thcfk_tbl NVARCHAR(128), @thcfk_col NVARCHAR(128);
        DECLARE @thcfk_del NVARCHAR(20), @thcfk_upd NVARCHAR(20);
        DECLARE @add_thcfk NVARCHAR(MAX);
        DECLARE thcfk_cur CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT fk_name, parent_table, parent_col, on_delete, on_update FROM #th_fks;
        OPEN thcfk_cur;
        FETCH NEXT FROM thcfk_cur INTO @thcfk_name, @thcfk_tbl, @thcfk_col, @thcfk_del, @thcfk_upd;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            IF OBJECT_ID('dbo.' + QUOTENAME(@thcfk_tbl), 'U') IS NOT NULL
               AND COL_LENGTH('dbo.' + QUOTENAME(@thcfk_tbl), @thcfk_col) IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = @thcfk_name)
            BEGIN
                DECLARE @th_del NVARCHAR(20) = REPLACE(@thcfk_del, N'_', N' ');
                DECLARE @th_upd NVARCHAR(20) = REPLACE(@thcfk_upd, N'_', N' ');
                IF @th_del = N'NO' SET @th_del = N'NO ACTION';
                IF @th_upd = N'NO' SET @th_upd = N'NO ACTION';
                SET @add_thcfk = N'ALTER TABLE [dbo].' + QUOTENAME(@thcfk_tbl) + N' ADD CONSTRAINT [' + @thcfk_name + N'] FOREIGN KEY ([' + @thcfk_col + N']) REFERENCES [dbo].[TaxHead]([id]) ON DELETE ' + @th_del + N' ON UPDATE ' + @th_upd;
                EXEC sp_executesql @add_thcfk;
            END
            FETCH NEXT FROM thcfk_cur INTO @thcfk_name, @thcfk_tbl, @thcfk_col, @thcfk_del, @thcfk_upd;
        END
        CLOSE thcfk_cur;
        DEALLOCATE thcfk_cur;

        DROP TABLE #th_map;
        DROP TABLE #th_fks;
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13b-TaxHead-id', N'OK', N'Migrated TaxHead.id to TAX-001...');
        PRINT N'  13b-TaxHead-id: OK';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF OBJECT_ID('tempdb..#th_map','U') IS NOT NULL DROP TABLE #th_map;
        IF OBJECT_ID('tempdb..#th_fks','U') IS NOT NULL DROP TABLE #th_fks;
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
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
        IF OBJECT_ID('tempdb..#prm_map', 'U') IS NOT NULL DROP TABLE #prm_map;
        CREATE TABLE #prm_map (old_id NVARCHAR(50), new_id NVARCHAR(50), tmp_id NVARCHAR(50));
        INSERT INTO #prm_map (old_id, new_id, tmp_id)
        SELECT [id],
               N'PRM-' + RIGHT(N'000' + CAST(ROW_NUMBER() OVER (ORDER BY [code]) AS NVARCHAR(10)), 4),
               N'tmp_PRM_' + RIGHT(N'000' + CAST(ROW_NUMBER() OVER (ORDER BY [code]) AS NVARCHAR(10)), 4)
        FROM dbo.Permission WHERE [id] NOT LIKE N'PRM-%';

        -- Drop FKs from RolePermission
        IF OBJECT_ID('tempdb..#prm_fks', 'U') IS NOT NULL DROP TABLE #prm_fks;
        CREATE TABLE #prm_fks (fk_name NVARCHAR(256), parent_table NVARCHAR(128), parent_col NVARCHAR(128), on_delete NVARCHAR(20), on_update NVARCHAR(20));
        INSERT INTO #prm_fks (fk_name, parent_table, parent_col, on_delete, on_update)
        SELECT fk.name, OBJECT_NAME(fk.parent_object_id), COL_NAME(fkc.parent_object_id, fkc.parent_column_id),
               fk.delete_referential_action_desc, fk.update_referential_action_desc
        FROM sys.foreign_keys fk
        JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
        WHERE fk.referenced_object_id = OBJECT_ID('dbo.Permission');

        DECLARE @pfk_name NVARCHAR(256), @pfk_parent NVARCHAR(128);
        DECLARE @drop_pfk NVARCHAR(MAX);
        DECLARE pfk_cur CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT fk_name, parent_table FROM #prm_fks;
        OPEN pfk_cur;
        FETCH NEXT FROM pfk_cur INTO @pfk_name, @pfk_parent;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = @pfk_name)
            BEGIN
                SET @drop_pfk = N'ALTER TABLE [dbo].' + QUOTENAME(@pfk_parent) + N' DROP CONSTRAINT [' + @pfk_name + N']';
                EXEC sp_executesql @drop_pfk;
            END
            FETCH NEXT FROM pfk_cur INTO @pfk_name, @pfk_parent;
        END
        CLOSE pfk_cur;
        DEALLOCATE pfk_cur;

        -- Drop PK
        DECLARE @prm_pk NVARCHAR(256);
        SELECT @prm_pk = name FROM sys.key_constraints WHERE type=N'PK' AND parent_object_id=OBJECT_ID('dbo.Permission');
        IF @prm_pk IS NOT NULL
        BEGIN
            DECLARE @drop_prmpk NVARCHAR(MAX) = N'ALTER TABLE [dbo].[Permission] DROP CONSTRAINT [' + @prm_pk + N']';
            EXEC sp_executesql @drop_prmpk;
        END
        ELSE SET @prm_pk = N'Permission_pkey';

        -- Two-phase update Permission
        UPDATE p SET p.[id] = m.tmp_id FROM dbo.Permission p JOIN #prm_map m ON p.[id] = m.old_id;
        UPDATE p SET p.[id] = m.new_id FROM dbo.Permission p JOIN #prm_map m ON p.[id] = m.tmp_id;

        -- Update RolePermission.permissionId
        IF COL_LENGTH('dbo.RolePermission','permissionId') IS NOT NULL
        BEGIN
            UPDATE rp SET rp.[permissionId] = m.new_id
            FROM dbo.RolePermission rp JOIN #prm_map m ON rp.[permissionId] = m.old_id;
        END

        -- ALTER COLUMN NOT NULL + recreate PK
        ALTER TABLE [dbo].[Permission] ALTER COLUMN [id] NVARCHAR(50) NOT NULL;
        IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE type=N'PK' AND parent_object_id=OBJECT_ID('dbo.Permission'))
        BEGIN
            DECLARE @add_prmpk NVARCHAR(MAX) = N'ALTER TABLE [dbo].[Permission] ADD CONSTRAINT [' + @prm_pk + N'] PRIMARY KEY CLUSTERED ([id])';
            EXEC sp_executesql @add_prmpk;
        END

        -- Recreate FKs
        DECLARE @pcfk_name NVARCHAR(256), @pcfk_tbl NVARCHAR(128), @pcfk_col NVARCHAR(128);
        DECLARE @pcfk_del NVARCHAR(20), @pcfk_upd NVARCHAR(20);
        DECLARE @add_pcfk NVARCHAR(MAX);
        DECLARE pcfk_cur CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT fk_name, parent_table, parent_col, on_delete, on_update FROM #prm_fks;
        OPEN pcfk_cur;
        FETCH NEXT FROM pcfk_cur INTO @pcfk_name, @pcfk_tbl, @pcfk_col, @pcfk_del, @pcfk_upd;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            IF OBJECT_ID('dbo.' + QUOTENAME(@pcfk_tbl), 'U') IS NOT NULL
               AND COL_LENGTH('dbo.' + QUOTENAME(@pcfk_tbl), @pcfk_col) IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = @pcfk_name)
            BEGIN
                DECLARE @p_del NVARCHAR(20) = REPLACE(@pcfk_del, N'_', N' ');
                DECLARE @p_upd NVARCHAR(20) = REPLACE(@pcfk_upd, N'_', N' ');
                IF @p_del = N'NO' SET @p_del = N'NO ACTION';
                IF @p_upd = N'NO' SET @p_upd = N'NO ACTION';
                SET @add_pcfk = N'ALTER TABLE [dbo].' + QUOTENAME(@pcfk_tbl) + N' ADD CONSTRAINT [' + @pcfk_name + N'] FOREIGN KEY ([' + @pcfk_col + N']) REFERENCES [dbo].[Permission]([id]) ON DELETE ' + @p_del + N' ON UPDATE ' + @p_upd;
                EXEC sp_executesql @add_pcfk;
            END
            FETCH NEXT FROM pcfk_cur INTO @pcfk_name, @pcfk_tbl, @pcfk_col, @pcfk_del, @pcfk_upd;
        END
        CLOSE pcfk_cur;
        DEALLOCATE pcfk_cur;

        DROP TABLE #prm_map;
        DROP TABLE #prm_fks;
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13c-Permission-id', N'OK', N'Migrated Permission.id to PRM-0001...');
        PRINT N'  13c-Permission-id: OK';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF OBJECT_ID('tempdb..#prm_map','U') IS NOT NULL DROP TABLE #prm_map;
        IF OBJECT_ID('tempdb..#prm_fks','U') IS NOT NULL DROP TABLE #prm_fks;
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
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
        IF OBJECT_ID('tempdb..#rol_map', 'U') IS NOT NULL DROP TABLE #rol_map;
        CREATE TABLE #rol_map (old_id NVARCHAR(50), new_id NVARCHAR(50), tmp_id NVARCHAR(50));
        INSERT INTO #rol_map (old_id, new_id, tmp_id)
        SELECT [id],
               N'ROL-' + RIGHT(N'00' + CAST(ROW_NUMBER() OVER (ORDER BY [name]) AS NVARCHAR(10)), 3),
               N'tmp_ROL_' + RIGHT(N'00' + CAST(ROW_NUMBER() OVER (ORDER BY [name]) AS NVARCHAR(10)), 3)
        FROM dbo.Role WHERE [id] NOT LIKE N'ROL-%';

        -- Drop FKs referencing Role
        IF OBJECT_ID('tempdb..#rol_fks', 'U') IS NOT NULL DROP TABLE #rol_fks;
        CREATE TABLE #rol_fks (fk_name NVARCHAR(256), parent_table NVARCHAR(128), parent_col NVARCHAR(128), on_delete NVARCHAR(20), on_update NVARCHAR(20));
        INSERT INTO #rol_fks (fk_name, parent_table, parent_col, on_delete, on_update)
        SELECT fk.name, OBJECT_NAME(fk.parent_object_id), COL_NAME(fkc.parent_object_id, fkc.parent_column_id),
               fk.delete_referential_action_desc, fk.update_referential_action_desc
        FROM sys.foreign_keys fk
        JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
        WHERE fk.referenced_object_id = OBJECT_ID('dbo.Role');

        DECLARE @rfk_name NVARCHAR(256), @rfk_parent NVARCHAR(128);
        DECLARE @drop_rfk NVARCHAR(MAX);
        DECLARE rfk_cur CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT fk_name, parent_table FROM #rol_fks;
        OPEN rfk_cur;
        FETCH NEXT FROM rfk_cur INTO @rfk_name, @rfk_parent;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = @rfk_name)
            BEGIN
                SET @drop_rfk = N'ALTER TABLE [dbo].' + QUOTENAME(@rfk_parent) + N' DROP CONSTRAINT [' + @rfk_name + N']';
                EXEC sp_executesql @drop_rfk;
            END
            FETCH NEXT FROM rfk_cur INTO @rfk_name, @rfk_parent;
        END
        CLOSE rfk_cur;
        DEALLOCATE rfk_cur;

        -- Drop PK
        DECLARE @rol_pk NVARCHAR(256);
        SELECT @rol_pk = name FROM sys.key_constraints WHERE type=N'PK' AND parent_object_id=OBJECT_ID('dbo.Role');
        IF @rol_pk IS NOT NULL
        BEGIN
            DECLARE @drop_rolpk NVARCHAR(MAX) = N'ALTER TABLE [dbo].[Role] DROP CONSTRAINT [' + @rol_pk + N']';
            EXEC sp_executesql @drop_rolpk;
        END
        ELSE SET @rol_pk = N'Role_pkey';

        -- Two-phase update Role
        UPDATE r SET r.[id] = m.tmp_id FROM dbo.Role r JOIN #rol_map m ON r.[id] = m.old_id;
        UPDATE r SET r.[id] = m.new_id FROM dbo.Role r JOIN #rol_map m ON r.[id] = m.tmp_id;

        -- Update User.roleId, RolePermission.roleId, ScreenPermission.roleId
        IF COL_LENGTH('dbo.[User]','roleId') IS NOT NULL
            UPDATE u SET u.[roleId] = m.new_id FROM dbo.[User] u JOIN #rol_map m ON u.[roleId] = m.old_id WHERE u.[roleId] IS NOT NULL;
        IF COL_LENGTH('dbo.RolePermission','roleId') IS NOT NULL
            UPDATE rp SET rp.[roleId] = m.new_id FROM dbo.RolePermission rp JOIN #rol_map m ON rp.[roleId] = m.old_id;
        IF COL_LENGTH('dbo.ScreenPermission','roleId') IS NOT NULL
            UPDATE sp SET sp.[roleId] = m.new_id FROM dbo.ScreenPermission sp JOIN #rol_map m ON sp.[roleId] = m.old_id;

        -- ALTER COLUMN NOT NULL + recreate PK
        ALTER TABLE [dbo].[Role] ALTER COLUMN [id] NVARCHAR(50) NOT NULL;
        IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE type=N'PK' AND parent_object_id=OBJECT_ID('dbo.Role'))
        BEGIN
            DECLARE @add_rolpk NVARCHAR(MAX) = N'ALTER TABLE [dbo].[Role] ADD CONSTRAINT [' + @rol_pk + N'] PRIMARY KEY CLUSTERED ([id])';
            EXEC sp_executesql @add_rolpk;
        END

        -- Recreate FKs
        DECLARE @rcfk_name NVARCHAR(256), @rcfk_tbl NVARCHAR(128), @rcfk_col NVARCHAR(128);
        DECLARE @rcfk_del NVARCHAR(20), @rcfk_upd NVARCHAR(20);
        DECLARE @add_rcfk NVARCHAR(MAX);
        DECLARE rcfk_cur CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT fk_name, parent_table, parent_col, on_delete, on_update FROM #rol_fks;
        OPEN rcfk_cur;
        FETCH NEXT FROM rcfk_cur INTO @rcfk_name, @rcfk_tbl, @rcfk_col, @rcfk_del, @rcfk_upd;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            IF OBJECT_ID('dbo.' + QUOTENAME(@rcfk_tbl), 'U') IS NOT NULL
               AND COL_LENGTH('dbo.' + QUOTENAME(@rcfk_tbl), @rcfk_col) IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = @rcfk_name)
            BEGIN
                DECLARE @r_del NVARCHAR(20) = REPLACE(@rcfk_del, N'_', N' ');
                DECLARE @r_upd NVARCHAR(20) = REPLACE(@rcfk_upd, N'_', N' ');
                IF @r_del = N'NO' SET @r_del = N'NO ACTION';
                IF @r_upd = N'NO' SET @r_upd = N'NO ACTION';
                SET @add_rcfk = N'ALTER TABLE [dbo].' + QUOTENAME(@rcfk_tbl) + N' ADD CONSTRAINT [' + @rcfk_name + N'] FOREIGN KEY ([' + @rcfk_col + N']) REFERENCES [dbo].[Role]([id]) ON DELETE ' + @r_del + N' ON UPDATE ' + @r_upd;
                EXEC sp_executesql @add_rcfk;
            END
            FETCH NEXT FROM rcfk_cur INTO @rcfk_name, @rcfk_tbl, @rcfk_col, @rcfk_del, @rcfk_upd;
        END
        CLOSE rcfk_cur;
        DEALLOCATE rcfk_cur;

        DROP TABLE #rol_map;
        DROP TABLE #rol_fks;
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13d-Role-id', N'OK', N'Migrated Role.id to ROL-001...');
        PRINT N'  13d-Role-id: OK';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF OBJECT_ID('tempdb..#rol_map','U') IS NOT NULL DROP TABLE #rol_map;
        IF OBJECT_ID('tempdb..#rol_fks','U') IS NOT NULL DROP TABLE #rol_fks;
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
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
        IF OBJECT_ID('tempdb..#usr_map', 'U') IS NOT NULL DROP TABLE #usr_map;
        CREATE TABLE #usr_map (old_id NVARCHAR(50), new_id NVARCHAR(50), tmp_id NVARCHAR(50));
        INSERT INTO #usr_map (old_id, new_id, tmp_id)
        SELECT [id],
               N'USR-' + RIGHT(N'000' + CAST(ROW_NUMBER() OVER (ORDER BY [createdAt], [username]) AS NVARCHAR(10)), 4),
               N'tmp_USR_' + RIGHT(N'000' + CAST(ROW_NUMBER() OVER (ORDER BY [createdAt], [username]) AS NVARCHAR(10)), 4)
        FROM dbo.[User] WHERE [id] NOT LIKE N'USR-%';

        -- Drop FKs referencing User
        IF OBJECT_ID('tempdb..#usr_fks', 'U') IS NOT NULL DROP TABLE #usr_fks;
        CREATE TABLE #usr_fks (fk_name NVARCHAR(256), parent_table NVARCHAR(128), parent_col NVARCHAR(128), on_delete NVARCHAR(20), on_update NVARCHAR(20));
        INSERT INTO #usr_fks (fk_name, parent_table, parent_col, on_delete, on_update)
        SELECT fk.name, OBJECT_NAME(fk.parent_object_id), COL_NAME(fkc.parent_object_id, fkc.parent_column_id),
               fk.delete_referential_action_desc, fk.update_referential_action_desc
        FROM sys.foreign_keys fk
        JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
        WHERE fk.referenced_object_id = OBJECT_ID('dbo.[User]');

        DECLARE @ufk_name NVARCHAR(256), @ufk_parent NVARCHAR(128);
        DECLARE @drop_ufk NVARCHAR(MAX);
        DECLARE ufk_cur CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT fk_name, parent_table FROM #usr_fks;
        OPEN ufk_cur;
        FETCH NEXT FROM ufk_cur INTO @ufk_name, @ufk_parent;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = @ufk_name)
            BEGIN
                SET @drop_ufk = N'ALTER TABLE [dbo].' + QUOTENAME(@ufk_parent) + N' DROP CONSTRAINT [' + @ufk_name + N']';
                EXEC sp_executesql @drop_ufk;
            END
            FETCH NEXT FROM ufk_cur INTO @ufk_name, @ufk_parent;
        END
        CLOSE ufk_cur;
        DEALLOCATE ufk_cur;

        -- Drop PK
        DECLARE @usr_pk NVARCHAR(256);
        SELECT @usr_pk = name FROM sys.key_constraints WHERE type=N'PK' AND parent_object_id=OBJECT_ID('dbo.[User]');
        IF @usr_pk IS NOT NULL
        BEGIN
            DECLARE @drop_usrpk NVARCHAR(MAX) = N'ALTER TABLE [dbo].[User] DROP CONSTRAINT [' + @usr_pk + N']';
            EXEC sp_executesql @drop_usrpk;
        END
        ELSE SET @usr_pk = N'User_pkey';

        -- Two-phase update User
        UPDATE u SET u.[id] = m.tmp_id FROM dbo.[User] u JOIN #usr_map m ON u.[id] = m.old_id;
        UPDATE u SET u.[id] = m.new_id FROM dbo.[User] u JOIN #usr_map m ON u.[id] = m.tmp_id;

        -- Update all referencing columns
        IF COL_LENGTH('dbo.AuditLog','userId') IS NOT NULL
            UPDATE a SET a.[userId] = m.new_id FROM dbo.AuditLog a JOIN #usr_map m ON a.[userId] = m.old_id WHERE a.[userId] IS NOT NULL;
        IF COL_LENGTH('dbo.Session','userId') IS NOT NULL
            UPDATE s SET s.[userId] = m.new_id FROM dbo.Session s JOIN #usr_map m ON s.[userId] = m.old_id;
        IF COL_LENGTH('dbo.UserPermission','userId') IS NOT NULL
            UPDATE up SET up.[userId] = m.new_id FROM dbo.UserPermission up JOIN #usr_map m ON up.[userId] = m.old_id;
        -- Voucher postedById columns (no FK, just string reference)
        IF COL_LENGTH('dbo.CashBook','postedById') IS NOT NULL
            UPDATE v SET v.[postedById] = m.new_id FROM dbo.CashBook v JOIN #usr_map m ON v.[postedById] = m.old_id WHERE v.[postedById] IS NOT NULL;
        IF COL_LENGTH('dbo.BankBook','postedById') IS NOT NULL
            UPDATE v SET v.[postedById] = m.new_id FROM dbo.BankBook v JOIN #usr_map m ON v.[postedById] = m.old_id WHERE v.[postedById] IS NOT NULL;
        IF COL_LENGTH('dbo.JV','postedById') IS NOT NULL
            UPDATE v SET v.[postedById] = m.new_id FROM dbo.JV v JOIN #usr_map m ON v.[postedById] = m.old_id WHERE v.[postedById] IS NOT NULL;
        IF COL_LENGTH('dbo.OpenTB','postedById') IS NOT NULL
            UPDATE v SET v.[postedById] = m.new_id FROM dbo.OpenTB v JOIN #usr_map m ON v.[postedById] = m.old_id WHERE v.[postedById] IS NOT NULL;
        -- Voucher deletedById
        IF COL_LENGTH('dbo.CashBook','deletedById') IS NOT NULL
            UPDATE v SET v.[deletedById] = m.new_id FROM dbo.CashBook v JOIN #usr_map m ON v.[deletedById] = m.old_id WHERE v.[deletedById] IS NOT NULL;
        IF COL_LENGTH('dbo.BankBook','deletedById') IS NOT NULL
            UPDATE v SET v.[deletedById] = m.new_id FROM dbo.BankBook v JOIN #usr_map m ON v.[deletedById] = m.old_id WHERE v.[deletedById] IS NOT NULL;
        IF COL_LENGTH('dbo.JV','deletedById') IS NOT NULL
            UPDATE v SET v.[deletedById] = m.new_id FROM dbo.JV v JOIN #usr_map m ON v.[deletedById] = m.old_id WHERE v.[deletedById] IS NOT NULL;
        IF COL_LENGTH('dbo.OpenTB','deletedById') IS NOT NULL
            UPDATE v SET v.[deletedById] = m.new_id FROM dbo.OpenTB v JOIN #usr_map m ON v.[deletedById] = m.old_id WHERE v.[deletedById] IS NOT NULL;
        -- Voucher reversedById
        IF COL_LENGTH('dbo.CashBook','reversedById') IS NOT NULL
            UPDATE v SET v.[reversedById] = m.new_id FROM dbo.CashBook v JOIN #usr_map m ON v.[reversedById] = m.old_id WHERE v.[reversedById] IS NOT NULL;
        IF COL_LENGTH('dbo.BankBook','reversedById') IS NOT NULL
            UPDATE v SET v.[reversedById] = m.new_id FROM dbo.BankBook v JOIN #usr_map m ON v.[reversedById] = m.old_id WHERE v.[reversedById] IS NOT NULL;
        IF COL_LENGTH('dbo.JV','reversedById') IS NOT NULL
            UPDATE v SET v.[reversedById] = m.new_id FROM dbo.JV v JOIN #usr_map m ON v.[reversedById] = m.old_id WHERE v.[reversedById] IS NOT NULL;
        IF COL_LENGTH('dbo.OpenTB','reversedById') IS NOT NULL
            UPDATE v SET v.[reversedById] = m.new_id FROM dbo.OpenTB v JOIN #usr_map m ON v.[reversedById] = m.old_id WHERE v.[reversedById] IS NOT NULL;
        -- Leave.approvedBy (string, no FK)
        IF COL_LENGTH('dbo.Leave','approvedBy') IS NOT NULL
            UPDATE l SET l.[approvedBy] = m.new_id FROM dbo.Leave l JOIN #usr_map m ON l.[approvedBy] = m.old_id WHERE l.[approvedBy] IS NOT NULL;
        -- Overtime.approvedBy
        IF COL_LENGTH('dbo.Overtime','approvedBy') IS NOT NULL
            UPDATE o SET o.[approvedBy] = m.new_id FROM dbo.Overtime o JOIN #usr_map m ON o.[approvedBy] = m.old_id WHERE o.[approvedBy] IS NOT NULL;
        -- KnockOff.createdById
        IF COL_LENGTH('dbo.KnockOff','createdById') IS NOT NULL
            UPDATE k SET k.[createdById] = m.new_id FROM dbo.KnockOff k JOIN #usr_map m ON k.[createdById] = m.old_id WHERE k.[createdById] IS NOT NULL;

        -- ALTER COLUMN NOT NULL + recreate PK
        ALTER TABLE [dbo].[User] ALTER COLUMN [id] NVARCHAR(50) NOT NULL;
        IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE type=N'PK' AND parent_object_id=OBJECT_ID('dbo.[User]'))
        BEGIN
            DECLARE @add_usrpk NVARCHAR(MAX) = N'ALTER TABLE [dbo].[User] ADD CONSTRAINT [' + @usr_pk + N'] PRIMARY KEY CLUSTERED ([id])';
            EXEC sp_executesql @add_usrpk;
        END

        -- Recreate FKs
        DECLARE @ucfk_name NVARCHAR(256), @ucfk_tbl NVARCHAR(128), @ucfk_col NVARCHAR(128);
        DECLARE @ucfk_del NVARCHAR(20), @ucfk_upd NVARCHAR(20);
        DECLARE @add_ucfk NVARCHAR(MAX);
        DECLARE ucfk_cur CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT fk_name, parent_table, parent_col, on_delete, on_update FROM #usr_fks;
        OPEN ucfk_cur;
        FETCH NEXT FROM ucfk_cur INTO @ucfk_name, @ucfk_tbl, @ucfk_col, @ucfk_del, @ucfk_upd;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            IF OBJECT_ID('dbo.' + QUOTENAME(@ucfk_tbl), 'U') IS NOT NULL
               AND COL_LENGTH('dbo.' + QUOTENAME(@ucfk_tbl), @ucfk_col) IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = @ucfk_name)
            BEGIN
                DECLARE @u_del NVARCHAR(20) = REPLACE(@ucfk_del, N'_', N' ');
                DECLARE @u_upd NVARCHAR(20) = REPLACE(@ucfk_upd, N'_', N' ');
                IF @u_del = N'NO' SET @u_del = N'NO ACTION';
                IF @u_upd = N'NO' SET @u_upd = N'NO ACTION';
                SET @add_ucfk = N'ALTER TABLE [dbo].' + QUOTENAME(@ucfk_tbl) + N' ADD CONSTRAINT [' + @ucfk_name + N'] FOREIGN KEY ([' + @ucfk_col + N']) REFERENCES [dbo].[User]([id]) ON DELETE ' + @u_del + N' ON UPDATE ' + @u_upd;
                EXEC sp_executesql @add_ucfk;
            END
            FETCH NEXT FROM ucfk_cur INTO @ucfk_name, @ucfk_tbl, @ucfk_col, @ucfk_del, @ucfk_upd;
        END
        CLOSE ucfk_cur;
        DEALLOCATE ucfk_cur;

        -- Delete all sessions (force re-login with new ids)
        IF OBJECT_ID('dbo.Session','U') IS NOT NULL
            DELETE FROM dbo.Session;

        DROP TABLE #usr_map;
        DROP TABLE #usr_fks;
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13e-User-id', N'OK', N'Migrated User.id to USR-0001...; sessions cleared (force re-login)');
        PRINT N'  13e-User-id: OK - sessions cleared, all users must re-login';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF OBJECT_ID('tempdb..#usr_map','U') IS NOT NULL DROP TABLE #usr_map;
        IF OBJECT_ID('tempdb..#usr_fks','U') IS NOT NULL DROP TABLE #usr_fks;
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
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
        IF OBJECT_ID('tempdb..#scp_map', 'U') IS NOT NULL DROP TABLE #scp_map;
        CREATE TABLE #scp_map (old_id NVARCHAR(50), new_id NVARCHAR(50), tmp_id NVARCHAR(50));
        INSERT INTO #scp_map (old_id, new_id, tmp_id)
        SELECT [id], N'SCP-' + RIGHT(N'000' + CAST(ROW_NUMBER() OVER (ORDER BY [id]) AS NVARCHAR(10)), 4),
               N'tmp_SCP_' + RIGHT(N'000' + CAST(ROW_NUMBER() OVER (ORDER BY [id]) AS NVARCHAR(10)), 4)
        FROM dbo.ScreenPermission WHERE [id] NOT LIKE N'SCP-%';

        DECLARE @scp_pk NVARCHAR(256);
        SELECT @scp_pk = name FROM sys.key_constraints WHERE type=N'PK' AND parent_object_id=OBJECT_ID('dbo.ScreenPermission');
        IF @scp_pk IS NOT NULL EXEC sp_executesql N'ALTER TABLE [dbo].[ScreenPermission] DROP CONSTRAINT [' + @scp_pk + N']';
        ELSE SET @scp_pk = N'ScreenPermission_pkey';

        UPDATE sp SET sp.[id] = m.tmp_id FROM dbo.ScreenPermission sp JOIN #scp_map m ON sp.[id] = m.old_id;
        UPDATE sp SET sp.[id] = m.new_id FROM dbo.ScreenPermission sp JOIN #scp_map m ON sp.[id] = m.tmp_id;

        ALTER TABLE [dbo].[ScreenPermission] ALTER COLUMN [id] NVARCHAR(50) NOT NULL;
        IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE type=N'PK' AND parent_object_id=OBJECT_ID('dbo.ScreenPermission'))
            EXEC sp_executesql N'ALTER TABLE [dbo].[ScreenPermission] ADD CONSTRAINT [' + @scp_pk + N'] PRIMARY KEY CLUSTERED ([id])';

        DROP TABLE #scp_map;
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13f-ScreenPermission-id', N'OK', N'Migrated to SCP-0001...');
        PRINT N'  13f-ScreenPermission-id: OK';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF OBJECT_ID('tempdb..#scp_map','U') IS NOT NULL DROP TABLE #scp_map;
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
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
        IF OBJECT_ID('tempdb..#upm_map', 'U') IS NOT NULL DROP TABLE #upm_map;
        CREATE TABLE #upm_map (old_id NVARCHAR(50), new_id NVARCHAR(50), tmp_id NVARCHAR(50));
        INSERT INTO #upm_map (old_id, new_id, tmp_id)
        SELECT [id], N'UPM-' + RIGHT(N'000' + CAST(ROW_NUMBER() OVER (ORDER BY [id]) AS NVARCHAR(10)), 4),
               N'tmp_UPM_' + RIGHT(N'000' + CAST(ROW_NUMBER() OVER (ORDER BY [id]) AS NVARCHAR(10)), 4)
        FROM dbo.UserPermission WHERE [id] NOT LIKE N'UPM-%';

        DECLARE @upm_pk NVARCHAR(256);
        SELECT @upm_pk = name FROM sys.key_constraints WHERE type=N'PK' AND parent_object_id=OBJECT_ID('dbo.UserPermission');
        IF @upm_pk IS NOT NULL EXEC sp_executesql N'ALTER TABLE [dbo].[UserPermission] DROP CONSTRAINT [' + @upm_pk + N']';
        ELSE SET @upm_pk = N'UserPermission_pkey';

        UPDATE up SET up.[id] = m.tmp_id FROM dbo.UserPermission up JOIN #upm_map m ON up.[id] = m.old_id;
        UPDATE up SET up.[id] = m.new_id FROM dbo.UserPermission up JOIN #upm_map m ON up.[id] = m.tmp_id;

        ALTER TABLE [dbo].[UserPermission] ALTER COLUMN [id] NVARCHAR(50) NOT NULL;
        IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE type=N'PK' AND parent_object_id=OBJECT_ID('dbo.UserPermission'))
            EXEC sp_executesql N'ALTER TABLE [dbo].[UserPermission] ADD CONSTRAINT [' + @upm_pk + N'] PRIMARY KEY CLUSTERED ([id])';

        DROP TABLE #upm_map;
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13f-UserPermission-id', N'OK', N'Migrated to UPM-0001...');
        PRINT N'  13f-UserPermission-id: OK';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF OBJECT_ID('tempdb..#upm_map','U') IS NOT NULL DROP TABLE #upm_map;
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
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
        IF OBJECT_ID('tempdb..#acm_map', 'U') IS NOT NULL DROP TABLE #acm_map;
        CREATE TABLE #acm_map (old_id NVARCHAR(50), new_id NVARCHAR(50), tmp_id NVARCHAR(50));
        INSERT INTO #acm_map (old_id, new_id, tmp_id)
        SELECT [id], N'ACM-' + RIGHT(N'00' + CAST(ROW_NUMBER() OVER (ORDER BY [id]) AS NVARCHAR(10)), 3),
               N'tmp_ACM_' + RIGHT(N'00' + CAST(ROW_NUMBER() OVER (ORDER BY [id]) AS NVARCHAR(10)), 3)
        FROM dbo.AccountMapping WHERE [id] NOT LIKE N'ACM-%';

        DECLARE @acm_pk NVARCHAR(256);
        SELECT @acm_pk = name FROM sys.key_constraints WHERE type=N'PK' AND parent_object_id=OBJECT_ID('dbo.AccountMapping');
        IF @acm_pk IS NOT NULL EXEC sp_executesql N'ALTER TABLE [dbo].[AccountMapping] DROP CONSTRAINT [' + @acm_pk + N']';
        ELSE SET @acm_pk = N'AccountMapping_pkey';

        UPDATE am SET am.[id] = m.tmp_id FROM dbo.AccountMapping am JOIN #acm_map m ON am.[id] = m.old_id;
        UPDATE am SET am.[id] = m.new_id FROM dbo.AccountMapping am JOIN #acm_map m ON am.[id] = m.tmp_id;

        ALTER TABLE [dbo].[AccountMapping] ALTER COLUMN [id] NVARCHAR(50) NOT NULL;
        IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE type=N'PK' AND parent_object_id=OBJECT_ID('dbo.AccountMapping'))
            EXEC sp_executesql N'ALTER TABLE [dbo].[AccountMapping] ADD CONSTRAINT [' + @acm_pk + N'] PRIMARY KEY CLUSTERED ([id])';

        DROP TABLE #acm_map;
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13f-AccountMapping-id', N'OK', N'Migrated to ACM-001...');
        PRINT N'  13f-AccountMapping-id: OK';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF OBJECT_ID('tempdb..#acm_map','U') IS NOT NULL DROP TABLE #acm_map;
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
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
        IF OBJECT_ID('tempdb..#fdf_map', 'U') IS NOT NULL DROP TABLE #fdf_map;
        CREATE TABLE #fdf_map (old_id NVARCHAR(50), new_id NVARCHAR(50), tmp_id NVARCHAR(50));
        INSERT INTO #fdf_map (old_id, new_id, tmp_id)
        SELECT [id], N'FDF-' + RIGHT(N'00' + CAST(ROW_NUMBER() OVER (ORDER BY [id]) AS NVARCHAR(10)), 3),
               N'tmp_FDF_' + RIGHT(N'00' + CAST(ROW_NUMBER() OVER (ORDER BY [id]) AS NVARCHAR(10)), 3)
        FROM dbo.FinanceDefaults WHERE [id] NOT LIKE N'FDF-%';

        DECLARE @fdf_pk NVARCHAR(256);
        SELECT @fdf_pk = name FROM sys.key_constraints WHERE type=N'PK' AND parent_object_id=OBJECT_ID('dbo.FinanceDefaults');
        IF @fdf_pk IS NOT NULL EXEC sp_executesql N'ALTER TABLE [dbo].[FinanceDefaults] DROP CONSTRAINT [' + @fdf_pk + N']';
        ELSE SET @fdf_pk = N'FinanceDefaults_pkey';

        UPDATE fd SET fd.[id] = m.tmp_id FROM dbo.FinanceDefaults fd JOIN #fdf_map m ON fd.[id] = m.old_id;
        UPDATE fd SET fd.[id] = m.new_id FROM dbo.FinanceDefaults fd JOIN #fdf_map m ON fd.[id] = m.tmp_id;

        ALTER TABLE [dbo].[FinanceDefaults] ALTER COLUMN [id] NVARCHAR(50) NOT NULL;
        IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE type=N'PK' AND parent_object_id=OBJECT_ID('dbo.FinanceDefaults'))
            EXEC sp_executesql N'ALTER TABLE [dbo].[FinanceDefaults] ADD CONSTRAINT [' + @fdf_pk + N'] PRIMARY KEY CLUSTERED ([id])';

        DROP TABLE #fdf_map;
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13f-FinanceDefaults-id', N'OK', N'Migrated to FDF-001...');
        PRINT N'  13f-FinanceDefaults-id: OK';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF OBJECT_ID('tempdb..#fdf_map','U') IS NOT NULL DROP TABLE #fdf_map;
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
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

        -- Allow unbalanced OTB (default 1 = ON, current behaviour)
        IF COL_LENGTH('dbo.FinanceDefaults','allowUnbalancedOTB') IS NULL
        BEGIN
            ALTER TABLE dbo.FinanceDefaults ADD [allowUnbalancedOTB] BIT NOT NULL CONSTRAINT [FinanceDefaults_allowUnbalancedOTB_df] DEFAULT 1;
            PRINT N'  13g: added allowUnbalancedOTB';
        END

        -- Allow back-dated voucher entry (default 1 = ON)
        IF COL_LENGTH('dbo.FinanceDefaults','allowBackDatedVouchers') IS NULL
        BEGIN
            ALTER TABLE dbo.FinanceDefaults ADD [allowBackDatedVouchers] BIT NOT NULL CONSTRAINT [FinanceDefaults_allowBackDatedVouchers_df] DEFAULT 1;
            PRINT N'  13g: added allowBackDatedVouchers';
        END

        -- Lock-before date (nullable; if set, vouchers before this date cannot be posted)
        IF COL_LENGTH('dbo.FinanceDefaults','lockBeforeDate') IS NULL
        BEGIN
            ALTER TABLE dbo.FinanceDefaults ADD [lockBeforeDate] DATETIME2;
            PRINT N'  13g: added lockBeforeDate';
        END

        -- Voucher approval required (default 0 = OFF, current behaviour)
        IF COL_LENGTH('dbo.FinanceDefaults','voucherApprovalRequired') IS NULL
        BEGIN
            ALTER TABLE dbo.FinanceDefaults ADD [voucherApprovalRequired] BIT NOT NULL CONSTRAINT [FinanceDefaults_voucherApprovalRequired_df] DEFAULT 0;
            PRINT N'  13g: added voucherApprovalRequired';
        END

        -- Allow editing posted vouchers (default 1 = ON, current behaviour)
        IF COL_LENGTH('dbo.FinanceDefaults','allowEditPostedVouchers') IS NULL
        BEGIN
            ALTER TABLE dbo.FinanceDefaults ADD [allowEditPostedVouchers] BIT NOT NULL CONSTRAINT [FinanceDefaults_allowEditPostedVouchers_df] DEFAULT 1;
            PRINT N'  13g: added allowEditPostedVouchers';
        END

        -- Default currency (nullable)
        IF COL_LENGTH('dbo.FinanceDefaults','defaultCurrency') IS NULL
        BEGIN
            ALTER TABLE dbo.FinanceDefaults ADD [defaultCurrency] NVARCHAR(50);
            PRINT N'  13g: added defaultCurrency';
        END

        -- Decimal places (default 2)
        IF COL_LENGTH('dbo.FinanceDefaults','decimalPlaces') IS NULL
        BEGIN
            ALTER TABLE dbo.FinanceDefaults ADD [decimalPlaces] INT NOT NULL CONSTRAINT [FinanceDefaults_decimalPlaces_df] DEFAULT 2;
            PRINT N'  13g: added decimalPlaces';
        END

        -- Default payment mode for cash vouchers (nullable)
        IF COL_LENGTH('dbo.FinanceDefaults','defaultCashPaymentMode') IS NULL
        BEGIN
            ALTER TABLE dbo.FinanceDefaults ADD [defaultCashPaymentMode] NVARCHAR(50);
            PRINT N'  13g: added defaultCashPaymentMode';
        END

        -- Default payment mode for bank vouchers (nullable)
        IF COL_LENGTH('dbo.FinanceDefaults','defaultBankPaymentMode') IS NULL
        BEGIN
            ALTER TABLE dbo.FinanceDefaults ADD [defaultBankPaymentMode] NVARCHAR(50);
            PRINT N'  13g: added defaultBankPaymentMode';
        END

        -- Allow negative cash balance (default 0 = OFF)
        IF COL_LENGTH('dbo.FinanceDefaults','allowNegativeCash') IS NULL
        BEGIN
            ALTER TABLE dbo.FinanceDefaults ADD [allowNegativeCash] BIT NOT NULL CONSTRAINT [FinanceDefaults_allowNegativeCash_df] DEFAULT 0;
            PRINT N'  13g: added allowNegativeCash';
        END

        -- Auto-post fee/POS receipts (default 1 = ON, current behaviour)
        IF COL_LENGTH('dbo.FinanceDefaults','autoPostReceipts') IS NULL
        BEGIN
            ALTER TABLE dbo.FinanceDefaults ADD [autoPostReceipts] BIT NOT NULL CONSTRAINT [FinanceDefaults_autoPostReceipts_df] DEFAULT 1;
            PRINT N'  13g: added autoPostReceipts';
        END

        -- Fiscal year start/end (nullable; for display purposes)
        IF COL_LENGTH('dbo.FinanceDefaults','fiscalYearStart') IS NULL
        BEGIN
            ALTER TABLE dbo.FinanceDefaults ADD [fiscalYearStart] DATETIME2;
            PRINT N'  13g: added fiscalYearStart';
        END
        IF COL_LENGTH('dbo.FinanceDefaults','fiscalYearEnd') IS NULL
        BEGIN
            ALTER TABLE dbo.FinanceDefaults ADD [fiscalYearEnd] DATETIME2;
            PRINT N'  13g: added fiscalYearEnd';
        END

        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13g-FinanceDefaults-columns', N'OK', N'Added expanded finance settings columns');
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
-- STEP 13h: Update IdSequence for migrated ids
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

        -- USER sequence
        IF NOT EXISTS (SELECT 1 FROM dbo.IdSequence WHERE [key] = N'USER')
            INSERT INTO dbo.IdSequence ([key], [next], [updatedAt]) VALUES (N'USER', 2, SYSDATETIME());
        ELSE
            UPDATE dbo.IdSequence SET [next] = (SELECT COUNT(*) FROM dbo.[User]) + 1, [updatedAt] = SYSDATETIME() WHERE [key] = N'USER' AND [next] <= (SELECT COUNT(*) FROM dbo.[User]);

        -- PERMISSION sequence
        IF NOT EXISTS (SELECT 1 FROM dbo.IdSequence WHERE [key] = N'PERMISSION')
            INSERT INTO dbo.IdSequence ([key], [next], [updatedAt]) VALUES (N'PERMISSION', 2, SYSDATETIME());
        ELSE
            UPDATE dbo.IdSequence SET [next] = (SELECT COUNT(*) FROM dbo.Permission) + 1, [updatedAt] = SYSDATETIME() WHERE [key] = N'PERMISSION' AND [next] <= (SELECT COUNT(*) FROM dbo.Permission);

        -- ROLE sequence
        IF NOT EXISTS (SELECT 1 FROM dbo.IdSequence WHERE [key] = N'ROLE')
            INSERT INTO dbo.IdSequence ([key], [next], [updatedAt]) VALUES (N'ROLE', 2, SYSDATETIME());
        ELSE
            UPDATE dbo.IdSequence SET [next] = (SELECT COUNT(*) FROM dbo.Role) + 1, [updatedAt] = SYSDATETIME() WHERE [key] = N'ROLE' AND [next] <= (SELECT COUNT(*) FROM dbo.Role);

        -- TAXHEAD sequence
        IF NOT EXISTS (SELECT 1 FROM dbo.IdSequence WHERE [key] = N'TAXHEAD')
            INSERT INTO dbo.IdSequence ([key], [next], [updatedAt]) VALUES (N'TAXHEAD', 2, SYSDATETIME());
        ELSE
            UPDATE dbo.IdSequence SET [next] = (SELECT COUNT(*) FROM dbo.TaxHead) + 1, [updatedAt] = SYSDATETIME() WHERE [key] = N'TAXHEAD' AND [next] <= (SELECT COUNT(*) FROM dbo.TaxHead);

        -- SCREENPERMISSION sequence
        IF NOT EXISTS (SELECT 1 FROM dbo.IdSequence WHERE [key] = N'SCREENPERMISSION')
            INSERT INTO dbo.IdSequence ([key], [next], [updatedAt]) VALUES (N'SCREENPERMISSION', 2, SYSDATETIME());

        -- USERPERMISSION sequence
        IF NOT EXISTS (SELECT 1 FROM dbo.IdSequence WHERE [key] = N'USERPERMISSION')
            INSERT INTO dbo.IdSequence ([key], [next], [updatedAt]) VALUES (N'USERPERMISSION', 2, SYSDATETIME());

        -- ACCOUNTMAPPING sequence
        IF NOT EXISTS (SELECT 1 FROM dbo.IdSequence WHERE [key] = N'ACCOUNTMAPPING')
            INSERT INTO dbo.IdSequence ([key], [next], [updatedAt]) VALUES (N'ACCOUNTMAPPING', 2, SYSDATETIME());

        -- FINANCEDEFAULTS sequence
        IF NOT EXISTS (SELECT 1 FROM dbo.IdSequence WHERE [key] = N'FINANCEDEFAULTS')
            INSERT INTO dbo.IdSequence ([key], [next], [updatedAt]) VALUES (N'FINANCEDEFAULTS', 2, SYSDATETIME());

        -- DEFAULTS sequence
        IF NOT EXISTS (SELECT 1 FROM dbo.IdSequence WHERE [key] = N'DEFAULTS')
            INSERT INTO dbo.IdSequence ([key], [next], [updatedAt]) VALUES (N'DEFAULTS', 2, SYSDATETIME());

        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13h-IdSequence', N'OK', N'Updated IdSequence for all migrated id formats');
        PRINT N'  13h-IdSequence: OK';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13h-IdSequence', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  13h-IdSequence: FAILED - ' + @eMsg;
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
    (N'13h-IdSequence');

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

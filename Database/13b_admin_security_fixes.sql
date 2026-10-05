USE GymDB;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- 13b_admin_security_fixes.sql
-- ============================================================================
-- Patches for issues the review found in 13_admin_security_upgrade.sql
-- AFTER it was already run. Does NOT modify script 13. Idempotent: every
-- step checks whether the work is already done and skips if so.
--
-- Issues addressed:
--   1. Script 13f used `EXEC sp_executesql N'...' + @var + N'...'` for
--      ScreenPermission, UserPermission, AccountMapping, FinanceDefaults.
--      That syntax is not officially supported for sp_executesql's first
--      parameter (must be a constant or variable). If those batches
--      failed, the rows in those tables are still on their old cuid-style
--      ids. This script re-runs the migration with proper NVARCHAR(MAX)
--      variable parameters so it always works.
--
--   2. Script 13h only INSERTed IdSequence rows for SCREENPERMISSION,
--      USERPERMISSION, ACCOUNTMAPPING, FINANCEDEFAULTS, DEFAULTS — it
--      never UPDATEs them. If those sequence rows already existed with
--      a stale value, the next id could collide with existing rows.
--      This script syncs every relevant sequence row with the actual
--      max numeric suffix in the corresponding table.
--
--   3. Script 13a hardcoded `UPDATE dbo.Defaults SET [id] = N'CMP-001'`
--      for all rows at once, which would have produced a duplicate PK
--      if Defaults had more than one row. This script assigns CMP-001,
--      CMP-002, ... per row, so the migration is safe even if there were
--      multiple company rows.
--
--   4. Script 13h's UPDATE clauses for USER/PERMISSION/ROLE/TAXHEAD used
--      `WHERE [next] <= (SELECT COUNT(*))`. That is correct for the
--      usual case but doesn't reset to "max existing numeric suffix + 1",
--      so it can leave the counter too small if rows were deleted and
--      re-created with higher ids. This script also re-syncs those rows
--      with the same robust rule.
--
-- All steps log into dbo._UpgradeLog with the prefix "13b-".
-- ============================================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;

PRINT N'=== STEP 13b: Admin & Security Upgrade Fixes ===';

DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);

-- ============================================================================
-- STEP 13b-1: Re-migrate ScreenPermission.id -> SCP-0001 (safe syntax)
-- ============================================================================
USE GymDB;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);

IF OBJECT_ID('dbo.ScreenPermission','U') IS NOT NULL
   AND EXISTS (SELECT 1 FROM dbo.ScreenPermission WHERE [id] NOT LIKE N'SCP-%')
BEGIN
    BEGIN TRY
        BEGIN TRAN;
        IF OBJECT_ID('tempdb..#scp2_map', 'U') IS NOT NULL DROP TABLE #scp2_map;
        CREATE TABLE #scp2_map (old_id NVARCHAR(50), new_id NVARCHAR(50), tmp_id NVARCHAR(50));
        INSERT INTO #scp2_map (old_id, new_id, tmp_id)
        SELECT [id], N'SCP-' + RIGHT(N'000' + CAST(ROW_NUMBER() OVER (ORDER BY [id]) AS NVARCHAR(10)), 4),
               N'tmp_SCP_' + RIGHT(N'000' + CAST(ROW_NUMBER() OVER (ORDER BY [id]) AS NVARCHAR(10)), 4)
        FROM dbo.ScreenPermission WHERE [id] NOT LIKE N'SCP-%';

        DECLARE @scp2_pk NVARCHAR(256);
        SELECT @scp2_pk = name FROM sys.key_constraints WHERE type=N'PK' AND parent_object_id=OBJECT_ID('dbo.ScreenPermission');
        IF @scp2_pk IS NOT NULL
        BEGIN
            DECLARE @drop_scp2 NVARCHAR(MAX) = N'ALTER TABLE [dbo].[ScreenPermission] DROP CONSTRAINT [' + @scp2_pk + N']';
            EXEC sp_executesql @drop_scp2;
        END
        ELSE SET @scp2_pk = N'ScreenPermission_pkey';

        UPDATE sp SET sp.[id] = m.tmp_id FROM dbo.ScreenPermission sp JOIN #scp2_map m ON sp.[id] = m.old_id;
        UPDATE sp SET sp.[id] = m.new_id FROM dbo.ScreenPermission sp JOIN #scp2_map m ON sp.[id] = m.tmp_id;

        ALTER TABLE [dbo].[ScreenPermission] ALTER COLUMN [id] NVARCHAR(50) NOT NULL;
        IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE type=N'PK' AND parent_object_id=OBJECT_ID('dbo.ScreenPermission'))
        BEGIN
            DECLARE @add_scp2 NVARCHAR(MAX) = N'ALTER TABLE [dbo].[ScreenPermission] ADD CONSTRAINT [' + @scp2_pk + N'] PRIMARY KEY CLUSTERED ([id])';
            EXEC sp_executesql @add_scp2;
        END

        DROP TABLE #scp2_map;
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13b-1-ScreenPermission-id', N'OK', N'Re-migrated to SCP-0001 (safe syntax)');
        PRINT N'  13b-1-ScreenPermission-id: OK';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF OBJECT_ID('tempdb..#scp2_map','U') IS NOT NULL DROP TABLE #scp2_map;
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13b-1-ScreenPermission-id', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  13b-1-ScreenPermission-id: FAILED - ' + @eMsg;
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13b-1-ScreenPermission-id', N'SKIPPED', N'Already migrated or table missing');
    PRINT N'  13b-1-ScreenPermission-id: SKIPPED';
END
GO

-- ============================================================================
-- STEP 13b-2: Re-migrate UserPermission.id -> UPM-0001 (safe syntax)
-- ============================================================================
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
        IF OBJECT_ID('tempdb..#upm2_map', 'U') IS NOT NULL DROP TABLE #upm2_map;
        CREATE TABLE #upm2_map (old_id NVARCHAR(50), new_id NVARCHAR(50), tmp_id NVARCHAR(50));
        INSERT INTO #upm2_map (old_id, new_id, tmp_id)
        SELECT [id], N'UPM-' + RIGHT(N'000' + CAST(ROW_NUMBER() OVER (ORDER BY [id]) AS NVARCHAR(10)), 4),
               N'tmp_UPM_' + RIGHT(N'000' + CAST(ROW_NUMBER() OVER (ORDER BY [id]) AS NVARCHAR(10)), 4)
        FROM dbo.UserPermission WHERE [id] NOT LIKE N'UPM-%';

        DECLARE @upm2_pk NVARCHAR(256);
        SELECT @upm2_pk = name FROM sys.key_constraints WHERE type=N'PK' AND parent_object_id=OBJECT_ID('dbo.UserPermission');
        IF @upm2_pk IS NOT NULL
        BEGIN
            DECLARE @drop_upm2 NVARCHAR(MAX) = N'ALTER TABLE [dbo].[UserPermission] DROP CONSTRAINT [' + @upm2_pk + N']';
            EXEC sp_executesql @drop_upm2;
        END
        ELSE SET @upm2_pk = N'UserPermission_pkey';

        UPDATE up SET up.[id] = m.tmp_id FROM dbo.UserPermission up JOIN #upm2_map m ON up.[id] = m.old_id;
        UPDATE up SET up.[id] = m.new_id FROM dbo.UserPermission up JOIN #upm2_map m ON up.[id] = m.tmp_id;

        ALTER TABLE [dbo].[UserPermission] ALTER COLUMN [id] NVARCHAR(50) NOT NULL;
        IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE type=N'PK' AND parent_object_id=OBJECT_ID('dbo.UserPermission'))
        BEGIN
            DECLARE @add_upm2 NVARCHAR(MAX) = N'ALTER TABLE [dbo].[UserPermission] ADD CONSTRAINT [' + @upm2_pk + N'] PRIMARY KEY CLUSTERED ([id])';
            EXEC sp_executesql @add_upm2;
        END

        DROP TABLE #upm2_map;
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13b-2-UserPermission-id', N'OK', N'Re-migrated to UPM-0001 (safe syntax)');
        PRINT N'  13b-2-UserPermission-id: OK';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF OBJECT_ID('tempdb..#upm2_map','U') IS NOT NULL DROP TABLE #upm2_map;
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13b-2-UserPermission-id', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  13b-2-UserPermission-id: FAILED - ' + @eMsg;
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13b-2-UserPermission-id', N'SKIPPED', N'Already migrated or table missing');
    PRINT N'  13b-2-UserPermission-id: SKIPPED';
END
GO

-- ============================================================================
-- STEP 13b-3: Re-migrate AccountMapping.id -> ACM-001 (safe syntax)
-- ============================================================================
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
        IF OBJECT_ID('tempdb..#acm2_map', 'U') IS NOT NULL DROP TABLE #acm2_map;
        CREATE TABLE #acm2_map (old_id NVARCHAR(50), new_id NVARCHAR(50), tmp_id NVARCHAR(50));
        INSERT INTO #acm2_map (old_id, new_id, tmp_id)
        SELECT [id], N'ACM-' + RIGHT(N'00' + CAST(ROW_NUMBER() OVER (ORDER BY [id]) AS NVARCHAR(10)), 3),
               N'tmp_ACM_' + RIGHT(N'00' + CAST(ROW_NUMBER() OVER (ORDER BY [id]) AS NVARCHAR(10)), 3)
        FROM dbo.AccountMapping WHERE [id] NOT LIKE N'ACM-%';

        DECLARE @acm2_pk NVARCHAR(256);
        SELECT @acm2_pk = name FROM sys.key_constraints WHERE type=N'PK' AND parent_object_id=OBJECT_ID('dbo.AccountMapping');
        IF @acm2_pk IS NOT NULL
        BEGIN
            DECLARE @drop_acm2 NVARCHAR(MAX) = N'ALTER TABLE [dbo].[AccountMapping] DROP CONSTRAINT [' + @acm2_pk + N']';
            EXEC sp_executesql @drop_acm2;
        END
        ELSE SET @acm2_pk = N'AccountMapping_pkey';

        UPDATE am SET am.[id] = m.tmp_id FROM dbo.AccountMapping am JOIN #acm2_map m ON am.[id] = m.old_id;
        UPDATE am SET am.[id] = m.new_id FROM dbo.AccountMapping am JOIN #acm2_map m ON am.[id] = m.tmp_id;

        ALTER TABLE [dbo].[AccountMapping] ALTER COLUMN [id] NVARCHAR(50) NOT NULL;
        IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE type=N'PK' AND parent_object_id=OBJECT_ID('dbo.AccountMapping'))
        BEGIN
            DECLARE @add_acm2 NVARCHAR(MAX) = N'ALTER TABLE [dbo].[AccountMapping] ADD CONSTRAINT [' + @acm2_pk + N'] PRIMARY KEY CLUSTERED ([id])';
            EXEC sp_executesql @add_acm2;
        END

        DROP TABLE #acm2_map;
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13b-3-AccountMapping-id', N'OK', N'Re-migrated to ACM-001 (safe syntax)');
        PRINT N'  13b-3-AccountMapping-id: OK';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF OBJECT_ID('tempdb..#acm2_map','U') IS NOT NULL DROP TABLE #acm2_map;
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13b-3-AccountMapping-id', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  13b-3-AccountMapping-id: FAILED - ' + @eMsg;
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13b-3-AccountMapping-id', N'SKIPPED', N'Already migrated or table missing');
    PRINT N'  13b-3-AccountMapping-id: SKIPPED';
END
GO

-- ============================================================================
-- STEP 13b-4: Re-migrate FinanceDefaults.id -> FDF-001 (safe syntax)
-- ============================================================================
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
        IF OBJECT_ID('tempdb..#fdf2_map', 'U') IS NOT NULL DROP TABLE #fdf2_map;
        CREATE TABLE #fdf2_map (old_id NVARCHAR(50), new_id NVARCHAR(50), tmp_id NVARCHAR(50));
        INSERT INTO #fdf2_map (old_id, new_id, tmp_id)
        SELECT [id], N'FDF-' + RIGHT(N'00' + CAST(ROW_NUMBER() OVER (ORDER BY [id]) AS NVARCHAR(10)), 3),
               N'tmp_FDF_' + RIGHT(N'00' + CAST(ROW_NUMBER() OVER (ORDER BY [id]) AS NVARCHAR(10)), 3)
        FROM dbo.FinanceDefaults WHERE [id] NOT LIKE N'FDF-%';

        DECLARE @fdf2_pk NVARCHAR(256);
        SELECT @fdf2_pk = name FROM sys.key_constraints WHERE type=N'PK' AND parent_object_id=OBJECT_ID('dbo.FinanceDefaults');
        IF @fdf2_pk IS NOT NULL
        BEGIN
            DECLARE @drop_fdf2 NVARCHAR(MAX) = N'ALTER TABLE [dbo].[FinanceDefaults] DROP CONSTRAINT [' + @fdf2_pk + N']';
            EXEC sp_executesql @drop_fdf2;
        END
        ELSE SET @fdf2_pk = N'FinanceDefaults_pkey';

        UPDATE fd SET fd.[id] = m.tmp_id FROM dbo.FinanceDefaults fd JOIN #fdf2_map m ON fd.[id] = m.old_id;
        UPDATE fd SET fd.[id] = m.new_id FROM dbo.FinanceDefaults fd JOIN #fdf2_map m ON fd.[id] = m.tmp_id;

        ALTER TABLE [dbo].[FinanceDefaults] ALTER COLUMN [id] NVARCHAR(50) NOT NULL;
        IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE type=N'PK' AND parent_object_id=OBJECT_ID('dbo.FinanceDefaults'))
        BEGIN
            DECLARE @add_fdf2 NVARCHAR(MAX) = N'ALTER TABLE [dbo].[FinanceDefaults] ADD CONSTRAINT [' + @fdf2_pk + N'] PRIMARY KEY CLUSTERED ([id])';
            EXEC sp_executesql @add_fdf2;
        END

        DROP TABLE #fdf2_map;
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13b-4-FinanceDefaults-id', N'OK', N'Re-migrated to FDF-001 (safe syntax)');
        PRINT N'  13b-4-FinanceDefaults-id: OK';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF OBJECT_ID('tempdb..#fdf2_map','U') IS NOT NULL DROP TABLE #fdf2_map;
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13b-4-FinanceDefaults-id', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  13b-4-FinanceDefaults-id: FAILED - ' + @eMsg;
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13b-4-FinanceDefaults-id', N'SKIPPED', N'Already migrated or table missing');
    PRINT N'  13b-4-FinanceDefaults-id: SKIPPED';
END
GO

-- ============================================================================
-- STEP 13b-5: Defaults.id -> CMP-001 (safe, multi-row)
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
        -- Build a mapping that assigns CMP-001, CMP-002, ... one per row.
        IF OBJECT_ID('tempdb..#cmp_map', 'U') IS NOT NULL DROP TABLE #cmp_map;
        CREATE TABLE #cmp_map (old_id NVARCHAR(50), new_id NVARCHAR(50), tmp_id NVARCHAR(50));
        INSERT INTO #cmp_map (old_id, new_id, tmp_id)
        SELECT [id],
               N'CMP-' + RIGHT(N'00' + CAST(ROW_NUMBER() OVER (ORDER BY [createdAt], [id]) AS NVARCHAR(10)), 3),
               N'tmp_CMP_' + RIGHT(N'00' + CAST(ROW_NUMBER() OVER (ORDER BY [createdAt], [id]) AS NVARCHAR(10)), 3)
        FROM dbo.Defaults WHERE [id] NOT LIKE N'CMP-%';

        DECLARE @cmp_pk NVARCHAR(256);
        SELECT @cmp_pk = name FROM sys.key_constraints WHERE type=N'PK' AND parent_object_id=OBJECT_ID('dbo.Defaults');
        IF @cmp_pk IS NOT NULL
        BEGIN
            DECLARE @drop_cmp NVARCHAR(MAX) = N'ALTER TABLE [dbo].[Defaults] DROP CONSTRAINT [' + @cmp_pk + N']';
            EXEC sp_executesql @drop_cmp;
        END
        ELSE SET @cmp_pk = N'Defaults_pkey';

        -- Two-phase update so the PK rebuild doesn't collide.
        UPDATE d SET d.[id] = m.tmp_id FROM dbo.Defaults d JOIN #cmp_map m ON d.[id] = m.old_id;
        UPDATE d SET d.[id] = m.new_id FROM dbo.Defaults d JOIN #cmp_map m ON d.[id] = m.tmp_id;

        ALTER TABLE [dbo].[Defaults] ALTER COLUMN [id] NVARCHAR(50) NOT NULL;
        IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE type=N'PK' AND parent_object_id=OBJECT_ID('dbo.Defaults'))
        BEGIN
            DECLARE @add_cmp NVARCHAR(MAX) = N'ALTER TABLE [dbo].[Defaults] ADD CONSTRAINT [' + @cmp_pk + N'] PRIMARY KEY CLUSTERED ([id])';
            EXEC sp_executesql @add_cmp;
        END

        DROP TABLE #cmp_map;
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13b-5-Defaults-id', N'OK', N'Migrated Defaults.id to CMP-001+ (safe multi-row)');
        PRINT N'  13b-5-Defaults-id: OK';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF OBJECT_ID('tempdb..#cmp_map','U') IS NOT NULL DROP TABLE #cmp_map;
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13b-5-Defaults-id', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  13b-5-Defaults-id: FAILED - ' + @eMsg;
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13b-5-Defaults-id', N'SKIPPED', N'Already migrated or table missing');
    PRINT N'  13b-5-Defaults-id: SKIPPED';
END
GO

-- ============================================================================
-- STEP 13b-6: Sync IdSequence rows with actual max numeric suffix + 1.
-- Each id format is parsed for its numeric suffix; the sequence row is set
-- to MAX(suffix)+1, but never decreased below its current value (so already
-- reserved ids are never re-issued).
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

        -- Helper: get the max numeric suffix of ids matching a LIKE pattern.
        -- Returns 0 if no matching rows.
        DECLARE @maxN INT, @desired INT, @cur INT, @prefix NVARCHAR(20), @pattern NVARCHAR(20);

        -- USER -> USR-NNNN
        SET @prefix = N'USR-'; SET @pattern = N'USR-%';
        SELECT @maxN = MAX(CAST(SUBSTRING([id], LEN(@prefix) + 1, 20) AS INT))
        FROM dbo.[User] WHERE [id] LIKE @pattern AND SUBSTRING([id], LEN(@prefix) + 1, 20) NOT LIKE N'%[^0-9]%'
        OPTION (MAXDOP 1);
        IF @maxN IS NULL SET @maxN = 0;
        SET @desired = @maxN + 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.IdSequence WHERE [key] = N'USER')
            INSERT INTO dbo.IdSequence ([key], [next], [updatedAt]) VALUES (N'USER', @desired, SYSDATETIME());
        ELSE
        BEGIN
            SELECT @cur = [next] FROM dbo.IdSequence WHERE [key] = N'USER';
            IF @cur < @desired UPDATE dbo.IdSequence SET [next] = @desired, [updatedAt] = SYSDATETIME() WHERE [key] = N'USER';
        END

        -- PERMISSION -> PRM-NNNN
        SET @prefix = N'PRM-'; SET @pattern = N'PRM-%';
        SELECT @maxN = MAX(CAST(SUBSTRING([id], LEN(@prefix) + 1, 20) AS INT))
        FROM dbo.Permission WHERE [id] LIKE @pattern AND SUBSTRING([id], LEN(@prefix) + 1, 20) NOT LIKE N'%[^0-9]%'
        OPTION (MAXDOP 1);
        IF @maxN IS NULL SET @maxN = 0;
        SET @desired = @maxN + 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.IdSequence WHERE [key] = N'PERMISSION')
            INSERT INTO dbo.IdSequence ([key], [next], [updatedAt]) VALUES (N'PERMISSION', @desired, SYSDATETIME());
        ELSE
        BEGIN
            SELECT @cur = [next] FROM dbo.IdSequence WHERE [key] = N'PERMISSION';
            IF @cur < @desired UPDATE dbo.IdSequence SET [next] = @desired, [updatedAt] = SYSDATETIME() WHERE [key] = N'PERMISSION';
        END

        -- ROLE -> ROL-NNN
        SET @prefix = N'ROL-'; SET @pattern = N'ROL-%';
        SELECT @maxN = MAX(CAST(SUBSTRING([id], LEN(@prefix) + 1, 20) AS INT))
        FROM dbo.Role WHERE [id] LIKE @pattern AND SUBSTRING([id], LEN(@prefix) + 1, 20) NOT LIKE N'%[^0-9]%'
        OPTION (MAXDOP 1);
        IF @maxN IS NULL SET @maxN = 0;
        SET @desired = @maxN + 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.IdSequence WHERE [key] = N'ROLE')
            INSERT INTO dbo.IdSequence ([key], [next], [updatedAt]) VALUES (N'ROLE', @desired, SYSDATETIME());
        ELSE
        BEGIN
            SELECT @cur = [next] FROM dbo.IdSequence WHERE [key] = N'ROLE';
            IF @cur < @desired UPDATE dbo.IdSequence SET [next] = @desired, [updatedAt] = SYSDATETIME() WHERE [key] = N'ROLE';
        END

        -- TAXHEAD -> TAX-NNN
        SET @prefix = N'TAX-'; SET @pattern = N'TAX-%';
        SELECT @maxN = MAX(CAST(SUBSTRING([id], LEN(@prefix) + 1, 20) AS INT))
        FROM dbo.TaxHead WHERE [id] LIKE @pattern AND SUBSTRING([id], LEN(@prefix) + 1, 20) NOT LIKE N'%[^0-9]%'
        OPTION (MAXDOP 1);
        IF @maxN IS NULL SET @maxN = 0;
        SET @desired = @maxN + 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.IdSequence WHERE [key] = N'TAXHEAD')
            INSERT INTO dbo.IdSequence ([key], [next], [updatedAt]) VALUES (N'TAXHEAD', @desired, SYSDATETIME());
        ELSE
        BEGIN
            SELECT @cur = [next] FROM dbo.IdSequence WHERE [key] = N'TAXHEAD';
            IF @cur < @desired UPDATE dbo.IdSequence SET [next] = @desired, [updatedAt] = SYSDATETIME() WHERE [key] = N'TAXHEAD';
        END

        -- SCREENPERMISSION -> SCP-NNNN
        SET @prefix = N'SCP-'; SET @pattern = N'SCP-%';
        SELECT @maxN = MAX(CAST(SUBSTRING([id], LEN(@prefix) + 1, 20) AS INT))
        FROM dbo.ScreenPermission WHERE [id] LIKE @pattern AND SUBSTRING([id], LEN(@prefix) + 1, 20) NOT LIKE N'%[^0-9]%'
        OPTION (MAXDOP 1);
        IF @maxN IS NULL SET @maxN = 0;
        SET @desired = @maxN + 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.IdSequence WHERE [key] = N'SCREENPERMISSION')
            INSERT INTO dbo.IdSequence ([key], [next], [updatedAt]) VALUES (N'SCREENPERMISSION', @desired, SYSDATETIME());
        ELSE
        BEGIN
            SELECT @cur = [next] FROM dbo.IdSequence WHERE [key] = N'SCREENPERMISSION';
            IF @cur < @desired UPDATE dbo.IdSequence SET [next] = @desired, [updatedAt] = SYSDATETIME() WHERE [key] = N'SCREENPERMISSION';
        END

        -- USERPERMISSION -> UPM-NNNN
        SET @prefix = N'UPM-'; SET @pattern = N'UPM-%';
        SELECT @maxN = MAX(CAST(SUBSTRING([id], LEN(@prefix) + 1, 20) AS INT))
        FROM dbo.UserPermission WHERE [id] LIKE @pattern AND SUBSTRING([id], LEN(@prefix) + 1, 20) NOT LIKE N'%[^0-9]%'
        OPTION (MAXDOP 1);
        IF @maxN IS NULL SET @maxN = 0;
        SET @desired = @maxN + 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.IdSequence WHERE [key] = N'USERPERMISSION')
            INSERT INTO dbo.IdSequence ([key], [next], [updatedAt]) VALUES (N'USERPERMISSION', @desired, SYSDATETIME());
        ELSE
        BEGIN
            SELECT @cur = [next] FROM dbo.IdSequence WHERE [key] = N'USERPERMISSION';
            IF @cur < @desired UPDATE dbo.IdSequence SET [next] = @desired, [updatedAt] = SYSDATETIME() WHERE [key] = N'USERPERMISSION';
        END

        -- ACCOUNTMAPPING -> ACM-NNN
        SET @prefix = N'ACM-'; SET @pattern = N'ACM-%';
        SELECT @maxN = MAX(CAST(SUBSTRING([id], LEN(@prefix) + 1, 20) AS INT))
        FROM dbo.AccountMapping WHERE [id] LIKE @pattern AND SUBSTRING([id], LEN(@prefix) + 1, 20) NOT LIKE N'%[^0-9]%'
        OPTION (MAXDOP 1);
        IF @maxN IS NULL SET @maxN = 0;
        SET @desired = @maxN + 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.IdSequence WHERE [key] = N'ACCOUNTMAPPING')
            INSERT INTO dbo.IdSequence ([key], [next], [updatedAt]) VALUES (N'ACCOUNTMAPPING', @desired, SYSDATETIME());
        ELSE
        BEGIN
            SELECT @cur = [next] FROM dbo.IdSequence WHERE [key] = N'ACCOUNTMAPPING';
            IF @cur < @desired UPDATE dbo.IdSequence SET [next] = @desired, [updatedAt] = SYSDATETIME() WHERE [key] = N'ACCOUNTMAPPING';
        END

        -- FINANCEDEFAULTS -> FDF-NNN
        SET @prefix = N'FDF-'; SET @pattern = N'FDF-%';
        SELECT @maxN = MAX(CAST(SUBSTRING([id], LEN(@prefix) + 1, 20) AS INT))
        FROM dbo.FinanceDefaults WHERE [id] LIKE @pattern AND SUBSTRING([id], LEN(@prefix) + 1, 20) NOT LIKE N'%[^0-9]%'
        OPTION (MAXDOP 1);
        IF @maxN IS NULL SET @maxN = 0;
        SET @desired = @maxN + 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.IdSequence WHERE [key] = N'FINANCEDEFAULTS')
            INSERT INTO dbo.IdSequence ([key], [next], [updatedAt]) VALUES (N'FINANCEDEFAULTS', @desired, SYSDATETIME());
        ELSE
        BEGIN
            SELECT @cur = [next] FROM dbo.IdSequence WHERE [key] = N'FINANCEDEFAULTS';
            IF @cur < @desired UPDATE dbo.IdSequence SET [next] = @desired, [updatedAt] = SYSDATETIME() WHERE [key] = N'FINANCEDEFAULTS';
        END

        -- DEFAULTS -> CMP-NNN
        SET @prefix = N'CMP-'; SET @pattern = N'CMP-%';
        SELECT @maxN = MAX(CAST(SUBSTRING([id], LEN(@prefix) + 1, 20) AS INT))
        FROM dbo.Defaults WHERE [id] LIKE @pattern AND SUBSTRING([id], LEN(@prefix) + 1, 20) NOT LIKE N'%[^0-9]%'
        OPTION (MAXDOP 1);
        IF @maxN IS NULL SET @maxN = 0;
        SET @desired = @maxN + 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.IdSequence WHERE [key] = N'DEFAULTS')
            INSERT INTO dbo.IdSequence ([key], [next], [updatedAt]) VALUES (N'DEFAULTS', @desired, SYSDATETIME());
        ELSE
        BEGIN
            SELECT @cur = [next] FROM dbo.IdSequence WHERE [key] = N'DEFAULTS';
            IF @cur < @desired UPDATE dbo.IdSequence SET [next] = @desired, [updatedAt] = SYSDATETIME() WHERE [key] = N'DEFAULTS';
        END

        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13b-6-IdSequence', N'OK', N'Synced all IdSequence rows with max numeric suffix + 1');
        PRINT N'  13b-6-IdSequence: OK';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13b-6-IdSequence', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  13b-6-IdSequence: FAILED - ' + @eMsg;
    END CATCH
END
GO

-- ============================================================================
-- STEP 13b-7: Make sure FinanceDefaults has at least one row so the
-- Management -> Finance Defaults tab can be saved without first creating
-- a row with a NULL id. Idempotent.
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
            INSERT INTO dbo.FinanceDefaults ([id], [branchId], [allowUnbalancedOTB], [allowBackDatedVouchers],
                [voucherApprovalRequired], [allowEditPostedVouchers], [decimalPlaces], [allowNegativeCash],
                [autoPostReceipts], [createdAt], [updatedAt])
            VALUES (N'FDF-001', NULL, 1, 1, 0, 1, 2, 0, 1, SYSDATETIME(), SYSDATETIME());
            PRINT N'  13b-7: created company-wide FinanceDefaults row (FDF-001)';
        END
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13b-7-FinanceDefaults-seed', N'OK', N'Company-wide FinanceDefaults row exists');
        PRINT N'  13b-7-FinanceDefaults-seed: OK';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13b-7-FinanceDefaults-seed', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  13b-7-FinanceDefaults-seed: FAILED - ' + @eMsg;
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
PRINT N'=== STEP 13b SUMMARY ===';

DECLARE @expected13b TABLE (step NVARCHAR(100) NOT NULL);
INSERT INTO @expected13b (step) VALUES
    (N'13b-1-ScreenPermission-id'),
    (N'13b-2-UserPermission-id'),
    (N'13b-3-AccountMapping-id'),
    (N'13b-4-FinanceDefaults-id'),
    (N'13b-5-Defaults-id'),
    (N'13b-6-IdSequence'),
    (N'13b-7-FinanceDefaults-seed');

DECLARE @missing13b INT = 0, @failed13b INT = 0;
SELECT @missing13b = COUNT(*) FROM @expected13b e WHERE NOT EXISTS (SELECT 1 FROM dbo._UpgradeLog l WHERE l.step = e.step);
SELECT @failed13b = COUNT(*) FROM dbo._UpgradeLog l WHERE l.step LIKE N'13b%' AND l.status = N'FAILED';

IF @missing13b = 0 AND @failed13b = 0
BEGIN
    PRINT N'SUCCESS';
    SELECT N'SUCCESS' AS result, COUNT(*) AS steps, SUM(CASE WHEN status=N'OK' THEN 1 ELSE 0 END) AS ok, SUM(CASE WHEN status=N'SKIPPED' THEN 1 ELSE 0 END) AS skipped, 0 AS failed
    FROM dbo._UpgradeLog WHERE step LIKE N'13b%';
END
ELSE
BEGIN
    DECLARE @failList13b NVARCHAR(MAX) = N'';
    SELECT @failList13b = @failList13b + step + N'; ' FROM dbo._UpgradeLog WHERE step LIKE N'13b%' AND status = N'FAILED' ORDER BY step;
    SELECT @failList13b = @failList13b + N'MISSING: ' + step + N'; ' FROM @expected13b e WHERE NOT EXISTS (SELECT 1 FROM dbo._UpgradeLog l WHERE l.step = e.step) ORDER BY e.step;
    PRINT N'FAILED - ' + @failList13b;
    SELECT N'FAILED' AS result, @failList13b AS details;
END
GO

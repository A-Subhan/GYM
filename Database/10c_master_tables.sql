USE GymDB;
GO

-- ============================================================================
-- 10c_master_tables.sql
-- ============================================================================
-- Step 3: Create the 6 master/detail tables (if missing).
-- All 3 masters share identical structure; all 3 details share identical
-- structure. Detail code = master code + 3-digit sequence (001001, 001002, ...).
-- Idempotent: each table guarded by IF OBJECT_ID.
-- ============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

PRINT N'=== STEP 3: master/detail tables ===';

-- Preflight
PRINT N'  preflight: gymmaster=' + CASE WHEN OBJECT_ID('dbo.gymmaster','U') IS NOT NULL THEN N'EXISTS' ELSE N'MISSING' END;
PRINT N'  preflight: gymmasterdetail=' + CASE WHEN OBJECT_ID('dbo.gymmasterdetail','U') IS NOT NULL THEN N'EXISTS' ELSE N'MISSING' END;
PRINT N'  preflight: financemaster=' + CASE WHEN OBJECT_ID('dbo.financemaster','U') IS NOT NULL THEN N'EXISTS' ELSE N'MISSING' END;
PRINT N'  preflight: financemasterdetail=' + CASE WHEN OBJECT_ID('dbo.financemasterdetail','U') IS NOT NULL THEN N'EXISTS' ELSE N'MISSING' END;
PRINT N'  preflight: payrollmaster=' + CASE WHEN OBJECT_ID('dbo.payrollmaster','U') IS NOT NULL THEN N'EXISTS' ELSE N'MISSING' END;
PRINT N'  preflight: payrollmasterdetail=' + CASE WHEN OBJECT_ID('dbo.payrollmasterdetail','U') IS NOT NULL THEN N'EXISTS' ELSE N'MISSING' END;

-- 3a. gymmaster
IF OBJECT_ID(N'dbo.gymmaster', N'U') IS NULL
BEGIN
    DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);
BEGIN TRY
        BEGIN TRAN;
        CREATE TABLE [dbo].[gymmaster] (
            [id]          NVARCHAR(50)  NOT NULL,
            [name]        NVARCHAR(255) NOT NULL,
            [description] NVARCHAR(MAX),
            [branchId]    NVARCHAR(50),
            [isActive]    BIT NOT NULL CONSTRAINT [gymmaster_isActive_df] DEFAULT 1,
            [createdAt]   DATETIME2 NOT NULL CONSTRAINT [gymmaster_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
            [updatedAt]   DATETIME2 NOT NULL,
            CONSTRAINT [gymmaster_pkey] PRIMARY KEY CLUSTERED ([id])
        );
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'3a-gymmaster', N'OK', N'Created gymmaster');
        PRINT N'  3a-gymmaster: OK - Created gymmaster';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'3a-gymmaster', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  3a-gymmaster: FAILED - Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg;
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'3a-gymmaster', N'SKIPPED', N'gymmaster already exists');
    PRINT N'  3a-gymmaster: SKIPPED - gymmaster already exists';
END
GO

-- 3b. gymmasterdetail
SET NOCOUNT ON; SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.gymmasterdetail', N'U') IS NULL
BEGIN
    DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);
    BEGIN TRY
        BEGIN TRAN;
        CREATE TABLE [dbo].[gymmasterdetail] (
            [id]          NVARCHAR(50)  NOT NULL,
            [masterId]    NVARCHAR(50)  NOT NULL,
            [name]        NVARCHAR(255) NOT NULL,
            [description] NVARCHAR(MAX),
            [branchId]    NVARCHAR(50),
            [isActive]    BIT NOT NULL CONSTRAINT [gymmasterdetail_isActive_df] DEFAULT 1,
            [createdAt]   DATETIME2 NOT NULL CONSTRAINT [gymmasterdetail_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
            [updatedAt]   DATETIME2 NOT NULL,
            CONSTRAINT [gymmasterdetail_pkey] PRIMARY KEY CLUSTERED ([id])
        );
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'3b-gymmasterdetail', N'OK', N'Created gymmasterdetail');
        PRINT N'  3b-gymmasterdetail: OK - Created gymmasterdetail';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'3b-gymmasterdetail', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  3b-gymmasterdetail: FAILED - Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg;
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'3b-gymmasterdetail', N'SKIPPED', N'gymmasterdetail already exists');
    PRINT N'  3b-gymmasterdetail: SKIPPED - gymmasterdetail already exists';
END
GO

-- 3c. financemaster
SET NOCOUNT ON; SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.financemaster', N'U') IS NULL
BEGIN
    DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);
    BEGIN TRY
        BEGIN TRAN;
        CREATE TABLE [dbo].[financemaster] (
            [id]          NVARCHAR(50)  NOT NULL,
            [name]        NVARCHAR(255) NOT NULL,
            [description] NVARCHAR(MAX),
            [branchId]    NVARCHAR(50),
            [isActive]    BIT NOT NULL CONSTRAINT [financemaster_isActive_df] DEFAULT 1,
            [createdAt]   DATETIME2 NOT NULL CONSTRAINT [financemaster_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
            [updatedAt]   DATETIME2 NOT NULL,
            CONSTRAINT [financemaster_pkey] PRIMARY KEY CLUSTERED ([id])
        );
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'3c-financemaster', N'OK', N'Created financemaster');
        PRINT N'  3c-financemaster: OK - Created financemaster';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'3c-financemaster', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  3c-financemaster: FAILED - Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg;
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'3c-financemaster', N'SKIPPED', N'financemaster already exists');
    PRINT N'  3c-financemaster: SKIPPED - financemaster already exists';
END
GO

-- 3d. financemasterdetail
SET NOCOUNT ON; SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.financemasterdetail', N'U') IS NULL
BEGIN
    DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);
    BEGIN TRY
        BEGIN TRAN;
        CREATE TABLE [dbo].[financemasterdetail] (
            [id]          NVARCHAR(50)  NOT NULL,
            [masterId]    NVARCHAR(50)  NOT NULL,
            [name]        NVARCHAR(255) NOT NULL,
            [description] NVARCHAR(MAX),
            [branchId]    NVARCHAR(50),
            [isActive]    BIT NOT NULL CONSTRAINT [financemasterdetail_isActive_df] DEFAULT 1,
            [createdAt]   DATETIME2 NOT NULL CONSTRAINT [financemasterdetail_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
            [updatedAt]   DATETIME2 NOT NULL,
            CONSTRAINT [financemasterdetail_pkey] PRIMARY KEY CLUSTERED ([id])
        );
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'3d-financemasterdetail', N'OK', N'Created financemasterdetail');
        PRINT N'  3d-financemasterdetail: OK - Created financemasterdetail';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'3d-financemasterdetail', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  3d-financemasterdetail: FAILED - Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg;
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'3d-financemasterdetail', N'SKIPPED', N'financemasterdetail already exists');
    PRINT N'  3d-financemasterdetail: SKIPPED - financemasterdetail already exists';
END
GO

-- 3e. payrollmaster
SET NOCOUNT ON; SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.payrollmaster', N'U') IS NULL
BEGIN
    DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);
    BEGIN TRY
        BEGIN TRAN;
        CREATE TABLE [dbo].[payrollmaster] (
            [id]          NVARCHAR(50)  NOT NULL,
            [name]        NVARCHAR(255) NOT NULL,
            [description] NVARCHAR(MAX),
            [branchId]    NVARCHAR(50),
            [isActive]    BIT NOT NULL CONSTRAINT [payrollmaster_isActive_df] DEFAULT 1,
            [createdAt]   DATETIME2 NOT NULL CONSTRAINT [payrollmaster_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
            [updatedAt]   DATETIME2 NOT NULL,
            CONSTRAINT [payrollmaster_pkey] PRIMARY KEY CLUSTERED ([id])
        );
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'3e-payrollmaster', N'OK', N'Created payrollmaster');
        PRINT N'  3e-payrollmaster: OK - Created payrollmaster';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'3e-payrollmaster', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  3e-payrollmaster: FAILED - Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg;
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'3e-payrollmaster', N'SKIPPED', N'payrollmaster already exists');
    PRINT N'  3e-payrollmaster: SKIPPED - payrollmaster already exists';
END
GO

-- 3f. payrollmasterdetail
SET NOCOUNT ON; SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.payrollmasterdetail', N'U') IS NULL
BEGIN
    DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);
    BEGIN TRY
        BEGIN TRAN;
        CREATE TABLE [dbo].[payrollmasterdetail] (
            [id]          NVARCHAR(50)  NOT NULL,
            [masterId]    NVARCHAR(50)  NOT NULL,
            [name]        NVARCHAR(255) NOT NULL,
            [description] NVARCHAR(MAX),
            [branchId]    NVARCHAR(50),
            [isActive]    BIT NOT NULL CONSTRAINT [payrollmasterdetail_isActive_df] DEFAULT 1,
            [createdAt]   DATETIME2 NOT NULL CONSTRAINT [payrollmasterdetail_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
            [updatedAt]   DATETIME2 NOT NULL,
            CONSTRAINT [payrollmasterdetail_pkey] PRIMARY KEY CLUSTERED ([id])
        );
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'3f-payrollmasterdetail', N'OK', N'Created payrollmasterdetail');
        PRINT N'  3f-payrollmasterdetail: OK - Created payrollmasterdetail';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'3f-payrollmasterdetail', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  3f-payrollmasterdetail: FAILED - Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg;
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'3f-payrollmasterdetail', N'SKIPPED', N'payrollmasterdetail already exists');
    PRINT N'  3f-payrollmasterdetail: SKIPPED - payrollmasterdetail already exists';
END
GO

-- 3g. Indexes on detail tables (masterId)
SET NOCOUNT ON; SET XACT_ABORT ON;

IF OBJECT_ID('dbo.gymmasterdetail','U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name=N'gymmasterdetail_masterId_idx' AND object_id=OBJECT_ID('dbo.gymmasterdetail'))
BEGIN
    BEGIN TRY
        CREATE NONCLUSTERED INDEX [gymmasterdetail_masterId_idx] ON [dbo].[gymmasterdetail]([masterId]);
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'3g-idx-gymmasterdetail', N'OK', N'Created index');
        PRINT N'  3g-idx-gymmasterdetail: OK';
    END TRY
    BEGIN CATCH
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'3g-idx-gymmasterdetail', N'FAILED', ERROR_MESSAGE());
        PRINT N'  3g-idx-gymmasterdetail: FAILED - ' + ERROR_MESSAGE();
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'3g-idx-gymmasterdetail', N'SKIPPED', N'Index exists or table missing');
    PRINT N'  3g-idx-gymmasterdetail: SKIPPED';
END
GO

SET NOCOUNT ON; SET XACT_ABORT ON;

IF OBJECT_ID('dbo.financemasterdetail','U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name=N'financemasterdetail_masterId_idx' AND object_id=OBJECT_ID('dbo.financemasterdetail'))
BEGIN
    BEGIN TRY
        CREATE NONCLUSTERED INDEX [financemasterdetail_masterId_idx] ON [dbo].[financemasterdetail]([masterId]);
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'3g-idx-financemasterdetail', N'OK', N'Created index');
        PRINT N'  3g-idx-financemasterdetail: OK';
    END TRY
    BEGIN CATCH
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'3g-idx-financemasterdetail', N'FAILED', ERROR_MESSAGE());
        PRINT N'  3g-idx-financemasterdetail: FAILED - ' + ERROR_MESSAGE();
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'3g-idx-financemasterdetail', N'SKIPPED', N'Index exists or table missing');
    PRINT N'  3g-idx-financemasterdetail: SKIPPED';
END
GO

SET NOCOUNT ON; SET XACT_ABORT ON;

IF OBJECT_ID('dbo.payrollmasterdetail','U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name=N'payrollmasterdetail_masterId_idx' AND object_id=OBJECT_ID('dbo.payrollmasterdetail'))
BEGIN
    BEGIN TRY
        CREATE NONCLUSTERED INDEX [payrollmasterdetail_masterId_idx] ON [dbo].[payrollmasterdetail]([masterId]);
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'3g-idx-payrollmasterdetail', N'OK', N'Created index');
        PRINT N'  3g-idx-payrollmasterdetail: OK';
    END TRY
    BEGIN CATCH
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'3g-idx-payrollmasterdetail', N'FAILED', ERROR_MESSAGE());
        PRINT N'  3g-idx-payrollmasterdetail: FAILED - ' + ERROR_MESSAGE();
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'3g-idx-payrollmasterdetail', N'SKIPPED', N'Index exists or table missing');
    PRINT N'  3g-idx-payrollmasterdetail: SKIPPED';
END
GO

-- 3h. Foreign keys (detail.masterId -> master.id)
-- Uses sp_executesql with a prebuilt @sql NVARCHAR variable.
SET NOCOUNT ON; SET XACT_ABORT ON;

DECLARE @fk_sql NVARCHAR(MAX);

IF OBJECT_ID('dbo.gymmasterdetail','U') IS NOT NULL
   AND OBJECT_ID('dbo.gymmaster','U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'gymmasterdetail_masterId_fkey')
BEGIN
    SET @fk_sql = N'ALTER TABLE [dbo].[gymmasterdetail] ADD CONSTRAINT [gymmasterdetail_masterId_fkey] FOREIGN KEY ([masterId]) REFERENCES [dbo].[gymmaster]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION';
    BEGIN TRY
        EXEC sp_executesql @fk_sql;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'3h-fk-gmd-master', N'OK', N'FK added');
        PRINT N'  3h-fk-gmd-master: OK';
    END TRY
    BEGIN CATCH
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'3h-fk-gmd-master', N'FAILED', ERROR_MESSAGE());
        PRINT N'  3h-fk-gmd-master: FAILED - ' + ERROR_MESSAGE();
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'3h-fk-gmd-master', N'SKIPPED', N'FK exists or table missing');
    PRINT N'  3h-fk-gmd-master: SKIPPED';
END
GO

SET NOCOUNT ON; SET XACT_ABORT ON;

DECLARE @fk_sql NVARCHAR(MAX);

IF OBJECT_ID('dbo.financemasterdetail','U') IS NOT NULL
   AND OBJECT_ID('dbo.financemaster','U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'financemasterdetail_masterId_fkey')
BEGIN
    SET @fk_sql = N'ALTER TABLE [dbo].[financemasterdetail] ADD CONSTRAINT [financemasterdetail_masterId_fkey] FOREIGN KEY ([masterId]) REFERENCES [dbo].[financemaster]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION';
    BEGIN TRY
        EXEC sp_executesql @fk_sql;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'3h-fk-fmd-master', N'OK', N'FK added');
        PRINT N'  3h-fk-fmd-master: OK';
    END TRY
    BEGIN CATCH
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'3h-fk-fmd-master', N'FAILED', ERROR_MESSAGE());
        PRINT N'  3h-fk-fmd-master: FAILED - ' + ERROR_MESSAGE();
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'3h-fk-fmd-master', N'SKIPPED', N'FK exists or table missing');
    PRINT N'  3h-fk-fmd-master: SKIPPED';
END
GO

SET NOCOUNT ON; SET XACT_ABORT ON;

DECLARE @fk_sql NVARCHAR(MAX);

IF OBJECT_ID('dbo.payrollmasterdetail','U') IS NOT NULL
   AND OBJECT_ID('dbo.payrollmaster','U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'payrollmasterdetail_masterId_fkey')
BEGIN
    SET @fk_sql = N'ALTER TABLE [dbo].[payrollmasterdetail] ADD CONSTRAINT [payrollmasterdetail_masterId_fkey] FOREIGN KEY ([masterId]) REFERENCES [dbo].[payrollmaster]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION';
    BEGIN TRY
        EXEC sp_executesql @fk_sql;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'3h-fk-pmd-master', N'OK', N'FK added');
        PRINT N'  3h-fk-pmd-master: OK';
    END TRY
    BEGIN CATCH
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'3h-fk-pmd-master', N'FAILED', ERROR_MESSAGE());
        PRINT N'  3h-fk-pmd-master: FAILED - ' + ERROR_MESSAGE();
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'3h-fk-pmd-master', N'SKIPPED', N'FK exists or table missing');
    PRINT N'  3h-fk-pmd-master: SKIPPED';
END
GO

USE GymDB;
GO

-- ============================================================================
-- 10o_master_categories.sql
-- ============================================================================
-- Step 14: Copy remaining MasterFile values into the paired master/detail
-- tables. COPY only — do not delete or modify MasterFile.
--
-- Mapping:
--   payrollmaster:  004 Department    <- MasterFile masterType='Department'
--                   005 Designation   <- MasterFile masterType='Designation'
--   gymmaster:      003 Exercise Type  <- MasterFile masterType='ExerciseCategories'
--                   004 Trainer Spec   <- MasterFile masterType='TrainerSpecializations'
--   financemaster:  003 Currency       <- MasterFile masterType='Currency'
--
-- Safety: refuses to run if payrollmaster still has duplicate head names
-- (10n must run first). Guards each head: if id exists with a different
-- name, RAISERROR and roll back.
--
-- Idempotent: each insert guarded by WHERE NOT EXISTS.
-- One transaction, SET XACT_ABORT ON, XACT_STATE() check in CATCH.
-- ============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

PRINT N'=== STEP 14: Master categories copy ===';

-- Preflight: refuse if payrollmaster still has duplicate head names
DECLARE @pf_pm_dups INT = 0;
IF OBJECT_ID('dbo.payrollmaster','U') IS NOT NULL
BEGIN
    SELECT @pf_pm_dups = COUNT(*) FROM (
        SELECT [name], COUNT(*) AS cnt
        FROM dbo.payrollmaster
        GROUP BY [name]
        HAVING COUNT(*) > 1
    ) x;
END

IF @pf_pm_dups > 0
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'14-master-categories', N'SKIPPED', N'payrollmaster still has duplicate head names — run 10n first');
    PRINT N'  14-master-categories: SKIPPED - payrollmaster still has duplicate head names. Run 10n first.';
END
ELSE
BEGIN
    -- Continue in the next batch
    PRINT N'  preflight: payrollmaster has no duplicate head names — proceeding';
END
GO

-- Main copy (only if no duplicate heads)
USE GymDB;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);

IF OBJECT_ID('dbo.MasterFile','U') IS NOT NULL
   AND OBJECT_ID('dbo.payrollmaster','U') IS NOT NULL
   AND NOT EXISTS (
       SELECT 1 FROM (
           SELECT [name], COUNT(*) AS cnt
           FROM dbo.payrollmaster
           GROUP BY [name]
           HAVING COUNT(*) > 1
       ) x
   )
BEGIN
    BEGIN TRY
        SET XACT_ABORT ON;
        BEGIN TRAN;

        -- ====================================================================
        -- GUARD: verify each target head id does not exist or has the expected name
        -- ====================================================================

        -- payrollmaster 004 must be 'Department' or not exist
        IF EXISTS (SELECT 1 FROM dbo.payrollmaster WHERE [id] = N'004' AND [name] <> N'Department')
            RAISERROR(N'payrollmaster head 004 exists with unexpected name — expected Department', 16, 1);

        IF EXISTS (SELECT 1 FROM dbo.payrollmaster WHERE [id] = N'005' AND [name] <> N'Designation')
            RAISERROR(N'payrollmaster head 005 exists with unexpected name — expected Designation', 16, 1);

        IF EXISTS (SELECT 1 FROM dbo.gymmaster WHERE [id] = N'003' AND [name] <> N'Exercise Type')
            RAISERROR(N'gymmaster head 003 exists with unexpected name — expected Exercise Type', 16, 1);

        IF EXISTS (SELECT 1 FROM dbo.gymmaster WHERE [id] = N'004' AND [name] <> N'Trainer Specializations')
            RAISERROR(N'gymmaster head 004 exists with unexpected name — expected Trainer Specializations', 16, 1);

        IF EXISTS (SELECT 1 FROM dbo.financemaster WHERE [id] = N'003' AND [name] <> N'Currency')
            RAISERROR(N'financemaster head 003 exists with unexpected name — expected Currency', 16, 1);

        PRINT N'  14: all head guards passed';

        -- ====================================================================
        -- PAYROLL MASTER: Department (004), Designation (005)
        -- ====================================================================

        IF NOT EXISTS (SELECT 1 FROM dbo.payrollmaster WHERE [id] = N'004')
        BEGIN
            INSERT INTO dbo.payrollmaster ([id], [name], [description], [branchId], [isActive], [createdAt], [updatedAt])
            VALUES (N'004', N'Department', N'Departments (from MasterFile)', NULL, 1, SYSDATETIME(), SYSDATETIME());
            PRINT N'  14: inserted payrollmaster head 004 Department';
        END

        INSERT INTO dbo.payrollmasterdetail ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt])
        SELECT
            N'004' + RIGHT(N'00' + CAST(src.rn AS NVARCHAR(10)), 3),
            N'004',
            src.[name],
            src.[description],
            src.[branchId],
            src.[isActive],
            SYSDATETIME(),
            SYSDATETIME()
        FROM (
            SELECT
                mf.[name],
                mf.[description],
                mf.[branchId],
                mf.[isActive],
                ROW_NUMBER() OVER (ORDER BY mf.[name]) AS rn
            FROM dbo.MasterFile mf
            WHERE mf.[masterType] = N'Department' AND mf.[isActive] = 1
        ) src
        WHERE NOT EXISTS (
            SELECT 1 FROM dbo.payrollmasterdetail d
            WHERE d.[masterId] = N'004' AND d.[name] = src.[name]
        );
        PRINT N'  14: copied Department details into payrollmasterdetail';

        IF NOT EXISTS (SELECT 1 FROM dbo.payrollmaster WHERE [id] = N'005')
        BEGIN
            INSERT INTO dbo.payrollmaster ([id], [name], [description], [branchId], [isActive], [createdAt], [updatedAt])
            VALUES (N'005', N'Designation', N'Designations (from MasterFile)', NULL, 1, SYSDATETIME(), SYSDATETIME());
            PRINT N'  14: inserted payrollmaster head 005 Designation';
        END

        INSERT INTO dbo.payrollmasterdetail ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt])
        SELECT
            N'005' + RIGHT(N'00' + CAST(src.rn AS NVARCHAR(10)), 3),
            N'005',
            src.[name],
            src.[description],
            src.[branchId],
            src.[isActive],
            SYSDATETIME(),
            SYSDATETIME()
        FROM (
            SELECT
                mf.[name],
                mf.[description],
                mf.[branchId],
                mf.[isActive],
                ROW_NUMBER() OVER (ORDER BY mf.[name]) AS rn
            FROM dbo.MasterFile mf
            WHERE mf.[masterType] = N'Designation' AND mf.[isActive] = 1
        ) src
        WHERE NOT EXISTS (
            SELECT 1 FROM dbo.payrollmasterdetail d
            WHERE d.[masterId] = N'005' AND d.[name] = src.[name]
        );
        PRINT N'  14: copied Designation details into payrollmasterdetail';

        -- ====================================================================
        -- GYM MASTER: ExerciseCategories (003), TrainerSpecializations (004)
        -- ====================================================================

        IF NOT EXISTS (SELECT 1 FROM dbo.gymmaster WHERE [id] = N'003')
        BEGIN
            INSERT INTO dbo.gymmaster ([id], [name], [description], [branchId], [isActive], [createdAt], [updatedAt])
            VALUES (N'003', N'Exercise Type', N'Exercise categories (from MasterFile)', NULL, 1, SYSDATETIME(), SYSDATETIME());
            PRINT N'  14: inserted gymmaster head 003 Exercise Type';
        END

        INSERT INTO dbo.gymmasterdetail ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt])
        SELECT
            N'003' + RIGHT(N'00' + CAST(src.rn AS NVARCHAR(10)), 3),
            N'003',
            src.[name],
            src.[description],
            src.[branchId],
            src.[isActive],
            SYSDATETIME(),
            SYSDATETIME()
        FROM (
            SELECT
                mf.[name],
                mf.[description],
                mf.[branchId],
                mf.[isActive],
                ROW_NUMBER() OVER (ORDER BY mf.[name]) AS rn
            FROM dbo.MasterFile mf
            WHERE mf.[masterType] = N'ExerciseCategories' AND mf.[isActive] = 1
        ) src
        WHERE NOT EXISTS (
            SELECT 1 FROM dbo.gymmasterdetail d
            WHERE d.[masterId] = N'003' AND d.[name] = src.[name]
        );
        PRINT N'  14: copied ExerciseCategories details into gymmasterdetail';

        IF NOT EXISTS (SELECT 1 FROM dbo.gymmaster WHERE [id] = N'004')
        BEGIN
            INSERT INTO dbo.gymmaster ([id], [name], [description], [branchId], [isActive], [createdAt], [updatedAt])
            VALUES (N'004', N'Trainer Specializations', N'Trainer specialization options (from MasterFile)', NULL, 1, SYSDATETIME(), SYSDATETIME());
            PRINT N'  14: inserted gymmaster head 004 Trainer Specializations';
        END

        INSERT INTO dbo.gymmasterdetail ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt])
        SELECT
            N'004' + RIGHT(N'00' + CAST(src.rn AS NVARCHAR(10)), 3),
            N'004',
            src.[name],
            src.[description],
            src.[branchId],
            src.[isActive],
            SYSDATETIME(),
            SYSDATETIME()
        FROM (
            SELECT
                mf.[name],
                mf.[description],
                mf.[branchId],
                mf.[isActive],
                ROW_NUMBER() OVER (ORDER BY mf.[name]) AS rn
            FROM dbo.MasterFile mf
            WHERE mf.[masterType] = N'TrainerSpecializations' AND mf.[isActive] = 1
        ) src
        WHERE NOT EXISTS (
            SELECT 1 FROM dbo.gymmasterdetail d
            WHERE d.[masterId] = N'004' AND d.[name] = src.[name]
        );
        PRINT N'  14: copied TrainerSpecializations details into gymmasterdetail';

        -- ====================================================================
        -- FINANCE MASTER: Currency (003)
        -- ====================================================================

        IF NOT EXISTS (SELECT 1 FROM dbo.financemaster WHERE [id] = N'003')
        BEGIN
            INSERT INTO dbo.financemaster ([id], [name], [description], [branchId], [isActive], [createdAt], [updatedAt])
            VALUES (N'003', N'Currency', N'Currencies (from MasterFile)', NULL, 1, SYSDATETIME(), SYSDATETIME());
            PRINT N'  14: inserted financemaster head 003 Currency';
        END

        INSERT INTO dbo.financemasterdetail ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt])
        SELECT
            N'003' + RIGHT(N'00' + CAST(src.rn AS NVARCHAR(10)), 3),
            N'003',
            src.[name],
            src.[description],
            src.[branchId],
            src.[isActive],
            SYSDATETIME(),
            SYSDATETIME()
        FROM (
            SELECT
                mf.[name],
                mf.[description],
                mf.[branchId],
                mf.[isActive],
                ROW_NUMBER() OVER (ORDER BY mf.[name]) AS rn
            FROM dbo.MasterFile mf
            WHERE mf.[masterType] = N'Currency' AND mf.[isActive] = 1
        ) src
        WHERE NOT EXISTS (
            SELECT 1 FROM dbo.financemasterdetail d
            WHERE d.[masterId] = N'003' AND d.[name] = src.[name]
        );
        PRINT N'  14: copied Currency details into financemasterdetail';

        -- ====================================================================
        -- Verify
        -- ====================================================================
        DECLARE @v_pm_heads INT = 0, @v_pm_details INT = 0;
        DECLARE @v_gm_heads INT = 0, @v_gm_details INT = 0;
        DECLARE @v_fm_heads INT = 0, @v_fm_details INT = 0;

        SELECT @v_pm_heads = COUNT(*) FROM dbo.payrollmaster;
        SELECT @v_pm_details = COUNT(*) FROM dbo.payrollmasterdetail;
        SELECT @v_gm_heads = COUNT(*) FROM dbo.gymmaster;
        SELECT @v_gm_details = COUNT(*) FROM dbo.gymmasterdetail;
        SELECT @v_fm_heads = COUNT(*) FROM dbo.financemaster;
        SELECT @v_fm_details = COUNT(*) FROM dbo.financemasterdetail;

        PRINT N'  14: payrollmaster ' + CAST(@v_pm_heads AS NVARCHAR(10)) + N' heads, ' + CAST(@v_pm_details AS NVARCHAR(10)) + N' details';
        PRINT N'  14: gymmaster ' + CAST(@v_gm_heads AS NVARCHAR(10)) + N' heads, ' + CAST(@v_gm_details AS NVARCHAR(10)) + N' details';
        PRINT N'  14: financemaster ' + CAST(@v_fm_heads AS NVARCHAR(10)) + N' heads, ' + CAST(@v_fm_details AS NVARCHAR(10)) + N' details';

        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'14-master-categories', N'OK', N'Copied Department, Designation, ExerciseCategories, TrainerSpecializations, Currency into paired tables');
        PRINT N'  14-master-categories: OK - all categories copied';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'14-master-categories', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  14-master-categories: FAILED - Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg;
    END CATCH
END
ELSE IF OBJECT_ID('dbo.MasterFile','U') IS NULL
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'14-master-categories', N'SKIPPED', N'MasterFile table missing');
    PRINT N'  14-master-categories: SKIPPED - MasterFile table missing';
END
GO

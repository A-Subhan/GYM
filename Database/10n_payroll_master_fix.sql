USE GymDB;
GO

-- ============================================================================
-- 10n_payroll_master_fix.sql
-- ============================================================================
-- Step 13: Fix payrollmaster/payrollmasterdetail after 10d step 4c created
-- duplicate heads (one per payrollmasterfile ROW instead of per DISTINCT
-- masterType).
--
-- Correct result:
--   3 heads: 001 Country, 002 Education, 003 Leave Type
--   12 details: 3 Country, 5 Education, 4 Leave Type
--   Leave Type JSON (allowedDays/isPaid) from payrollmasterfile.extra
--   stored in payrollmasterdetail.description as JSON.
--
-- Idempotent: only runs if duplicate head names exist in payrollmaster.
-- One transaction, SET XACT_ABORT ON, XACT_STATE() check in CATCH.
-- In-place: no table rename/rebuild, no sp_rename.
-- ============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

PRINT N'=== STEP 13: Payroll master fix ===';

-- Preflight: check for duplicate head names
DECLARE @pf_dup_heads INT = 0;
IF OBJECT_ID('dbo.payrollmaster','U') IS NOT NULL
BEGIN
    SELECT @pf_dup_heads = COUNT(*) FROM (
        SELECT [name], COUNT(*) AS cnt
        FROM dbo.payrollmaster
        GROUP BY [name]
        HAVING COUNT(*) > 1
    ) x;
END
PRINT N'  preflight: ' + CAST(@pf_dup_heads AS NVARCHAR(10)) + N' duplicate head names in payrollmaster';

IF @pf_dup_heads = 0
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13-payroll-master-fix', N'SKIPPED', N'No duplicate head names - payrollmaster already correct');
    PRINT N'  13-payroll-master-fix: SKIPPED - no duplicate head names';
END
GO

-- Main fix (only if duplicates exist)
USE GymDB;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);

IF OBJECT_ID('dbo.payrollmaster','U') IS NOT NULL
   AND OBJECT_ID('dbo.payrollmasterdetail','U') IS NOT NULL
   AND EXISTS (
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

        -- 13a. Discover any FKs or columns referencing payrollmaster/payrollmasterdetail.
        DECLARE @fk_count INT = 0;
        SELECT @fk_count = COUNT(*)
        FROM sys.foreign_keys fk
        WHERE fk.referenced_object_id IN (OBJECT_ID('dbo.payrollmaster'), OBJECT_ID('dbo.payrollmasterdetail'));
        PRINT N'  13: FKs referencing payrollmaster/detail: ' + CAST(@fk_count AS NVARCHAR(10));

        -- 13b. Delete all existing payrollmasterdetail and payrollmaster rows.
        DELETE FROM dbo.payrollmasterdetail;
        PRINT N'  13: deleted all payrollmasterdetail rows';

        DELETE FROM dbo.payrollmaster;
        PRINT N'  13: deleted all payrollmaster rows';

        -- 13c. Rebuild from payrollmasterfile: one head per DISTINCT masterType.
        -- Bug fix: SELECT DISTINCT + ROW_NUMBER does NOT dedupe (window runs first).
        -- Fix: use a derived table with GROUP BY [masterType] first, then ROW_NUMBER
        -- over that grouped result. Both heads and details use the same grouped
        -- derived table to ensure catRn matches.
        IF OBJECT_ID('dbo.payrollmasterfile','U') IS NOT NULL
        BEGIN
            -- Build the grouped heads into a temp table (used by both heads and details).
            IF OBJECT_ID('tempdb..#pm_cats', 'U') IS NOT NULL DROP TABLE #pm_cats;
            CREATE TABLE #pm_cats (masterType NVARCHAR(255), catRn INT);

            INSERT INTO #pm_cats (masterType, catRn)
            SELECT
                g.[masterType],
                ROW_NUMBER() OVER (ORDER BY
                    CASE g.[masterType]
                        WHEN N'Country' THEN 1
                        WHEN N'Education' THEN 2
                        WHEN N'Leave Type' THEN 3
                        ELSE 99
                    END,
                    g.[masterType]
                ) AS rn
            FROM (
                -- GROUP BY first to get one row per masterType (deduped)
                SELECT [masterType]
                FROM dbo.payrollmasterfile
                WHERE [masterType] IN (N'Country', N'Education', N'Leave Type')
                GROUP BY [masterType]
            ) g;

            -- Insert heads from the grouped temp table
            INSERT INTO dbo.payrollmaster ([id], [name], [description], [branchId], [isActive], [createdAt], [updatedAt])
            SELECT
                RIGHT(N'00' + CAST(c.catRn AS NVARCHAR(10)), 3),
                c.[masterType],
                N'Migrated from payrollmasterfile',
                NULL,
                1,
                SYSDATETIME(),
                SYSDATETIME()
            FROM #pm_cats c;

            PRINT N'  13: inserted payrollmaster heads';

            -- Insert details: one per payrollmasterfile row, ordered by name.
            -- Detail id = head code (catRn) + 3-digit sequence (rn).
            -- Bug fix: use items.catRn (not cats.rn — cats is not in scope).
            -- For Leave Type rows, store the JSON from [extra] in [description].
            INSERT INTO dbo.payrollmasterdetail ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt])
            SELECT
                RIGHT(N'00' + CAST(items.catRn AS NVARCHAR(10)), 3)
                    + RIGHT(N'00' + CAST(items.rn AS NVARCHAR(10)), 3),
                RIGHT(N'00' + CAST(items.catRn AS NVARCHAR(10)), 3),
                items.[name],
                CASE
                    WHEN items.[masterType] = N'Leave Type' AND items.[extra] IS NOT NULL
                        THEN items.[extra]
                    ELSE items.[description]
                END,
                items.[branchId],
                items.[isActive],
                SYSDATETIME(),
                SYSDATETIME()
            FROM (
                SELECT
                    p.[masterType],
                    p.[name],
                    p.[description],
                    p.[extra],
                    p.[branchId],
                    p.[isActive],
                    c.catRn AS catRn,
                    ROW_NUMBER() OVER (PARTITION BY p.[masterType] ORDER BY p.[name]) AS rn
                FROM dbo.payrollmasterfile p
                JOIN #pm_cats c ON c.[masterType] = p.[masterType]
                WHERE p.[masterType] IN (N'Country', N'Education', N'Leave Type')
                  AND p.[isActive] = 1
            ) items;

            PRINT N'  13: inserted payrollmasterdetail rows';

            DROP TABLE #pm_cats;
        END
        ELSE
        BEGIN
            -- No payrollmasterfile — insert from 06_master_data.sql seed defaults
            INSERT INTO dbo.payrollmaster ([id], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES
                (N'001', N'Country', N'Countries', NULL, 1, SYSDATETIME(), SYSDATETIME()),
                (N'002', N'Education', N'Education levels', NULL, 1, SYSDATETIME(), SYSDATETIME()),
                (N'003', N'Leave Type', N'Leave types (used by the Leave screen)', NULL, 1, SYSDATETIME(), SYSDATETIME());

            PRINT N'  13: inserted default payrollmaster heads (no payrollmasterfile)';
        END

        -- 13d. Verify: exactly 3 heads, exactly 12 details, no duplicate (masterId, name).
        -- Expected breakdown: 3 Country + 5 Education + 4 Leave Type = 12 details.
        DECLARE @v_heads INT = 0, @v_details INT = 0, @v_dup INT = 0;
        SELECT @v_heads = COUNT(*) FROM dbo.payrollmaster;
        SELECT @v_details = COUNT(*) FROM dbo.payrollmasterdetail;
        SELECT @v_dup = COUNT(*) FROM (
            SELECT [masterId], [name], COUNT(*) AS cnt
            FROM dbo.payrollmasterdetail
            GROUP BY [masterId], [name]
            HAVING COUNT(*) > 1
        ) x;

        IF @v_heads <> 3
            RAISERROR(N'Verification failed: expected 3 heads, got %d', 16, 1, @v_heads);
        IF @v_details <> 12
            RAISERROR(N'Verification failed: expected 12 details, got %d', 16, 1, @v_details);
        IF @v_dup > 0
            RAISERROR(N'Verification failed: %d duplicate (masterId, name) pairs', 16, 1, @v_dup);

        -- Verify Leave Type JSON landed in description
        DECLARE @v_lt_json INT = 0;
        SELECT @v_lt_json = COUNT(*)
        FROM dbo.payrollmasterdetail d
        JOIN dbo.payrollmaster m ON m.[id] = d.[masterId]
        WHERE m.[name] = N'Leave Type'
          AND d.[description] LIKE N'%allowedDays%'
          AND d.[description] LIKE N'%isPaid%';
        IF @v_lt_json <> 4
            RAISERROR(N'Verification failed: expected 4 Leave Type rows with JSON, got %d', 16, 1, @v_lt_json);

        PRINT N'  13: verification OK (' + CAST(@v_heads AS NVARCHAR(10)) + N' heads, ' + CAST(@v_details AS NVARCHAR(10)) + N' details, 0 duplicates, ' + CAST(@v_lt_json AS NVARCHAR(10)) + N' Leave Type JSON rows)';

        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13-payroll-master-fix', N'OK', N'Rebuilt payrollmaster: 3 heads, 12 details, Leave Type JSON stored in description');
        PRINT N'  13-payroll-master-fix: OK - payrollmaster rebuilt correctly';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF OBJECT_ID('tempdb..#pm_cats', 'U') IS NOT NULL DROP TABLE #pm_cats;
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'13-payroll-master-fix', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  13-payroll-master-fix: FAILED - Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg;
    END CATCH
END
GO

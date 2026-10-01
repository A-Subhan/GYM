USE GymDB;
GO

-- ============================================================================
-- 10l_feepayment_ids.sql
-- ============================================================================
-- Step 11c: FeePayment id format conversion.
-- Converts existing FeePayment ids (cuid) to the app's format:
--   FP/{branchCode}/{MMMyy}/{000001}
--
-- After migration, updates dbo.IdSequence so app-generated ids continue
-- after the migrated ones without clashing. The backend (ids.ts) uses key:
--   FEEPAY/{branchCode}/{MMMyy}
-- and generates ids as:
--   FP/{branchCode}/{MMMyy}/{pad(seq, 6)}
-- where MMMyy = uppercase month abbrev + 2-digit year (e.g. SEP26).
--
-- NOTE: compile-time errors (e.g. Msg 8120) bypass TRY/CATCH and are
-- handled by SET XACT_ABORT ON (rolls back the entire transaction).
-- Runtime errors are caught by CATCH which captures error info, rolls
-- back via XACT_STATE(), then logs to dbo._UpgradeLog.
-- ============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

PRINT N'=== STEP 11c: FeePayment id format ===';

-- Preflight
IF OBJECT_ID('dbo.FeePayment','U') IS NOT NULL
BEGIN
    DECLARE @pf_bad INT = 0;
    SELECT @pf_bad = COUNT(*) FROM dbo.FeePayment WHERE [id] NOT LIKE N'FP/%';
    PRINT N'  preflight: ' + CAST(@pf_bad AS NVARCHAR(10)) + N' FeePayment rows with non-FP/ ids';

    IF @pf_bad = 0
    BEGIN
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'11c-FeePayment-ids', N'SKIPPED', N'All FeePayment ids already match FP/ format');
        PRINT N'  11c-FeePayment-ids: SKIPPED - All ids already match FP/ format';
    END
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'11c-FeePayment-ids', N'SKIPPED', N'FeePayment table missing');
    PRINT N'  11c-FeePayment-ids: SKIPPED - FeePayment table missing';
END
GO

-- Main migration (only if there are non-FP/ ids)
USE GymDB;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);

IF OBJECT_ID('dbo.FeePayment','U') IS NOT NULL
   AND EXISTS (SELECT 1 FROM dbo.FeePayment WHERE [id] NOT LIKE N'FP/%')
BEGIN
    BEGIN TRY
        SET XACT_ABORT ON;
        BEGIN TRAN;

        -- 11c-a. Discover FKs referencing FeePayment (likely none).
        IF OBJECT_ID('tempdb..#fp_fks', 'U') IS NOT NULL DROP TABLE #fp_fks;
        CREATE TABLE #fp_fks (
            fk_name NVARCHAR(256),
            parent_table NVARCHAR(128),
            parent_col NVARCHAR(128),
            on_delete NVARCHAR(20),
            on_update NVARCHAR(20)
        );

        INSERT INTO #fp_fks (fk_name, parent_table, parent_col, on_delete, on_update)
        SELECT
            fk.name,
            OBJECT_NAME(fk.parent_object_id),
            COL_NAME(fkc.parent_object_id, fkc.parent_column_id),
            fk.delete_referential_action_desc,
            fk.update_referential_action_desc
        FROM sys.foreign_keys fk
        JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
        WHERE fk.referenced_object_id = OBJECT_ID('dbo.FeePayment');

        -- Drop any FKs referencing FeePayment
        DECLARE @ffk_name NVARCHAR(256), @ffk_parent NVARCHAR(128);
        DECLARE @drop_ffk_sql NVARCHAR(MAX);
        DECLARE drop_ffk_cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT DISTINCT fk_name, parent_table FROM #fp_fks;

        OPEN drop_ffk_cur;
        FETCH NEXT FROM drop_ffk_cur INTO @ffk_name, @ffk_parent;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @drop_ffk_sql = N'ALTER TABLE [dbo].' + QUOTENAME(@ffk_parent)
                + N' DROP CONSTRAINT [' + @ffk_name + N']';
            EXEC sp_executesql @drop_ffk_sql;
            PRINT N'  11c: dropped FK [' + @ffk_name + N'] on [' + @ffk_parent + N']';
            FETCH NEXT FROM drop_ffk_cur INTO @ffk_name, @ffk_parent;
        END
        CLOSE drop_ffk_cur;
        DEALLOCATE drop_ffk_cur;

        -- 11c-b. Build new ids for each FeePayment row.
        -- Month abbreviation is locale-independent:
        --   SUBSTRING(N'JANFEBMARAPRMAYJUNJULAUGSEPOCTNOVDEC', (MONTH(x)-1)*3+1, 3)
        -- This produces 'Sep' for September, matching the backend MONTHS array.
        IF OBJECT_ID('tempdb..#fp_map', 'U') IS NOT NULL DROP TABLE #fp_map;
        CREATE TABLE #fp_map (old_id NVARCHAR(50), new_id NVARCHAR(50));

        -- First: FeePayment rows with a valid Fee -> Branch chain.
        -- Compute branchCode and monthKey as plain columns in a derived table,
        -- then use ROW_NUMBER() PARTITION BY those plain columns.
        INSERT INTO #fp_map (old_id, new_id)
        SELECT
            src.fp_id,
            N'FP/' + src.branchCode + N'/' + src.monthKey
                + N'/' + RIGHT(N'00000' + CAST(src.rn AS NVARCHAR(10)), 6)
        FROM (
            SELECT
                fp.[id] AS fp_id,
                b.[code] AS branchCode,
                SUBSTRING(N'JANFEBMARAPRMAYJUNJULAUGSEPOCTNOVDEC',
                    (MONTH(fp.[createdAt]) - 1) * 3 + 1, 3)
                    + RIGHT(CAST(YEAR(fp.[createdAt]) AS NVARCHAR(10)), 2) AS monthKey,
                ROW_NUMBER() OVER (
                    PARTITION BY b.[code],
                        SUBSTRING(N'JANFEBMARAPRMAYJUNJULAUGSEPOCTNOVDEC',
                            (MONTH(fp.[createdAt]) - 1) * 3 + 1, 3)
                        + RIGHT(CAST(YEAR(fp.[createdAt]) AS NVARCHAR(10)), 2)
                    ORDER BY fp.[createdAt], fp.[id]
                ) AS rn
            FROM dbo.FeePayment fp
            JOIN dbo.Fee f ON f.[id] = fp.[feeId]
            JOIN dbo.Branch b ON b.[id] = f.[branchId]
        ) src;

        -- Second: FeePayment rows where Fee or Branch might be missing.
        -- Uses 'UNKNOWN' as branch code.
        INSERT INTO #fp_map (old_id, new_id)
        SELECT
            src.fp_id,
            N'FP/UNKNOWN/' + src.monthKey
                + N'/' + RIGHT(N'00000' + CAST(src.rn AS NVARCHAR(10)), 6)
        FROM (
            SELECT
                fp.[id] AS fp_id,
                SUBSTRING(N'JANFEBMARAPRMAYJUNJULAUGSEPOCTNOVDEC',
                    (MONTH(fp.[createdAt]) - 1) * 3 + 1, 3)
                    + RIGHT(CAST(YEAR(fp.[createdAt]) AS NVARCHAR(10)), 2) AS monthKey,
                ROW_NUMBER() OVER (
                    PARTITION BY
                        SUBSTRING(N'JANFEBMARAPRMAYJUNJULAUGSEPOCTNOVDEC',
                            (MONTH(fp.[createdAt]) - 1) * 3 + 1, 3)
                        + RIGHT(CAST(YEAR(fp.[createdAt]) AS NVARCHAR(10)), 2)
                    ORDER BY fp.[createdAt], fp.[id]
                ) AS rn
            FROM dbo.FeePayment fp
            WHERE NOT EXISTS (
                SELECT 1 FROM #fp_map existing_m WHERE existing_m.old_id = fp.[id]
            )
        ) src;

        DECLARE @map_count INT = 0;
        SELECT @map_count = COUNT(*) FROM #fp_map;
        PRINT N'  11c: built ' + CAST(@map_count AS NVARCHAR(10)) + N' new FeePayment ids';

        -- 11c-c. Drop FeePayment PK.
        DECLARE @fp_pk_name NVARCHAR(256);
        SELECT @fp_pk_name = name FROM sys.key_constraints
        WHERE type = N'PK' AND parent_object_id = OBJECT_ID('dbo.FeePayment');
        IF @fp_pk_name IS NOT NULL
        BEGIN
            DECLARE @drop_fp_pk NVARCHAR(MAX) = N'ALTER TABLE [dbo].[FeePayment] DROP CONSTRAINT [' + @fp_pk_name + N']';
            EXEC sp_executesql @drop_fp_pk;
            PRINT N'  11c: dropped PK [' + @fp_pk_name + N']';
        END

        -- 11c-d. Update FeePayment.id to new format.
        UPDATE fp SET fp.[id] = m.new_id
        FROM dbo.FeePayment fp
        JOIN #fp_map m ON fp.[id] = m.old_id;
        PRINT N'  11c: updated FeePayment.id';

        -- 11c-e. Ensure id column is NOT NULL before recreating PK.
        ALTER TABLE [dbo].[FeePayment] ALTER COLUMN [id] NVARCHAR(50) NOT NULL;
        PRINT N'  11c: altered FeePayment.id to NOT NULL';

        -- 11c-f. Recreate PK.
        IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE type=N'PK' AND parent_object_id=OBJECT_ID('dbo.FeePayment'))
            ALTER TABLE [dbo].[FeePayment] ADD CONSTRAINT [FeePayment_pkey] PRIMARY KEY CLUSTERED ([id]);
        PRINT N'  11c: recreated PK FeePayment_pkey';

        -- 11c-g. Recreate FKs (if any were dropped).
        DECLARE @rfk_name NVARCHAR(256), @rfk_tbl NVARCHAR(128), @rfk_col NVARCHAR(128);
        DECLARE @rfk_del NVARCHAR(20), @rfk_upd NVARCHAR(20);
        DECLARE @add_rfk_sql NVARCHAR(MAX);
        DECLARE add_rfk_cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT DISTINCT fk_name, parent_table, parent_col, on_delete, on_update FROM #fp_fks;

        OPEN add_rfk_cur;
        FETCH NEXT FROM add_rfk_cur INTO @rfk_name, @rfk_tbl, @rfk_col, @rfk_del, @rfk_upd;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            IF OBJECT_ID('dbo.' + QUOTENAME(@rfk_tbl), 'U') IS NOT NULL
               AND COL_LENGTH('dbo.' + QUOTENAME(@rfk_tbl), @rfk_col) IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = @rfk_name)
            BEGIN
                DECLARE @rf_del NVARCHAR(20) = REPLACE(@rfk_del, N'_', N' ');
                DECLARE @rf_upd NVARCHAR(20) = REPLACE(@rfk_upd, N'_', N' ');
                IF @rf_del = N'NO' SET @rf_del = N'NO ACTION';
                IF @rf_upd = N'NO' SET @rf_upd = N'NO ACTION';

                SET @add_rfk_sql = N'ALTER TABLE [dbo].' + QUOTENAME(@rfk_tbl)
                    + N' ADD CONSTRAINT [' + @rfk_name + N'] FOREIGN KEY ([' + @rfk_col
                    + N']) REFERENCES [dbo].[FeePayment]([id]) ON DELETE ' + @rf_del
                    + N' ON UPDATE ' + @rf_upd;
                EXEC sp_executesql @add_rfk_sql;
            END
            FETCH NEXT FROM add_rfk_cur INTO @rfk_name, @rfk_tbl, @rfk_col, @rfk_del, @rfk_upd;
        END
        CLOSE add_rfk_cur;
        DEALLOCATE add_rfk_cur;

        -- 11c-h. Update IdSequence so app-generated ids continue after migrated ones.
        -- The backend uses key: FEEPAY/{branchCode}/{MMMyy}
        -- IdSequence has [updatedAt] DATETIME2 NOT NULL (no default) — must supply it.
        --
        -- Compute branchCode and monthKey as plain columns in a derived table,
        -- then GROUP BY only those plain columns. Build the key in the outer
        -- SELECT. No DATENAME/YEAR expressions inside GROUP BY.
        IF OBJECT_ID('dbo.IdSequence','U') IS NOT NULL
        BEGIN
            -- Step 1: Build the aggregated (seq_key, next_val) from migrated ids.
            IF OBJECT_ID('tempdb..#fp_seq', 'U') IS NOT NULL DROP TABLE #fp_seq;
            CREATE TABLE #fp_seq (seq_key NVARCHAR(191), next_val INT);

            INSERT INTO #fp_seq (seq_key, next_val)
            SELECT
                N'FEEPAY/' + agg.branchCode + N'/' + agg.monthKey,
                MAX(CAST(RIGHT(agg.new_id, 6) AS INT)) + 1
            FROM (
                -- Inner query: compute plain columns (branchCode, monthKey, seq number)
                -- from the FeePayment rows that now have FP/ ids.
                SELECT
                    fp_m.new_id,
                    b.[code] AS branchCode,
                    SUBSTRING(N'JANFEBMARAPRMAYJUNJULAUGSEPOCTNOVDEC',
                        (MONTH(fp.[createdAt]) - 1) * 3 + 1, 3)
                        + RIGHT(CAST(YEAR(fp.[createdAt]) AS NVARCHAR(10)), 2) AS monthKey
                FROM #fp_map fp_m
                JOIN dbo.FeePayment fp ON fp.[id] = fp_m.new_id
                JOIN dbo.Fee f ON f.[id] = fp.[feeId]
                JOIN dbo.Branch b ON b.[id] = f.[branchId]
                WHERE fp_m.new_id LIKE N'FP/%/%/%'
                  AND fp_m.new_id NOT LIKE N'FP/UNKNOWN/%'
            ) agg
            GROUP BY agg.branchCode, agg.monthKey;

            -- Step 2: Insert new IdSequence rows (for keys that don't exist yet).
            INSERT INTO dbo.IdSequence ([key], [next], [updatedAt])
            SELECT fs.seq_key, fs.next_val, SYSDATETIME()
            FROM #fp_seq fs
            WHERE NOT EXISTS (SELECT 1 FROM dbo.IdSequence s WHERE s.[key] = fs.seq_key);

            -- Step 3: Update existing IdSequence rows: only raise [next], never lower it.
            UPDATE s SET s.[next] = d.next_val, s.[updatedAt] = SYSDATETIME()
            FROM dbo.IdSequence s
            JOIN #fp_seq d ON s.[key] = d.seq_key
            WHERE s.[next] < d.next_val;

            PRINT N'  11c: updated IdSequence for FeePayment';
        END

        -- 11c-i. Verify: all ids match FP/, no duplicates.
        DECLARE @v_bad_fp INT = 0;
        SELECT @v_bad_fp = COUNT(*) FROM dbo.FeePayment WHERE [id] NOT LIKE N'FP/%';
        IF @v_bad_fp > 0
            RAISERROR(N'Verification failed: %d FeePayment ids not FP/ format', 16, 1, @v_bad_fp);

        DECLARE @v_dup_fp INT = 0;
        SELECT @v_dup_fp = COUNT(*) FROM (SELECT [id] FROM dbo.FeePayment GROUP BY [id] HAVING COUNT(*) > 1) x;
        IF @v_dup_fp > 0
            RAISERROR(N'Verification failed: %d duplicate FeePayment ids', 16, 1, @v_dup_fp);

        PRINT N'  11c: verification OK (all FP/, no duplicates)';

        IF OBJECT_ID('tempdb..#fp_seq', 'U') IS NOT NULL DROP TABLE #fp_seq;
        DROP TABLE #fp_map;
        DROP TABLE #fp_fks;

        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'11c-FeePayment-ids', N'OK', N'FeePayment ids converted to FP/{branchCode}/{MMMyy}/{000001}; IdSequence updated');
        PRINT N'  11c-FeePayment-ids: OK - FeePayment ids converted to FP/ format; IdSequence updated';
    END TRY
    BEGIN CATCH
        -- CATCH: capture error info FIRST, then rollback via XACT_STATE(),
        -- then log to _UpgradeLog. Note: compile-time errors (e.g. Msg 8120)
        -- bypass TRY/CATCH entirely and are handled by SET XACT_ABORT ON.
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF OBJECT_ID('tempdb..#fp_seq', 'U') IS NOT NULL DROP TABLE #fp_seq;
        IF OBJECT_ID('tempdb..#fp_map', 'U') IS NOT NULL DROP TABLE #fp_map;
        IF OBJECT_ID('tempdb..#fp_fks', 'U') IS NOT NULL DROP TABLE #fp_fks;
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'11c-FeePayment-ids', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  11c-FeePayment-ids: FAILED - Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg;
    END CATCH
END
GO

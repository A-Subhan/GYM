USE GymDB;
GO

-- ============================================================================
-- 10g_calendar_ids.sql
-- ============================================================================
-- Step 7: CalendarDay id renumbering — cuid -> 001, 002, ...
-- CalendarDay has NO inbound FKs (nothing references it), so we can safely
-- renumber in place by dropping the PK, updating, and re-adding the PK.
-- Idempotent: if all ids are already 3-digit, SKIPS.
-- ============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

PRINT N'=== STEP 7: CalendarDay id renumbering ===';

-- Preflight
IF OBJECT_ID('dbo.CalendarDay','U') IS NOT NULL
BEGIN
    DECLARE @pf_cal_bad INT = 0;
    SELECT @pf_cal_bad = COUNT(*) FROM dbo.CalendarDay WHERE [id] NOT LIKE N'[0-9][0-9][0-9]';
    PRINT N'  preflight: ' + CAST(@pf_cal_bad AS NVARCHAR(10)) + N' CalendarDay rows with non-3-digit ids';
END
ELSE
    PRINT N'  preflight: CalendarDay table MISSING';

IF OBJECT_ID('dbo.CalendarDay','U') IS NOT NULL
BEGIN
    IF EXISTS (SELECT 1 FROM dbo.CalendarDay WHERE [id] NOT LIKE N'[0-9][0-9][0-9]')
    BEGIN
        DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);
BEGIN TRY
            SET XACT_ABORT ON;
            BEGIN TRAN;

            -- 7a. Drop the PK
            DECLARE @cd_pk_name NVARCHAR(256);
            SELECT @cd_pk_name = name FROM sys.key_constraints
            WHERE type=N'PK' AND parent_object_id=OBJECT_ID('dbo.CalendarDay');
            IF @cd_pk_name IS NOT NULL
            BEGIN
                DECLARE @drop_cd_pk NVARCHAR(MAX) = N'ALTER TABLE [dbo].[CalendarDay] DROP CONSTRAINT [' + @cd_pk_name + N']';
                EXEC sp_executesql @drop_cd_pk;
            END

            -- 7b. Drop the unique date constraint
            IF EXISTS (SELECT 1 FROM sys.key_constraints WHERE name=N'CalendarDay_date_key' AND parent_object_id=OBJECT_ID('dbo.CalendarDay'))
            BEGIN
                DECLARE @drop_cd_dk NVARCHAR(MAX) = N'ALTER TABLE [dbo].[CalendarDay] DROP CONSTRAINT [CalendarDay_date_key]';
                EXEC sp_executesql @drop_cd_dk;
            END

            -- 7c. Drop Branch FK if any
            IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'CalendarDay_branchId_fkey')
            BEGIN
                DECLARE @drop_cd_br NVARCHAR(MAX) = N'ALTER TABLE [dbo].[CalendarDay] DROP CONSTRAINT [CalendarDay_branchId_fkey]';
                EXEC sp_executesql @drop_cd_br;
            END

            -- 7d. Renumber ids in place
            ;WITH c AS (
                SELECT [id], ROW_NUMBER() OVER (ORDER BY [date]) AS rn
                FROM dbo.CalendarDay
            )
            UPDATE cd SET [id] = RIGHT(N'00' + CAST(c.rn AS NVARCHAR(10)), 3)
            FROM dbo.CalendarDay cd JOIN c ON cd.[id] = c.[id];

            -- 7e. Re-add PK
            ALTER TABLE [dbo].[CalendarDay] ADD CONSTRAINT [CalendarDay_pkey] PRIMARY KEY CLUSTERED ([id]);

            -- 7f. Re-add unique date constraint
            IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name=N'CalendarDay_date_key' AND parent_object_id=OBJECT_ID('dbo.CalendarDay'))
                ALTER TABLE [dbo].[CalendarDay] ADD CONSTRAINT [CalendarDay_date_key] UNIQUE NONCLUSTERED ([date]);

            -- 7g. Re-add Branch FK
            IF COL_LENGTH('dbo.CalendarDay','branchId') IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'CalendarDay_branchId_fkey')
            BEGIN
                DECLARE @add_cd_br NVARCHAR(MAX) = N'ALTER TABLE [dbo].[CalendarDay] ADD CONSTRAINT [CalendarDay_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION';
                EXEC sp_executesql @add_cd_br;
            END

            COMMIT TRAN;
            INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'7-CalendarDay-renumber', N'OK', N'CalendarDay ids renumbered to 001/002/...');
            PRINT N'  7-CalendarDay-renumber: OK - CalendarDay ids renumbered to 001/002/...';
        END TRY
        BEGIN CATCH
            SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
            IF XACT_STATE() <> 0 ROLLBACK TRAN;
            INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'7-CalendarDay-renumber', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
            PRINT N'  7-CalendarDay-renumber: FAILED - Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg;
        END CATCH
    END
    ELSE
    BEGIN
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'7-CalendarDay-renumber', N'SKIPPED', N'All CalendarDay ids already 3-digit');
        PRINT N'  7-CalendarDay-renumber: SKIPPED - All CalendarDay ids already 3-digit';
    END
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'7-CalendarDay-renumber', N'SKIPPED', N'CalendarDay table missing');
    PRINT N'  7-CalendarDay-renumber: SKIPPED - CalendarDay table missing';
END
GO

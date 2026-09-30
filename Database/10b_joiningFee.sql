USE GymDB;
GO

-- ============================================================================
-- 10b_joiningFee.sql
-- ============================================================================
-- Step 2: Member.joiningFee (default 0).
-- Idempotent.
-- ============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

PRINT N'=== STEP 2: Member.joiningFee ===';

IF COL_LENGTH('dbo.Member', 'joiningFee') IS NULL
    PRINT N'  preflight: joiningFee MISSING - will add'
ELSE
    PRINT N'  preflight: joiningFee EXISTS - will skip';

IF COL_LENGTH('dbo.Member', 'joiningFee') IS NULL
BEGIN
    DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);
BEGIN TRY
        BEGIN TRAN;
        ALTER TABLE dbo.Member ADD [joiningFee] FLOAT NOT NULL CONSTRAINT [Member_joiningFee_df] DEFAULT 0;
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'2-joiningFee', N'OK', N'Added Member.joiningFee');
        PRINT N'  2-joiningFee: OK - Added Member.joiningFee';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'2-joiningFee', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  2-joiningFee: FAILED - Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg;
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'2-joiningFee', N'SKIPPED', N'joiningFee already exists');
    PRINT N'  2-joiningFee: SKIPPED - joiningFee already exists';
END
GO

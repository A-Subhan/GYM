USE GymDB;
GO

-- ============================================================================
-- 10_00_log_table.sql
-- ============================================================================
-- Creates dbo._UpgradeLog (the permanent step-status log table).
-- Run this BEFORE any other 10xx script.
-- Idempotent: safe to re-run.
-- ============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

PRINT N'=== STEP 00: log table ===';

IF OBJECT_ID(N'dbo._UpgradeLog', N'U') IS NOT NULL
BEGIN
    PRINT N'  dbo._UpgradeLog already exists - SKIPPED';
END
ELSE
BEGIN
    BEGIN TRY
        BEGIN TRAN;
        CREATE TABLE [dbo]._UpgradeLog (
            [step]     NVARCHAR(100) NOT NULL,
            [status]   NVARCHAR(20)  NOT NULL,  -- 'OK' | 'SKIPPED' | 'FAILED'
            [message]  NVARCHAR(MAX),
            [at]       DATETIME2     NOT NULL CONSTRAINT [_UpgradeLog_at_df] DEFAULT CURRENT_TIMESTAMP
        );
        COMMIT TRAN;
        PRINT N'  dbo._UpgradeLog created - OK';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        PRINT N'  dbo._UpgradeLog FAILED: ' + ERROR_MESSAGE();
        THROW;
    END CATCH
END
GO

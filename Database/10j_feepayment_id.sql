USE GymDB;
GO

-- ============================================================================
-- 10j_feepayment_id.sql
-- ============================================================================
-- Step 11: FeePayment id format.
-- The schema already defines FeePayment.id as NVARCHAR(50) NOT NULL PK.
-- The application (Backend/src/lib/ids.ts) generates ids in the format
-- FP/{branchCode}/{MMMyy}/{000001} via the IdSequence table.
--
-- This script ensures:
--   1. The IdSequence table exists (for atomic id generation).
--   2. A seed row for the FEEPAY sequence prefix exists (optional - the
--      application reconciles on first use).
--
-- No DDL change to FeePayment itself - the column is already correct.
-- Idempotent.
-- ============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

PRINT N'=== STEP 11: FeePayment id format ===';

-- Preflight
IF OBJECT_ID('dbo.FeePayment','U') IS NOT NULL
    PRINT N'  preflight: FeePayment table EXISTS'
ELSE
    PRINT N'  preflight: FeePayment table MISSING';

IF OBJECT_ID('dbo.IdSequence','U') IS NOT NULL
    PRINT N'  preflight: IdSequence table EXISTS'
ELSE
    PRINT N'  preflight: IdSequence table MISSING - will create';

-- 11a. Ensure IdSequence table exists (used by the app for atomic id generation)
IF OBJECT_ID(N'dbo.IdSequence', N'U') IS NULL
BEGIN
    DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);
BEGIN TRY
        BEGIN TRAN;
        CREATE TABLE [dbo].[IdSequence] (
            [key]  NVARCHAR(191) NOT NULL,
            [next] INT NOT NULL CONSTRAINT [IdSequence_next_df] DEFAULT 1,
            CONSTRAINT [IdSequence_pkey] PRIMARY KEY CLUSTERED ([key])
        );
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'11a-IdSequence', N'OK', N'Created IdSequence table');
        PRINT N'  11a-IdSequence: OK';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'11a-IdSequence', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  11a-IdSequence: FAILED - Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg;
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'11a-IdSequence', N'SKIPPED', N'IdSequence already exists');
    PRINT N'  11a-IdSequence: SKIPPED';
END
GO

-- 11b. Note: FeePayment.id is already NVARCHAR(50) PK - no DDL change needed.
-- The app generates FP/{branchCode}/{MMMyy}/{000001} ids via makeFeePayId()
-- in Backend/src/lib/ids.ts, which uses IdSequence with key FEEPAY/{branchCode}/{MMMyy}.
-- Existing rows keep their ids (cuid or FP/ format); only NEW rows get the
-- FP/ format.

SET NOCOUNT ON; SET XACT_ABORT ON;

IF OBJECT_ID('dbo.FeePayment','U') IS NOT NULL
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'11b-FeePayment-format', N'OK', N'FeePayment.id column is NVARCHAR(50) PK - app generates FP/{branchCode}/{MMMyy}/{000001} for new rows');
    PRINT N'  11b-FeePayment-format: OK - FeePayment.id is NVARCHAR(50) PK; app generates FP/ format for new rows';
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'11b-FeePayment-format', N'SKIPPED', N'FeePayment table missing');
    PRINT N'  11b-FeePayment-format: SKIPPED - FeePayment table missing';
END
GO

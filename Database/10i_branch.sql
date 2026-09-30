USE GymDB;
GO

-- ============================================================================
-- 10i_branch.sql
-- ============================================================================
-- Step 10: Branch hierarchical — ensure nodeType column exists (Control/Detail).
-- Also: Branch.nodeType defaults for existing top-level branches.
-- Idempotent.
-- ============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

PRINT N'=== STEP 10: Branch.nodeType ===';

-- Preflight
IF COL_LENGTH('dbo.Branch', 'nodeType') IS NULL
    PRINT N'  preflight: Branch.nodeType MISSING - will add'
ELSE
    PRINT N'  preflight: Branch.nodeType EXISTS - will skip';

IF COL_LENGTH('dbo.Branch', 'nodeType') IS NULL
BEGIN
    DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);
BEGIN TRY
        BEGIN TRAN;
        ALTER TABLE dbo.Branch ADD [nodeType] NVARCHAR(1000) NOT NULL CONSTRAINT [Branch_nodeType_df] DEFAULT N'Detail';
        -- Existing top-level branches (parentId IS NULL) default to Control
        UPDATE dbo.Branch SET [nodeType] = N'Control' WHERE [parentId] IS NULL;
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'10-Branch-nodeType', N'OK', N'Added Branch.nodeType; top-level set to Control');
        PRINT N'  10-Branch-nodeType: OK - Added Branch.nodeType; top-level set to Control';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'10-Branch-nodeType', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  10-Branch-nodeType: FAILED - Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg;
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'10-Branch-nodeType', N'SKIPPED', N'Branch.nodeType already exists');
    PRINT N'  10-Branch-nodeType: SKIPPED';
END
GO

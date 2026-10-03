-- ============================================================================
-- Contoura Gym Management System - STEP 12b: User email uniqueness allows
-- deleted / NULL-email users
-- ============================================================================
-- User_email_key was a plain unique index on [email]. SQL Server treats
-- NULLs as equal in a unique index, so (a) only ONE user without an email
-- could ever exist and (b) a soft-DELETED user kept blocking that slot
-- forever (new users without email failed with a 500).
--
-- Fix: drop the old unique index/constraint on [email] (discovered
-- dynamically — it exists as an INDEX today, but the script also handles a
-- UQ CONSTRAINT) and create a FILTERED unique index:
--     WHERE [email] IS NOT NULL AND [isDeleted] = 0
-- so any number of users may have no email or be deleted, while two ACTIVE
-- users still cannot share an email.
--
-- Idempotent: re-running finds nothing to drop and skips index creation.
-- ============================================================================

USE [GymDB];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX), @sql NVARCHAR(MAX), @dropped NVARCHAR(200);

BEGIN TRY
    BEGIN TRAN;

    -- Discover the existing unique email index/constraint dynamically.
    IF EXISTS (
        SELECT 1
        FROM sys.key_constraints kc
        WHERE kc.type = N'UQ'
          AND kc.parent_object_id = OBJECT_ID(N'dbo.[User]')
          AND kc.name = N'User_email_key'
    )
    BEGIN
        SET @sql = N'ALTER TABLE dbo.[User] DROP CONSTRAINT [User_email_key];';
        SET @dropped = N'CONSTRAINT User_email_key';
    END
    ELSE IF EXISTS (
        SELECT 1
        FROM sys.indexes i
        WHERE i.object_id = OBJECT_ID(N'dbo.[User]')
          AND i.is_unique = 1
          AND i.name = N'User_email_key'
          -- the index must be exactly on [email] and nothing else
          AND (SELECT COUNT(*) FROM sys.index_columns ic WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id) = 1
          AND EXISTS (
              SELECT 1
              FROM sys.index_columns ic
              JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
              WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND c.name = N'email'
          )
    )
    BEGIN
        SET @sql = N'DROP INDEX [User_email_key] ON dbo.[User];';
        SET @dropped = N'INDEX User_email_key';
    END
    ELSE
    BEGIN
        SET @sql = NULL;
        SET @dropped = NULL;
    END

    IF @sql IS NOT NULL
        EXEC sp_executesql @sql;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes i
        WHERE i.object_id = OBJECT_ID(N'dbo.[User]') AND i.name = N'User_email_active_uq'
    )
        CREATE UNIQUE INDEX [User_email_active_uq]
            ON dbo.[User] ([email])
            WHERE [email] IS NOT NULL AND [isDeleted] = 0;

    COMMIT TRAN;

    DECLARE @msg NVARCHAR(400) = N'Unique email switched to filtered index User_email_active_uq (email IS NOT NULL AND isDeleted = 0)';
    IF @dropped IS NOT NULL
        SET @msg = @msg + N'; dropped ' + @dropped;

    INSERT INTO dbo._UpgradeLog (step, status, message)
    VALUES (N'12b-fix-user-email-unique', N'OK', @msg);
    PRINT N'  12b-fix-user-email-unique: OK (' + @msg + N')';
END TRY
BEGIN CATCH
    SET @eNum = ERROR_NUMBER();
    SET @eLine = ERROR_LINE();
    SET @eMsg = ERROR_MESSAGE();
    IF XACT_STATE() <> 0 ROLLBACK TRAN;
    INSERT INTO dbo._UpgradeLog (step, status, message)
    VALUES (N'12b-fix-user-email-unique', N'FAILED',
            N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
    PRINT N'  12b-fix-user-email-unique: FAILED - Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg;
END CATCH
GO

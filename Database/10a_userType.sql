USE GymDB;
GO

-- ============================================================================
-- 10a_userType.sql
-- ============================================================================
-- Step 1: User.userType (Admin|User) + nullable roleId.
-- Fixes the 08 Msg 207 (column added+used in same batch) by using GO
-- between the ALTER ADD and the UPDATE.
-- Idempotent: checks IF COL_LENGTH before adding.
-- ============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

PRINT N'=== STEP 1a: User.userType ===';

-- Preflight
IF COL_LENGTH('dbo.[User]', 'userType') IS NULL
    PRINT N'  preflight: userType MISSING - will add';
ELSE
    PRINT N'  preflight: userType EXISTS - will skip';

-- 1a. Add userType if missing
IF COL_LENGTH('dbo.[User]', 'userType') IS NULL
BEGIN
    BEGIN TRY
        BEGIN TRAN;
        ALTER TABLE dbo.[User] ADD [userType] NVARCHAR(255) NOT NULL CONSTRAINT [User_userType_df] DEFAULT N'User';
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'1a-userType', N'OK', N'Added User.userType column');
        PRINT N'  1a-userType: OK - Added User.userType column';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'1a-userType', N'FAILED', ERROR_MESSAGE());
        PRINT N'  1a-userType: FAILED - ' + ERROR_MESSAGE();
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'1a-userType', N'SKIPPED', N'userType already exists');
    PRINT N'  1a-userType: SKIPPED - userType already exists';
END
GO

-- 1b. Make roleId nullable (separate batch)
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.[User]') AND name = N'roleId' AND is_nullable = 0
)
BEGIN
    BEGIN TRY
        BEGIN TRAN;
        ALTER TABLE dbo.[User] ALTER COLUMN [roleId] NVARCHAR(50) NULL;
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'1b-roleId', N'OK', N'User.roleId set to nullable');
        PRINT N'  1b-roleId: OK - User.roleId set to nullable';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'1b-roleId', N'FAILED', ERROR_MESSAGE());
        PRINT N'  1b-roleId: FAILED - ' + ERROR_MESSAGE();
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'1b-roleId', N'SKIPPED', N'roleId already nullable or column missing');
    PRINT N'  1b-roleId: SKIPPED - roleId already nullable or column missing';
END
GO

-- 1c. Populate userType: admin -> Admin, rest -> User
-- Separate batch so the column from 1a definitely exists.
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF COL_LENGTH('dbo.[User]', 'userType') IS NOT NULL
BEGIN
    BEGIN TRY
        BEGIN TRAN;
        UPDATE dbo.[User] SET [userType] = N'User'
        WHERE [userType] IS NULL OR [userType] NOT IN (N'Admin', N'User');

        UPDATE dbo.[User] SET [userType] = N'Admin'
        WHERE [username] = N'admin' AND [userType] <> N'Admin';

        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'1c-userType-data', N'OK', N'Populated userType (admin=Admin, rest=User)');
        PRINT N'  1c-userType-data: OK - Populated userType (admin=Admin, rest=User)';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'1c-userType-data', N'FAILED', ERROR_MESSAGE());
        PRINT N'  1c-userType-data: FAILED - ' + ERROR_MESSAGE();
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'1c-userType-data', N'SKIPPED', N'userType column missing');
    PRINT N'  1c-userType-data: SKIPPED - userType column missing';
END
GO

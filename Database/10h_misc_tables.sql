USE GymDB;
GO

-- ============================================================================
-- 10h_misc_tables.sql
-- ============================================================================
-- Step 9: Create the gym operation tables (if missing).
-- Tables: ScreenPermission, UserPermission, TrainerAvailability,
-- TrainerSchedule, FitnessGoal, PersonalTrainingSession, StaffDocument, KnockOff.
-- Also: Staff.isDeleted (soft delete) and Member soft-delete columns.
-- Idempotent: each table guarded by IF OBJECT_ID.
-- ============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

PRINT N'=== STEP 9: gym operation + permission tables ===';

-- 9a. ScreenPermission
IF OBJECT_ID(N'dbo.ScreenPermission', N'U') IS NULL
BEGIN
    DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);
BEGIN TRY
        BEGIN TRAN;
        CREATE TABLE [dbo].[ScreenPermission] (
            [id]        NVARCHAR(50)  NOT NULL,
            [roleId]    NVARCHAR(50)  NOT NULL,
            [screenKey] NVARCHAR(255) NOT NULL,
            [canView]   BIT NOT NULL CONSTRAINT [ScreenPermission_canView_df] DEFAULT 0,
            [canAdd]    BIT NOT NULL CONSTRAINT [ScreenPermission_canAdd_df] DEFAULT 0,
            [canEdit]   BIT NOT NULL CONSTRAINT [ScreenPermission_canEdit_df] DEFAULT 0,
            [canDelete] BIT NOT NULL CONSTRAINT [ScreenPermission_canDelete_df] DEFAULT 0,
            [canPrint]  BIT NOT NULL CONSTRAINT [ScreenPermission_canPrint_df] DEFAULT 0,
            CONSTRAINT [ScreenPermission_pkey] PRIMARY KEY CLUSTERED ([id]),
            CONSTRAINT [ScreenPermission_roleId_screenKey_key] UNIQUE NONCLUSTERED ([roleId],[screenKey])
        );
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'9a-ScreenPermission', N'OK', N'Created ScreenPermission');
        PRINT N'  9a-ScreenPermission: OK';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'9a-ScreenPermission', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  9a-ScreenPermission: FAILED - Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg;
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'9a-ScreenPermission', N'SKIPPED', N'ScreenPermission already exists');
    PRINT N'  9a-ScreenPermission: SKIPPED';
END
GO

-- 9b. UserPermission
SET NOCOUNT ON; SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.UserPermission', N'U') IS NULL
BEGIN
    DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);
    BEGIN TRY
        BEGIN TRAN;
        CREATE TABLE [dbo].[UserPermission] (
            [id]        NVARCHAR(50)  NOT NULL,
            [userId]    NVARCHAR(50)  NOT NULL,
            [screenKey] NVARCHAR(255) NOT NULL,
            [canView]   BIT NOT NULL CONSTRAINT [UserPermission_canView_df] DEFAULT 0,
            [canAdd]    BIT NOT NULL CONSTRAINT [UserPermission_canAdd_df] DEFAULT 0,
            [canEdit]   BIT NOT NULL CONSTRAINT [UserPermission_canEdit_df] DEFAULT 0,
            [canDelete] BIT NOT NULL CONSTRAINT [UserPermission_canDelete_df] DEFAULT 0,
            [canPrint]  BIT NOT NULL CONSTRAINT [UserPermission_canPrint_df] DEFAULT 0,
            CONSTRAINT [UserPermission_pkey] PRIMARY KEY CLUSTERED ([id]),
            CONSTRAINT [UserPermission_userId_screenKey_key] UNIQUE NONCLUSTERED ([userId],[screenKey])
        );
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'9b-UserPermission', N'OK', N'Created UserPermission');
        PRINT N'  9b-UserPermission: OK';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'9b-UserPermission', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  9b-UserPermission: FAILED - Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg;
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'9b-UserPermission', N'SKIPPED', N'UserPermission already exists');
    PRINT N'  9b-UserPermission: SKIPPED';
END
GO

-- 9c. TrainerAvailability
SET NOCOUNT ON; SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.TrainerAvailability', N'U') IS NULL
BEGIN
    DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);
    BEGIN TRY
        BEGIN TRAN;
        CREATE TABLE [dbo].[TrainerAvailability] (
            [id]         NVARCHAR(50)  NOT NULL,
            [staffId]    NVARCHAR(50)  NOT NULL,
            [dayOfWeek]  NVARCHAR(255) NOT NULL,
            [startTime]   NVARCHAR(255) NOT NULL,
            [endTime]     NVARCHAR(255) NOT NULL,
            [branchId]   NVARCHAR(50),
            [status]     NVARCHAR(255) NOT NULL CONSTRAINT [TrainerAvailability_status_df] DEFAULT N'Available',
            [createdAt]  DATETIME2 NOT NULL CONSTRAINT [TrainerAvailability_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
            CONSTRAINT [TrainerAvailability_pkey] PRIMARY KEY CLUSTERED ([id])
        );
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'9c-TrainerAvailability', N'OK', N'Created TrainerAvailability');
        PRINT N'  9c-TrainerAvailability: OK';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'9c-TrainerAvailability', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  9c-TrainerAvailability: FAILED - Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg;
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'9c-TrainerAvailability', N'SKIPPED', N'TrainerAvailability already exists');
    PRINT N'  9c-TrainerAvailability: SKIPPED';
END
GO

-- 9d. TrainerSchedule
SET NOCOUNT ON; SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.TrainerSchedule', N'U') IS NULL
BEGIN
    DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);
    BEGIN TRY
        BEGIN TRAN;
        CREATE TABLE [dbo].[TrainerSchedule] (
            [id]         NVARCHAR(50)  NOT NULL,
            [staffId]    NVARCHAR(50)  NOT NULL,
            [branchId]   NVARCHAR(50),
            [date]       DATETIME2 NOT NULL,
            [dayOfWeek]  NVARCHAR(255) NOT NULL,
            [startTime]   NVARCHAR(255) NOT NULL,
            [endTime]     NVARCHAR(255) NOT NULL,
            [sessionType] NVARCHAR(255) NOT NULL,
            [memberId]   NVARCHAR(50),
            [classId]    NVARCHAR(50),
            [status]     NVARCHAR(255) NOT NULL CONSTRAINT [TrainerSchedule_status_df] DEFAULT N'Scheduled',
            [notes]      NVARCHAR(MAX),
            [createdAt]  DATETIME2 NOT NULL CONSTRAINT [TrainerSchedule_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
            CONSTRAINT [TrainerSchedule_pkey] PRIMARY KEY CLUSTERED ([id])
        );
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'9d-TrainerSchedule', N'OK', N'Created TrainerSchedule');
        PRINT N'  9d-TrainerSchedule: OK';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'9d-TrainerSchedule', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  9d-TrainerSchedule: FAILED - Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg;
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'9d-TrainerSchedule', N'SKIPPED', N'TrainerSchedule already exists');
    PRINT N'  9d-TrainerSchedule: SKIPPED';
END
GO

-- 9e. FitnessGoal
SET NOCOUNT ON; SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.FitnessGoal', N'U') IS NULL
BEGIN
    DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);
    BEGIN TRY
        BEGIN TRAN;
        CREATE TABLE [dbo].[FitnessGoal] (
            [id]           NVARCHAR(50)  NOT NULL,
            [memberId]     NVARCHAR(50)  NOT NULL,
            [goalType]     NVARCHAR(255) NOT NULL,
            [targetValue]  FLOAT(53),
            [unit]         NVARCHAR(255),
            [startDate]    DATETIME2 NOT NULL CONSTRAINT [FitnessGoal_startDate_df] DEFAULT CURRENT_TIMESTAMP,
            [targetDate]   DATETIME2,
            [status]       NVARCHAR(255) NOT NULL CONSTRAINT [FitnessGoal_status_df] DEFAULT N'Active',
            [notes]        NVARCHAR(MAX),
            [createdAt]    DATETIME2 NOT NULL CONSTRAINT [FitnessGoal_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
            [updatedAt]    DATETIME2 NOT NULL,
            CONSTRAINT [FitnessGoal_pkey] PRIMARY KEY CLUSTERED ([id])
        );
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'9e-FitnessGoal', N'OK', N'Created FitnessGoal');
        PRINT N'  9e-FitnessGoal: OK';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'9e-FitnessGoal', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  9e-FitnessGoal: FAILED - Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg;
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'9e-FitnessGoal', N'SKIPPED', N'FitnessGoal already exists');
    PRINT N'  9e-FitnessGoal: SKIPPED';
END
GO

-- 9f. PersonalTrainingSession
SET NOCOUNT ON; SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.PersonalTrainingSession', N'U') IS NULL
BEGIN
    DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);
    BEGIN TRY
        BEGIN TRAN;
        CREATE TABLE [dbo].[PersonalTrainingSession] (
            [id]                NVARCHAR(50)  NOT NULL,
            [memberId]          NVARCHAR(50)  NOT NULL,
            [trainerId]         NVARCHAR(50)  NOT NULL,
            [branchId]          NVARCHAR(50),
            [sessionsPurchased] INT NOT NULL CONSTRAINT [PersonalTrainingSession_sessionsPurchased_df] DEFAULT 0,
            [sessionsUsed]      INT NOT NULL CONSTRAINT [PersonalTrainingSession_sessionsUsed_df] DEFAULT 0,
            [sessionsRemaining] INT NOT NULL CONSTRAINT [PersonalTrainingSession_sessionsRemaining_df] DEFAULT 0,
            [sessionDate]       DATETIME2,
            [sessionStatus]     NVARCHAR(255) NOT NULL CONSTRAINT [PersonalTrainingSession_sessionStatus_df] DEFAULT N'Scheduled',
            [startDate]         DATETIME2,
            [endDate]           DATETIME2,
            [notes]             NVARCHAR(MAX),
            [status]            NVARCHAR(255) NOT NULL CONSTRAINT [PersonalTrainingSession_status_df] DEFAULT N'Active',
            [createdAt]         DATETIME2 NOT NULL CONSTRAINT [PersonalTrainingSession_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
            [updatedAt]         DATETIME2 NOT NULL,
            CONSTRAINT [PersonalTrainingSession_pkey] PRIMARY KEY CLUSTERED ([id])
        );
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'9f-PersonalTrainingSession', N'OK', N'Created PersonalTrainingSession');
        PRINT N'  9f-PersonalTrainingSession: OK';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'9f-PersonalTrainingSession', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  9f-PersonalTrainingSession: FAILED - Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg;
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'9f-PersonalTrainingSession', N'SKIPPED', N'PersonalTrainingSession already exists');
    PRINT N'  9f-PersonalTrainingSession: SKIPPED';
END
GO

-- 9g. StaffDocument
SET NOCOUNT ON; SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.StaffDocument', N'U') IS NULL
BEGIN
    DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);
    BEGIN TRY
        BEGIN TRAN;
        CREATE TABLE [dbo].[StaffDocument] (
            [id]            NVARCHAR(50)  NOT NULL,
            [staffId]       NVARCHAR(50)  NOT NULL,
            [documentType]  NVARCHAR(255) NOT NULL,
            [documentName]  NVARCHAR(255) NOT NULL,
            [fileUrl]       NVARCHAR(255) NOT NULL,
            [issueDate]     DATETIME2,
            [expiryDate]    DATETIME2,
            [status]        NVARCHAR(255) NOT NULL CONSTRAINT [StaffDocument_status_df] DEFAULT N'Active',
            [notes]         NVARCHAR(MAX),
            [uploadedBy]    NVARCHAR(255),
            [createdAt]     DATETIME2 NOT NULL CONSTRAINT [StaffDocument_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
            [updatedAt]     DATETIME2 NOT NULL,
            CONSTRAINT [StaffDocument_pkey] PRIMARY KEY CLUSTERED ([id])
        );
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'9g-StaffDocument', N'OK', N'Created StaffDocument');
        PRINT N'  9g-StaffDocument: OK';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'9g-StaffDocument', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  9g-StaffDocument: FAILED - Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg;
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'9g-StaffDocument', N'SKIPPED', N'StaffDocument already exists');
    PRINT N'  9g-StaffDocument: SKIPPED';
END
GO

-- 9h. KnockOff
SET NOCOUNT ON; SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.KnockOff', N'U') IS NULL
BEGIN
    DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);
    BEGIN TRY
        BEGIN TRAN;
        CREATE TABLE [dbo].[KnockOff] (
            [id]              NVARCHAR(50)  NOT NULL,
            [billId]          NVARCHAR(50)  NOT NULL,
            [billNumber]      NVARCHAR(255),
            [referenceNumber] NVARCHAR(255),
            [billType]        NVARCHAR(255),
            [amount]          FLOAT(53) NOT NULL,
            [dcFlag]          NVARCHAR(10) NOT NULL CONSTRAINT [KnockOff_dcFlag_df] DEFAULT N'Debit',
            [referenceDate]   DATETIME2,
            [dueDate]         DATETIME2,
            [description]      NVARCHAR(20),
            [accountId]       NVARCHAR(50) NOT NULL,
            [branchId]        NVARCHAR(50) NOT NULL,
            [createdById]     NVARCHAR(50),
            [createdAt]       DATETIME2 NOT NULL CONSTRAINT [KnockOff_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
            [updatedAt]       DATETIME2 NOT NULL,
            CONSTRAINT [KnockOff_pkey] PRIMARY KEY CLUSTERED ([id]),
            CONSTRAINT [KnockOff_billId_key] UNIQUE NONCLUSTERED ([billId])
        );
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'9h-KnockOff', N'OK', N'Created KnockOff');
        PRINT N'  9h-KnockOff: OK';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'9h-KnockOff', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  9h-KnockOff: FAILED - Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg;
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'9h-KnockOff', N'SKIPPED', N'KnockOff already exists');
    PRINT N'  9h-KnockOff: SKIPPED';
END
GO

-- 9i. Staff.isDeleted
SET NOCOUNT ON; SET XACT_ABORT ON;

IF COL_LENGTH('dbo.Staff', 'isDeleted') IS NULL
BEGIN
    DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);
    BEGIN TRY
        BEGIN TRAN;
        ALTER TABLE dbo.Staff ADD [isDeleted] BIT NOT NULL CONSTRAINT [Staff_isDeleted_df] DEFAULT 0;
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'9i-Staff-isDeleted', N'OK', N'Added Staff.isDeleted');
        PRINT N'  9i-Staff-isDeleted: OK';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'9i-Staff-isDeleted', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  9i-Staff-isDeleted: FAILED - Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg;
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'9i-Staff-isDeleted', N'SKIPPED', N'Staff.isDeleted already exists');
    PRINT N'  9i-Staff-isDeleted: SKIPPED';
END
GO

-- 9j. Member soft-delete columns (isDeleted + deletedAt)
SET NOCOUNT ON; SET XACT_ABORT ON;

IF COL_LENGTH('dbo.Member', 'isDeleted') IS NULL
   AND COL_LENGTH('dbo.Member', 'deletedAt') IS NULL
BEGIN
    DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);
    BEGIN TRY
        BEGIN TRAN;
        ALTER TABLE dbo.Member ADD [isDeleted] BIT NOT NULL CONSTRAINT [Member_isDeleted_df] DEFAULT 0;
        ALTER TABLE dbo.Member ADD [deletedAt] DATETIME2;
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'9j-Member-softdelete', N'OK', N'Added Member.isDeleted + deletedAt');
        PRINT N'  9j-Member-softdelete: OK';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'9j-Member-softdelete', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  9j-Member-softdelete: FAILED - Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg;
    END CATCH
END
ELSE IF COL_LENGTH('dbo.Member', 'isDeleted') IS NOT NULL
        AND COL_LENGTH('dbo.Member', 'deletedAt') IS NULL
BEGIN
    DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);
    BEGIN TRY
        BEGIN TRAN;
        ALTER TABLE dbo.Member ADD [deletedAt] DATETIME2;
        COMMIT TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'9j-Member-softdelete', N'OK', N'Added Member.deletedAt (isDeleted already existed)');
        PRINT N'  9j-Member-softdelete: OK - added deletedAt';
    END TRY
    BEGIN CATCH
        SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'9j-Member-softdelete', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
        PRINT N'  9j-Member-softdelete: FAILED - Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg;
    END CATCH
END
ELSE
BEGIN
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'9j-Member-softdelete', N'SKIPPED', N'Member soft-delete columns already exist');
    PRINT N'  9j-Member-softdelete: SKIPPED';
END
GO

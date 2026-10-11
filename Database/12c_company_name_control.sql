USE GymDB;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- 12c_company_name_control.sql
-- ============================================================================
-- Stored procedure for changing the company name through the controlled
-- mechanism (SESSION_CONTEXT flag) that trg_Defaults_CompanyNameLock honors.
-- The application API calls this via Prisma $executeRaw; manual DBAs can
-- also call it directly. Logs the change to AuditLog.
--
-- Idempotent: re-creating the procedure is safe.
-- ============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);

IF OBJECT_ID('dbo._UpgradeLog','U') IS NULL
BEGIN
    CREATE TABLE dbo._UpgradeLog (
        id INT IDENTITY(1,1) NOT NULL,
        step NVARCHAR(100) NOT NULL,
        status NVARCHAR(20) NOT NULL,
        message NVARCHAR(MAX),
        createdAt DATETIME2 NOT NULL CONSTRAINT [_UpgradeLog_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT [_UpgradeLog_pkey] PRIMARY KEY CLUSTERED ([id])
    );
END
GO

USE GymDB;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);

BEGIN TRY
    -- Create or alter the stored procedure
    IF OBJECT_ID('dbo.usp_Defaults_ChangeCompanyName','P') IS NULL
    BEGIN
        EXEC(N'CREATE PROCEDURE dbo.usp_Defaults_ChangeCompanyName AS BEGIN SET NOCOUNT ON; END');
    END
    GO

    USE GymDB;
    GO
    SET QUOTED_IDENTIFIER ON;

    DECLARE @eNum2 INT, @eLine2 INT, @eMsg2 NVARCHAR(MAX);

    BEGIN TRY
        EXEC sp_executesql N'
        CREATE OR ALTER PROCEDURE dbo.usp_Defaults_ChangeCompanyName
            @newName NVARCHAR(255),
            @changedBy NVARCHAR(50) = N''system-admin''
        AS
        BEGIN
            SET NOCOUNT ON;
            SET XACT_ABORT ON;

            DECLARE @oldName NVARCHAR(255);
            SELECT @oldName = companyName FROM dbo.Defaults;

            -- Set the session flag the trigger honors
            EXEC sp_set_session_context @key = N''allow_company_name_change'', @value = 1;

            BEGIN TRY
                BEGIN TRAN;
                UPDATE dbo.Defaults SET companyName = @newName, updatedAt = SYSDATETIME();

                -- Log the change
                INSERT INTO dbo.AuditLog (userId, action, module, details, createdAt)
                VALUES (
                    @changedBy,
                    N''COMPANY_NAME_CHANGE'',
                    N''company'',
                    JSON modification (N''{"old":"'' + ISNULL(@oldName, N'''') + N''","new":"'' + @newName + N''","by":"'' + @changedBy + N''"}''),
                    SYSDATETIME()
                );

                COMMIT TRAN;
            END TRY
            BEGIN CATCH
                IF XACT_STATE() <> 0 ROLLBACK TRAN;
                -- Clear the flag even on failure
                EXEC sp_set_session_context @key = N''allow_company_name_change'', @value = 0;
                ;THROW;
            END CATCH

            -- Always clear the flag after the operation
            EXEC sp_set_session_context @key = N''allow_company_name_change'', @value = 0;

            SELECT @oldName AS oldName, @newName AS newName, N''OK'' AS result;
        END';

        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'12c-company-name-control', N'OK', N'Created usp_Defaults_ChangeCompanyName stored procedure');
        PRINT N'  12c-company-name-control: OK';
    END TRY
    BEGIN CATCH
        SET @eNum2 = ERROR_NUMBER(); SET @eLine2 = ERROR_LINE(); SET @eMsg2 = ERROR_MESSAGE();
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'12c-company-name-control', N'FAILED', N'Err ' + CAST(@eNum2 AS NVARCHAR(10)) + N' at line ' + CAST(@eLine2 AS NVARCHAR(10)) + N': ' + @eMsg2);
        PRINT N'  12c-company-name-control: FAILED - ' + @eMsg2;
    END CATCH
END
GO

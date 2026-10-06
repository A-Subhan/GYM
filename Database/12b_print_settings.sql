USE GymDB;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- 12b_print_settings.sql
-- ============================================================================
-- Creates the dbo.PrintSettings table for per-document-type print/PDF/export
-- settings. Each row stores settings for one document type:
--   BPV, BRV, CPV, CRV, JV, OTB, Reports.
--
-- Settings per document type:
--   a. Signatures: Prepared By, Checked By, Approved By, Print By
--      (each on/off, name source = 'username' | 'custom', custom text)
--   b. Company name + address position (left/center/right, top/bottom, on/off)
--   c. Print date on/off
--   d. Party remaining balance on/off
--   e. Logo on/off, position, width, height
--   f. Font family + size
--
-- Idempotent. Seeds default rows for all 7 document types.
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
    BEGIN TRAN;

    -- Create the PrintSettings table if it doesn't exist
    IF OBJECT_ID('dbo.PrintSettings','U') IS NULL
    BEGIN
        CREATE TABLE [dbo].[PrintSettings] (
            [id] NVARCHAR(50) NOT NULL,
            [documentType] NVARCHAR(20) NOT NULL,
            -- Signatures
            [sigPreparedBy] BIT NOT NULL CONSTRAINT [PrintSettings_sigPreparedBy_df] DEFAULT 1,
            [sigPreparedBySource] NVARCHAR(20) NOT NULL CONSTRAINT [PrintSettings_sigPreparedBySource_df] DEFAULT 'username',
            [sigPreparedByCustom] NVARCHAR(255) NULL,
            [sigCheckedBy] BIT NOT NULL CONSTRAINT [PrintSettings_sigCheckedBy_df] DEFAULT 1,
            [sigCheckedBySource] NVARCHAR(20) NOT NULL CONSTRAINT [PrintSettings_sigCheckedBySource_df] DEFAULT 'username',
            [sigCheckedByCustom] NVARCHAR(255) NULL,
            [sigApprovedBy] BIT NOT NULL CONSTRAINT [PrintSettings_sigApprovedBy_df] DEFAULT 0,
            [sigApprovedBySource] NVARCHAR(20) NOT NULL CONSTRAINT [PrintSettings_sigApprovedBySource_df] DEFAULT 'username',
            [sigApprovedByCustom] NVARCHAR(255) NULL,
            [sigPrintBy] BIT NOT NULL CONSTRAINT [PrintSettings_sigPrintBy_df] DEFAULT 0,
            [sigPrintBySource] NVARCHAR(20) NOT NULL CONSTRAINT [PrintSettings_sigPrintBySource_df] DEFAULT 'username',
            [sigPrintByCustom] NVARCHAR(255) NULL,
            -- Company name + address
            [showCompanyName] BIT NOT NULL CONSTRAINT [PrintSettings_showCompanyName_df] DEFAULT 1,
            [companyNamePosition] NVARCHAR(10) NOT NULL CONSTRAINT [PrintSettings_companyNamePosition_df] DEFAULT 'center',
            [companyNameVertical] NVARCHAR(10) NOT NULL CONSTRAINT [PrintSettings_companyNameVertical_df] DEFAULT 'top',
            [showCompanyAddress] BIT NOT NULL CONSTRAINT [PrintSettings_showCompanyAddress_df] DEFAULT 1,
            [companyAddressPosition] NVARCHAR(10) NOT NULL CONSTRAINT [PrintSettings_companyAddressPosition_df] DEFAULT 'center',
            [companyAddressVertical] NVARCHAR(10) NOT NULL CONSTRAINT [PrintSettings_companyAddressVertical_df] DEFAULT 'top',
            -- Print date
            [showPrintDate] BIT NOT NULL CONSTRAINT [PrintSettings_showPrintDate_df] DEFAULT 1,
            -- Party remaining balance
            [showPartyBalance] BIT NOT NULL CONSTRAINT [PrintSettings_showPartyBalance_df] DEFAULT 0,
            -- Logo
            [showLogo] BIT NOT NULL CONSTRAINT [PrintSettings_showLogo_df] DEFAULT 1,
            [logoPosition] NVARCHAR(10) NOT NULL CONSTRAINT [PrintSettings_logoPosition_df] DEFAULT 'left',
            [logoWidth] INT NOT NULL CONSTRAINT [PrintSettings_logoWidth_df] DEFAULT 80,
            [logoHeight] INT NOT NULL CONSTRAINT [PrintSettings_logoHeight_df] DEFAULT 80,
            -- Font
            [fontFamily] NVARCHAR(100) NOT NULL CONSTRAINT [PrintSettings_fontFamily_df] DEFAULT 'Arial, sans-serif',
            [fontSize] INT NOT NULL CONSTRAINT [PrintSettings_fontSize_df] DEFAULT 12,
            -- Timestamps
            [createdAt] DATETIME2 NOT NULL CONSTRAINT [PrintSettings_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
            [updatedAt] DATETIME2 NOT NULL,
            CONSTRAINT [PrintSettings_pkey] PRIMARY KEY CLUSTERED ([id]),
            CONSTRAINT [PrintSettings_documentType_key] UNIQUE NONCLUSTERED ([documentType])
        );
    END

    -- Seed default rows for all 7 document types if they don't exist
    DECLARE @docTypes TABLE (dt NVARCHAR(20));
    INSERT INTO @docTypes VALUES
        (N'BPV'), (N'BRV'), (N'CPV'), (N'CRV'), (N'JV'), (N'OTB'), (N'Reports');

    DECLARE @dt NVARCHAR(20), @newId NVARCHAR(50);
    DECLARE dt_cur CURSOR LOCAL FAST_FORWARD FOR SELECT dt FROM @docTypes;
    OPEN dt_cur;
    FETCH NEXT FROM dt_cur INTO @dt;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM dbo.PrintSettings WHERE documentType = @dt)
        BEGIN
            SET @newId = N'PRT-' + UPPER(@dt);
            INSERT INTO dbo.PrintSettings (
                [id], [documentType],
                [sigPreparedBy], [sigPreparedBySource], [sigPreparedByCustom],
                [sigCheckedBy], [sigCheckedBySource], [sigCheckedByCustom],
                [sigApprovedBy], [sigApprovedBySource], [sigApprovedByCustom],
                [sigPrintBy], [sigPrintBySource], [sigPrintByCustom],
                [showCompanyName], [companyNamePosition], [companyNameVertical],
                [showCompanyAddress], [companyAddressPosition], [companyAddressVertical],
                [showPrintDate], [showPartyBalance],
                [showLogo], [logoPosition], [logoWidth], [logoHeight],
                [fontFamily], [fontSize],
                [updatedAt]
            ) VALUES (
                @newId, @dt,
                1, 'username', NULL,
                1, 'username', NULL,
                0, 'username', NULL,
                0, 'username', NULL,
                1, 'center', 'top',
                1, 'center', 'top',
                1, 0,
                1, 'left', 80, 80,
                'Arial, sans-serif', 12,
                SYSDATETIME()
            );
        END
        FETCH NEXT FROM dt_cur INTO @dt;
    END
    CLOSE dt_cur;
    DEALLOCATE dt_cur;

    COMMIT TRAN;
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'12b-print-settings', N'OK', N'PrintSettings table created and seeded for 7 document types');
    PRINT N'  12b-print-settings: OK';
END TRY
BEGIN CATCH
    SET @eNum = ERROR_NUMBER(); SET @eLine = ERROR_LINE(); SET @eMsg = ERROR_MESSAGE();
    IF XACT_STATE() <> 0 ROLLBACK TRAN;
    INSERT INTO dbo._UpgradeLog (step, status, message) VALUES (N'12b-print-settings', N'FAILED', N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
    PRINT N'  12b-print-settings: FAILED - ' + @eMsg;
END CATCH
GO

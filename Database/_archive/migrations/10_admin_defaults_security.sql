-- ============================================================================
-- Contoura Gym ERP — Migration 10: ADMIN DEFAULTS + BRANCH HIERARCHY +
--                                  USER PERMISSIONS + MAPPING BACKFILL
-- ============================================================================
-- 1. dbo.Defaults — THE company/defaults table:
--      companyName  write-once (trigger trg_Defaults_CompanyNameLock blocks
--                   updates once set), company info (address, logo, STRN,
--                   NTN, FBR), financeType (FIFO | BillWise),
--                   coaLevelDigits (chart-of-accounts level digits, e.g. '2'),
--                   coaLocked (prevents COA level changes once accounts exist)
--    Seeded from the single Company row; Company is renamed to
--    zz_backup_Company_<yyyymmdd>.
-- 2. AccountMapping: branchId backfill — rows without a branch are copied
--    per existing branch (branch-wise mapping), then the NULL templates are
--    removed.
-- 3. Branch hierarchy: parentId + nodeType (Control | Detail) + trn/fbr
--    columns. A Company node (Control) is created; the oldest existing
--    branch becomes the Head Office node (Control) under the Company node;
--    all remaining branches attach under Head Office as Detail nodes. If no
--    branch exists yet, a Head Office node is created.
-- 4. dbo.UserPermission — per USER and per screen: View/Add/Edit/Delete/Print.
-- ============================================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET LANGUAGE us_english;
GO

DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'09_hr_payroll_masterfile', @self = N'10_admin_defaults_security', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    10 already applied, skipping.'; RETURN; END
BEGIN TRY
    BEGIN TRAN;

    -- 1. Defaults table
    IF OBJECT_ID('dbo.Defaults') IS NULL
    BEGIN
        CREATE TABLE dbo.Defaults (
            id              NVARCHAR(50)  NOT NULL CONSTRAINT PK_Defaults PRIMARY KEY,
            companyName     NVARCHAR(255) NULL,          -- write-once (trigger below)
            address         NVARCHAR(MAX) NULL,
            phone           NVARCHAR(255) NULL,
            email           NVARCHAR(255) NULL,
            website         NVARCHAR(255) NULL,
            logo            NVARCHAR(255) NULL,
            strn            NVARCHAR(255) NULL,
            ntn             NVARCHAR(255) NULL,
            fbr             NVARCHAR(255) NULL,
            financeType     NVARCHAR(255) NOT NULL CONSTRAINT DF_Defaults_fin DEFAULT 'FIFO', -- FIFO | BillWise
            coaLevelDigits  NVARCHAR(100) NOT NULL CONSTRAINT DF_Defaults_coaDigits DEFAULT '2', -- digits per level, e.g. 2,2,3
            coaLocked       BIT           NOT NULL CONSTRAINT DF_Defaults_coaLocked DEFAULT 0,
            createdAt       DATETIME2     NOT NULL CONSTRAINT DF_Defaults_created DEFAULT SYSDATETIME(),
            updatedAt       DATETIME2     NOT NULL CONSTRAINT DF_Defaults_updated DEFAULT SYSDATETIME()
        );
        PRINT '  dbo.Defaults created';
    END

    IF NOT EXISTS (SELECT 1 FROM dbo.Defaults)
    BEGIN
        IF OBJECT_ID('dbo.Company') IS NOT NULL
        BEGIN
            INSERT INTO dbo.Defaults (id, companyName, address, phone, email, website, logo, strn, ntn, fbr,
                                      financeType, coaLevelDigits, coaLocked, createdAt, updatedAt)
            SELECT TOP 1
                LOWER(REPLACE(NEWID(), '-', '')), c.name, c.address, c.phone, c.email, c.website, c.logo,
                c.strn, c.ntn, NULL,
                CASE WHEN c.accountingType = 'BillWise' THEN 'BillWise' ELSE 'FIFO' END,
                '2',
                CASE WHEN OBJECT_ID('dbo.charts') IS NOT NULL AND (SELECT COUNT(*) FROM dbo.charts) > 0 THEN 1 ELSE 0 END,
                SYSDATETIME(), SYSDATETIME()
            FROM dbo.Company c;
            PRINT '  Defaults seeded from Company';
        END
        ELSE
        BEGIN
            INSERT INTO dbo.Defaults (id, companyName, financeType, coaLevelDigits, coaLocked, createdAt, updatedAt)
            VALUES (LOWER(REPLACE(NEWID(), '-', '')), NULL, 'FIFO', '2', 0, SYSDATETIME(), SYSDATETIME());
            PRINT '  Defaults seeded empty (no Company row found)';
        END
    END

    -- write-once company name trigger
    IF OBJECT_ID('dbo.trg_Defaults_CompanyNameLock', 'TR') IS NULL
    BEGIN
        EXEC (N'CREATE TRIGGER dbo.trg_Defaults_CompanyNameLock ON dbo.Defaults AFTER UPDATE AS
        BEGIN
            SET NOCOUNT ON;
            IF UPDATE(companyName)
               AND EXISTS (SELECT 1 FROM inserted i JOIN deleted d ON d.id = i.id
                           WHERE ISNULL(d.companyName, '''') <> ''''
                             AND ISNULL(i.companyName, '''') <> ISNULL(d.companyName, ''''))
            BEGIN
                ROLLBACK TRAN;
                THROW 51100, ''Company name is locked: it can only be set once in Admin Defaults.'', 1;
            END
        END;');
        PRINT '  trg_Defaults_CompanyNameLock created (company name write-once)';
    END

    -- retire Company (rename, never drop)
    IF OBJECT_ID('dbo.Company') IS NOT NULL
    BEGIN
        DECLARE @dc sysname = CONVERT(varchar(8), GETDATE(), 112);
        EXEC sp_rename 'dbo.Company', CONCAT('zz_backup_Company_', @dc);
        PRINT '  Company renamed to zz_backup_Company_' + @dc + ' (dbo.Defaults is the source of truth now)';
    END
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'10_admin_defaults_security';
    THROW;
END CATCH
GO

-- 2. AccountMapping: branch-wise backfill
DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'09_hr_payroll_masterfile', @self = N'10_admin_defaults_security', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    10 already applied, skipping.'; RETURN; END
BEGIN TRY
    IF OBJECT_ID('dbo.AccountMapping') IS NOT NULL AND COL_LENGTH('dbo.AccountMapping','branchId') IS NOT NULL
    BEGIN
        DECLARE @nullCount int = (SELECT COUNT(*) FROM dbo.AccountMapping WHERE branchId IS NULL);
        IF @nullCount > 0
        BEGIN
            -- copy each unassigned mapping to every branch
            INSERT INTO dbo.AccountMapping (id, branchId, [key], accountId, description, createdAt, updatedAt)
            SELECT LOWER(REPLACE(NEWID(), '-', '')), b.id, am.[key], am.accountId, am.description, SYSDATETIME(), SYSDATETIME()
            FROM dbo.AccountMapping am
            CROSS JOIN dbo.Branch b
            WHERE am.branchId IS NULL
              AND NOT EXISTS (SELECT 1 FROM dbo.AccountMapping x
                              WHERE x.branchId = b.id AND x.[key] = am.[key] AND x.accountId = am.accountId);
            PRINT '  AccountMapping rows copied per branch: ' + CAST(@@ROWCOUNT AS varchar(10));

            -- the NULL template rows are superseded — remove them
            DELETE FROM dbo.AccountMapping WHERE branchId IS NULL;
            PRINT '  NULL template mappings removed (copies exist per branch)';
        END
        ELSE
            PRINT '  AccountMapping already branch-wise - skipped';

        IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_AccountMapping_branch')
            ALTER TABLE dbo.AccountMapping ADD CONSTRAINT FK_AccountMapping_branch
                FOREIGN KEY (branchId) REFERENCES dbo.Branch (id);
    END
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'10_admin_defaults_security';
    THROW;
END CATCH
GO

-- 3. Branch hierarchy
DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'09_hr_payroll_masterfile', @self = N'10_admin_defaults_security', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    10 already applied, skipping.'; RETURN; END
BEGIN TRY
    IF COL_LENGTH('dbo.Branch','parentId') IS NULL
        ALTER TABLE dbo.Branch ADD parentId NVARCHAR(50) NULL;
    IF COL_LENGTH('dbo.Branch','nodeType') IS NULL
        ALTER TABLE dbo.Branch ADD nodeType NVARCHAR(255) NOT NULL CONSTRAINT DF_Branch_nodeType DEFAULT 'Detail';
    IF COL_LENGTH('dbo.Branch','trn') IS NULL
        ALTER TABLE dbo.Branch ADD trn NVARCHAR(255) NULL;
    IF COL_LENGTH('dbo.Branch','fbr') IS NULL
        ALTER TABLE dbo.Branch ADD fbr NVARCHAR(255) NULL;
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'10_admin_defaults_security';
    THROW;
END CATCH
GO

-- 3b. hierarchy nodes (separate batch: references the new columns)
DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'09_hr_payroll_masterfile', @self = N'10_admin_defaults_security', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    10 already applied, skipping.'; RETURN; END
BEGIN TRY
    DECLARE @companyId NVARCHAR(50) = 'BR-COMPANY';
    DECLARE @companyName NVARCHAR(255) = (SELECT TOP 1 companyName FROM dbo.Defaults);
    IF @companyName IS NULL SET @companyName = N'Company';

    IF NOT EXISTS (SELECT 1 FROM dbo.Branch WHERE id = @companyId)
    BEGIN
        INSERT INTO dbo.Branch (id, code, name, nodeType, parentId, isActive, createdAt, updatedAt, isDeleted)
        VALUES (@companyId, 'CMP', @companyName, 'Control', NULL, 1, SYSDATETIME(), SYSDATETIME(), 0);
        PRINT '  Company node created (Control)';
    END

    DECLARE @hoId NVARCHAR(50) = (SELECT TOP 1 id FROM dbo.Branch
                                  WHERE id <> @companyId ORDER BY createdAt);
    IF @hoId IS NULL
    BEGIN
        INSERT INTO dbo.Branch (id, code, name, nodeType, parentId, isActive, createdAt, updatedAt, isDeleted)
        VALUES ('BR-HO', 'HO', 'Head Office', 'Control', @companyId, 1, SYSDATETIME(), SYSDATETIME(), 0);
        PRINT '  Head Office node created (Control)';
    END
    ELSE
    BEGIN
        -- oldest existing branch becomes the Head Office (Control) under the Company node
        UPDATE dbo.Branch SET nodeType = 'Control', parentId = @companyId WHERE id = @hoId;
        -- all remaining branches attach under Head Office as Detail nodes
        UPDATE dbo.Branch SET nodeType = 'Detail', parentId = @hoId
        WHERE id <> @companyId AND id <> @hoId AND parentId IS NULL;
        PRINT '  branches attached under Head Office (Detail)';
    END

    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Branch_parent')
        ALTER TABLE dbo.Branch ADD CONSTRAINT FK_Branch_parent
            FOREIGN KEY (parentId) REFERENCES dbo.Branch (id);
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'10_admin_defaults_security';
    THROW;
END CATCH
GO

-- 4. UserPermission (per user, per screen)
DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'09_hr_payroll_masterfile', @self = N'10_admin_defaults_security', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    10 already applied, skipping.'; RETURN; END
BEGIN TRY
    IF OBJECT_ID('dbo.UserPermission') IS NULL
    BEGIN
        CREATE TABLE dbo.UserPermission (
            id        NVARCHAR(50)  NOT NULL CONSTRAINT PK_UserPermission PRIMARY KEY CONSTRAINT DF_UP_id DEFAULT REPLACE(NEWID(), '-', ''),
            userId    NVARCHAR(50)  NOT NULL,
            screenKey NVARCHAR(255) NOT NULL,
            canView   BIT           NOT NULL CONSTRAINT DF_UP_view   DEFAULT 0,
            canAdd    BIT           NOT NULL CONSTRAINT DF_UP_add    DEFAULT 0,
            canEdit   BIT           NOT NULL CONSTRAINT DF_UP_edit   DEFAULT 0,
            canDelete BIT           NOT NULL CONSTRAINT DF_UP_delete DEFAULT 0,
            canPrint  BIT           NOT NULL CONSTRAINT DF_UP_print  DEFAULT 0,
            CONSTRAINT FK_UserPermission_user FOREIGN KEY (userId) REFERENCES dbo.[User] (id) ON DELETE CASCADE
        );
        IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'UQ_UserPermission_user_screen')
            ALTER TABLE dbo.UserPermission ADD CONSTRAINT UQ_UserPermission_user_screen UNIQUE (userId, screenKey);
        IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_UserPermission_screen')
            CREATE INDEX IX_UserPermission_screen ON dbo.UserPermission (screenKey);
        PRINT '  dbo.UserPermission created (View/Add/Edit/Delete/Print per user per screen)';
    END
    ELSE
        PRINT '  dbo.UserPermission already present';
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'10_admin_defaults_security';
    THROW;
END CATCH
GO

-- Final verification + Success marker
DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'09_hr_payroll_masterfile', @self = N'10_admin_defaults_security', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    10 already applied, skipping.'; RETURN; END
BEGIN TRY
    IF OBJECT_ID('dbo.Defaults') IS NULL THROW 51101, 'verification failed: Defaults missing', 1;
    IF OBJECT_ID('dbo.trg_Defaults_CompanyNameLock', 'TR') IS NULL THROW 51101, 'verification failed: company-name lock trigger missing', 1;
    IF COL_LENGTH('dbo.Branch','nodeType') IS NULL THROW 51101, 'verification failed: Branch.nodeType missing', 1;
    IF OBJECT_ID('dbo.UserPermission') IS NULL THROW 51101, 'verification failed: UserPermission missing', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Branch WHERE nodeType = 'Control')
        THROW 51101, 'verification failed: no Control node in branch hierarchy', 1;

    EXEC dbo.__mig_Done @self = N'10_admin_defaults_security';
    IF @@TRANCOUNT > 0 COMMIT TRAN;
    PRINT '=== 10 done ===';
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'10_admin_defaults_security';
    THROW;
END CATCH
GO

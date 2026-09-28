-- ============================================================================
-- Contoura Gym ERP — Migration 09: HR PAYROLL MASTER FILE + LEAVE
-- ============================================================================
-- 1. dbo.payrollmasterfile — HR master categories (Education, Designation,
--    Country, Department, Shift, Leave Type, Allowance, ...). Existing
--    designation / department / leave type / shift / allowance values are
--    migrated into it.
-- 2. Leave: business ids LV-0001 (mapping kept in __idmap_Leave) and a new
--    branchId column backfilled from the employee's branch (default branch
--    when unknown).
-- 3. Leave.leaveType keeps storing the type NAME; it now matches
--    payrollmasterfile.name where masterType = 'Leave Type'. The legacy
--    [dbo].[LeaveType] table is RENAMED to zz_backup_LeaveType_<yyyymmdd>
--    after its rows are migrated (never dropped).
-- ============================================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET LANGUAGE us_english;
GO

DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'08_gym_masterfile_and_softdelete', @self = N'09_hr_payroll_masterfile', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    09 already applied, skipping.'; RETURN; END
BEGIN TRY
    BEGIN TRAN;

    IF OBJECT_ID('dbo.payrollmasterfile') IS NULL
    BEGIN
        CREATE TABLE dbo.payrollmasterfile (
            id          NVARCHAR(50)  NOT NULL CONSTRAINT PK_payrollmasterfile PRIMARY KEY CONSTRAINT DF_pmf_id DEFAULT REPLACE(NEWID(), '-', ''),
            masterType  NVARCHAR(255) NOT NULL,           -- Education | Designation | Country | Department | Shift | Leave Type | Allowance | ...
            name        NVARCHAR(255) NOT NULL,
            description NVARCHAR(MAX) NULL,
            extra       NVARCHAR(255) NULL,               -- JSON/aux metadata (e.g. allowedDays, isPaid)
            branchId    NVARCHAR(50)  NULL,
            isActive    BIT           NOT NULL CONSTRAINT DF_pmf_active DEFAULT 1,
            createdAt   DATETIME2     NOT NULL CONSTRAINT DF_pmf_created DEFAULT SYSDATETIME(),
            updatedAt   DATETIME2     NOT NULL CONSTRAINT DF_pmf_updated DEFAULT SYSDATETIME(),
            CONSTRAINT FK_payrollmasterfile_branch FOREIGN KEY (branchId) REFERENCES dbo.Branch (id)
        );
        IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'UQ_payrollmasterfile_type_name')
            ALTER TABLE dbo.payrollmasterfile ADD CONSTRAINT UQ_payrollmasterfile_type_name UNIQUE (masterType, name);
        IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_payrollmasterfile_type')
            CREATE INDEX IX_payrollmasterfile_type ON dbo.payrollmasterfile (masterType);
        PRINT '  dbo.payrollmasterfile created';
    END

    -- migrate existing values (idempotent via unique constraint + NOT EXISTS)
    IF OBJECT_ID('dbo.Staff') IS NOT NULL
    BEGIN
        INSERT INTO dbo.payrollmasterfile (masterType, name, isActive, createdAt, updatedAt)
        SELECT DISTINCT 'Designation', designation, 1, SYSDATETIME(), SYSDATETIME()
        FROM dbo.Staff
        WHERE designation IS NOT NULL AND designation <> ''
          AND NOT EXISTS (SELECT 1 FROM dbo.payrollmasterfile p WHERE p.masterType = 'Designation' AND p.name = Staff.designation);

        INSERT INTO dbo.payrollmasterfile (masterType, name, isActive, createdAt, updatedAt)
        SELECT DISTINCT 'Department', department, 1, SYSDATETIME(), SYSDATETIME()
        FROM dbo.Staff
        WHERE department IS NOT NULL AND department <> ''
          AND NOT EXISTS (SELECT 1 FROM dbo.payrollmasterfile p WHERE p.masterType = 'Department' AND p.name = Staff.department);
    END

    IF OBJECT_ID('dbo.LeaveType') IS NOT NULL
    BEGIN
        INSERT INTO dbo.payrollmasterfile (masterType, name, extra, isActive, createdAt, updatedAt)
        SELECT 'Leave Type', lt.name,
               CONCAT('{"allowedDays":', lt.allowedDays, ',"isPaid":', CASE WHEN lt.isPaid = 1 THEN 'true' ELSE 'false' END, '}'),
               1, SYSDATETIME(), SYSDATETIME()
        FROM dbo.LeaveType lt
        WHERE NOT EXISTS (SELECT 1 FROM dbo.payrollmasterfile p WHERE p.masterType = 'Leave Type' AND p.name = lt.name);
        PRINT '  leave types migrated into payrollmasterfile';
    END
    ELSE
        PRINT '  legacy LeaveType table not present - migration of its rows skipped';

    IF OBJECT_ID('dbo.Shift') IS NOT NULL
    BEGIN
        INSERT INTO dbo.payrollmasterfile (masterType, name, branchId, isActive, createdAt, updatedAt)
        SELECT DISTINCT 'Shift', s.name, s.branchId, 1, SYSDATETIME(), SYSDATETIME()
        FROM dbo.Shift s
        WHERE NOT EXISTS (SELECT 1 FROM dbo.payrollmasterfile p WHERE p.masterType = 'Shift' AND p.name = s.name);
    END

    IF OBJECT_ID('dbo.Allowance') IS NOT NULL
    BEGIN
        INSERT INTO dbo.payrollmasterfile (masterType, name, description, isActive, createdAt, updatedAt)
        SELECT 'Allowance', a.name, a.description, 1, SYSDATETIME(), SYSDATETIME()
        FROM dbo.Allowance a
        WHERE NOT EXISTS (SELECT 1 FROM dbo.payrollmasterfile p WHERE p.masterType = 'Allowance' AND p.name = a.name);
    END

    -- seed Education / Country defaults so the categories are usable at once
    IF NOT EXISTS (SELECT 1 FROM dbo.payrollmasterfile WHERE masterType = 'Education')
        INSERT INTO dbo.payrollmasterfile (masterType, name, isActive, createdAt, updatedAt)
        SELECT 'Education', t.name, 1, SYSDATETIME(), SYSDATETIME()
        FROM (VALUES ('Matric'),('Intermediate'),('Bachelor'),('Master'),('Certification')) t(name)
        WHERE NOT EXISTS (SELECT 1 FROM dbo.payrollmasterfile p WHERE p.masterType = 'Education' AND p.name = t.name);

    IF NOT EXISTS (SELECT 1 FROM dbo.payrollmasterfile WHERE masterType = 'Country')
        INSERT INTO dbo.payrollmasterfile (masterType, name, isActive, createdAt, updatedAt)
        SELECT 'Country', t.name, 1, SYSDATETIME(), SYSDATETIME()
        FROM (VALUES ('Pakistan'),('United Arab Emirates'),('Saudi Arabia')) t(name)
        WHERE NOT EXISTS (SELECT 1 FROM dbo.payrollmasterfile p WHERE p.masterType = 'Country' AND p.name = t.name);
    PRINT '  payrollmasterfile values migrated/seeded';

    -- Leave: add branchId in THIS batch (referenced only in later batches)
    IF OBJECT_ID('dbo.Leave') IS NOT NULL AND COL_LENGTH('dbo.Leave','branchId') IS NULL
        ALTER TABLE dbo.Leave ADD branchId NVARCHAR(50) NULL;
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'09_hr_payroll_masterfile';
    THROW;
END CATCH
GO

-- (separate batch: backfill + NOT NULL + FK + LV-0001 regeneration)
DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'08_gym_masterfile_and_softdelete', @self = N'09_hr_payroll_masterfile', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    09 already applied, skipping.'; RETURN; END
BEGIN TRY
    IF OBJECT_ID('dbo.Leave') IS NOT NULL
    BEGIN
        IF COL_LENGTH('dbo.Leave','branchId') IS NOT NULL
           AND EXISTS (SELECT 1 FROM dbo.Leave WHERE branchId IS NULL)
        BEGIN
            UPDATE l SET l.branchId = s.branchId FROM dbo.Leave l JOIN dbo.Staff s ON s.id = l.staffId;
            DECLARE @defBranch NVARCHAR(50) = (SELECT TOP 1 id FROM dbo.Branch ORDER BY createdAt);
            UPDATE l SET l.branchId = @defBranch WHERE l.branchId IS NULL;
            ALTER TABLE dbo.Leave ALTER COLUMN branchId NVARCHAR(50) NOT NULL;
            IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Leave_branch')
                ALTER TABLE dbo.Leave ADD CONSTRAINT FK_Leave_branch FOREIGN KEY (branchId) REFERENCES dbo.Branch (id);
            PRINT '  Leave.branchId added and backfilled from staff branch';
        END

        IF OBJECT_ID('dbo.__idmap_Leave') IS NOT NULL DROP TABLE dbo.__idmap_Leave;
        SELECT id AS oldId, CONCAT('LV-', FORMAT(ROW_NUMBER() OVER (ORDER BY fromDate, createdAt, id), '0000')) AS newId
        INTO dbo.__idmap_Leave
        FROM dbo.Leave;
        ALTER TABLE dbo.__idmap_Leave ADD CONSTRAINT PK_idmap_Leave PRIMARY KEY (oldId);
        IF EXISTS (SELECT newId FROM dbo.__idmap_Leave GROUP BY newId HAVING COUNT(*) > 1)
            THROW 51090, 'Leave ID regeneration produced duplicates - aborted.', 1;
        UPDATE l SET l.id = x.newId FROM dbo.Leave l JOIN dbo.__idmap_Leave x ON x.oldId = l.id;
        PRINT '  Leave ids regenerated (LV-0001)';

        MERGE dbo.IdSequence AS t
        USING (SELECT 'LEAVE' AS [key], ISNULL(MAX(TRY_CAST(SUBSTRING(id, 4, 20) AS INT)), 0) + 1 AS nxt
               FROM dbo.Leave WHERE id LIKE 'LV-%') s
           ON t.[key] = s.[key]
        WHEN MATCHED AND t.[next] < s.nxt THEN UPDATE SET t.[next] = s.nxt, t.updatedAt = SYSDATETIME()
        WHEN NOT MATCHED THEN INSERT ([key],[next]) VALUES (s.[key], s.[nxt]);
    END

    -- retire legacy LeaveType (rename, never drop)
    IF OBJECT_ID('dbo.LeaveType') IS NOT NULL
    BEGIN
        DECLARE @d sysname = CONVERT(varchar(8), GETDATE(), 112);
        EXEC sp_rename 'dbo.LeaveType', CONCAT('zz_backup_LeaveType_', @d);
        PRINT '  LeaveType renamed to zz_backup_LeaveType_' + @d + ' (Leave.leaveType keeps the type NAME)';
    END
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'09_hr_payroll_masterfile';
    THROW;
END CATCH
GO

-- Final verification + Success marker
DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'08_gym_masterfile_and_softdelete', @self = N'09_hr_payroll_masterfile', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    09 already applied, skipping.'; RETURN; END
BEGIN TRY
    IF OBJECT_ID('dbo.payrollmasterfile') IS NULL THROW 51091, 'verification failed: payrollmasterfile missing', 1;
    IF OBJECT_ID('dbo.LeaveType') IS NOT NULL THROW 51091, 'verification failed: LeaveType still present (should be renamed)', 1;
    IF OBJECT_ID('dbo.Leave') IS NOT NULL AND COL_LENGTH('dbo.Leave','branchId') IS NULL
        THROW 51091, 'verification failed: Leave.branchId missing', 1;

    EXEC dbo.__mig_Done @self = N'09_hr_payroll_masterfile';
    IF @@TRANCOUNT > 0 COMMIT TRAN;
    PRINT '=== 09 done ===';
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'09_hr_payroll_masterfile';
    THROW;
END CATCH
GO

-- ============================================================================
-- Contoura Gym ERP — Migration 08: GYM MASTER FILE + MEMBER SOFT DELETE
-- ============================================================================
-- 1. dbo.gymmasterfile — master categories (3-digit master id) and their
--    items ({masterId}{4-digit seq}, e.g. 0010001). Categories are seeded;
--    Equipment items are branch-wise (branchId column).
--       001 Exercise  |  002 Equipment  |  003 Exercise Type
-- 2. Member soft delete: deletedAt column added (isDeleted already exists).
-- ============================================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET LANGUAGE us_english;
GO

DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'07_regenerate_gym_ids', @self = N'08_gym_masterfile_and_softdelete', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    08 already applied, skipping.'; RETURN; END
BEGIN TRY
    BEGIN TRAN;

    IF OBJECT_ID('dbo.gymmasterfile') IS NULL
    BEGIN
        CREATE TABLE dbo.gymmasterfile (
            id          NVARCHAR(50)  NOT NULL CONSTRAINT PK_gymmasterfile PRIMARY KEY, -- 3-digit master or 7-digit item
            name        NVARCHAR(255) NOT NULL,
            level       INT           NOT NULL,                 -- 1 = category, 2 = item
            parentCode  NVARCHAR(50)  NULL,                     -- category of an item
            branchId    NVARCHAR(50)  NULL,                     -- branch-wise (equipment items)
            description NVARCHAR(MAX) NULL,
            isActive    BIT           NOT NULL CONSTRAINT DF_gymmf_active DEFAULT 1,
            createdAt   DATETIME2     NOT NULL CONSTRAINT DF_gymmf_created DEFAULT SYSDATETIME(),
            updatedAt   DATETIME2     NOT NULL CONSTRAINT DF_gymmf_updated DEFAULT SYSDATETIME(),
            CONSTRAINT FK_gymmasterfile_parent FOREIGN KEY (parentCode) REFERENCES dbo.gymmasterfile (id),
            CONSTRAINT FK_gymmasterfile_branch FOREIGN KEY (branchId)   REFERENCES dbo.Branch (id)
        );
        PRINT '  dbo.gymmasterfile created';
    END

    -- seed master categories (3-digit master ids)
    IF NOT EXISTS (SELECT 1 FROM dbo.gymmasterfile WHERE id = '001')
        INSERT INTO dbo.gymmasterfile (id, name, level, parentCode, branchId, description, isActive, createdAt, updatedAt)
        VALUES ('001', 'Exercise', 1, NULL, NULL, 'Exercise master category', 1, SYSDATETIME(), SYSDATETIME());
    IF NOT EXISTS (SELECT 1 FROM dbo.gymmasterfile WHERE id = '002')
        INSERT INTO dbo.gymmasterfile (id, name, level, parentCode, branchId, description, isActive, createdAt, updatedAt)
        VALUES ('002', 'Equipment', 1, NULL, NULL, 'Equipment master category (items are branch-wise)', 1, SYSDATETIME(), SYSDATETIME());
    IF NOT EXISTS (SELECT 1 FROM dbo.gymmasterfile WHERE id = '003')
        INSERT INTO dbo.gymmasterfile (id, name, level, parentCode, branchId, description, isActive, createdAt, updatedAt)
        VALUES ('003', 'Exercise Type', 1, NULL, NULL, 'Exercise Type master category', 1, SYSDATETIME(), SYSDATETIME());
    PRINT '  gymmasterfile categories seeded (001 Exercise, 002 Equipment, 003 Exercise Type)';

    -- member soft delete timestamp
    IF COL_LENGTH('dbo.Member','deletedAt') IS NULL
    BEGIN
        ALTER TABLE dbo.Member ADD deletedAt DATETIME2 NULL;
        PRINT '  Member.deletedAt added';
    END
    ELSE
        PRINT '  Member.deletedAt already present';
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'08_gym_masterfile_and_softdelete';
    THROW;
END CATCH
GO

-- Final verification + Success marker
DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'07_regenerate_gym_ids', @self = N'08_gym_masterfile_and_softdelete', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    08 already applied, skipping.'; RETURN; END
BEGIN TRY
    IF OBJECT_ID('dbo.gymmasterfile') IS NULL THROW 51080, 'verification failed: gymmasterfile missing', 1;
    IF COL_LENGTH('dbo.Member','deletedAt') IS NULL THROW 51080, 'verification failed: Member.deletedAt missing', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.gymmasterfile WHERE id = '001' AND level = 1)
        THROW 51080, 'verification failed: master categories not seeded', 1;

    EXEC dbo.__mig_Done @self = N'08_gym_masterfile_and_softdelete';
    IF @@TRANCOUNT > 0 COMMIT TRAN;
    PRINT '=== 08 done ===';
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'08_gym_masterfile_and_softdelete';
    THROW;
END CATCH
GO

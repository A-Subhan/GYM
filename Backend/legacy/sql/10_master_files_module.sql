/* ============================================================================
   CONTOURA LABS — GYM MANAGEMENT SYSTEM
   MASTER FILES MODULE (10_master_files_module.sql) — Run AFTER 09.
   Idempotent — safe to re-run.
   ----------------------------------------------------------------------------
   Replaces the hard-coded Designations / Educations tables (from 09) with a
   metadata-driven master files system:

     MasterDefinitions  — one row per master file (Designation 01, Education 02,
                          Currency 03, ...) with Global/Branch scope.
     MasterItems        — the records inside each master file. ItemCode =
                          <MasterCode><0001 sequence> e.g. 010001, 020001.
                          Unique per definition, generated inside a transaction
                          with UPDLOCK/HOLDLOCK (concurrency safe).

   Also:
   - Migrates rows from the old Designations / Educations tables (if present),
     then drops those tables and their CRUD procedures.
   - Seeds: Designation (01), Education (02), Currency (03).
   - Adds masters.* permissions (view/add/edit/delete/status) and grants them
     to roles following the existing RBAC pattern.
   - Referential integrity: deleting a master item is blocked at the DATABASE
     level while any record still references it (e.g. Staff.Designation).
   ============================================================================ */

USE GymDB;
GO

/* ================================================================== */
/* TABLES                                                             */
/* ================================================================== */

IF OBJECT_ID('dbo.MasterDefinitions', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.MasterDefinitions (
        MasterDefinitionID INT IDENTITY(1,1) PRIMARY KEY,
        MasterCode         NVARCHAR(5)   NOT NULL UNIQUE,   -- 01, 02, 03 ...
        Name               NVARCHAR(50)  NOT NULL UNIQUE,   -- Designation, Education ...
        Scope              NVARCHAR(10)  NOT NULL DEFAULT 'Global'
                           CHECK (Scope IN ('Global','Branch')), -- Branch = items are per branch
        IsActive           BIT           NOT NULL DEFAULT 1,
        CreatedAt          DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
        UpdatedAt          DATETIME2     NULL,
        CreatedBy          INT           NULL,
        UpdatedBy          INT           NULL
    );
END
GO

IF OBJECT_ID('dbo.MasterItems', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.MasterItems (
        MasterItemID       INT IDENTITY(1,1) PRIMARY KEY,
        MasterDefinitionID INT           NOT NULL FOREIGN KEY REFERENCES dbo.MasterDefinitions(MasterDefinitionID),
        ItemCode           NVARCHAR(20)  NOT NULL,          -- 010001, 020001 ...
        Name               NVARCHAR(50)  NOT NULL,
        IsActive           BIT           NOT NULL DEFAULT 1,
        BranchID           INT           NULL FOREIGN KEY REFERENCES dbo.Branches(BranchID), -- NULL for Global masters
        CreatedAt          DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
        UpdatedAt          DATETIME2     NULL,
        CreatedBy          INT           NULL,
        UpdatedBy          INT           NULL,
        CONSTRAINT UQ_MasterItems_Def_Code UNIQUE (MasterDefinitionID, ItemCode)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_MasterItems_Def')
    CREATE INDEX IX_MasterItems_Def ON dbo.MasterItems(MasterDefinitionID, IsActive);
GO

/* ================================================================== */
/* MIGRATE OLD Designations / Educations TABLES (from 09), if present */
/* ================================================================== */

IF OBJECT_ID('dbo.Designations', 'U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM dbo.MasterDefinitions WHERE Name = 'Designation')
BEGIN
    INSERT INTO dbo.MasterDefinitions (MasterCode, Name, Scope, IsActive)
    VALUES ('01', 'Designation', 'Global', 1);

    DECLARE @DesigDef INT = (SELECT MasterDefinitionID FROM dbo.MasterDefinitions WHERE Name = 'Designation');

    INSERT INTO dbo.MasterItems (MasterDefinitionID, ItemCode, Name, IsActive)
    SELECT @DesigDef, '01' + RIGHT('0000' + d.Code, 4), d.Name, 1
    FROM dbo.Designations d;
END
GO

IF OBJECT_ID('dbo.Educations', 'U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM dbo.MasterDefinitions WHERE Name = 'Education')
BEGIN
    INSERT INTO dbo.MasterDefinitions (MasterCode, Name, Scope, IsActive)
    VALUES ('02', 'Education', 'Global', 1);

    DECLARE @EduDef INT = (SELECT MasterDefinitionID FROM dbo.MasterDefinitions WHERE Name = 'Education');

    INSERT INTO dbo.MasterItems (MasterDefinitionID, ItemCode, Name, IsActive)
    SELECT @EduDef, '02' + RIGHT('0000' + e.Code, 4), e.Name, 1
    FROM dbo.Educations e;
END
GO

/* ---------- Seed defaults (only when the master has no items) ------ */

IF NOT EXISTS (SELECT 1 FROM dbo.MasterDefinitions WHERE Name = 'Designation')
    INSERT INTO dbo.MasterDefinitions (MasterCode, Name, Scope, IsActive) VALUES ('01', 'Designation', 'Global', 1);
GO

IF NOT EXISTS (SELECT 1 FROM dbo.MasterDefinitions WHERE Name = 'Education')
    INSERT INTO dbo.MasterDefinitions (MasterCode, Name, Scope, IsActive) VALUES ('02', 'Education', 'Global', 1);
GO

IF NOT EXISTS (SELECT 1 FROM dbo.MasterDefinitions WHERE Name = 'Currency')
    INSERT INTO dbo.MasterDefinitions (MasterCode, Name, Scope, IsActive) VALUES ('03', 'Currency', 'Global', 1);
GO

DECLARE @DefID INT, @MaxSeq INT;

SELECT @DefID = MasterDefinitionID FROM dbo.MasterDefinitions WHERE Name = 'Designation';
IF NOT EXISTS (SELECT 1 FROM dbo.MasterItems WHERE MasterDefinitionID = @DefID)
    INSERT INTO dbo.MasterItems (MasterDefinitionID, ItemCode, Name, IsActive) VALUES
    (@DefID, '010001', 'CEO',          1),
    (@DefID, '010002', 'Manager',      1),
    (@DefID, '010003', 'Accountant',   1),
    (@DefID, '010004', 'Trainer',      1),
    (@DefID, '010005', 'Receptionist', 1),
    (@DefID, '010006', 'Sweeper',      1);

SELECT @DefID = MasterDefinitionID FROM dbo.MasterDefinitions WHERE Name = 'Currency';
IF NOT EXISTS (SELECT 1 FROM dbo.MasterItems WHERE MasterDefinitionID = @DefID)
    INSERT INTO dbo.MasterItems (MasterDefinitionID, ItemCode, Name, IsActive) VALUES
    (@DefID, '030001', 'Pakistani Rupee', 1),
    (@DefID, '030002', 'US Dollar',       1);
GO

/* ---------- Retire the old hard-coded tables + procedures ---------- */

DROP PROCEDURE IF EXISTS dbo.sp_Designations_List;
DROP PROCEDURE IF EXISTS dbo.sp_Designations_Create;
DROP PROCEDURE IF EXISTS dbo.sp_Designations_Update;
DROP PROCEDURE IF EXISTS dbo.sp_Designations_Delete;
DROP PROCEDURE IF EXISTS dbo.sp_Educations_List;
DROP PROCEDURE IF EXISTS dbo.sp_Educations_Create;
DROP PROCEDURE IF EXISTS dbo.sp_Educations_Update;
DROP PROCEDURE IF EXISTS dbo.sp_Educations_Delete;
GO

IF OBJECT_ID('dbo.Designations', 'U') IS NOT NULL
    DROP TABLE dbo.Designations;
GO

IF OBJECT_ID('dbo.Educations', 'U') IS NOT NULL
    DROP TABLE dbo.Educations;
GO

/* ================================================================== */
/* PERMISSIONS: masters.view / add / edit / delete / status           */
/* ================================================================== */

INSERT INTO Permissions (Module, Action, Description)
SELECT v.Module, v.Action, v.Description
FROM (VALUES
    ('masters', 'view',   'View master files'),
    ('masters', 'add',    'Add master file data'),
    ('masters', 'edit',   'Edit master file data'),
    ('masters', 'delete', 'Delete master file data'),
    ('masters', 'status', 'Activate / deactivate master file data')
) v(Module, Action, Description)
WHERE NOT EXISTS (SELECT 1 FROM Permissions p WHERE p.Module = v.Module AND p.Action = v.Action);
GO

-- Super Admin bypasses checks; grant everything to Owner (2)
INSERT INTO RolePermissions (RoleID, PermissionID)
SELECT 2, p.PermissionID FROM Permissions p
WHERE p.Module = 'masters'
  AND NOT EXISTS (SELECT 1 FROM RolePermissions x WHERE x.RoleID = 2 AND x.PermissionID = p.PermissionID);
GO

-- Manager (3): view + add + edit + status (no delete)
INSERT INTO RolePermissions (RoleID, PermissionID)
SELECT 3, p.PermissionID FROM Permissions p
WHERE p.Module = 'masters' AND p.Action IN ('view','add','edit','status')
  AND NOT EXISTS (SELECT 1 FROM RolePermissions x WHERE x.RoleID = 3 AND x.PermissionID = p.PermissionID);
GO

-- Receptionist (4) / Trainer (5) / Accountant (6) / Staff (7): view only
INSERT INTO RolePermissions (RoleID, PermissionID)
SELECT r.RoleID, p.PermissionID
FROM (VALUES (4),(5),(6),(7)) r(RoleID)
CROSS JOIN Permissions p
WHERE p.Module = 'masters' AND p.Action = 'view'
  AND NOT EXISTS (SELECT 1 FROM RolePermissions x WHERE x.RoleID = r.RoleID AND x.PermissionID = p.PermissionID);
GO

/* ================================================================== */
/* MASTER DEFINITIONS SPs                                             */
/* ================================================================== */

CREATE OR ALTER PROCEDURE sp_MasterDefinitions_List
    @IncludeInactive BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  d.MasterDefinitionID, d.MasterCode, d.Name, d.Scope, d.IsActive,
            d.CreatedAt,
            (SELECT COUNT(*) FROM MasterItems i WHERE i.MasterDefinitionID = d.MasterDefinitionID) AS ItemCount
    FROM    MasterDefinitions d
    WHERE   (@IncludeInactive = 1 OR d.IsActive = 1)
    ORDER BY d.MasterCode;
END;
GO

CREATE OR ALTER PROCEDURE sp_MasterDefinitions_Create
    @Name NVARCHAR(50), @MasterCode NVARCHAR(5) = NULL,
    @Scope NVARCHAR(10) = 'Global', @CreatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @Scope = UPPER(LEFT(@Scope, 1)) + SUBSTRING(LOWER(@Scope), 2, 20);
    IF @Scope NOT IN ('Global', 'Branch')
        THROW 50140, 'Scope must be Global or Branch.', 1;

    BEGIN TRAN;

    DECLARE @Code NVARCHAR(5);

    IF @MasterCode IS NULL OR LTRIM(RTRIM(@MasterCode)) = ''
    BEGIN
        SELECT @Code = RIGHT('00' + CAST(ISNULL(MAX(TRY_CAST(MasterCode AS INT)), 0) + 1 AS NVARCHAR(2)), 2)
        FROM MasterDefinitions WITH (UPDLOCK, HOLDLOCK);
    END
    ELSE
    BEGIN
        SET @Code = LTRIM(RTRIM(@MasterCode));
        IF TRY_CAST(@Code AS INT) IS NULL OR LEN(@Code) > 5
        BEGIN
            ROLLBACK TRAN;
            THROW 50141, 'Master code must be a number (e.g. 04).', 1;
        END
        IF EXISTS (SELECT 1 FROM MasterDefinitions WHERE MasterCode = @Code)
        BEGIN
            ROLLBACK TRAN;
            THROW 50142, 'This master code is already in use.', 1;
        END
    END

    IF EXISTS (SELECT 1 FROM MasterDefinitions WHERE UPPER(Name) = UPPER(@Name))
    BEGIN
        ROLLBACK TRAN;
        THROW 50143, 'Master file already exists.', 1;
    END

    INSERT INTO MasterDefinitions (MasterCode, Name, Scope, IsActive, CreatedBy)
    VALUES (@Code, @Name, @Scope, 1, @CreatedBy);

    COMMIT TRAN;

    SELECT CAST(SCOPE_IDENTITY() AS INT) AS MasterDefinitionID, @Code AS MasterCode;
END;
GO

CREATE OR ALTER PROCEDURE sp_MasterDefinitions_Update
    @MasterDefinitionID INT, @Name NVARCHAR(50) = NULL,
    @Scope NVARCHAR(10) = NULL, @IsActive BIT = NULL, @UpdatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM MasterDefinitions WHERE MasterDefinitionID = @MasterDefinitionID)
        THROW 50144, 'Master file not found.', 1;

    IF @Name IS NOT NULL AND EXISTS (
        SELECT 1 FROM MasterDefinitions
        WHERE UPPER(Name) = UPPER(@Name) AND MasterDefinitionID <> @MasterDefinitionID)
        THROW 50143, 'Master file already exists.', 1;

    UPDATE MasterDefinitions
       SET Name = COALESCE(@Name, Name),
           Scope = COALESCE(@Scope, Scope),
           IsActive = COALESCE(@IsActive, IsActive),
           UpdatedBy = @UpdatedBy,
           UpdatedAt = SYSUTCDATETIME()
     WHERE MasterDefinitionID = @MasterDefinitionID;
END;
GO

CREATE OR ALTER PROCEDURE sp_MasterDefinitions_Delete
    @MasterDefinitionID INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM MasterDefinitions WHERE MasterDefinitionID = @MasterDefinitionID)
        THROW 50144, 'Master file not found.', 1;

    IF EXISTS (SELECT 1 FROM MasterItems WHERE MasterDefinitionID = @MasterDefinitionID)
        THROW 50145, 'This master file still has records. Delete its records first.', 1;

    DELETE FROM MasterDefinitions WHERE MasterDefinitionID = @MasterDefinitionID;
END;
GO

/* ================================================================== */
/* MASTER ITEMS SPs                                                   */
/* ================================================================== */

CREATE OR ALTER PROCEDURE sp_MasterItems_List
    @MasterDefinitionID INT,
    @Search NVARCHAR(100) = NULL,
    @IsActive BIT = NULL,
    @BranchID INT = NULL,          -- applied only for Branch-scope masters
    @Page INT = 1,
    @PageSize INT = 20
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Scope NVARCHAR(10);
    SELECT @Scope = Scope FROM MasterDefinitions WHERE MasterDefinitionID = @MasterDefinitionID;
    IF @Scope IS NULL
        THROW 50144, 'Master file not found.', 1;

    DECLARE @Offset INT = (@Page - 1) * @PageSize;
    DECLARE @UseBranch BIT = CASE WHEN @Scope = 'Branch' THEN 1 ELSE 0 END;

    SELECT  i.MasterItemID, i.ItemCode, i.Name, i.IsActive, i.BranchID,
            b.Name AS BranchName, i.CreatedAt
    FROM    MasterItems i
    LEFT JOIN Branches b ON b.BranchID = i.BranchID
    WHERE   i.MasterDefinitionID = @MasterDefinitionID
      AND   (@IsActive IS NULL OR i.IsActive = @IsActive)
      AND   (@UseBranch = 0 OR (@BranchID IS NULL OR i.BranchID = @BranchID))
      AND   (@Search IS NULL OR i.Name LIKE '%'+@Search+'%' OR i.ItemCode LIKE '%'+@Search+'%')
    ORDER BY i.ItemCode
    OFFSET  @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT  COUNT(*) AS Total
    FROM    MasterItems i
    WHERE   i.MasterDefinitionID = @MasterDefinitionID
      AND   (@IsActive IS NULL OR i.IsActive = @IsActive)
      AND   (@UseBranch = 0 OR (@BranchID IS NULL OR i.BranchID = @BranchID))
      AND   (@Search IS NULL OR i.Name LIKE '%'+@Search+'%' OR i.ItemCode LIKE '%'+@Search+'%');
END;
GO

CREATE OR ALTER PROCEDURE sp_MasterItems_Create
    @MasterDefinitionID INT, @Name NVARCHAR(50),
    @BranchID INT = NULL, @CreatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Scope NVARCHAR(10), @MasterCode NVARCHAR(5);
    SELECT @Scope = Scope, @MasterCode = MasterCode
    FROM MasterDefinitions
    WHERE MasterDefinitionID = @MasterDefinitionID AND IsActive = 1;

    IF @MasterCode IS NULL
        THROW 50144, 'Master file not found.', 1;

    -- Branch-scope masters must know which branch the record belongs to
    IF @Scope = 'Branch' AND @BranchID IS NULL
        THROW 50146, 'Branch is required for this master file.', 1;
    IF @Scope = 'Global'
        SET @BranchID = NULL;

    -- Duplicate name inside the same master (and same branch for branch scopes)
    IF EXISTS (
        SELECT 1 FROM MasterItems
        WHERE MasterDefinitionID = @MasterDefinitionID
          AND UPPER(LTRIM(RTRIM(Name))) = UPPER(LTRIM(RTRIM(@Name)))
          AND (@Scope = 'Global' OR BranchID = @BranchID))
        THROW 50147, 'This name already exists in this master file.', 1;

    DECLARE @ItemCode NVARCHAR(20), @Seq INT;

    BEGIN TRAN;

    -- Concurrency-safe sequence: lock the range until commit
    SELECT @Seq = ISNULL(MAX(TRY_CAST(RIGHT(ItemCode, 4) AS INT)), 0) + 1
    FROM MasterItems WITH (UPDLOCK, HOLDLOCK)
    WHERE MasterDefinitionID = @MasterDefinitionID;

    SET @ItemCode = @MasterCode + RIGHT('0000' + CAST(@Seq AS NVARCHAR(4)), 4);

    INSERT INTO MasterItems (MasterDefinitionID, ItemCode, Name, IsActive, BranchID, CreatedBy)
    VALUES (@MasterDefinitionID, @ItemCode, LTRIM(RTRIM(@Name)), 1, @BranchID, @CreatedBy);

    COMMIT TRAN;

    SELECT CAST(SCOPE_IDENTITY() AS INT) AS MasterItemID, @ItemCode AS ItemCode;
END;
GO

CREATE OR ALTER PROCEDURE sp_MasterItems_Update
    @MasterItemID INT, @Name NVARCHAR(50), @UpdatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @DefID INT, @BranchID INT, @Scope NVARCHAR(10);
    SELECT  @DefID = i.MasterDefinitionID, @BranchID = i.BranchID,
            @Scope = d.Scope
    FROM MasterItems i
    JOIN MasterDefinitions d ON d.MasterDefinitionID = i.MasterDefinitionID
    WHERE i.MasterItemID = @MasterItemID;

    IF @DefID IS NULL
        THROW 50148, 'Master record not found.', 1;

    IF EXISTS (
        SELECT 1 FROM MasterItems
        WHERE MasterDefinitionID = @DefID
          AND MasterItemID <> @MasterItemID
          AND UPPER(LTRIM(RTRIM(Name))) = UPPER(LTRIM(RTRIM(@Name)))
          AND (@Scope = 'Global' OR BranchID = @BranchID))
        THROW 50147, 'This name already exists in this master file.', 1;

    UPDATE MasterItems
       SET Name = LTRIM(RTRIM(@Name)),
           UpdatedBy = @UpdatedBy,
           UpdatedAt = SYSUTCDATETIME()
     WHERE MasterItemID = @MasterItemID;
END;
GO

CREATE OR ALTER PROCEDURE sp_MasterItems_SetStatus
    @MasterItemID INT, @IsActive BIT, @UpdatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE MasterItems
       SET IsActive = @IsActive,
           UpdatedBy = @UpdatedBy,
           UpdatedAt = SYSUTCDATETIME()
     WHERE MasterItemID = @MasterItemID;
END;
GO

CREATE OR ALTER PROCEDURE sp_MasterItems_Delete
    @MasterItemID INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @DefName NVARCHAR(50), @ItemName NVARCHAR(50), @UsedCount INT;

    SELECT  @DefName = d.Name, @ItemName = i.Name
    FROM MasterItems i
    JOIN MasterDefinitions d ON d.MasterDefinitionID = i.MasterDefinitionID
    WHERE i.MasterItemID = @MasterItemID;

    IF @ItemName IS NULL
        THROW 50148, 'Master record not found.', 1;

    /* ------------------------------------------------------------
       REFERENTIAL INTEGRITY — one block per integrated entity.
       A master item that is still referenced anywhere must NOT be
       deleted. Extend this list as more forms start referencing
       master files.
       ------------------------------------------------------------ */
    IF @DefName = 'Designation'
    BEGIN
        SELECT @UsedCount = COUNT(*) FROM Staff WHERE Designation = @ItemName AND IsDeleted = 0;
        IF @UsedCount > 0
        BEGIN
            /* RETURN is critical: RAISERROR alone does NOT stop execution */
            RAISERROR('''%s'' cannot be deleted because it is currently assigned to one or more staff records.', 16, 1, @ItemName);
            RETURN;
        END
    END

    DELETE FROM MasterItems WHERE MasterItemID = @MasterItemID;
END;
GO

/* ================================================================== */
/* VERIFY                                                             */
/* ================================================================== */

SELECT d.MasterCode, d.Name AS MasterFile, d.Scope, COUNT(i.MasterItemID) AS Items
FROM MasterDefinitions d
LEFT JOIN MasterItems i ON i.MasterDefinitionID = d.MasterDefinitionID
GROUP BY d.MasterCode, d.Name, d.Scope
ORDER BY d.MasterCode;
GO

SELECT 'masters permissions' AS CheckName, COUNT(*) AS [Value]
FROM Permissions WHERE Module = 'masters';
GO

PRINT '=== Master Files module applied successfully. ===';
GO

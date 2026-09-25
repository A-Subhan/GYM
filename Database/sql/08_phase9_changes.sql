/* ============================================================================
   CONTOURA LABS — GYM MANAGEMENT SYSTEM
   PHASE 9 CHANGES (08_phase9_changes.sql) — Run AFTER 07_fixes.sql
   ----------------------------------------------------------------------------
   Three changes applied by this script:

   PART 1 — "Active Memberships" page removed:
     - Drops sp_MemberMemberships_ActiveList / _Renew / _Freeze / _Cancel
     - Drops the MembershipFreezes table (only used by freeze)
     - KEEPS MemberMemberships + sp_MemberMemberships_Create
       (a plan is now assigned when a member is created)

   PART 2 — Staff & Trainers merged into ONE staff page:
     - Staff rows can now be TAGGED as trainer (IsTrainer flag on staff
       API; a row in the Trainers table = tagged)
     - sp_Staff_List / sp_Staff_Get return the trainer tag
     - sp_Staff_Create / sp_Staff_Update / sp_Staff_SoftDelete maintain
       the Trainers tag automatically
     - sp_Staff_ListTrainers lists staff tagged as trainer (used by the
       member/workout/diet trainer dropdowns)
     - Drops the old sp_Trainers_* procedures
     - Removes the standalone trainers.* permissions and grants staff.view
       to every role that had trainers.view

   The Trainers TABLE itself is kept: it stores specialization/experience
   and Members.TrainerID + WorkoutPlans/DietPlans reference it.
   ============================================================================ */

USE GymDB;
GO

/* ================================================================== */
/* PART 1 — ACTIVE MEMBERSHIPS PAGE REMOVAL                           */
/* ================================================================== */

DROP PROCEDURE IF EXISTS dbo.sp_MemberMemberships_ActiveList;
DROP PROCEDURE IF EXISTS dbo.sp_MemberMemberships_Renew;
DROP PROCEDURE IF EXISTS dbo.sp_MemberMemberships_Freeze;
DROP PROCEDURE IF EXISTS dbo.sp_MemberMemberships_Cancel;
GO

IF OBJECT_ID('dbo.MembershipFreezes', 'U') IS NOT NULL
    DROP TABLE dbo.MembershipFreezes;
GO

/* ================================================================== */
/* PART 2 — STAFF / TRAINER MERGE                                     */
/* ================================================================== */

/* ---------- List: expose the trainer tag on every staff row -------- */

CREATE OR ALTER PROCEDURE sp_Staff_List
    @Page INT = 1,
    @PageSize INT = 20,
    @Search NVARCHAR(100) = NULL,
    @BranchID INT = NULL,
    @DepartmentID INT = NULL,
    @Status NVARCHAR(20) = NULL,
    @IsTrainer BIT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Offset INT = (@Page - 1) * @PageSize;

    SELECT  s.StaffID, s.FullName, s.FatherName, s.CNIC, s.Mobile, s.Email, s.Photo,
            s.JoiningDate, s.Designation, s.BaseSalary, s.Status,
            s.BranchID, b.Name AS BranchName,
            s.DepartmentID, d.Name AS DepartmentName,
            u.Username, u.UserID,
            t.TrainerID,
            CASE WHEN t.TrainerID IS NULL THEN 0 ELSE 1 END AS IsTrainer,
            t.Specialization, t.Experience,
            (SELECT COUNT(*) FROM Members m WHERE m.TrainerID = t.TrainerID AND m.IsDeleted = 0) AS AssignedMembers
    FROM    Staff s
    LEFT JOIN Branches b ON b.BranchID = s.BranchID
    LEFT JOIN Departments d ON d.DepartmentID = s.DepartmentID
    LEFT JOIN Users u ON u.UserID = s.UserID
    OUTER APPLY (SELECT TOP 1 tr.TrainerID, tr.Specialization, tr.Experience
                 FROM Trainers tr
                 WHERE tr.StaffID = s.StaffID AND tr.IsActive = 1
                 ORDER BY tr.TrainerID DESC) t
    WHERE   s.IsDeleted = 0
      AND   (@BranchID IS NULL OR s.BranchID = @BranchID)
      AND   (@DepartmentID IS NULL OR s.DepartmentID = @DepartmentID)
      AND   (@Status IS NULL OR s.Status = @Status)
      AND   (@IsTrainer IS NULL OR CASE WHEN t.TrainerID IS NULL THEN 0 ELSE 1 END = @IsTrainer)
      AND   (@Search IS NULL OR s.FullName LIKE '%'+@Search+'%' OR s.CNIC LIKE '%'+@Search+'%' OR s.Mobile LIKE '%'+@Search+'%')
    ORDER BY s.StaffID DESC
    OFFSET  @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT  COUNT(*) AS Total
    FROM    Staff s
    OUTER APPLY (SELECT TOP 1 tr.TrainerID
                 FROM Trainers tr
                 WHERE tr.StaffID = s.StaffID AND tr.IsActive = 1
                 ORDER BY tr.TrainerID DESC) t
    WHERE   s.IsDeleted = 0
      AND   (@BranchID IS NULL OR s.BranchID = @BranchID)
      AND   (@DepartmentID IS NULL OR s.DepartmentID = @DepartmentID)
      AND   (@Status IS NULL OR s.Status = @Status)
      AND   (@IsTrainer IS NULL OR CASE WHEN t.TrainerID IS NULL THEN 0 ELSE 1 END = @IsTrainer)
      AND   (@Search IS NULL OR s.FullName LIKE '%'+@Search+'%' OR s.CNIC LIKE '%'+@Search+'%' OR s.Mobile LIKE '%'+@Search+'%');
END;
GO

CREATE OR ALTER PROCEDURE sp_Staff_Get
    @StaffID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  s.*, b.Name AS BranchName, d.Name AS DepartmentName, u.Username,
            t.TrainerID,
            CASE WHEN t.TrainerID IS NULL THEN 0 ELSE 1 END AS IsTrainer,
            t.Specialization, t.Experience
    FROM    Staff s
    LEFT JOIN Branches b ON b.BranchID = s.BranchID
    LEFT JOIN Departments d ON d.DepartmentID = s.DepartmentID
    LEFT JOIN Users u ON u.UserID = s.UserID
    OUTER APPLY (SELECT TOP 1 tr.TrainerID, tr.Specialization, tr.Experience
                 FROM Trainers tr
                 WHERE tr.StaffID = s.StaffID AND tr.IsActive = 1
                 ORDER BY tr.TrainerID DESC) t
    WHERE   s.StaffID = @StaffID AND s.IsDeleted = 0;
END;
GO

/* ---------- Create: optionally tag the new staff as trainer -------- */

CREATE OR ALTER PROCEDURE sp_Staff_Create
    @BranchID INT, @DepartmentID INT, @UserID INT = NULL,
    @FullName NVARCHAR(150), @FatherName NVARCHAR(150) = NULL,
    @CNIC NVARCHAR(20) = NULL, @Mobile NVARCHAR(30) = NULL,
    @Email NVARCHAR(150) = NULL, @Address NVARCHAR(500) = NULL,
    @Photo NVARCHAR(500) = NULL, @JoiningDate DATE,
    @Designation NVARCHAR(100) = NULL, @BaseSalary DECIMAL(18,2) = 0,
    @Status NVARCHAR(20) = 'Active',
    @IsTrainer BIT = 0, @Specialization NVARCHAR(200) = NULL, @Experience NVARCHAR(100) = NULL,
    @CreatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @StaffID INT;

    INSERT INTO Staff (BranchID, DepartmentID, UserID, FullName, FatherName, CNIC, Mobile, Email,
                       Address, Photo, JoiningDate, Designation, BaseSalary, Status, CreatedBy)
    VALUES (@BranchID, @DepartmentID, @UserID, @FullName, @FatherName, @CNIC, @Mobile, @Email,
            @Address, @Photo, @JoiningDate, @Designation, @BaseSalary, @Status, @CreatedBy);

    SET @StaffID = CAST(SCOPE_IDENTITY() AS INT);

    IF @IsTrainer = 1
    BEGIN
        INSERT INTO Trainers (StaffID, Specialization, Experience, IsActive)
        VALUES (@StaffID, @Specialization, @Experience, 1);
    END

    SELECT @StaffID AS StaffID;
END;
GO

/* ---------- Update: tag / untag as trainer ------------------------- */
/* Untagging deactivates the Trainers row and unassigns its members
   (same behavior the old sp_Trainers_Deactivate had).                */

CREATE OR ALTER PROCEDURE sp_Staff_Update
    @StaffID INT, @BranchID INT = NULL, @DepartmentID INT = NULL,
    @UserID INT = NULL, @FullName NVARCHAR(150) = NULL, @FatherName NVARCHAR(150) = NULL,
    @CNIC NVARCHAR(20) = NULL, @Mobile NVARCHAR(30) = NULL, @Email NVARCHAR(150) = NULL,
    @Address NVARCHAR(500) = NULL, @Photo NVARCHAR(500) = NULL, @JoiningDate DATE = NULL,
    @Designation NVARCHAR(100) = NULL, @BaseSalary DECIMAL(18,2) = NULL,
    @Status NVARCHAR(20) = NULL,
    @IsTrainer BIT = NULL, @Specialization NVARCHAR(200) = NULL, @Experience NVARCHAR(100) = NULL,
    @UpdatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE Staff
       SET BranchID     = COALESCE(@BranchID, BranchID),
           DepartmentID = COALESCE(@DepartmentID, DepartmentID),
           UserID       = COALESCE(@UserID, UserID),
           FullName     = COALESCE(@FullName, FullName),
           FatherName   = COALESCE(@FatherName, FatherName),
           CNIC         = COALESCE(@CNIC, CNIC),
           Mobile       = COALESCE(@Mobile, Mobile),
           Email        = COALESCE(@Email, Email),
           Address      = COALESCE(@Address, Address),
           Photo        = COALESCE(@Photo, Photo),
           JoiningDate  = COALESCE(@JoiningDate, JoiningDate),
           Designation  = COALESCE(@Designation, Designation),
           BaseSalary   = COALESCE(@BaseSalary, BaseSalary),
           Status       = COALESCE(@Status, Status),
           UpdatedBy    = @UpdatedBy,
           UpdatedAt    = SYSUTCDATETIME()
     WHERE StaffID = @StaffID;

    IF @IsTrainer = 1
    BEGIN
        IF EXISTS (SELECT 1 FROM Trainers WHERE StaffID = @StaffID)
            UPDATE Trainers
               SET IsActive = 1,
                   Specialization = COALESCE(@Specialization, Specialization),
                   Experience     = COALESCE(@Experience, Experience)
             WHERE StaffID = @StaffID;
        ELSE
            INSERT INTO Trainers (StaffID, Specialization, Experience, IsActive)
            VALUES (@StaffID, @Specialization, @Experience, 1);
    END
    ELSE IF @IsTrainer = 0
    BEGIN
        UPDATE Trainers SET IsActive = 0 WHERE StaffID = @StaffID AND IsActive = 1;

        UPDATE m SET m.TrainerID = NULL
        FROM Members m
        JOIN Trainers t ON t.TrainerID = m.TrainerID
        WHERE t.StaffID = @StaffID;
    END
    /* @IsTrainer NULL = leave the tag untouched */
END;
GO

/* ---------- Soft delete: also drop the trainer tag ----------------- */

CREATE OR ALTER PROCEDURE sp_Staff_SoftDelete
    @StaffID INT, @DeletedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE Staff SET IsDeleted = 1, Status = 'Terminated', UpdatedBy = @DeletedBy, UpdatedAt = SYSUTCDATETIME()
     WHERE StaffID = @StaffID;

    UPDATE Trainers SET IsActive = 0 WHERE StaffID = @StaffID AND IsActive = 1;

    UPDATE m SET m.TrainerID = NULL
    FROM Members m
    JOIN Trainers t ON t.TrainerID = m.TrainerID
    WHERE t.StaffID = @StaffID;
END;
GO

/* ---------- Trainer dropdown list (staff tagged as trainer) -------- */

CREATE OR ALTER PROCEDURE sp_Staff_ListTrainers
    @BranchID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  t.TrainerID, t.StaffID, t.Specialization, t.Experience,
            s.FullName AS StaffName, s.Mobile, s.Photo, s.Email, s.Designation,
            s.BranchID, b.Name AS BranchName,
            (SELECT COUNT(*) FROM Members m WHERE m.TrainerID = t.TrainerID AND m.IsDeleted = 0) AS AssignedMembers
    FROM    Trainers t
    JOIN    Staff s ON s.StaffID = t.StaffID AND s.IsDeleted = 0
    LEFT JOIN Branches b ON b.BranchID = s.BranchID
    WHERE   t.IsActive = 1
      AND   (@BranchID IS NULL OR s.BranchID = @BranchID)
    ORDER BY s.FullName;
END;
GO

/* ---------- Drop the old standalone trainer procedures ------------- */

DROP PROCEDURE IF EXISTS dbo.sp_Trainers_List;
DROP PROCEDURE IF EXISTS dbo.sp_Trainers_Get;
DROP PROCEDURE IF EXISTS dbo.sp_Trainers_GetMembers;
DROP PROCEDURE IF EXISTS dbo.sp_Trainers_Create;
DROP PROCEDURE IF EXISTS dbo.sp_Trainers_Update;
DROP PROCEDURE IF EXISTS dbo.sp_Trainers_Deactivate;
GO

/* ================================================================== */
/* PART 3 — PERMISSIONS: remove trainers.*, grant staff.view          */
/* ================================================================== */

-- Every role that could see trainers now sees the merged Staff page
INSERT INTO RolePermissions (RoleID, PermissionID)
SELECT rp.RoleID, p2.PermissionID
FROM RolePermissions rp
JOIN Permissions p  ON p.PermissionID  = rp.PermissionID AND p.Module = 'trainers'
JOIN Permissions p2 ON p2.Module = 'staff' AND p2.Action = 'view'
WHERE NOT EXISTS (
    SELECT 1 FROM RolePermissions x
    WHERE x.RoleID = rp.RoleID AND x.PermissionID = p2.PermissionID
);
GO

DELETE FROM RolePermissions
WHERE PermissionID IN (SELECT PermissionID FROM Permissions WHERE Module = 'trainers');
GO

DELETE FROM Permissions WHERE Module = 'trainers';
GO

/* ================================================================== */
/* PART 4 — MEMBERS HEIGHT COLUMNS ALIGNMENT (idempotent)             */
/* The live database already stores HeightFeet/HeightInches/Photo.
   Fresh installs made from the older 01_schema.sql used a single
   Height (cm) column — this block migrates it safely. It is a no-op
   when the columns already exist.                                    */
/* ================================================================== */

IF COL_LENGTH('dbo.Members', 'HeightFeet') IS NULL
   AND COL_LENGTH('dbo.Members', 'Height') IS NOT NULL
BEGIN
    -- dynamic SQL: Members.Height may not exist at batch compile time
    EXEC sp_executesql N'
        ALTER TABLE Members ADD HeightFeet TINYINT NULL, HeightInches TINYINT NULL;

        -- old column stored feet as decimal (e.g. 5.5) -> split into ft/in
        UPDATE Members
           SET HeightFeet   = CAST(FLOOR(Height) AS TINYINT),
               HeightInches = CAST(ROUND((Height - FLOOR(Height)) * 12, 0) AS TINYINT)
         WHERE Height IS NOT NULL;

        ALTER TABLE Members DROP COLUMN Height;';
    PRINT 'Members.Height migrated to HeightFeet/HeightInches.';
END
GO

/* ================================================================== */
/* VERIFY                                                             */
/* ================================================================== */

SELECT 'Remaining trainer SPs' AS CheckName, COUNT(*) AS [Value]
FROM sys.procedures WHERE name LIKE 'sp_Trainers%';
GO

SELECT 'Staff procedures' AS CheckName, COUNT(*) AS [Value]
FROM sys.procedures WHERE name LIKE 'sp_Staff%';
GO

SELECT 'trainers permissions left' AS CheckName, COUNT(*) AS [Value]
FROM Permissions WHERE Module = 'trainers';
GO

PRINT '=== Phase 9 changes applied successfully. ===';
GO

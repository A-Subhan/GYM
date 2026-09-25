/* ============================================================================
   CONTOURA LABS — GYM MANAGEMENT SYSTEM
   MASTER FILES + STAFF CODE (09_master_files_staff_code.sql)
   Run AFTER 08_phase9_changes.sql. Idempotent — safe to re-run.
   ----------------------------------------------------------------------------
   PART 1 — Member check-in validation (fixes raw FK error):
     sp_Attendance_CheckIn now verifies the member exists before insert.

   PART 2 — (moved to 10_master_files_module.sql)

   PART 3 — Staff changes:
     - Staff.StaffCode column, auto-generated as  "<BranchID>/0001"
       (0001 sequence per branch), backfilled for existing staff.
     - The "Tag as Trainer" checkbox is gone: trainer status now derives
       from the Designation (any designation containing 'trainer').
       sp_Staff_Create / sp_Staff_Update maintain the Trainers tag
       automatically from the designation.
   ============================================================================ */

USE GymDB;
GO

/* ================================================================== */
/* PART 1 — MEMBER CHECK-IN VALIDATION                                */
/* ================================================================== */

CREATE OR ALTER PROCEDURE sp_Attendance_CheckIn
    @MemberID INT, @BranchID INT, @Method NVARCHAR(20) = 'Manual',
    @IPAddress NVARCHAR(50) = NULL, @CreatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM Members WHERE MemberID = @MemberID AND IsDeleted = 0)
        THROW 50020, 'Member not found. Please select a valid member.', 1;

    INSERT INTO Attendance (MemberID, BranchID, CheckInTime, Method, IPAddress, CreatedBy)
    VALUES (@MemberID, @BranchID, SYSUTCDATETIME(), @Method, @IPAddress, @CreatedBy);

    SELECT CAST(SCOPE_IDENTITY() AS BIGINT) AS AttendanceID;
END;
GO

/* ================================================================== */
/* PART 2 — MASTER FILES                                              */
/* ================================================================== */

/* NOTE: the hard-coded Designations / Educations tables and their CRUD
   procedures that used to live here were replaced by the metadata-driven
   Master Files module — see 10_master_files_module.sql. */

/* ================================================================== */
/* PART 3 — STAFF CODE + DESIGNATION-DRIVEN TRAINER TAG               */
/* ================================================================== */

IF COL_LENGTH('dbo.Staff', 'StaffCode') IS NULL
    ALTER TABLE dbo.Staff ADD StaffCode NVARCHAR(20) NULL;
GO

/* Backfill existing staff: <BranchID>/0001, 0002 ... per branch */
;WITH s AS (
    SELECT StaffID, StaffCode, BranchID,
           ROW_NUMBER() OVER (PARTITION BY BranchID ORDER BY StaffID) AS rn
    FROM   Staff
    WHERE  StaffCode IS NULL
)
UPDATE s
   SET StaffCode = CAST(BranchID AS NVARCHAR(10)) + '/' + RIGHT('0000' + CAST(rn AS NVARCHAR(4)), 4);
GO

/* ---------- List: expose StaffCode --------------------------------- */

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

    SELECT  s.StaffID, s.StaffCode, s.FullName, s.FatherName, s.CNIC, s.Mobile, s.Email, s.Photo,
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
      AND   (@Search IS NULL OR s.FullName LIKE '%'+@Search+'%' OR s.CNIC LIKE '%'+@Search+'%' OR s.Mobile LIKE '%'+@Search+'%' OR s.StaffCode LIKE '%'+@Search+'%')
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
      AND   (@Search IS NULL OR s.FullName LIKE '%'+@Search+'%' OR s.CNIC LIKE '%'+@Search+'%' OR s.Mobile LIKE '%'+@Search+'%' OR s.StaffCode LIKE '%'+@Search+'%');
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

/* ---------- Create: staff code + designation-driven trainer tag ---- */

CREATE OR ALTER PROCEDURE sp_Staff_Create
    @BranchID INT, @DepartmentID INT, @UserID INT = NULL,
    @FullName NVARCHAR(150), @FatherName NVARCHAR(150) = NULL,
    @CNIC NVARCHAR(20) = NULL, @Mobile NVARCHAR(30) = NULL,
    @Email NVARCHAR(150) = NULL, @Address NVARCHAR(500) = NULL,
    @Photo NVARCHAR(500) = NULL, @JoiningDate DATE,
    @Designation NVARCHAR(30) = NULL, @BaseSalary DECIMAL(18,2) = 0,
    @Status NVARCHAR(20) = 'Active',
    @Specialization NVARCHAR(200) = NULL, @Experience NVARCHAR(100) = NULL,
    @CreatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @StaffID INT, @StaffCode NVARCHAR(20), @Seq INT;

    -- Staff code: <BranchID>/0001, sequence per branch
    SELECT @Seq = ISNULL(MAX(TRY_CAST(RIGHT(StaffCode, 4) AS INT)), 0) + 1
    FROM Staff
    WHERE BranchID = @BranchID AND StaffCode IS NOT NULL;

    SET @StaffCode = CAST(@BranchID AS NVARCHAR(10)) + '/' + RIGHT('0000' + CAST(@Seq AS NVARCHAR(4)), 4);

    INSERT INTO Staff (BranchID, DepartmentID, UserID, FullName, FatherName, CNIC, Mobile, Email,
                       Address, Photo, JoiningDate, Designation, BaseSalary, Status, StaffCode, CreatedBy)
    VALUES (@BranchID, @DepartmentID, @UserID, @FullName, @FatherName, @CNIC, @Mobile, @Email,
            @Address, @Photo, @JoiningDate, @Designation, @BaseSalary, @Status, @StaffCode, @CreatedBy);

    SET @StaffID = CAST(SCOPE_IDENTITY() AS INT);

    -- Trainer designation => tag as trainer
    IF @Designation IS NOT NULL AND UPPER(@Designation) LIKE '%TRAINER%'
        INSERT INTO Trainers (StaffID, Specialization, Experience, IsActive)
        VALUES (@StaffID, @Specialization, @Experience, 1);

    SELECT @StaffID AS StaffID, @StaffCode AS StaffCode;
END;
GO

/* ---------- Update: trainer tag follows the designation ------------ */

CREATE OR ALTER PROCEDURE sp_Staff_Update
    @StaffID INT, @BranchID INT = NULL, @DepartmentID INT = NULL,
    @UserID INT = NULL, @FullName NVARCHAR(150) = NULL, @FatherName NVARCHAR(150) = NULL,
    @CNIC NVARCHAR(20) = NULL, @Mobile NVARCHAR(30) = NULL, @Email NVARCHAR(150) = NULL,
    @Address NVARCHAR(500) = NULL, @Photo NVARCHAR(500) = NULL, @JoiningDate DATE = NULL,
    @Designation NVARCHAR(30) = NULL, @BaseSalary DECIMAL(18,2) = NULL,
    @Status NVARCHAR(20) = NULL,
    @Specialization NVARCHAR(200) = NULL, @Experience NVARCHAR(100) = NULL,
    @UpdatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @EffDesignation NVARCHAR(30);

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

    -- Effective designation after the update decides trainer status
    SELECT @EffDesignation = Designation FROM Staff WHERE StaffID = @StaffID;

    IF @EffDesignation IS NOT NULL AND UPPER(@EffDesignation) LIKE '%TRAINER%'
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
    ELSE
    BEGIN
        -- Not a trainer designation anymore: drop the tag + unassign members
        UPDATE Trainers SET IsActive = 0 WHERE StaffID = @StaffID AND IsActive = 1;

        UPDATE m SET m.TrainerID = NULL
        FROM Members m
        JOIN Trainers t ON t.TrainerID = m.TrainerID
        WHERE t.StaffID = @StaffID;
    END
END;
GO

/* ================================================================== */
/* VERIFY                                                             */
/* ================================================================== */

SELECT 'Staff with code' AS CheckName, COUNT(*) AS [Value] FROM Staff WHERE StaffCode IS NOT NULL
UNION ALL SELECT 'Staff total', COUNT(*) FROM Staff WHERE IsDeleted = 0;
GO

PRINT '=== Master files + staff code applied successfully. ===';
GO

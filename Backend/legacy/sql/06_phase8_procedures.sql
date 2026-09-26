/* ============================================================================
   CONTOURA LABS — GYM MANAGEMENT SYSTEM
   SQL Server 2022 — PHASE 8 STORED PROCEDURES (06_phase8_procedures.sql)
   ----------------------------------------------------------------------------
   Covers: Trainers, Staff, Payroll, WorkoutPlans, DietPlans, Progress,
           Equipment, Inventory, Suppliers, Notifications, Reports, Backup
   Run AFTER 01_schema.sql + 02_procedures.sql
   ============================================================================ */

USE GymDB;
GO

/* ================================================================== */
/* TRAINERS                                                            */
/* ================================================================== */

CREATE OR ALTER PROCEDURE sp_Trainers_List
    @BranchID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  t.TrainerID, t.StaffID, t.Specialization, t.Experience, t.IsActive,
            s.FullName AS StaffName, s.Phone, s.Photo, s.Email,
            s.BranchID, b.Name AS BranchName, s.Designation,
            (SELECT COUNT(*) FROM Members m WHERE m.TrainerID = t.TrainerID AND m.IsDeleted = 0) AS AssignedMembers
    FROM    Trainers t
    JOIN    Staff s ON s.StaffID = t.StaffID
    LEFT JOIN Branches b ON b.BranchID = s.BranchID
    WHERE   (@BranchID IS NULL OR s.BranchID = @BranchID)
    ORDER BY s.FullName;
END;
GO

CREATE OR ALTER PROCEDURE sp_Trainers_Get
    @TrainerID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  t.*, s.FullName AS StaffName, s.Phone, s.Photo, s.Email, s.Designation,
            s.BranchID, b.Name AS BranchName
    FROM    Trainers t
    JOIN    Staff s ON s.StaffID = t.StaffID
    LEFT JOIN Branches b ON b.BranchID = s.BranchID
    WHERE   t.TrainerID = @TrainerID;
END;
GO

CREATE OR ALTER PROCEDURE sp_Trainers_GetMembers
    @TrainerID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  MemberID, Code, FullName, Gender, Mobile, Photo, JoiningDate, Status,
            (SELECT TOP 1 EndDate FROM MemberMemberships mm WHERE mm.MemberID = m.MemberID AND mm.Status = 'Active' ORDER BY mm.MemberMembershipID DESC) AS MembershipEndDate
    FROM    Members m
    WHERE   m.TrainerID = @TrainerID AND m.IsDeleted = 0
    ORDER BY m.FullName;
END;
GO

CREATE OR ALTER PROCEDURE sp_Trainers_Create
    @StaffID INT, @Specialization NVARCHAR(200) = NULL,
    @Experience NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM Trainers WHERE StaffID = @StaffID)
    BEGIN
        -- Already a trainer, just update
        UPDATE Trainers
           SET Specialization = COALESCE(@Specialization, Specialization),
               Experience = COALESCE(@Experience, Experience),
               IsActive = 1
         WHERE StaffID = @StaffID;
        SELECT TrainerID FROM Trainers WHERE StaffID = @StaffID;
    END
    ELSE
    BEGIN
        INSERT INTO Trainers (StaffID, Specialization, Experience, IsActive)
        VALUES (@StaffID, @Specialization, @Experience, 1);
        SELECT CAST(SCOPE_IDENTITY() AS INT) AS TrainerID;
    END
END;
GO

CREATE OR ALTER PROCEDURE sp_Trainers_Update
    @TrainerID INT, @Specialization NVARCHAR(200) = NULL,
    @Experience NVARCHAR(100) = NULL, @IsActive BIT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE Trainers
       SET Specialization = COALESCE(@Specialization, Specialization),
           Experience     = COALESCE(@Experience, Experience),
           IsActive       = COALESCE(@IsActive, IsActive)
     WHERE TrainerID = @TrainerID;
END;
GO

CREATE OR ALTER PROCEDURE sp_Trainers_Deactivate
    @TrainerID INT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE Trainers SET IsActive = 0 WHERE TrainerID = @TrainerID;
    -- Unassign members from this trainer
    UPDATE Members SET TrainerID = NULL WHERE TrainerID = @TrainerID;
END;
GO

/* ================================================================== */
/* STAFF                                                               */
/* ================================================================== */

CREATE OR ALTER PROCEDURE sp_Departments_List
AS
BEGIN
    SET NOCOUNT ON;
    SELECT DepartmentID, Name, Description FROM Departments ORDER BY Name;
END;
GO

CREATE OR ALTER PROCEDURE sp_Staff_List
    @Page INT = 1,
    @PageSize INT = 20,
    @Search NVARCHAR(100) = NULL,
    @BranchID INT = NULL,
    @DepartmentID INT = NULL,
    @Status NVARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Offset INT = (@Page - 1) * @PageSize;

    SELECT  s.StaffID, s.FullName, s.FatherName, s.CNIC, s.Mobile, s.Email, s.Photo,
            s.JoiningDate, s.Designation, s.BaseSalary, s.Status,
            s.BranchID, b.Name AS BranchName,
            s.DepartmentID, d.Name AS DepartmentName,
            u.Username, u.UserID
    FROM    Staff s
    LEFT JOIN Branches b ON b.BranchID = s.BranchID
    LEFT JOIN Departments d ON d.DepartmentID = s.DepartmentID
    LEFT JOIN Users u ON u.UserID = s.UserID
    WHERE   s.IsDeleted = 0
      AND   (@BranchID IS NULL OR s.BranchID = @BranchID)
      AND   (@DepartmentID IS NULL OR s.DepartmentID = @DepartmentID)
      AND   (@Status IS NULL OR s.Status = @Status)
      AND   (@Search IS NULL OR s.FullName LIKE '%'+@Search+'%' OR s.CNIC LIKE '%'+@Search+'%' OR s.Mobile LIKE '%'+@Search+'%')
    ORDER BY s.StaffID DESC
    OFFSET  @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT  COUNT(*) AS Total
    FROM    Staff s
    WHERE   s.IsDeleted = 0
      AND   (@BranchID IS NULL OR s.BranchID = @BranchID)
      AND   (@DepartmentID IS NULL OR s.DepartmentID = @DepartmentID)
      AND   (@Status IS NULL OR s.Status = @Status)
      AND   (@Search IS NULL OR s.FullName LIKE '%'+@Search+'%' OR s.CNIC LIKE '%'+@Search+'%' OR s.Mobile LIKE '%'+@Search+'%');
END;
GO

CREATE OR ALTER PROCEDURE sp_Staff_Get
    @StaffID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  s.*, b.Name AS BranchName, d.Name AS DepartmentName, u.Username
    FROM    Staff s
    LEFT JOIN Branches b ON b.BranchID = s.BranchID
    LEFT JOIN Departments d ON d.DepartmentID = s.DepartmentID
    LEFT JOIN Users u ON u.UserID = s.UserID
    WHERE   s.StaffID = @StaffID AND s.IsDeleted = 0;
END;
GO

CREATE OR ALTER PROCEDURE sp_Staff_Create
    @BranchID INT, @DepartmentID INT, @UserID INT = NULL,
    @FullName NVARCHAR(150), @FatherName NVARCHAR(150) = NULL,
    @CNIC NVARCHAR(20) = NULL, @Mobile NVARCHAR(30) = NULL,
    @Email NVARCHAR(150) = NULL, @Address NVARCHAR(500) = NULL,
    @Photo NVARCHAR(500) = NULL, @JoiningDate DATE,
    @Designation NVARCHAR(100) = NULL, @BaseSalary DECIMAL(18,2) = 0,
    @Status NVARCHAR(20) = 'Active', @CreatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO Staff (BranchID, DepartmentID, UserID, FullName, FatherName, CNIC, Mobile, Email,
                       Address, Photo, JoiningDate, Designation, BaseSalary, Status, CreatedBy)
    VALUES (@BranchID, @DepartmentID, @UserID, @FullName, @FatherName, @CNIC, @Mobile, @Email,
            @Address, @Photo, @JoiningDate, @Designation, @BaseSalary, @Status, @CreatedBy);
    SELECT CAST(SCOPE_IDENTITY() AS INT) AS StaffID;
END;
GO

CREATE OR ALTER PROCEDURE sp_Staff_Update
    @StaffID INT, @BranchID INT = NULL, @DepartmentID INT = NULL,
    @UserID INT = NULL, @FullName NVARCHAR(150) = NULL, @FatherName NVARCHAR(150) = NULL,
    @CNIC NVARCHAR(20) = NULL, @Mobile NVARCHAR(30) = NULL, @Email NVARCHAR(150) = NULL,
    @Address NVARCHAR(500) = NULL, @Photo NVARCHAR(500) = NULL, @JoiningDate DATE = NULL,
    @Designation NVARCHAR(100) = NULL, @BaseSalary DECIMAL(18,2) = NULL,
    @Status NVARCHAR(20) = NULL, @UpdatedBy INT = NULL
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
END;
GO

CREATE OR ALTER PROCEDURE sp_Staff_SoftDelete
    @StaffID INT, @DeletedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE Staff SET IsDeleted = 1, Status = 'Terminated', UpdatedBy = @DeletedBy, UpdatedAt = SYSUTCDATETIME()
     WHERE StaffID = @StaffID;
END;
GO

/* Staff Attendance */
CREATE OR ALTER PROCEDURE sp_StaffAttendance_List
    @StaffID INT = NULL,
    @FromDate DATE = NULL,
    @ToDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  sa.StaffAttendanceID, sa.StaffID, s.FullName AS StaffName,
            sa.[Date], sa.CheckIn, sa.CheckOut, sa.Status, sa.Notes
    FROM    StaffAttendance sa
    JOIN    Staff s ON s.StaffID = sa.StaffID
    WHERE   (@StaffID IS NULL OR sa.StaffID = @StaffID)
      AND   (@FromDate IS NULL OR sa.[Date] >= @FromDate)
      AND   (@ToDate IS NULL OR sa.[Date] <= @ToDate)
    ORDER BY sa.[Date] DESC;
END;
GO

CREATE OR ALTER PROCEDURE sp_StaffAttendance_Mark
    @StaffID INT, @Date DATE, @CheckIn DATETIME2 = NULL,
    @CheckOut DATETIME2 = NULL, @Status NVARCHAR(20) = 'Present',
    @Notes NVARCHAR(300) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM StaffAttendance WHERE StaffID = @StaffID AND [Date] = @Date)
    BEGIN
        UPDATE StaffAttendance
           SET CheckIn = COALESCE(@CheckIn, CheckIn),
               CheckOut = COALESCE(@CheckOut, CheckOut),
               Status = @Status,
               Notes = @Notes
         WHERE StaffID = @StaffID AND [Date] = @Date;
    END
    ELSE
    BEGIN
        INSERT INTO StaffAttendance (StaffID, [Date], CheckIn, CheckOut, Status, Notes)
        VALUES (@StaffID, @Date, @CheckIn, @CheckOut, @Status, @Notes);
    END
END;
GO

/* Staff Leaves */
CREATE OR ALTER PROCEDURE sp_StaffLeaves_List
    @StaffID INT = NULL,
    @Status NVARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  l.LeaveID, l.StaffID, s.FullName AS StaffName,
            l.LeaveType, l.StartDate, l.EndDate, l.Reason, l.Status, l.CreatedAt
    FROM    StaffLeaves l
    JOIN    Staff s ON s.StaffID = l.StaffID
    WHERE   (@StaffID IS NULL OR l.StaffID = @StaffID)
      AND   (@Status IS NULL OR l.Status = @Status)
    ORDER BY l.LeaveID DESC;
END;
GO

CREATE OR ALTER PROCEDURE sp_StaffLeaves_Create
    @StaffID INT, @LeaveType NVARCHAR(30), @StartDate DATE,
    @EndDate DATE, @Reason NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO StaffLeaves (StaffID, LeaveType, StartDate, EndDate, Reason, Status)
    VALUES (@StaffID, @LeaveType, @StartDate, @EndDate, @Reason, 'Pending');
    SELECT CAST(SCOPE_IDENTITY() AS INT) AS LeaveID;
END;
GO

CREATE OR ALTER PROCEDURE sp_StaffLeaves_UpdateStatus
    @LeaveID INT, @Status NVARCHAR(20), @ApprovedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE StaffLeaves
       SET Status = @Status,
           ApprovedBy = @ApprovedBy
     WHERE LeaveID = @LeaveID;
END;
GO

/* ================================================================== */
/* PAYROLL                                                             */
/* ================================================================== */

CREATE OR ALTER PROCEDURE sp_Payroll_List
    @Page INT = 1,
    @PageSize INT = 20,
    @StaffID INT = NULL,
    @BranchID INT = NULL,
    @Month INT = NULL,
    @Year INT = NULL,
    @Status NVARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Offset INT = (@Page - 1) * @PageSize;

    SELECT  p.PayrollID, p.StaffID, s.FullName AS StaffName,
            s.Designation, d.Name AS DepartmentName,
            p.[Month], p.[Year], p.BaseSalary, p.Bonus, p.Overtime,
            p.LeaveDeduction, p.Commission, p.NetSalary, p.Status,
            p.GeneratedAt, p.PaidAt
    FROM    Payroll p
    JOIN    Staff s ON s.StaffID = p.StaffID
    LEFT JOIN Departments d ON d.DepartmentID = s.DepartmentID
    WHERE   (@StaffID IS NULL OR p.StaffID = @StaffID)
      AND   (@BranchID IS NULL OR p.BranchID = @BranchID)
      AND   (@Month IS NULL OR p.[Month] = @Month)
      AND   (@Year IS NULL OR p.[Year] = @Year)
      AND   (@Status IS NULL OR p.Status = @Status)
    ORDER BY p.[Year] DESC, p.[Month] DESC, p.PayrollID DESC
    OFFSET  @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT  COUNT(*) AS Total, ISNULL(SUM(NetSalary),0) AS TotalNet
    FROM    Payroll p
    WHERE   (@StaffID IS NULL OR p.StaffID = @StaffID)
      AND   (@BranchID IS NULL OR p.BranchID = @BranchID)
      AND   (@Month IS NULL OR p.[Month] = @Month)
      AND   (@Year IS NULL OR p.[Year] = @Year)
      AND   (@Status IS NULL OR p.Status = @Status);
END;
GO

CREATE OR ALTER PROCEDURE sp_Payroll_Get
    @PayrollID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  p.*, s.FullName AS StaffName, s.Designation, s.CNIC, s.Mobile,
            d.Name AS DepartmentName, b.Name AS BranchName
    FROM    Payroll p
    JOIN    Staff s ON s.StaffID = p.StaffID
    LEFT JOIN Departments d ON d.DepartmentID = s.DepartmentID
    LEFT JOIN Branches b ON b.BranchID = p.BranchID
    WHERE   p.PayrollID = @PayrollID;
END;
GO

CREATE OR ALTER PROCEDURE sp_Payroll_Generate
    @StaffID INT, @Month INT, @Year INT,
    @Bonus DECIMAL(18,2) = 0, @Overtime DECIMAL(18,2) = 0,
    @LeaveDeduction DECIMAL(18,2) = 0, @Commission DECIMAL(18,2) = 0,
    @GeneratedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Base DECIMAL(18,2), @BranchID INT, @Net DECIMAL(18,2);
    SELECT @Base = BaseSalary, @BranchID = BranchID FROM Staff WHERE StaffID = @StaffID;
    SET @Net = @Base + @Bonus + @Overtime + @Commission - @LeaveDeduction;

    IF EXISTS (SELECT 1 FROM Payroll WHERE StaffID = @StaffID AND [Month] = @Month AND [Year] = @Year)
    BEGIN
        UPDATE Payroll
           SET BaseSalary = @Base, Bonus = @Bonus, Overtime = @Overtime,
               LeaveDeduction = @LeaveDeduction, Commission = @Commission,
               NetSalary = @Net, GeneratedBy = @GeneratedBy, GeneratedAt = SYSUTCDATETIME()
         WHERE StaffID = @StaffID AND [Month] = @Month AND [Year] = @Year;
        SELECT PayrollID FROM Payroll WHERE StaffID = @StaffID AND [Month] = @Month AND [Year] = @Year;
    END
    ELSE
    BEGIN
        INSERT INTO Payroll (StaffID, BranchID, [Month], [Year], BaseSalary, Bonus, Overtime,
                             LeaveDeduction, Commission, NetSalary, Status, GeneratedBy)
        VALUES (@StaffID, @BranchID, @Month, @Year, @Base, @Bonus, @Overtime,
                @LeaveDeduction, @Commission, @Net, 'Generated', @GeneratedBy);
        SELECT CAST(SCOPE_IDENTITY() AS INT) AS PayrollID;
    END
END;
GO

CREATE OR ALTER PROCEDURE sp_Payroll_GenerateAll
    @Month INT, @Year INT, @BranchID INT = NULL,
    @Bonus DECIMAL(18,2) = 0, @Overtime DECIMAL(18,2) = 0,
    @LeaveDeduction DECIMAL(18,2) = 0, @Commission DECIMAL(18,2) = 0,
    @GeneratedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Inserted INT = 0;
    DECLARE staff_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT StaffID, BaseSalary, BranchID
        FROM   Staff
        WHERE  IsDeleted = 0 AND Status = 'Active'
          AND  (@BranchID IS NULL OR BranchID = @BranchID);

    DECLARE @SID INT, @Base DECIMAL(18,2), @BID INT, @Net DECIMAL(18,2);
    OPEN staff_cursor;
    FETCH NEXT FROM staff_cursor INTO @SID, @Base, @BID;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @Net = @Base + @Bonus + @Overtime + @Commission - @LeaveDeduction;
        IF NOT EXISTS (SELECT 1 FROM Payroll WHERE StaffID = @SID AND [Month] = @Month AND [Year] = @Year)
        BEGIN
            INSERT INTO Payroll (StaffID, BranchID, [Month], [Year], BaseSalary, Bonus, Overtime,
                                 LeaveDeduction, Commission, NetSalary, Status, GeneratedBy)
            VALUES (@SID, @BID, @Month, @Year, @Base, @Bonus, @Overtime,
                    @LeaveDeduction, @Commission, @Net, 'Generated', @GeneratedBy);
            SET @Inserted = @Inserted + 1;
        END
        FETCH NEXT FROM staff_cursor INTO @SID, @Base, @BID;
    END
    CLOSE staff_cursor;
    DEALLOCATE staff_cursor;
    SELECT @Inserted AS InsertedCount;
END;
GO

CREATE OR ALTER PROCEDURE sp_Payroll_MarkPaid
    @PayrollID INT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE Payroll SET Status = 'Paid', PaidAt = SYSUTCDATETIME()
     WHERE PayrollID = @PayrollID;
END;
GO

CREATE OR ALTER PROCEDURE sp_Payroll_Update
    @PayrollID INT, @Bonus DECIMAL(18,2) = NULL, @Overtime DECIMAL(18,2) = NULL,
    @LeaveDeduction DECIMAL(18,2) = NULL, @Commission DECIMAL(18,2) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE Payroll
       SET Bonus = COALESCE(@Bonus, Bonus),
           Overtime = COALESCE(@Overtime, Overtime),
           LeaveDeduction = COALESCE(@LeaveDeduction, LeaveDeduction),
           Commission = COALESCE(@Commission, Commission),
           NetSalary = BaseSalary + COALESCE(@Bonus, Bonus) + COALESCE(@Overtime, Overtime)
                       + COALESCE(@Commission, Commission) - COALESCE(@LeaveDeduction, LeaveDeduction)
     WHERE PayrollID = @PayrollID;
END;
GO

/* ================================================================== */
/* WORKOUT PLANS                                                       */
/* ================================================================== */

CREATE OR ALTER PROCEDURE sp_WorkoutPlans_List
    @TrainerID INT = NULL,
    @MemberID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  wp.PlanID, wp.TrainerID, wp.MemberID, wp.Title, wp.DayOfWeek,
            wp.StartDate, wp.EndDate, wp.Notes, wp.CreatedAt,
            s.FullName AS TrainerName, m.FullName AS MemberName, m.Code AS MemberCode
    FROM    WorkoutPlans wp
    LEFT JOIN Trainers t ON t.TrainerID = wp.TrainerID
    LEFT JOIN Staff s ON s.StaffID = t.StaffID
    LEFT JOIN Members m ON m.MemberID = wp.MemberID
    WHERE   (@TrainerID IS NULL OR wp.TrainerID = @TrainerID)
      AND   (@MemberID IS NULL OR wp.MemberID = @MemberID)
    ORDER BY wp.PlanID DESC;
END;
GO

CREATE OR ALTER PROCEDURE sp_WorkoutPlans_Get
    @PlanID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  wp.*, s.FullName AS TrainerName, m.FullName AS MemberName, m.Code AS MemberCode
    FROM    WorkoutPlans wp
    LEFT JOIN Trainers t ON t.TrainerID = wp.TrainerID
    LEFT JOIN Staff s ON s.StaffID = t.StaffID
    LEFT JOIN Members m ON m.MemberID = wp.MemberID
    WHERE   wp.PlanID = @PlanID;

    SELECT  ItemID, PlanID, Exercise, [Sets], Reps, Weight, RestPeriod, Notes, SortOrder
    FROM    WorkoutPlanItems
    WHERE   PlanID = @PlanID
    ORDER BY SortOrder, ItemID;
END;
GO

CREATE OR ALTER PROCEDURE sp_WorkoutPlans_Create
    @TrainerID INT, @MemberID INT, @Title NVARCHAR(200),
    @DayOfWeek NVARCHAR(20) = NULL, @StartDate DATE = NULL,
    @EndDate DATE = NULL, @Notes NVARCHAR(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO WorkoutPlans (TrainerID, MemberID, Title, DayOfWeek, StartDate, EndDate, Notes)
    VALUES (@TrainerID, @MemberID, @Title, @DayOfWeek, @StartDate, @EndDate, @Notes);
    SELECT CAST(SCOPE_IDENTITY() AS INT) AS PlanID;
END;
GO

CREATE OR ALTER PROCEDURE sp_WorkoutPlans_Update
    @PlanID INT, @Title NVARCHAR(200) = NULL, @DayOfWeek NVARCHAR(20) = NULL,
    @StartDate DATE = NULL, @EndDate DATE = NULL, @Notes NVARCHAR(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE WorkoutPlans
       SET Title = COALESCE(@Title, Title),
           DayOfWeek = COALESCE(@DayOfWeek, DayOfWeek),
           StartDate = COALESCE(@StartDate, StartDate),
           EndDate = COALESCE(@EndDate, EndDate),
           Notes = COALESCE(@Notes, Notes),
           UpdatedAt = SYSUTCDATETIME()
     WHERE PlanID = @PlanID;
END;
GO

CREATE OR ALTER PROCEDURE sp_WorkoutPlans_Delete
    @PlanID INT
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM WorkoutPlanItems WHERE PlanID = @PlanID;
    DELETE FROM WorkoutPlans WHERE PlanID = @PlanID;
END;
GO

CREATE OR ALTER PROCEDURE sp_WorkoutPlanItems_Add
    @PlanID INT, @Exercise NVARCHAR(200), @Sets INT = NULL,
    @Reps NVARCHAR(20) = NULL, @Weight NVARCHAR(50) = NULL,
    @RestPeriod NVARCHAR(20) = NULL, @Notes NVARCHAR(500) = NULL,
    @SortOrder INT = 0
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO WorkoutPlanItems (PlanID, Exercise, [Sets], Reps, Weight, RestPeriod, Notes, SortOrder)
    VALUES (@PlanID, @Exercise, @Sets, @Reps, @Weight, @RestPeriod, @Notes, @SortOrder);
    SELECT CAST(SCOPE_IDENTITY() AS INT) AS ItemID;
END;
GO

CREATE OR ALTER PROCEDURE sp_WorkoutPlanItems_Update
    @ItemID INT, @Exercise NVARCHAR(200) = NULL, @Sets INT = NULL,
    @Reps NVARCHAR(20) = NULL, @Weight NVARCHAR(50) = NULL,
    @RestPeriod NVARCHAR(20) = NULL, @Notes NVARCHAR(500) = NULL,
    @SortOrder INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE WorkoutPlanItems
       SET Exercise = COALESCE(@Exercise, Exercise),
           [Sets] = COALESCE(@Sets, [Sets]),
           Reps = COALESCE(@Reps, Reps),
           Weight = COALESCE(@Weight, Weight),
           RestPeriod = COALESCE(@RestPeriod, RestPeriod),
           Notes = COALESCE(@Notes, Notes),
           SortOrder = COALESCE(@SortOrder, SortOrder)
     WHERE ItemID = @ItemID;
END;
GO

CREATE OR ALTER PROCEDURE sp_WorkoutPlanItems_Delete
    @ItemID INT
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM WorkoutPlanItems WHERE ItemID = @ItemID;
END;
GO

/* ================================================================== */
/* DIET PLANS                                                          */
/* ================================================================== */

CREATE OR ALTER PROCEDURE sp_DietPlans_List
    @TrainerID INT = NULL,
    @MemberID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  dp.PlanID, dp.TrainerID, dp.MemberID, dp.Title, dp.StartDate, dp.EndDate,
            dp.Notes, dp.CreatedAt, s.FullName AS TrainerName, m.FullName AS MemberName, m.Code AS MemberCode
    FROM    DietPlans dp
    LEFT JOIN Trainers t ON t.TrainerID = dp.TrainerID
    LEFT JOIN Staff s ON s.StaffID = t.StaffID
    LEFT JOIN Members m ON m.MemberID = dp.MemberID
    WHERE   (@TrainerID IS NULL OR dp.TrainerID = @TrainerID)
      AND   (@MemberID IS NULL OR dp.MemberID = @MemberID)
    ORDER BY dp.PlanID DESC;
END;
GO

CREATE OR ALTER PROCEDURE sp_DietPlans_Get
    @PlanID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  dp.*, s.FullName AS TrainerName, m.FullName AS MemberName, m.Code AS MemberCode
    FROM    DietPlans dp
    LEFT JOIN Trainers t ON t.TrainerID = dp.TrainerID
    LEFT JOIN Staff s ON s.StaffID = t.StaffID
    LEFT JOIN Members m ON m.MemberID = dp.MemberID
    WHERE   dp.PlanID = @PlanID;

    SELECT  ItemID, PlanID, Meal, Food, Calories, Protein, Carbs, Fat, Notes, SortOrder
    FROM    DietPlanItems
    WHERE   PlanID = @PlanID
    ORDER BY SortOrder, ItemID;
END;
GO

CREATE OR ALTER PROCEDURE sp_DietPlans_Create
    @TrainerID INT, @MemberID INT, @Title NVARCHAR(200),
    @StartDate DATE = NULL, @EndDate DATE = NULL,
    @Notes NVARCHAR(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO DietPlans (TrainerID, MemberID, Title, StartDate, EndDate, Notes)
    VALUES (@TrainerID, @MemberID, @Title, @StartDate, @EndDate, @Notes);
    SELECT CAST(SCOPE_IDENTITY() AS INT) AS PlanID;
END;
GO

CREATE OR ALTER PROCEDURE sp_DietPlans_Update
    @PlanID INT, @Title NVARCHAR(200) = NULL, @StartDate DATE = NULL,
    @EndDate DATE = NULL, @Notes NVARCHAR(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE DietPlans
       SET Title = COALESCE(@Title, Title),
           StartDate = COALESCE(@StartDate, StartDate),
           EndDate = COALESCE(@EndDate, EndDate),
           Notes = COALESCE(@Notes, Notes)
     WHERE PlanID = @PlanID;
END;
GO

CREATE OR ALTER PROCEDURE sp_DietPlans_Delete
    @PlanID INT
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM DietPlanItems WHERE PlanID = @PlanID;
    DELETE FROM DietPlans WHERE PlanID = @PlanID;
END;
GO

CREATE OR ALTER PROCEDURE sp_DietPlanItems_Add
    @PlanID INT, @Meal NVARCHAR(50), @Food NVARCHAR(300),
    @Calories DECIMAL(10,2) = NULL, @Protein DECIMAL(10,2) = NULL,
    @Carbs DECIMAL(10,2) = NULL, @Fat DECIMAL(10,2) = NULL,
    @Notes NVARCHAR(500) = NULL, @SortOrder INT = 0
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO DietPlanItems (PlanID, Meal, Food, Calories, Protein, Carbs, Fat, Notes, SortOrder)
    VALUES (@PlanID, @Meal, @Food, @Calories, @Protein, @Carbs, @Fat, @Notes, @SortOrder);
    SELECT CAST(SCOPE_IDENTITY() AS INT) AS ItemID;
END;
GO

CREATE OR ALTER PROCEDURE sp_DietPlanItems_Delete
    @ItemID INT
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM DietPlanItems WHERE ItemID = @ItemID;
END;
GO

/* ================================================================== */
/* PROGRESS TRACKING                                                   */
/* ================================================================== */

CREATE OR ALTER PROCEDURE sp_Progress_List
    @MemberID INT = NULL,
    @Page INT = 1,
    @PageSize INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Offset INT = (@Page - 1) * @PageSize;
    SELECT  p.ProgressID, p.MemberID, m.FullName AS MemberName, m.Code AS MemberCode,
            p.[Date], p.Weight, p.BMI, p.BodyFat, p.Waist, p.Chest, p.Arms, p.Legs,
            p.Notes, p.CreatedAt
    FROM    ProgressTracking p
    JOIN    Members m ON m.MemberID = p.MemberID
    WHERE   (@MemberID IS NULL OR p.MemberID = @MemberID)
    ORDER BY p.[Date] DESC, p.ProgressID DESC
    OFFSET  @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT COUNT(*) AS Total
    FROM   ProgressTracking p
    WHERE  (@MemberID IS NULL OR p.MemberID = @MemberID);
END;
GO

CREATE OR ALTER PROCEDURE sp_Progress_Create
    @MemberID INT, @Date DATE,
    @Weight DECIMAL(5,2) = NULL, @BMI DECIMAL(5,2) = NULL,
    @BodyFat DECIMAL(5,2) = NULL, @Waist DECIMAL(5,2) = NULL,
    @Chest DECIMAL(5,2) = NULL, @Arms DECIMAL(5,2) = NULL,
    @Legs DECIMAL(5,2) = NULL, @Notes NVARCHAR(1000) = NULL,
    @CreatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO ProgressTracking (MemberID, [Date], Weight, BMI, BodyFat, Waist, Chest, Arms, Legs, Notes, CreatedBy)
    VALUES (@MemberID, @Date, @Weight, @BMI, @BodyFat, @Waist, @Chest, @Arms, @Legs, @Notes, @CreatedBy);
    SELECT CAST(SCOPE_IDENTITY() AS INT) AS ProgressID;
END;
GO

CREATE OR ALTER PROCEDURE sp_Progress_Update
    @ProgressID INT, @Date DATE = NULL,
    @Weight DECIMAL(5,2) = NULL, @BMI DECIMAL(5,2) = NULL,
    @BodyFat DECIMAL(5,2) = NULL, @Waist DECIMAL(5,2) = NULL,
    @Chest DECIMAL(5,2) = NULL, @Arms DECIMAL(5,2) = NULL,
    @Legs DECIMAL(5,2) = NULL, @Notes NVARCHAR(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE ProgressTracking
       SET [Date] = COALESCE(@Date, [Date]),
           Weight = COALESCE(@Weight, Weight),
           BMI = COALESCE(@BMI, BMI),
           BodyFat = COALESCE(@BodyFat, BodyFat),
           Waist = COALESCE(@Waist, Waist),
           Chest = COALESCE(@Chest, Chest),
           Arms = COALESCE(@Arms, Arms),
           Legs = COALESCE(@Legs, Legs),
           Notes = COALESCE(@Notes, Notes)
     WHERE ProgressID = @ProgressID;
END;
GO

CREATE OR ALTER PROCEDURE sp_Progress_Delete
    @ProgressID INT
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM ProgressPhotos WHERE ProgressID = @ProgressID;
    DELETE FROM ProgressTracking WHERE ProgressID = @ProgressID;
END;
GO

CREATE OR ALTER PROCEDURE sp_ProgressPhotos_Add
    @ProgressID INT, @FilePath NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO ProgressPhotos (ProgressID, FilePath)
    VALUES (@ProgressID, @FilePath);
    SELECT CAST(SCOPE_IDENTITY() AS INT) AS PhotoID;
END;
GO

CREATE OR ALTER PROCEDURE sp_ProgressPhotos_List
    @ProgressID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT PhotoID, FilePath, TakenAt FROM ProgressPhotos WHERE ProgressID = @ProgressID ORDER BY PhotoID;
END;
GO

CREATE OR ALTER PROCEDURE sp_Progress_Chart
    @MemberID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  [Date], Weight, BMI, BodyFat, Waist, Chest, Arms, Legs
    FROM    ProgressTracking
    WHERE   MemberID = @MemberID
    ORDER BY [Date] ASC;
END;
GO

/* ================================================================== */
/* EQUIPMENT                                                           */
/* ================================================================== */

CREATE OR ALTER PROCEDURE sp_Equipment_List
    @Page INT = 1,
    @PageSize INT = 50,
    @BranchID INT = NULL,
    @Status NVARCHAR(20) = NULL,
    @Search NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Offset INT = (@Page - 1) * @PageSize;

    SELECT  e.EquipmentID, e.BranchID, b.Name AS BranchName, e.Name, e.Brand,
            e.SerialNo, e.PurchaseDate, e.PurchasePrice, e.WarrantyExpiry,
            e.Status, e.Notes
    FROM    Equipment e
    LEFT JOIN Branches b ON b.BranchID = e.BranchID
    WHERE   e.IsDeleted = 0
      AND   (@BranchID IS NULL OR e.BranchID = @BranchID)
      AND   (@Status IS NULL OR e.Status = @Status)
      AND   (@Search IS NULL OR e.Name LIKE '%'+@Search+'%' OR e.Brand LIKE '%'+@Search+'%' OR e.SerialNo LIKE '%'+@Search+'%')
    ORDER BY e.EquipmentID DESC
    OFFSET  @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT  COUNT(*) AS Total,
            SUM(CASE WHEN Status='Active' THEN 1 ELSE 0 END) AS ActiveCount,
            SUM(CASE WHEN Status='Maintenance' THEN 1 ELSE 0 END) AS MaintenanceCount,
            SUM(CASE WHEN Status='Broken' THEN 1 ELSE 0 END) AS BrokenCount
    FROM    Equipment
    WHERE   IsDeleted = 0
      AND   (@BranchID IS NULL OR BranchID = @BranchID)
      AND   (@Status IS NULL OR Status = @Status)
      AND   (@Search IS NULL OR Name LIKE '%'+@Search+'%' OR Brand LIKE '%'+@Search+'%' OR SerialNo LIKE '%'+@Search+'%');
END;
GO

CREATE OR ALTER PROCEDURE sp_Equipment_Get
    @EquipmentID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  e.*, b.Name AS BranchName
    FROM    Equipment e
    LEFT JOIN Branches b ON b.BranchID = e.BranchID
    WHERE   e.EquipmentID = @EquipmentID AND e.IsDeleted = 0;
END;
GO

CREATE OR ALTER PROCEDURE sp_Equipment_Create
    @BranchID INT, @Name NVARCHAR(200), @Brand NVARCHAR(100) = NULL,
    @SerialNo NVARCHAR(100) = NULL, @PurchaseDate DATE = NULL,
    @PurchasePrice DECIMAL(18,2) = NULL, @WarrantyExpiry DATE = NULL,
    @Status NVARCHAR(20) = 'Active', @Notes NVARCHAR(500) = NULL,
    @CreatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO Equipment (BranchID, Name, Brand, SerialNo, PurchaseDate, PurchasePrice,
                           WarrantyExpiry, Status, Notes, CreatedBy)
    VALUES (@BranchID, @Name, @Brand, @SerialNo, @PurchaseDate, @PurchasePrice,
            @WarrantyExpiry, @Status, @Notes, @CreatedBy);
    SELECT CAST(SCOPE_IDENTITY() AS INT) AS EquipmentID;
END;
GO

CREATE OR ALTER PROCEDURE sp_Equipment_Update
    @EquipmentID INT, @BranchID INT = NULL, @Name NVARCHAR(200) = NULL,
    @Brand NVARCHAR(100) = NULL, @SerialNo NVARCHAR(100) = NULL,
    @PurchaseDate DATE = NULL, @PurchasePrice DECIMAL(18,2) = NULL,
    @WarrantyExpiry DATE = NULL, @Status NVARCHAR(20) = NULL,
    @Notes NVARCHAR(500) = NULL, @UpdatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE Equipment
       SET BranchID = COALESCE(@BranchID, BranchID),
           Name = COALESCE(@Name, Name),
           Brand = COALESCE(@Brand, Brand),
           SerialNo = COALESCE(@SerialNo, SerialNo),
           PurchaseDate = COALESCE(@PurchaseDate, PurchaseDate),
           PurchasePrice = COALESCE(@PurchasePrice, PurchasePrice),
           WarrantyExpiry = COALESCE(@WarrantyExpiry, WarrantyExpiry),
           Status = COALESCE(@Status, Status),
           Notes = COALESCE(@Notes, Notes),
           UpdatedAt = SYSUTCDATETIME()
     WHERE EquipmentID = @EquipmentID;
END;
GO

CREATE OR ALTER PROCEDURE sp_Equipment_SoftDelete
    @EquipmentID INT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE Equipment SET IsDeleted = 1, UpdatedAt = SYSUTCDATETIME() WHERE EquipmentID = @EquipmentID;
END;
GO

CREATE OR ALTER PROCEDURE sp_EquipmentMaintenance_List
    @EquipmentID INT = NULL,
    @BranchID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  m.MaintID, m.EquipmentID, e.Name AS EquipmentName, e.Brand,
            m.Type, m.Cost, m.StartDate, m.EndDate, m.Notes, m.CreatedAt
    FROM    EquipmentMaintenance m
    JOIN    Equipment e ON e.EquipmentID = m.EquipmentID
    WHERE   (@EquipmentID IS NULL OR m.EquipmentID = @EquipmentID)
      AND   (@BranchID IS NULL OR e.BranchID = @BranchID)
    ORDER BY m.MaintID DESC;
END;
GO

CREATE OR ALTER PROCEDURE sp_EquipmentMaintenance_Create
    @EquipmentID INT, @Type NVARCHAR(50) = 'Routine',
    @Cost DECIMAL(18,2) = 0, @StartDate DATE, @EndDate DATE = NULL,
    @Notes NVARCHAR(500) = NULL, @CreatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO EquipmentMaintenance (EquipmentID, Type, Cost, StartDate, EndDate, Notes, CreatedBy)
    VALUES (@EquipmentID, @Type, @Cost, @StartDate, @EndDate, @Notes, @CreatedBy);
    SELECT CAST(SCOPE_IDENTITY() AS INT) AS MaintID;
    -- If start date is today and no end date, mark equipment as Maintenance
    IF @EndDate IS NULL AND @StartDate = CAST(GETDATE() AS DATE)
    BEGIN
        UPDATE Equipment SET Status = 'Maintenance' WHERE EquipmentID = @EquipmentID;
    END
END;
GO

CREATE OR ALTER PROCEDURE sp_EquipmentMaintenance_Complete
    @MaintID INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @EID INT;
    SELECT @EID = EquipmentID FROM EquipmentMaintenance WHERE MaintID = @MaintID;
    UPDATE EquipmentMaintenance SET EndDate = CAST(GETDATE() AS DATE) WHERE MaintID = @MaintID;
    -- Restore equipment status to Active (if still broken/maintenance)
    UPDATE Equipment SET Status = 'Active' WHERE EquipmentID = @EID AND Status = 'Maintenance';
END;
GO

/* ================================================================== */
/* SUPPLIERS + INVENTORY                                               */
/* ================================================================== */

CREATE OR ALTER PROCEDURE sp_Suppliers_List
    @IsActive BIT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT SupplierID, Name, Contact, Phone, Email, Address, IsActive, CreatedAt
    FROM   Suppliers
    WHERE  (@IsActive IS NULL OR IsActive = @IsActive)
    ORDER BY Name;
END;
GO

CREATE OR ALTER PROCEDURE sp_Suppliers_Create
    @Name NVARCHAR(150), @Contact NVARCHAR(100) = NULL,
    @Phone NVARCHAR(30) = NULL, @Email NVARCHAR(150) = NULL,
    @Address NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO Suppliers (Name, Contact, Phone, Email, Address, IsActive)
    VALUES (@Name, @Contact, @Phone, @Email, @Address, 1);
    SELECT CAST(SCOPE_IDENTITY() AS INT) AS SupplierID;
END;
GO

CREATE OR ALTER PROCEDURE sp_Suppliers_Update
    @SupplierID INT, @Name NVARCHAR(150) = NULL, @Contact NVARCHAR(100) = NULL,
    @Phone NVARCHAR(30) = NULL, @Email NVARCHAR(150) = NULL,
    @Address NVARCHAR(500) = NULL, @IsActive BIT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE Suppliers
       SET Name = COALESCE(@Name, Name),
           Contact = COALESCE(@Contact, Contact),
           Phone = COALESCE(@Phone, Phone),
           Email = COALESCE(@Email, Email),
           Address = COALESCE(@Address, Address),
           IsActive = COALESCE(@IsActive, IsActive)
     WHERE SupplierID = @SupplierID;
END;
GO

CREATE OR ALTER PROCEDURE sp_Suppliers_SoftDelete
    @SupplierID INT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE Suppliers SET IsActive = 0 WHERE SupplierID = @SupplierID;
END;
GO

CREATE OR ALTER PROCEDURE sp_Inventory_List
    @Page INT = 1,
    @PageSize INT = 50,
    @BranchID INT = NULL,
    @Category NVARCHAR(50) = NULL,
    @Search NVARCHAR(100) = NULL,
    @LowStockOnly BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Offset INT = (@Page - 1) * @PageSize;

    SELECT  i.ItemID, i.BranchID, b.Name AS BranchName, i.Name, i.Category, i.SKU,
            i.StockQty, i.ReorderLevel, i.SalePrice, i.PurchasePrice, i.IsActive,
            CASE WHEN i.StockQty <= i.ReorderLevel THEN 1 ELSE 0 END AS IsLowStock
    FROM    InventoryItems i
    LEFT JOIN Branches b ON b.BranchID = i.BranchID
    WHERE   i.IsDeleted = 0
      AND   (@BranchID IS NULL OR i.BranchID = @BranchID)
      AND   (@Category IS NULL OR i.Category = @Category)
      AND   (@Search IS NULL OR i.Name LIKE '%'+@Search+'%' OR i.SKU LIKE '%'+@Search+'%')
      AND   (@LowStockOnly = 0 OR i.StockQty <= i.ReorderLevel)
    ORDER BY i.ItemID DESC
    OFFSET  @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT  COUNT(*) AS Total,
            ISNULL(SUM(i.StockQty * i.PurchasePrice),0) AS InventoryValue,
            SUM(CASE WHEN i.StockQty <= i.ReorderLevel THEN 1 ELSE 0 END) AS LowStockCount
    FROM    InventoryItems i
    WHERE   i.IsDeleted = 0
      AND   (@BranchID IS NULL OR i.BranchID = @BranchID)
      AND   (@Category IS NULL OR i.Category = @Category)
      AND   (@Search IS NULL OR i.Name LIKE '%'+@Search+'%' OR i.SKU LIKE '%'+@Search+'%')
      AND   (@LowStockOnly = 0 OR i.StockQty <= i.ReorderLevel);
END;
GO

CREATE OR ALTER PROCEDURE sp_Inventory_Create
    @BranchID INT, @Name NVARCHAR(200), @Category NVARCHAR(50),
    @SKU NVARCHAR(50) = NULL, @StockQty DECIMAL(18,2) = 0,
    @ReorderLevel DECIMAL(18,2) = 0, @SalePrice DECIMAL(18,2) = 0,
    @PurchasePrice DECIMAL(18,2) = 0, @CreatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO InventoryItems (BranchID, Name, Category, SKU, StockQty, ReorderLevel,
                                 SalePrice, PurchasePrice, IsActive, CreatedBy)
    VALUES (@BranchID, @Name, @Category, @SKU, @StockQty, @ReorderLevel,
            @SalePrice, @PurchasePrice, 1, @CreatedBy);
    SELECT CAST(SCOPE_IDENTITY() AS INT) AS ItemID;
END;
GO

CREATE OR ALTER PROCEDURE sp_Inventory_Update
    @ItemID INT, @Name NVARCHAR(200) = NULL, @Category NVARCHAR(50) = NULL,
    @SKU NVARCHAR(50) = NULL, @StockQty DECIMAL(18,2) = NULL,
    @ReorderLevel DECIMAL(18,2) = NULL, @SalePrice DECIMAL(18,2) = NULL,
    @PurchasePrice DECIMAL(18,2) = NULL, @IsActive BIT = NULL,
    @UpdatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE InventoryItems
       SET Name = COALESCE(@Name, Name),
           Category = COALESCE(@Category, Category),
           SKU = COALESCE(@SKU, SKU),
           StockQty = COALESCE(@StockQty, StockQty),
           ReorderLevel = COALESCE(@ReorderLevel, ReorderLevel),
           SalePrice = COALESCE(@SalePrice, SalePrice),
           PurchasePrice = COALESCE(@PurchasePrice, PurchasePrice),
           IsActive = COALESCE(@IsActive, IsActive),
           UpdatedAt = SYSUTCDATETIME()
     WHERE ItemID = @ItemID;
END;
GO

CREATE OR ALTER PROCEDURE sp_Inventory_SoftDelete
    @ItemID INT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE InventoryItems SET IsDeleted = 1, IsActive = 0, UpdatedAt = SYSUTCDATETIME() WHERE ItemID = @ItemID;
END;
GO

CREATE OR ALTER PROCEDURE sp_InventoryTransactions_List
    @ItemID INT = NULL,
    @Type NVARCHAR(20) = NULL,
    @FromDate DATE = NULL,
    @ToDate DATE = NULL,
    @Page INT = 1,
    @PageSize INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Offset INT = (@Page - 1) * @PageSize;

    SELECT  t.TxnID, t.ItemID, i.Name AS ItemName, i.SKU,
            t.Type, t.Qty, t.UnitPrice, t.SupplierID, sup.Name AS SupplierName,
            t.TxnDate, t.Notes, t.CreatedAt
    FROM    InventoryTransactions t
    JOIN    InventoryItems i ON i.ItemID = t.ItemID
    LEFT JOIN Suppliers sup ON sup.SupplierID = t.SupplierID
    WHERE   (@ItemID IS NULL OR t.ItemID = @ItemID)
      AND   (@Type IS NULL OR t.Type = @Type)
      AND   (@FromDate IS NULL OR t.TxnDate >= @FromDate)
      AND   (@ToDate IS NULL OR t.TxnDate <= @ToDate)
    ORDER BY t.TxnID DESC
    OFFSET  @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT  COUNT(*) AS Total,
            ISNULL(SUM(CASE WHEN Type='Sale' THEN Qty * UnitPrice ELSE 0 END),0) AS TotalSalesValue,
            ISNULL(SUM(CASE WHEN Type='Purchase' THEN Qty * UnitPrice ELSE 0 END),0) AS TotalPurchaseValue
    FROM    InventoryTransactions t
    WHERE   (@ItemID IS NULL OR t.ItemID = @ItemID)
      AND   (@Type IS NULL OR t.Type = @Type)
      AND   (@FromDate IS NULL OR t.TxnDate >= @FromDate)
      AND   (@ToDate IS NULL OR t.TxnDate <= @ToDate);
END;
GO

CREATE OR ALTER PROCEDURE sp_InventoryTransactions_Create
    @ItemID INT, @Type NVARCHAR(20), @Qty DECIMAL(18,2),
    @UnitPrice DECIMAL(18,2) = 0, @SupplierID INT = NULL,
    @TxnDate DATE = NULL, @Notes NVARCHAR(500) = NULL,
    @CreatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @TxnDate = COALESCE(@TxnDate, CAST(GETDATE() AS DATE));
    BEGIN TRAN;
    INSERT INTO InventoryTransactions (ItemID, Type, Qty, UnitPrice, SupplierID, TxnDate, Notes, CreatedBy)
    VALUES (@ItemID, @Type, @Qty, @UnitPrice, @SupplierID, @TxnDate, @Notes, @CreatedBy);
    DECLARE @NewID BIGINT = CAST(SCOPE_IDENTITY() AS BIGINT);

    -- Adjust stock
    IF @Type = 'Purchase'
        UPDATE InventoryItems SET StockQty = StockQty + @Qty WHERE ItemID = @ItemID;
    ELSE IF @Type = 'Sale'
        UPDATE InventoryItems SET StockQty = StockQty - @Qty WHERE ItemID = @ItemID;
    ELSE IF @Type = 'Adjustment'
        UPDATE InventoryItems SET StockQty = StockQty + @Qty WHERE ItemID = @ItemID; -- +/-
    COMMIT TRAN;
    SELECT @NewID AS TxnID;
END;
GO

/* ================================================================== */
/* NOTIFICATIONS                                                       */
/* ================================================================== */

CREATE OR ALTER PROCEDURE sp_Notifications_List
    @UserID INT = NULL,
    @UnreadOnly BIT = 0,
    @Page INT = 1,
    @PageSize INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Offset INT = (@Page - 1) * @PageSize;

    SELECT  n.NotificationID, n.Type, n.Title, n.Message, n.UserID,
            n.EntityID, n.IsRead, n.CreatedAt,
            u.FullName AS UserName
    FROM    Notifications n
    LEFT JOIN Users u ON u.UserID = n.UserID
    WHERE   (@UserID IS NULL OR n.UserID = @UserID OR n.UserID IS NULL)
      AND   (@UnreadOnly = 0 OR n.IsRead = 0)
    ORDER BY n.NotificationID DESC
    OFFSET  @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT  COUNT(*) AS Total,
            SUM(CASE WHEN IsRead = 0 THEN 1 ELSE 0 END) AS UnreadCount
    FROM    Notifications
    WHERE   (@UserID IS NULL OR UserID = @UserID OR UserID IS NULL);
END;
GO

CREATE OR ALTER PROCEDURE sp_Notifications_MarkRead
    @NotificationID INT,
    @UserID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE Notifications
       SET IsRead = 1
     WHERE NotificationID = @NotificationID
       AND (@UserID IS NULL OR UserID = @UserID OR UserID IS NULL);
END;
GO

CREATE OR ALTER PROCEDURE sp_Notifications_MarkAllRead
    @UserID INT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE Notifications
       SET IsRead = 1
     WHERE (UserID = @UserID OR UserID IS NULL) AND IsRead = 0;
END;
GO

CREATE OR ALTER PROCEDURE sp_Notifications_Create
    @Type NVARCHAR(50), @Title NVARCHAR(200), @Message NVARCHAR(1000),
    @UserID INT = NULL, @EntityID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO Notifications (Type, Title, Message, UserID, EntityID, IsRead)
    VALUES (@Type, @Title, @Message, @UserID, @EntityID, 0);
    SELECT CAST(SCOPE_IDENTITY() AS BIGINT) AS NotificationID;
END;
GO

CREATE OR ALTER PROCEDURE sp_Notifications_Delete
    @NotificationID INT
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM Notifications WHERE NotificationID = @NotificationID;
END;
GO

/* ================================================================== */
/* REPORTS                                                             */
/* ================================================================== */

CREATE OR ALTER PROCEDURE sp_Reports_Members
    @BranchID INT = NULL,
    @Status NVARCHAR(20) = NULL,
    @FromDate DATE = NULL,
    @ToDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  m.Code, m.FullName, m.Gender, m.Mobile, m.Email, m.JoiningDate, m.Status,
            b.Name AS BranchName, m.MedicalNotes
    FROM    Members m
    LEFT JOIN Branches b ON b.BranchID = m.BranchID
    WHERE   m.IsDeleted = 0
      AND   (@BranchID IS NULL OR m.BranchID = @BranchID)
      AND   (@Status IS NULL OR m.Status = @Status)
      AND   (@FromDate IS NULL OR m.JoiningDate >= @FromDate)
      AND   (@ToDate IS NULL OR m.JoiningDate <= @ToDate)
    ORDER BY m.MemberID;
END;
GO

CREATE OR ALTER PROCEDURE sp_Reports_Attendance
    @BranchID INT = NULL,
    @FromDate DATE = NULL,
    @ToDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  CAST(a.CheckInTime AS DATE) AS [Date],
            COUNT(DISTINCT a.MemberID) AS UniqueMembers,
            COUNT(*) AS TotalCheckIns,
            b.Name AS BranchName
    FROM    Attendance a
    LEFT JOIN Branches b ON b.BranchID = a.BranchID
    WHERE   (@BranchID IS NULL OR a.BranchID = @BranchID)
      AND   (@FromDate IS NULL OR CAST(a.CheckInTime AS DATE) >= @FromDate)
      AND   (@ToDate IS NULL OR CAST(a.CheckInTime AS DATE) <= @ToDate)
    GROUP BY CAST(a.CheckInTime AS DATE), b.Name
    ORDER BY [Date] DESC;
END;
GO

CREATE OR ALTER PROCEDURE sp_Reports_Payments
    @BranchID INT = NULL,
    @FromDate DATE = NULL,
    @ToDate DATE = NULL,
    @MethodID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  fc.CollectionID, m.Code AS MemberCode, m.FullName AS MemberName,
            fc.Amount, pm.Name AS Method, fc.TransactionRef,
            fc.CollectedAt, b.Name AS BranchName, u.FullName AS CollectedBy
    FROM    FeeCollections fc
    JOIN    Members m ON m.MemberID = fc.MemberID
    JOIN    PaymentMethods pm ON pm.MethodID = fc.MethodID
    LEFT JOIN Branches b ON b.BranchID = fc.BranchID
    LEFT JOIN Users u ON u.UserID = fc.CollectedBy
    WHERE   fc.IsDeleted = 0
      AND   (@BranchID IS NULL OR fc.BranchID = @BranchID)
      AND   (@MethodID IS NULL OR fc.MethodID = @MethodID)
      AND   (@FromDate IS NULL OR CAST(fc.CollectedAt AS DATE) >= @FromDate)
      AND   (@ToDate IS NULL OR CAST(fc.CollectedAt AS DATE) <= @ToDate)
    ORDER BY fc.CollectedAt DESC;
END;
GO

CREATE OR ALTER PROCEDURE sp_Reports_Expenses
    @BranchID INT = NULL,
    @Category NVARCHAR(50) = NULL,
    @FromDate DATE = NULL,
    @ToDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  e.ExpenseID, e.Category, e.Amount, e.ExpenseDate, e.Notes,
            b.Name AS BranchName
    FROM    Expenses e
    LEFT JOIN Branches b ON b.BranchID = e.BranchID
    WHERE   e.IsDeleted = 0
      AND   (@BranchID IS NULL OR e.BranchID = @BranchID)
      AND   (@Category IS NULL OR e.Category = @Category)
      AND   (@FromDate IS NULL OR e.ExpenseDate >= @FromDate)
      AND   (@ToDate IS NULL OR e.ExpenseDate <= @ToDate)
    ORDER BY e.ExpenseDate DESC;
END;
GO

CREATE OR ALTER PROCEDURE sp_Reports_Income
    @BranchID INT = NULL,
    @CategoryID INT = NULL,
    @FromDate DATE = NULL,
    @ToDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  ir.IncomeID, ic.Name AS Category, ir.Source, ir.Amount, ir.IncomeDate,
            ir.Notes, b.Name AS BranchName
    FROM    IncomeRecords ir
    JOIN    IncomeCategories ic ON ic.CatID = ir.CategoryID
    LEFT JOIN Branches b ON b.BranchID = ir.BranchID
    WHERE   ir.IsDeleted = 0
      AND   (@BranchID IS NULL OR ir.BranchID = @BranchID)
      AND   (@CategoryID IS NULL OR ir.CategoryID = @CategoryID)
      AND   (@FromDate IS NULL OR ir.IncomeDate >= @FromDate)
      AND   (@ToDate IS NULL OR ir.IncomeDate <= @ToDate)
    ORDER BY ir.IncomeDate DESC;
END;
GO

CREATE OR ALTER PROCEDURE sp_Reports_Salary
    @BranchID INT = NULL,
    @Month INT = NULL,
    @Year INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  p.PayrollID, s.FullName AS StaffName, s.Designation,
            d.Name AS Department, p.[Month], p.[Year],
            p.BaseSalary, p.Bonus, p.Overtime, p.LeaveDeduction, p.Commission,
            p.NetSalary, p.Status, p.PaidAt
    FROM    Payroll p
    JOIN    Staff s ON s.StaffID = p.StaffID
    LEFT JOIN Departments d ON d.DepartmentID = s.DepartmentID
    WHERE   (@BranchID IS NULL OR p.BranchID = @BranchID)
      AND   (@Month IS NULL OR p.[Month] = @Month)
      AND   (@Year IS NULL OR p.[Year] = @Year)
    ORDER BY p.[Year] DESC, p.[Month] DESC, s.FullName;
END;
GO

CREATE OR ALTER PROCEDURE sp_Reports_Equipment
    @BranchID INT = NULL,
    @Status NVARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  e.Name, e.Brand, e.SerialNo, e.PurchaseDate, e.PurchasePrice,
            e.WarrantyExpiry, e.Status, b.Name AS BranchName,
            (SELECT ISNULL(SUM(Cost),0) FROM EquipmentMaintenance WHERE EquipmentID = e.EquipmentID) AS TotalMaintenanceCost,
            (SELECT COUNT(*) FROM EquipmentMaintenance WHERE EquipmentID = e.EquipmentID) AS MaintenanceCount
    FROM    Equipment e
    LEFT JOIN Branches b ON b.BranchID = e.BranchID
    WHERE   e.IsDeleted = 0
      AND   (@BranchID IS NULL OR e.BranchID = @BranchID)
      AND   (@Status IS NULL OR e.Status = @Status)
    ORDER BY e.Name;
END;
GO

CREATE OR ALTER PROCEDURE sp_Reports_Inventory
    @BranchID INT = NULL,
    @Category NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  i.Name, i.Category, i.SKU, i.StockQty, i.ReorderLevel,
            i.SalePrice, i.PurchasePrice,
            (i.StockQty * i.PurchasePrice) AS StockValue,
            (i.StockQty * i.SalePrice) AS RetailValue,
            b.Name AS BranchName,
            CASE WHEN i.StockQty <= i.ReorderLevel THEN 'Low' ELSE 'OK' END AS StockStatus
    FROM    InventoryItems i
    LEFT JOIN Branches b ON b.BranchID = i.BranchID
    WHERE   i.IsDeleted = 0
      AND   (@BranchID IS NULL OR i.BranchID = @BranchID)
      AND   (@Category IS NULL OR i.Category = @Category)
    ORDER BY i.Name;
END;
GO

CREATE OR ALTER PROCEDURE sp_Reports_ProfitLoss
    @BranchID INT = NULL,
    @FromDate DATE = NULL,
    @ToDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @FromDate = COALESCE(@FromDate, DATEADD(MONTH, -1, CAST(GETDATE() AS DATE)));
    SET @ToDate   = COALESCE(@ToDate, CAST(GETDATE() AS DATE));

    DECLARE @MembershipIncome DECIMAL(18,2), @OtherIncome DECIMAL(18,2), @TotalIncome DECIMAL(18,2);
    DECLARE @SalaryExp DECIMAL(18,2), @RentExp DECIMAL(18,2), @ElectricityExp DECIMAL(18,2);
    DECLARE @InternetExp DECIMAL(18,2), @WaterExp DECIMAL(18,2), @MaintenanceExp DECIMAL(18,2);
    DECLARE @MiscExp DECIMAL(18,2), @TotalExpenses DECIMAL(18,2), @NetProfit DECIMAL(18,2);

    SELECT @MembershipIncome = ISNULL(SUM(Amount),0) FROM FeeCollections
     WHERE CAST(CollectedAt AS DATE) BETWEEN @FromDate AND @ToDate AND IsDeleted = 0
       AND (@BranchID IS NULL OR BranchID = @BranchID);

    SELECT @OtherIncome = ISNULL(SUM(Amount),0) FROM IncomeRecords
     WHERE IncomeDate BETWEEN @FromDate AND @ToDate AND IsDeleted = 0
       AND (@BranchID IS NULL OR BranchID = @BranchID);

    SET @TotalIncome = @MembershipIncome + @OtherIncome;

    SELECT @SalaryExp     = ISNULL(SUM(CASE WHEN Category='Salary' THEN Amount ELSE 0 END),0),
           @RentExp       = ISNULL(SUM(CASE WHEN Category='Rent' THEN Amount ELSE 0 END),0),
           @ElectricityExp= ISNULL(SUM(CASE WHEN Category='Electricity' THEN Amount ELSE 0 END),0),
           @InternetExp   = ISNULL(SUM(CASE WHEN Category='Internet' THEN Amount ELSE 0 END),0),
           @WaterExp      = ISNULL(SUM(CASE WHEN Category='Water' THEN Amount ELSE 0 END),0),
           @MaintenanceExp= ISNULL(SUM(CASE WHEN Category='Maintenance' THEN Amount ELSE 0 END),0),
           @MiscExp       = ISNULL(SUM(CASE WHEN Category='Misc' THEN Amount ELSE 0 END),0)
    FROM   Expenses
    WHERE  ExpenseDate BETWEEN @FromDate AND @ToDate AND IsDeleted = 0
      AND  (@BranchID IS NULL OR BranchID = @BranchID);

    SET @TotalExpenses = @SalaryExp + @RentExp + @ElectricityExp + @InternetExp + @WaterExp + @MaintenanceExp + @MiscExp;
    SET @NetProfit = @TotalIncome - @TotalExpenses;

    SELECT  @FromDate AS FromDate, @ToDate AS ToDate,
            @MembershipIncome AS MembershipIncome, @OtherIncome AS OtherIncome,
            @TotalIncome AS TotalIncome,
            @SalaryExp AS Salary, @RentExp AS Rent, @ElectricityExp AS Electricity,
            @InternetExp AS Internet, @WaterExp AS Water, @MaintenanceExp AS Maintenance,
            @MiscExp AS Misc, @TotalExpenses AS TotalExpenses,
            @NetProfit AS NetProfit;
END;
GO

PRINT 'Phase 8 stored procedures created successfully.';
GO

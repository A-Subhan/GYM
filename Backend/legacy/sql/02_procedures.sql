/* ============================================================================
   CONTOURA LABS — GYM MANAGEMENT SYSTEM
   SQL Server 2022 — STORED PROCEDURES (02_procedures.sql)
   ----------------------------------------------------------------------------
   All app DB access is via these procedures (no inline SQL in the app).
   ============================================================================ */

USE GymDB;
GO

/* ------------------------------------------------------------------ */
/* AUTH                                                                */
/* ------------------------------------------------------------------ */

CREATE OR ALTER PROCEDURE sp_Users_GetByUsername
    @Username NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  u.*, r.Name AS RoleName
    FROM    Users u
    JOIN    Roles r ON r.RoleID = u.RoleID
    WHERE   LOWER(u.Username) = LOWER(@Username) AND u.IsDeleted = 0;
END;
GO

CREATE OR ALTER PROCEDURE sp_Users_GetByID
    @UserID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  u.UserID, u.Username, u.Email, u.FullName, u.Phone, u.Photo,
            u.IsActive, u.RoleID, r.Name AS RoleName, u.BranchID,
            u.LastLoginAt, u.CreatedAt
    FROM    Users u
    JOIN    Roles r ON r.RoleID = u.RoleID
    WHERE   u.UserID = @UserID AND u.IsDeleted = 0;
END;
GO

CREATE OR ALTER PROCEDURE sp_Users_List
    @Page INT = 1,
    @PageSize INT = 20,
    @Search NVARCHAR(100) = NULL,
    @RoleID INT = NULL,
    @BranchID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Offset INT = (@Page - 1) * @PageSize;

    SELECT  u.UserID, u.Username, u.Email, u.FullName, u.Phone, u.Photo,
            u.IsActive, u.RoleID, r.Name AS RoleName, u.BranchID,
            b.Name AS BranchName, u.LastLoginAt, u.CreatedAt
    FROM    Users u
    JOIN    Roles r ON r.RoleID = u.RoleID
    LEFT JOIN Branches b ON b.BranchID = u.BranchID
    WHERE   u.IsDeleted = 0
      AND   (@Search IS NULL OR u.Username LIKE '%'+@Search+'%' OR u.FullName LIKE '%'+@Search+'%' OR u.Email LIKE '%'+@Search+'%')
      AND   (@RoleID IS NULL OR u.RoleID = @RoleID)
      AND   (@BranchID IS NULL OR u.BranchID = @BranchID)
    ORDER BY u.UserID
    OFFSET  @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT  COUNT(*) AS Total
    FROM    Users u
    WHERE   u.IsDeleted = 0
      AND   (@Search IS NULL OR u.Username LIKE '%'+@Search+'%' OR u.FullName LIKE '%'+@Search+'%' OR u.Email LIKE '%'+@Search+'%')
      AND   (@RoleID IS NULL OR u.RoleID = @RoleID)
      AND   (@BranchID IS NULL OR u.BranchID = @BranchID);
END;
GO

CREATE OR ALTER PROCEDURE sp_Users_Create
    @Username NVARCHAR(50),
    @Email NVARCHAR(150),
    @FullName NVARCHAR(150),
    @PasswordHash NVARCHAR(255),
    @RoleID INT,
    @BranchID INT = NULL,
    @Phone NVARCHAR(30) = NULL,
    @Photo NVARCHAR(500) = NULL,
    @MustChangePassword BIT = 0,
    @CreatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO Users (Username, Email, FullName, PasswordHash, RoleID, BranchID, Phone, Photo, MustChangePassword, CreatedBy)
    VALUES (@Username, @Email, @FullName, @PasswordHash, @RoleID, @BranchID, @Phone, @Photo, @MustChangePassword, @CreatedBy);
    SELECT CAST(SCOPE_IDENTITY() AS INT) AS NewUserID;
END;
GO

CREATE OR ALTER PROCEDURE sp_Users_Update
    @UserID INT,
    @Email NVARCHAR(150) = NULL,
    @FullName NVARCHAR(150) = NULL,
    @RoleID INT = NULL,
    @BranchID INT = NULL,
    @Phone NVARCHAR(30) = NULL,
    @Photo NVARCHAR(500) = NULL,
    @IsActive BIT = NULL,
    @UpdatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE Users
       SET Email       = COALESCE(@Email, Email),
           FullName    = COALESCE(@FullName, FullName),
           RoleID      = COALESCE(@RoleID, RoleID),
           BranchID    = COALESCE(@BranchID, BranchID),
           Phone       = COALESCE(@Phone, Phone),
           Photo       = COALESCE(@Photo, Photo),
           IsActive    = COALESCE(@IsActive, IsActive),
           UpdatedBy   = @UpdatedBy,
           UpdatedAt   = SYSUTCDATETIME()
     WHERE UserID = @UserID;
END;
GO

CREATE OR ALTER PROCEDURE sp_Users_ChangePassword
    @UserID INT,
    @PasswordHash NVARCHAR(255),
    @MustChangePassword BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE Users
       SET PasswordHash = @PasswordHash,
           MustChangePassword = @MustChangePassword,
           UpdatedAt = SYSUTCDATETIME()
     WHERE UserID = @UserID;
END;
GO

CREATE OR ALTER PROCEDURE sp_Users_UpdateLogin
    @UserID INT,
    @IPAddress NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE Users
       SET LastLoginAt = SYSUTCDATETIME(),
           FailedLoginCount = 0
     WHERE UserID = @UserID;
END;
GO

CREATE OR ALTER PROCEDURE sp_Users_SoftDelete
    @UserID INT,
    @DeletedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE Users
       SET IsDeleted = 1, IsActive = 0, UpdatedBy = @DeletedBy, UpdatedAt = SYSUTCDATETIME()
     WHERE UserID = @UserID;
END;
GO

CREATE OR ALTER PROCEDURE sp_Users_GetPermissions
    @UserID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  DISTINCT p.PermissionID, p.Module, p.Action, p.Code
    FROM    Users u
    JOIN    RolePermissions rp ON rp.RoleID = u.RoleID
    JOIN    Permissions p      ON p.PermissionID = rp.PermissionID
    WHERE   u.UserID = @UserID;
END;
GO

/* ------------------------------------------------------------------ */
/* SESSIONS                                                            */
/* ------------------------------------------------------------------ */

CREATE OR ALTER PROCEDURE sp_Sessions_Create
    @UserID INT,
    @RefreshToken NVARCHAR(500),
    @IPAddress NVARCHAR(50) = NULL,
    @UserAgent NVARCHAR(500) = NULL,
    @Location NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO UserSessions (UserID, RefreshToken, IPAddress, UserAgent, Location, LoginAt, LastActivityAt, Status)
    VALUES (@UserID, @RefreshToken, @IPAddress, @UserAgent, @Location, SYSUTCDATETIME(), SYSUTCDATETIME(), 'Active');
    SELECT CAST(SCOPE_IDENTITY() AS BIGINT) AS SessionID;
END;
GO

CREATE OR ALTER PROCEDURE sp_Sessions_Logout
    @RefreshToken NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE UserSessions
       SET LogoutAt = SYSUTCDATETIME(),
           Status = 'LoggedOut',
           LastActivityAt = SYSUTCDATETIME()
     WHERE RefreshToken = @RefreshToken;
END;
GO

CREATE OR ALTER PROCEDURE sp_Sessions_Heartbeat
    @RefreshToken NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE UserSessions
       SET LastActivityAt = SYSUTCDATETIME()
     WHERE RefreshToken = @RefreshToken AND Status = 'Active';
END;
GO

CREATE OR ALTER PROCEDURE sp_Sessions_GetByToken
    @RefreshToken NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  s.*, u.UserID AS U_UserID, u.Username, u.FullName, u.RoleID, u.BranchID, u.IsActive
    FROM    UserSessions s
    JOIN    Users u ON u.UserID = s.UserID
    WHERE   s.RefreshToken = @RefreshToken;
END;
GO

CREATE OR ALTER PROCEDURE sp_Sessions_ListByUser
    @UserID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  SessionID, IPAddress, UserAgent, Location, LoginAt, LogoutAt, LastActivityAt, Status
    FROM    UserSessions
    WHERE   UserID = @UserID
    ORDER BY LoginAt DESC;
END;
GO

/* ------------------------------------------------------------------ */
/* AUDIT                                                               */
/* ------------------------------------------------------------------ */

CREATE OR ALTER PROCEDURE sp_AuditLog_Write
    @UserID INT = NULL,
    @Action NVARCHAR(50),
    @Module NVARCHAR(50),
    @EntityID INT = NULL,
    @Details NVARCHAR(MAX) = NULL,
    @IPAddress NVARCHAR(50) = NULL,
    @Location NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO AuditLogs (UserID, Action, Module, EntityID, Details, IPAddress, Location)
    VALUES (@UserID, @Action, @Module, @EntityID, @Details, @IPAddress, @Location);
END;
GO

CREATE OR ALTER PROCEDURE sp_AuditLogs_List
    @Page INT = 1,
    @PageSize INT = 50,
    @UserID INT = NULL,
    @Module NVARCHAR(50) = NULL,
    @Action NVARCHAR(50) = NULL,
    @FromDate DATETIME2 = NULL,
    @ToDate DATETIME2 = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Offset INT = (@Page - 1) * @PageSize;

    SELECT  a.LogID, a.UserID, u.FullName AS UserName, u.Username,
            a.Action, a.Module, a.EntityID, a.Details, a.IPAddress, a.Location, a.CreatedAt
    FROM    AuditLogs a
    LEFT JOIN Users u ON u.UserID = a.UserID
    WHERE   (@UserID IS NULL OR a.UserID = @UserID)
      AND   (@Module IS NULL OR a.Module = @Module)
      AND   (@Action IS NULL OR a.Action = @Action)
      AND   (@FromDate IS NULL OR a.CreatedAt >= @FromDate)
      AND   (@ToDate IS NULL OR a.CreatedAt <= @ToDate)
    ORDER BY a.LogID DESC
    OFFSET  @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT  COUNT(*) AS Total
    FROM    AuditLogs a
    WHERE   (@UserID IS NULL OR a.UserID = @UserID)
      AND   (@Module IS NULL OR a.Module = @Module)
      AND   (@Action IS NULL OR a.Action = @Action)
      AND   (@FromDate IS NULL OR a.CreatedAt >= @FromDate)
      AND   (@ToDate IS NULL OR a.CreatedAt <= @ToDate);
END;
GO

/* ------------------------------------------------------------------ */
/* ROLES & PERMISSIONS                                                 */
/* ------------------------------------------------------------------ */

CREATE OR ALTER PROCEDURE sp_Roles_List
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  RoleID, Name, Description, IsSystem, CreatedAt
    FROM    Roles
    ORDER BY RoleID;
END;
GO

CREATE OR ALTER PROCEDURE sp_Permissions_List
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  PermissionID, Module, Action, Code, Description
    FROM    Permissions
    ORDER BY Module, Action;
END;
GO

CREATE OR ALTER PROCEDURE sp_RolePermissions_Get
    @RoleID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  p.PermissionID, p.Module, p.Action, p.Code
    FROM    RolePermissions rp
    JOIN    Permissions p ON p.PermissionID = rp.PermissionID
    WHERE   rp.RoleID = @RoleID;
END;
GO

CREATE OR ALTER PROCEDURE sp_RolePermissions_Set
    @RoleID INT,
    @PermissionIDs VARCHAR(MAX)   -- CSV "1,2,3,4"
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRAN;
    DELETE FROM RolePermissions WHERE RoleID = @RoleID;

    IF @PermissionIDs IS NOT NULL AND LEN(@PermissionIDs) > 0
    BEGIN
        DECLARE @xml XML = CAST('<i>'+REPLACE(@PermissionIDs,',','</i><i>')+'</i>' AS XML);
        INSERT INTO RolePermissions (RoleID, PermissionID)
        SELECT  @RoleID, x.i.value('.','INT')
        FROM    @xml.nodes('/i') AS x(i);
    END
    COMMIT TRAN;
END;
GO

/* ------------------------------------------------------------------ */
/* BRANCHES                                                            */
/* ------------------------------------------------------------------ */

CREATE OR ALTER PROCEDURE sp_Branches_List
    @IsActive BIT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  BranchID, Code, Name, Address, City, Phone, Email, ManagerName, IsActive, CreatedAt
    FROM    Branches
    WHERE   IsDeleted = 0
      AND   (@IsActive IS NULL OR IsActive = @IsActive)
    ORDER BY Name;
END;
GO

CREATE OR ALTER PROCEDURE sp_Branches_Get
    @BranchID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  * FROM Branches WHERE BranchID = @BranchID AND IsDeleted = 0;
END;
GO

CREATE OR ALTER PROCEDURE sp_Branches_Create
    @Code NVARCHAR(20), @Name NVARCHAR(150), @Address NVARCHAR(500) = NULL,
    @City NVARCHAR(100) = NULL, @Phone NVARCHAR(30) = NULL, @Email NVARCHAR(150) = NULL,
    @ManagerName NVARCHAR(150) = NULL, @CreatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO Branches (Code, Name, Address, City, Phone, Email, ManagerName, CreatedBy)
    VALUES (@Code, @Name, @Address, @City, @Phone, @Email, @ManagerName, @CreatedBy);
    SELECT CAST(SCOPE_IDENTITY() AS INT) AS NewBranchID;
END;
GO

CREATE OR ALTER PROCEDURE sp_Branches_Update
    @BranchID INT, @Code NVARCHAR(20) = NULL, @Name NVARCHAR(150) = NULL,
    @Address NVARCHAR(500) = NULL, @City NVARCHAR(100) = NULL, @Phone NVARCHAR(30) = NULL,
    @Email NVARCHAR(150) = NULL, @ManagerName NVARCHAR(150) = NULL, @IsActive BIT = NULL,
    @UpdatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE Branches
       SET Code = COALESCE(@Code, Code),
           Name = COALESCE(@Name, Name),
           Address = COALESCE(@Address, Address),
           City = COALESCE(@City, City),
           Phone = COALESCE(@Phone, Phone),
           Email = COALESCE(@Email, Email),
           ManagerName = COALESCE(@ManagerName, ManagerName),
           IsActive = COALESCE(@IsActive, IsActive),
           UpdatedBy = @UpdatedBy,
           UpdatedAt = SYSUTCDATETIME()
     WHERE BranchID = @BranchID;
END;
GO

CREATE OR ALTER PROCEDURE sp_Branches_SoftDelete
    @BranchID INT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE Branches SET IsDeleted = 1, UpdatedAt = SYSUTCDATETIME() WHERE BranchID = @BranchID;
END;
GO

/* ------------------------------------------------------------------ */
/* MEMBERS                                                             */
/* ------------------------------------------------------------------ */

CREATE OR ALTER PROCEDURE sp_Members_GetNextCode
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Next INT = 1;
    SELECT @Next = ISNULL(MAX(MemberID),0) + 1 FROM Members;
    SELECT 'M-' + RIGHT('00000' + CAST(@Next AS VARCHAR(10)), 5) AS NextCode;
END;
GO

CREATE OR ALTER PROCEDURE sp_Members_List
    @Page INT = 1,
    @PageSize INT = 20,
    @Search NVARCHAR(100) = NULL,
    @BranchID INT = NULL,
    @Status NVARCHAR(20) = NULL,
    @TrainerID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Offset INT = (@Page - 1) * @PageSize;

    SELECT  m.MemberID, m.Code, m.FullName, m.Gender, m.Mobile, m.WhatsApp, m.Email,
            m.Photo, m.JoiningDate, m.Status, m.BranchID, b.Name AS BranchName,
            m.TrainerID, t.StaffID AS TrainerStaffID,
            ISNULL(st.FullName, 'No Trainer') AS TrainerName,
            (SELECT TOP 1 EndDate FROM MemberMemberships mm WHERE mm.MemberID = m.MemberID AND mm.Status = 'Active' ORDER BY mm.MemberMembershipID DESC) AS MembershipEndDate,
            m.CreatedAt
    FROM    Members m
    LEFT JOIN Branches b ON b.BranchID = m.BranchID
    LEFT JOIN Trainers t ON t.TrainerID = m.TrainerID
    LEFT JOIN Staff st  ON st.StaffID = t.StaffID
    WHERE   m.IsDeleted = 0
      AND   (@BranchID IS NULL OR m.BranchID = @BranchID)
      AND   (@Status IS NULL OR m.Status = @Status)
      AND   (@TrainerID IS NULL OR m.TrainerID = @TrainerID)
      AND   (@Search IS NULL OR m.FullName LIKE '%'+@Search+'%' OR m.Code LIKE '%'+@Search+'%' OR m.Mobile LIKE '%'+@Search+'%' OR m.CNIC LIKE '%'+@Search+'%')
    ORDER BY m.MemberID DESC
    OFFSET  @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT  COUNT(*) AS Total
    FROM    Members m
    WHERE   m.IsDeleted = 0
      AND   (@BranchID IS NULL OR m.BranchID = @BranchID)
      AND   (@Status IS NULL OR m.Status = @Status)
      AND   (@TrainerID IS NULL OR m.TrainerID = @TrainerID)
      AND   (@Search IS NULL OR m.FullName LIKE '%'+@Search+'%' OR m.Code LIKE '%'+@Search+'%' OR m.Mobile LIKE '%'+@Search+'%' OR m.CNIC LIKE '%'+@Search+'%');
END;
GO

CREATE OR ALTER PROCEDURE sp_Members_Get
    @MemberID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  m.*, b.Name AS BranchName,
            ISNULL(st.FullName,'No Trainer') AS TrainerName
    FROM    Members m
    LEFT JOIN Branches b ON b.BranchID = m.BranchID
    LEFT JOIN Trainers t ON t.TrainerID = m.TrainerID
    LEFT JOIN Staff st ON st.StaffID = t.StaffID
    WHERE   m.MemberID = @MemberID AND m.IsDeleted = 0;
END;
GO

CREATE OR ALTER PROCEDURE sp_Members_Create
    @BranchID INT, @FullName NVARCHAR(150), @FatherName NVARCHAR(150) = NULL,
    @Gender NVARCHAR(10) = NULL, @DOB DATE = NULL, @CNIC NVARCHAR(20) = NULL,
    @Mobile NVARCHAR(30) = NULL, @WhatsApp NVARCHAR(30) = NULL, @Email NVARCHAR(150) = NULL,
    @Address NVARCHAR(500) = NULL, @EmergencyContact NVARCHAR(30) = NULL,
    @Photo NVARCHAR(500) = NULL, @JoiningDate DATE, @TrainerID INT = NULL,
    @Height DECIMAL(5,2) = NULL, @Weight DECIMAL(5,2) = NULL,
    @MedicalNotes NVARCHAR(1000) = NULL, @Status NVARCHAR(20) = 'Active',
    @CreatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Code NVARCHAR(30);
    EXEC sp_Members_GetNextCode;
    -- fetch from above result
    SELECT @Code = 'M-' + RIGHT('00000' + CAST(ISNULL(MAX(MemberID),0)+1 AS VARCHAR(10)),5) FROM Members;

    INSERT INTO Members (BranchID, Code, FullName, FatherName, Gender, DOB, CNIC, Mobile, WhatsApp, Email,
                         Address, EmergencyContact, Photo, JoiningDate, TrainerID, Height, Weight,
                         MedicalNotes, Status, CreatedBy)
    VALUES (@BranchID, @Code, @FullName, @FatherName, @Gender, @DOB, @CNIC, @Mobile, @WhatsApp, @Email,
            @Address, @EmergencyContact, @Photo, @JoiningDate, @TrainerID, @Height, @Weight,
            @MedicalNotes, @Status, @CreatedBy);
    SELECT CAST(SCOPE_IDENTITY() AS INT) AS MemberID, @Code AS Code;
END;
GO

CREATE OR ALTER PROCEDURE sp_Members_Update
    @MemberID INT, @FullName NVARCHAR(150) = NULL, @FatherName NVARCHAR(150) = NULL,
    @Gender NVARCHAR(10) = NULL, @DOB DATE = NULL, @CNIC NVARCHAR(20) = NULL,
    @Mobile NVARCHAR(30) = NULL, @WhatsApp NVARCHAR(30) = NULL, @Email NVARCHAR(150) = NULL,
    @Address NVARCHAR(500) = NULL, @EmergencyContact NVARCHAR(30) = NULL,
    @Photo NVARCHAR(500) = NULL, @JoiningDate DATE = NULL, @TrainerID INT = NULL,
    @Height DECIMAL(5,2) = NULL, @Weight DECIMAL(5,2) = NULL,
    @MedicalNotes NVARCHAR(1000) = NULL, @Status NVARCHAR(20) = NULL,
    @UpdatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE Members
       SET FullName = COALESCE(@FullName, FullName),
           FatherName = COALESCE(@FatherName, FatherName),
           Gender = COALESCE(@Gender, Gender),
           DOB = COALESCE(@DOB, DOB),
           CNIC = COALESCE(@CNIC, CNIC),
           Mobile = COALESCE(@Mobile, Mobile),
           WhatsApp = COALESCE(@WhatsApp, WhatsApp),
           Email = COALESCE(@Email, Email),
           Address = COALESCE(@Address, Address),
           EmergencyContact = COALESCE(@EmergencyContact, EmergencyContact),
           Photo = COALESCE(@Photo, Photo),
           JoiningDate = COALESCE(@JoiningDate, JoiningDate),
           TrainerID = COALESCE(@TrainerID, TrainerID),
           Height = COALESCE(@Height, Height),
           Weight = COALESCE(@Weight, Weight),
           MedicalNotes = COALESCE(@MedicalNotes, MedicalNotes),
           Status = COALESCE(@Status, Status),
           UpdatedBy = @UpdatedBy,
           UpdatedAt = SYSUTCDATETIME()
     WHERE MemberID = @MemberID;
END;
GO

CREATE OR ALTER PROCEDURE sp_Members_SoftDelete
    @MemberID INT,
    @DeletedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE Members SET IsDeleted = 1, Status = 'Inactive', UpdatedBy = @DeletedBy, UpdatedAt = SYSUTCDATETIME()
     WHERE MemberID = @MemberID;
END;
GO

CREATE OR ALTER PROCEDURE sp_Members_GetPayments
    @MemberID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  fc.CollectionID, fc.Amount, fc.TransactionRef, fc.CollectedAt, pm.Name AS MethodName,
            fc.InvoiceID, fc.Notes, u.FullName AS CollectedByName
    FROM    FeeCollections fc
    LEFT JOIN PaymentMethods pm ON pm.MethodID = fc.MethodID
    LEFT JOIN Users u ON u.UserID = fc.CollectedBy
    WHERE   fc.MemberID = @MemberID AND fc.IsDeleted = 0
    ORDER BY fc.CollectedAt DESC;
END;
GO

CREATE OR ALTER PROCEDURE sp_Members_GetAttendance
    @MemberID INT,
    @FromDate DATE = NULL,
    @ToDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  AttendanceID, CheckInTime, CheckOutTime, Method
    FROM    Attendance
    WHERE   MemberID = @MemberID
      AND   (@FromDate IS NULL OR CAST(CheckInTime AS DATE) >= @FromDate)
      AND   (@ToDate IS NULL OR CAST(CheckInTime AS DATE) <= @ToDate)
    ORDER BY CheckInTime DESC;
END;
GO

CREATE OR ALTER PROCEDURE sp_Members_GetMemberships
    @MemberID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  mm.*, mp.Name AS PlanName, mp.DurationMonths
    FROM    MemberMemberships mm
    JOIN    MembershipPlans mp ON mp.PlanID = mm.PlanID
    WHERE   mm.MemberID = @MemberID AND mm.IsDeleted = 0
    ORDER BY mm.MemberMembershipID DESC;
END;
GO

CREATE OR ALTER PROCEDURE sp_Members_GetProgress
    @MemberID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  ProgressID, [Date], Weight, BMI, BodyFat, Waist, Chest, Arms, Legs, Notes
    FROM    ProgressTracking
    WHERE   MemberID = @MemberID
    ORDER BY [Date] DESC;
END;
GO

/* ------------------------------------------------------------------ */
/* MEMBERSHIP PLANS                                                    */
/* ------------------------------------------------------------------ */

CREATE OR ALTER PROCEDURE sp_MembershipPlans_List
    @IsActive BIT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  * FROM MembershipPlans
    WHERE   IsDeleted = 0 AND (@IsActive IS NULL OR IsActive = @IsActive)
    ORDER BY DurationMonths;
END;
GO

CREATE OR ALTER PROCEDURE sp_MembershipPlans_Create
    @Name NVARCHAR(100), @DurationMonths INT, @Price DECIMAL(18,2),
    @JoiningFee DECIMAL(18,2) = 0, @Discount DECIMAL(5,2) = 0,
    @Description NVARCHAR(500) = NULL, @CreatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO MembershipPlans (Name, DurationMonths, Price, JoiningFee, Discount, Description, CreatedBy)
    VALUES (@Name, @DurationMonths, @Price, @JoiningFee, @Discount, @Description, @CreatedBy);
    SELECT CAST(SCOPE_IDENTITY() AS INT) AS PlanID;
END;
GO

CREATE OR ALTER PROCEDURE sp_MembershipPlans_Update
    @PlanID INT, @Name NVARCHAR(100) = NULL, @DurationMonths INT = NULL,
    @Price DECIMAL(18,2) = NULL, @JoiningFee DECIMAL(18,2) = NULL,
    @Discount DECIMAL(5,2) = NULL, @Description NVARCHAR(500) = NULL,
    @IsActive BIT = NULL, @UpdatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE MembershipPlans
       SET Name = COALESCE(@Name, Name),
           DurationMonths = COALESCE(@DurationMonths, DurationMonths),
           Price = COALESCE(@Price, Price),
           JoiningFee = COALESCE(@JoiningFee, JoiningFee),
           Discount = COALESCE(@Discount, Discount),
           Description = COALESCE(@Description, Description),
           IsActive = COALESCE(@IsActive, IsActive),
           UpdatedBy = @UpdatedBy,
           UpdatedAt = SYSUTCDATETIME()
     WHERE PlanID = @PlanID;
END;
GO

CREATE OR ALTER PROCEDURE sp_MembershipPlans_SoftDelete
    @PlanID INT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE MembershipPlans SET IsDeleted = 1, IsActive = 0, UpdatedAt = SYSUTCDATETIME() WHERE PlanID = @PlanID;
END;
GO

/* ------------------------------------------------------------------ */
/* MEMBER MEMBERSHIPS                                                  */
/* ------------------------------------------------------------------ */

CREATE OR ALTER PROCEDURE sp_MemberMemberships_ActiveList
    @BranchID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  mm.MemberMembershipID, mm.MemberID, m.FullName AS MemberName, m.Code AS MemberCode,
            mp.Name AS PlanName, mp.DurationMonths, mm.StartDate, mm.EndDate, mm.Status,
            mm.AmountPaid, mm.FrozenDays
    FROM    MemberMemberships mm
    JOIN    Members m ON m.MemberID = mm.MemberID
    JOIN    MembershipPlans mp ON mp.PlanID = mm.PlanID
    WHERE   mm.IsDeleted = 0
      AND   (@BranchID IS NULL OR m.BranchID = @BranchID)
    ORDER BY mm.MemberMembershipID DESC;
END;
GO

CREATE OR ALTER PROCEDURE sp_MemberMemberships_Create
    @MemberID INT, @PlanID INT, @StartDate DATE, @AmountPaid DECIMAL(18,2) = 0,
    @Notes NVARCHAR(500) = NULL, @CreatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Duration INT, @EndDate DATE;
    SELECT @Duration = DurationMonths FROM MembershipPlans WHERE PlanID = @PlanID;
    IF @Duration = 0
        SET @EndDate = DATEADD(YEAR, 100, @StartDate);  -- lifetime
    ELSE
        SET @EndDate = DATEADD(MONTH, @Duration, @StartDate);

    INSERT INTO MemberMemberships (MemberID, PlanID, StartDate, EndDate, Status, AmountPaid, Notes, CreatedBy)
    VALUES (@MemberID, @PlanID, @StartDate, @EndDate, 'Active', @AmountPaid, @Notes, @CreatedBy);
    SELECT CAST(SCOPE_IDENTITY() AS INT) AS MemberMembershipID, @EndDate AS EndDate;
END;
GO

CREATE OR ALTER PROCEDURE sp_MemberMemberships_Renew
    @MemberMembershipID INT, @NewPlanID INT, @StartDate DATE,
    @AmountPaid DECIMAL(18,2) = 0, @Notes NVARCHAR(500) = NULL, @CreatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @MemberID INT, @Duration INT, @EndDate DATE;
    SELECT @MemberID = MemberID FROM MemberMemberships WHERE MemberMembershipID = @MemberMembershipID;
    SELECT @Duration = DurationMonths FROM MembershipPlans WHERE PlanID = @NewPlanID;
    SET @EndDate = CASE WHEN @Duration = 0 THEN DATEADD(YEAR,100,@StartDate) ELSE DATEADD(MONTH,@Duration,@StartDate) END;

    -- mark old as Expired
    UPDATE MemberMemberships SET Status = 'Expired', UpdatedAt = SYSUTCDATETIME()
     WHERE MemberMembershipID = @MemberMembershipID;

    INSERT INTO MemberMemberships (MemberID, PlanID, StartDate, EndDate, Status, AmountPaid, Notes, CreatedBy)
    VALUES (@MemberID, @NewPlanID, @StartDate, @EndDate, 'Active', @AmountPaid, @Notes, @CreatedBy);
    SELECT CAST(SCOPE_IDENTITY() AS INT) AS MemberMembershipID, @EndDate AS EndDate;
END;
GO

CREATE OR ALTER PROCEDURE sp_MemberMemberships_Freeze
    @MemberMembershipID INT, @StartDate DATE, @EndDate DATE, @Reason NVARCHAR(500),
    @CreatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Days INT = DATEDIFF(DAY, @StartDate, @EndDate) + 1;
    DECLARE @OldEndDate DATE, @MemberID INT;
    SELECT @OldEndDate = EndDate, @MemberID = MemberID FROM MemberMemberships WHERE MemberMembershipID = @MemberMembershipID;

    UPDATE MemberMemberships
       SET Status = 'Frozen',
           FrozenDays = FrozenDays + @Days,
           EndDate = DATEADD(DAY, @Days, EndDate),
           UpdatedAt = SYSUTCDATETIME()
     WHERE MemberMembershipID = @MemberMembershipID;

    INSERT INTO MembershipFreezes (MemberMembershipID, StartDate, EndDate, Reason, CreatedBy)
    VALUES (@MemberMembershipID, @StartDate, @EndDate, @Reason, @CreatedBy);

    UPDATE Members SET Status = 'Frozen' WHERE MemberID = @MemberID;
END;
GO

CREATE OR ALTER PROCEDURE sp_MemberMemberships_Cancel
    @MemberMembershipID INT, @Notes NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @MemberID INT;
    SELECT @MemberID = MemberID FROM MemberMemberships WHERE MemberMembershipID = @MemberMembershipID;
    UPDATE MemberMemberships SET Status = 'Cancelled', Notes = @Notes, UpdatedAt = SYSUTCDATETIME()
     WHERE MemberMembershipID = @MemberMembershipID;
    UPDATE Members SET Status = 'Inactive' WHERE MemberID = @MemberID;
END;
GO

/* ------------------------------------------------------------------ */
/* ATTENDANCE                                                          */
/* ------------------------------------------------------------------ */

CREATE OR ALTER PROCEDURE sp_Attendance_List
    @Page INT = 1,
    @PageSize INT = 50,
    @BranchID INT = NULL,
    @MemberID INT = NULL,
    @Date DATE = NULL,
    @FromDate DATE = NULL,
    @ToDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Offset INT = (@Page - 1) * @PageSize;

    SELECT  a.AttendanceID, a.MemberID, m.Code AS MemberCode, m.FullName AS MemberName,
            a.CheckInTime, a.CheckOutTime, a.Method, a.BranchID
    FROM    Attendance a
    JOIN    Members m ON m.MemberID = a.MemberID
    WHERE   (@BranchID IS NULL OR a.BranchID = @BranchID)
      AND   (@MemberID IS NULL OR a.MemberID = @MemberID)
      AND   (@Date IS NULL OR CAST(a.CheckInTime AS DATE) = @Date)
      AND   (@FromDate IS NULL OR CAST(a.CheckInTime AS DATE) >= @FromDate)
      AND   (@ToDate IS NULL OR CAST(a.CheckInTime AS DATE) <= @ToDate)
    ORDER BY a.CheckInTime DESC
    OFFSET  @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT  COUNT(*) AS Total
    FROM    Attendance a
    WHERE   (@BranchID IS NULL OR a.BranchID = @BranchID)
      AND   (@MemberID IS NULL OR a.MemberID = @MemberID)
      AND   (@Date IS NULL OR CAST(a.CheckInTime AS DATE) = @Date)
      AND   (@FromDate IS NULL OR CAST(a.CheckInTime AS DATE) >= @FromDate)
      AND   (@ToDate IS NULL OR CAST(a.CheckInTime AS DATE) <= @ToDate);
END;
GO

CREATE OR ALTER PROCEDURE sp_Attendance_CheckIn
    @MemberID INT, @BranchID INT, @Method NVARCHAR(20) = 'Manual',
    @IPAddress NVARCHAR(50) = NULL, @CreatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO Attendance (MemberID, BranchID, CheckInTime, Method, IPAddress, CreatedBy)
    VALUES (@MemberID, @BranchID, SYSUTCDATETIME(), @Method, @IPAddress, @CreatedBy);
    SELECT CAST(SCOPE_IDENTITY() AS BIGINT) AS AttendanceID;
END;
GO

CREATE OR ALTER PROCEDURE sp_Attendance_CheckOut
    @AttendanceID BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE Attendance SET CheckOutTime = SYSUTCDATETIME()
     WHERE AttendanceID = @AttendanceID AND CheckOutTime IS NULL;
END;
GO

CREATE OR ALTER PROCEDURE sp_Attendance_TodayCount
    @BranchID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  COUNT(*) AS TodayCount
    FROM    Attendance
    WHERE   CAST(CheckInTime AS DATE) = CAST(GETDATE() AS DATE)
      AND   (@BranchID IS NULL OR BranchID = @BranchID);
END;
GO

/* ------------------------------------------------------------------ */
/* FEES / INVOICES                                                     */
/* ------------------------------------------------------------------ */

CREATE OR ALTER PROCEDURE sp_Invoices_GetNextNo
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Next INT = 1;
    SELECT @Next = ISNULL(MAX(InvoiceID),0) + 1 FROM Invoices;
    SELECT 'INV-' + FORMAT(GETDATE(),'yyyyMM') + '-' + RIGHT('0000'+CAST(@Next AS VARCHAR(10)),4) AS InvoiceNo;
END;
GO

CREATE OR ALTER PROCEDURE sp_Invoices_Create
    @MemberID INT, @MemberMembershipID INT = NULL,
    @TotalAmount DECIMAL(18,2), @Discount DECIMAL(18,2) = 0,
    @LateFee DECIMAL(18,2) = 0, @Tax DECIMAL(18,2) = 0,
    @DueDate DATE = NULL, @Notes NVARCHAR(500) = NULL,
    @CreatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Net DECIMAL(18,2) = @TotalAmount - @Discount + @LateFee + @Tax;
    DECLARE @InvNo NVARCHAR(30);
    SELECT @InvNo = 'INV-' + FORMAT(GETDATE(),'yyyyMM') + '-' + RIGHT('0000'+CAST(ISNULL(MAX(InvoiceID),0)+1 AS VARCHAR(10)),4) FROM Invoices;

    INSERT INTO Invoices (InvoiceNo, MemberID, MemberMembershipID, TotalAmount, Discount, LateFee, Tax,
                          NetAmount, Status, DueDate, Notes, CreatedBy)
    VALUES (@InvNo, @MemberID, @MemberMembershipID, @TotalAmount, @Discount, @LateFee, @Tax,
            @Net, 'Unpaid', @DueDate, @Notes, @CreatedBy);
    SELECT CAST(SCOPE_IDENTITY() AS INT) AS InvoiceID, @InvNo AS InvoiceNo, @Net AS NetAmount;
END;
GO

CREATE OR ALTER PROCEDURE sp_Invoices_List
    @Page INT = 1, @PageSize INT = 20,
    @MemberID INT = NULL, @Status NVARCHAR(20) = NULL,
    @FromDate DATE = NULL, @ToDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Offset INT = (@Page - 1) * @PageSize;

    SELECT  i.InvoiceID, i.InvoiceNo, i.MemberID, m.Code AS MemberCode, m.FullName AS MemberName,
            i.TotalAmount, i.Discount, i.LateFee, i.Tax, i.NetAmount, i.PaidAmount, i.Status,
            i.IssueDate, i.DueDate
    FROM    Invoices i
    JOIN    Members m ON m.MemberID = i.MemberID
    WHERE   i.IsDeleted = 0
      AND   (@MemberID IS NULL OR i.MemberID = @MemberID)
      AND   (@Status IS NULL OR i.Status = @Status)
      AND   (@FromDate IS NULL OR i.IssueDate >= @FromDate)
      AND   (@ToDate IS NULL OR i.IssueDate <= @ToDate)
    ORDER BY i.InvoiceID DESC
    OFFSET  @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT  COUNT(*) AS Total
    FROM    Invoices i
    WHERE   i.IsDeleted = 0
      AND   (@MemberID IS NULL OR i.MemberID = @MemberID)
      AND   (@Status IS NULL OR i.Status = @Status)
      AND   (@FromDate IS NULL OR i.IssueDate >= @FromDate)
      AND   (@ToDate IS NULL OR i.IssueDate <= @ToDate);
END;
GO

CREATE OR ALTER PROCEDURE sp_FeeCollections_Collect
    @InvoiceID INT = NULL, @MemberID INT, @Amount DECIMAL(18,2),
    @MethodID INT, @TransactionRef NVARCHAR(100) = NULL,
    @BranchID INT, @Notes NVARCHAR(500) = NULL, @CollectedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRAN;
    INSERT INTO FeeCollections (InvoiceID, MemberID, Amount, MethodID, TransactionRef,
                                CollectedBy, BranchID, CollectedAt, Notes)
    VALUES (@InvoiceID, @MemberID, @Amount, @MethodID, @TransactionRef,
            @CollectedBy, @BranchID, SYSUTCDATETIME(), @Notes);
    DECLARE @NewID BIGINT = CAST(SCOPE_IDENTITY() AS BIGINT);

    IF @InvoiceID IS NOT NULL
    BEGIN
        UPDATE Invoices
           SET PaidAmount = PaidAmount + @Amount,
               Status = CASE WHEN PaidAmount + @Amount >= NetAmount THEN 'Paid' ELSE 'Partial' END
         WHERE InvoiceID = @InvoiceID;
    END
    COMMIT TRAN;
    SELECT @NewID AS CollectionID;
END;
GO

CREATE OR ALTER PROCEDURE sp_FeeCollections_List
    @Page INT = 1, @PageSize INT = 20,
    @MemberID INT = NULL, @BranchID INT = NULL,
    @FromDate DATE = NULL, @ToDate DATE = NULL,
    @MethodID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Offset INT = (@Page - 1) * @PageSize;

    SELECT  fc.CollectionID, fc.MemberID, m.Code AS MemberCode, m.FullName AS MemberName,
            fc.Amount, pm.Name AS MethodName, fc.TransactionRef, fc.InvoiceID,
            fc.CollectedAt, fc.BranchID, u.FullName AS CollectedByName
    FROM    FeeCollections fc
    JOIN    Members m ON m.MemberID = fc.MemberID
    JOIN    PaymentMethods pm ON pm.MethodID = fc.MethodID
    LEFT JOIN Users u ON u.UserID = fc.CollectedBy
    WHERE   fc.IsDeleted = 0
      AND   (@MemberID IS NULL OR fc.MemberID = @MemberID)
      AND   (@BranchID IS NULL OR fc.BranchID = @BranchID)
      AND   (@MethodID IS NULL OR fc.MethodID = @MethodID)
      AND   (@FromDate IS NULL OR CAST(fc.CollectedAt AS DATE) >= @FromDate)
      AND   (@ToDate IS NULL OR CAST(fc.CollectedAt AS DATE) <= @ToDate)
    ORDER BY fc.CollectionID DESC
    OFFSET  @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT  COUNT(*) AS Total, ISNULL(SUM(Amount),0) AS TotalAmount
    FROM    FeeCollections fc
    WHERE   fc.IsDeleted = 0
      AND   (@MemberID IS NULL OR fc.MemberID = @MemberID)
      AND   (@BranchID IS NULL OR fc.BranchID = @BranchID)
      AND   (@MethodID IS NULL OR fc.MethodID = @MethodID)
      AND   (@FromDate IS NULL OR CAST(fc.CollectedAt AS DATE) >= @FromDate)
      AND   (@ToDate IS NULL OR CAST(fc.CollectedAt AS DATE) <= @ToDate);
END;
GO

CREATE OR ALTER PROCEDURE sp_PaymentMethods_List
AS
BEGIN
    SET NOCOUNT ON;
    SELECT MethodID, Name, IsActive FROM PaymentMethods ORDER BY MethodID;
END;
GO

/* ------------------------------------------------------------------ */
/* FINANCE — INCOME / EXPENSES                                         */
/* ------------------------------------------------------------------ */

CREATE OR ALTER PROCEDURE sp_Expenses_Create
    @BranchID INT, @Category NVARCHAR(50), @Amount DECIMAL(18,2),
    @ExpenseDate DATE = NULL, @Notes NVARCHAR(500) = NULL, @CreatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO Expenses (BranchID, Category, Amount, ExpenseDate, Notes, CreatedBy)
    VALUES (@BranchID, @Category, @Amount, COALESCE(@ExpenseDate, CAST(GETDATE() AS DATE)), @Notes, @CreatedBy);
    SELECT CAST(SCOPE_IDENTITY() AS INT) AS ExpenseID;
END;
GO

CREATE OR ALTER PROCEDURE sp_Expenses_List
    @Page INT = 1, @PageSize INT = 50,
    @BranchID INT = NULL, @Category NVARCHAR(50) = NULL,
    @FromDate DATE = NULL, @ToDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Offset INT = (@Page - 1) * @PageSize;

    SELECT  ExpenseID, BranchID, Category, Amount, ExpenseDate, Notes, CreatedAt
    FROM    Expenses
    WHERE   IsDeleted = 0
      AND   (@BranchID IS NULL OR BranchID = @BranchID)
      AND   (@Category IS NULL OR Category = @Category)
      AND   (@FromDate IS NULL OR ExpenseDate >= @FromDate)
      AND   (@ToDate IS NULL OR ExpenseDate <= @ToDate)
    ORDER BY ExpenseID DESC
    OFFSET  @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT  COUNT(*) AS Total, ISNULL(SUM(Amount),0) AS TotalAmount
    FROM    Expenses
    WHERE   IsDeleted = 0
      AND   (@BranchID IS NULL OR BranchID = @BranchID)
      AND   (@Category IS NULL OR Category = @Category)
      AND   (@FromDate IS NULL OR ExpenseDate >= @FromDate)
      AND   (@ToDate IS NULL OR ExpenseDate <= @ToDate);
END;
GO

CREATE OR ALTER PROCEDURE sp_Income_Create
    @BranchID INT, @CategoryID INT, @Source NVARCHAR(100) = NULL,
    @Amount DECIMAL(18,2), @IncomeDate DATE = NULL, @Notes NVARCHAR(500) = NULL,
    @CreatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO IncomeRecords (BranchID, CategoryID, Source, Amount, IncomeDate, Notes, CreatedBy)
    VALUES (@BranchID, @CategoryID, @Source, @Amount, COALESCE(@IncomeDate, CAST(GETDATE() AS DATE)), @Notes, @CreatedBy);
    SELECT CAST(SCOPE_IDENTITY() AS INT) AS IncomeID;
END;
GO

CREATE OR ALTER PROCEDURE sp_Income_List
    @Page INT = 1, @PageSize INT = 50,
    @BranchID INT = NULL, @CategoryID INT = NULL,
    @FromDate DATE = NULL, @ToDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Offset INT = (@Page - 1) * @PageSize;

    SELECT  ir.IncomeID, ir.BranchID, ic.Name AS CategoryName, ir.Source, ir.Amount,
            ir.IncomeDate, ir.Notes, ir.CreatedAt
    FROM    IncomeRecords ir
    JOIN    IncomeCategories ic ON ic.CatID = ir.CategoryID
    WHERE   ir.IsDeleted = 0
      AND   (@BranchID IS NULL OR ir.BranchID = @BranchID)
      AND   (@CategoryID IS NULL OR ir.CategoryID = @CategoryID)
      AND   (@FromDate IS NULL OR ir.IncomeDate >= @FromDate)
      AND   (@ToDate IS NULL OR ir.IncomeDate <= @ToDate)
    ORDER BY ir.IncomeID DESC
    OFFSET  @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT  COUNT(*) AS Total, ISNULL(SUM(Amount),0) AS TotalAmount
    FROM    IncomeRecords
    WHERE   IsDeleted = 0
      AND   (@BranchID IS NULL OR BranchID = @BranchID)
      AND   (@CategoryID IS NULL OR CategoryID = @CategoryID)
      AND   (@FromDate IS NULL OR IncomeDate >= @FromDate)
      AND   (@ToDate IS NULL OR IncomeDate <= @ToDate);
END;
GO

CREATE OR ALTER PROCEDURE sp_IncomeCategories_List
AS
BEGIN
    SET NOCOUNT ON;
    SELECT CatID, Name, IsActive FROM IncomeCategories ORDER BY CatID;
END;
GO

/* ------------------------------------------------------------------ */
/* DASHBOARD                                                           */
/* ------------------------------------------------------------------ */

CREATE OR ALTER PROCEDURE sp_Dashboard_Stats
    @BranchID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @TotalMembers INT, @ActiveMembers INT, @ExpiredMembers INT, @NewMembers INT;
    DECLARE @TodayAttendance INT, @MonthlyIncome DECIMAL(18,2), @MonthlyExpenses DECIMAL(18,2);
    DECLARE @PendingFees DECIMAL(18,2), @SalaryDue DECIMAL(18,2), @RentDue DECIMAL(18,2);
    DECLARE @EquipmentMaintenance INT, @MembershipExpiryAlerts INT;

    SELECT @TotalMembers  = COUNT(*) FROM Members WHERE IsDeleted = 0 AND (@BranchID IS NULL OR BranchID = @BranchID);
    SELECT @ActiveMembers = COUNT(*) FROM Members WHERE IsDeleted = 0 AND Status = 'Active' AND (@BranchID IS NULL OR BranchID = @BranchID);
    SELECT @ExpiredMembers = COUNT(*) FROM Members WHERE IsDeleted = 0 AND Status = 'Expired' AND (@BranchID IS NULL OR BranchID = @BranchID);
    SELECT @NewMembers = COUNT(*) FROM Members WHERE IsDeleted = 0 AND MONTH(JoiningDate) = MONTH(GETDATE()) AND YEAR(JoiningDate) = YEAR(GETDATE()) AND (@BranchID IS NULL OR BranchID = @BranchID);

    SELECT @TodayAttendance = COUNT(*) FROM Attendance WHERE CAST(CheckInTime AS DATE) = CAST(GETDATE() AS DATE) AND (@BranchID IS NULL OR BranchID = @BranchID);

    SELECT @MonthlyIncome = ISNULL(SUM(Amount),0) FROM FeeCollections
     WHERE MONTH(CollectedAt) = MONTH(GETDATE()) AND YEAR(CollectedAt) = YEAR(GETDATE())
       AND IsDeleted = 0 AND (@BranchID IS NULL OR BranchID = @BranchID);

    SELECT @MonthlyExpenses = ISNULL(SUM(Amount),0) FROM Expenses
     WHERE MONTH(ExpenseDate) = MONTH(GETDATE()) AND YEAR(ExpenseDate) = YEAR(GETDATE())
       AND IsDeleted = 0 AND (@BranchID IS NULL OR BranchID = @BranchID);

    SELECT @PendingFees = ISNULL(SUM(NetAmount - PaidAmount),0) FROM Invoices
     WHERE Status IN ('Unpaid','Partial') AND IsDeleted = 0
       AND (@BranchID IS NULL OR MemberID IN (SELECT MemberID FROM Members WHERE BranchID = @BranchID));

    SELECT @SalaryDue = ISNULL(SUM(BaseSalary + Bonus + Overtime + Commission - LeaveDeduction),0)
    FROM Payroll p JOIN Staff s ON s.StaffID = p.StaffID
    WHERE p.Status = 'Generated' AND p.[Month] = MONTH(GETDATE()) AND p.[Year] = YEAR(GETDATE())
      AND (@BranchID IS NULL OR s.BranchID = @BranchID);

    SELECT @RentDue = ISNULL(SUM(Amount),0) FROM Expenses
     WHERE Category = 'Rent' AND ExpenseDate <= EOMONTH(GETDATE())
       AND IsDeleted = 0 AND (@BranchID IS NULL OR BranchID = @BranchID);

    SELECT @EquipmentMaintenance = COUNT(*) FROM Equipment
     WHERE Status = 'Maintenance' AND IsDeleted = 0 AND (@BranchID IS NULL OR BranchID = @BranchID);

    SELECT @MembershipExpiryAlerts = COUNT(*)
    FROM MemberMemberships mm JOIN Members m ON m.MemberID = mm.MemberID
    WHERE mm.Status = 'Active' AND DATEDIFF(DAY, GETDATE(), mm.EndDate) <= 7
      AND (@BranchID IS NULL OR m.BranchID = @BranchID);

    SELECT  @TotalMembers AS TotalMembers, @ActiveMembers AS ActiveMembers,
            @ExpiredMembers AS ExpiredMembers, @NewMembers AS NewMembers,
            @TodayAttendance AS TodayAttendance, @MonthlyIncome AS MonthlyIncome,
            @MonthlyExpenses AS MonthlyExpenses, @PendingFees AS PendingFees,
            @SalaryDue AS SalaryDue, @RentDue AS RentDue,
            @EquipmentMaintenance AS EquipmentUnderMaintenance,
            @MembershipExpiryAlerts AS MembershipExpiryAlerts;
END;
GO

CREATE OR ALTER PROCEDURE sp_Dashboard_Charts
    @Months INT = 6,
    @BranchID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Start DATE = DATEADD(MONTH, -@Months + 1, DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1));

    -- Revenue per month (FeeCollections)
    SELECT  FORMAT(d.DateMonth, 'yyyy-MM') AS [Month],
            ISNULL(SUM(fc.Amount), 0) AS Revenue
    FROM    (SELECT TOP (@Months) DATEADD(MONTH, NUMBER, @Start) AS DateMonth
             FROM master..spt_values WHERE type='P' ORDER BY NUMBER) d
    LEFT JOIN FeeCollections fc ON FORMAT(fc.CollectedAt,'yyyy-MM') = FORMAT(d.DateMonth,'yyyy-MM')
                                AND fc.IsDeleted = 0
                                AND (@BranchID IS NULL OR fc.BranchID = @BranchID)
    GROUP BY d.DateMonth
    ORDER BY d.DateMonth;

    -- Expenses per month
    SELECT  FORMAT(d.DateMonth, 'yyyy-MM') AS [Month],
            ISNULL(SUM(e.Amount), 0) AS Expenses
    FROM    (SELECT TOP (@Months) DATEADD(MONTH, NUMBER, @Start) AS DateMonth
             FROM master..spt_values WHERE type='P' ORDER BY NUMBER) d
    LEFT JOIN Expenses e ON FORMAT(e.ExpenseDate,'yyyy-MM') = FORMAT(d.DateMonth,'yyyy-MM')
                         AND e.IsDeleted = 0
                         AND (@BranchID IS NULL OR e.BranchID = @BranchID)
    GROUP BY d.DateMonth
    ORDER BY d.DateMonth;

    -- Attendance per day (last 14 days)
    SELECT  FORMAT(d.DateDay, 'yyyy-MM-dd') AS [Date],
            ISNULL(COUNT(a.AttendanceID),0) AS Attendance
    FROM    (SELECT TOP (14) DATEADD(DAY, NUMBER*-1, CAST(GETDATE() AS DATE)) AS DateDay
             FROM master..spt_values WHERE type='P' ORDER BY NUMBER DESC) d
    LEFT JOIN Attendance a ON CAST(a.CheckInTime AS DATE) = d.DateDay
                           AND (@BranchID IS NULL OR a.BranchID = @BranchID)
    GROUP BY d.DateDay
    ORDER BY d.DateDay;

    -- Membership growth per month (cumulative)
    SELECT  FORMAT(d.DateMonth,'yyyy-MM') AS [Month],
            (SELECT COUNT(*) FROM Members m
              WHERE m.JoiningDate <= EOMONTH(d.DateMonth) AND m.IsDeleted = 0
                AND (@BranchID IS NULL OR m.BranchID = @BranchID)) AS TotalMembers
    FROM    (SELECT TOP (@Months) DATEADD(MONTH, NUMBER, @Start) AS DateMonth
             FROM master..spt_values WHERE type='P' ORDER BY NUMBER) d
    ORDER BY d.DateMonth;
END;
GO

PRINT 'Stored procedures created successfully.';
GO

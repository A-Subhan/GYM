/* ============================================================================
   CONTOURA LABS — GYM MANAGEMENT SYSTEM
   SQL Server 2022 — SCHEMA SCRIPT (01_schema.sql)
   ----------------------------------------------------------------------------
   - Creates database GymDB
   - Creates ~40 tables (3NF, with PK/FK/constraints/indexes)
   - All password fields store bcrypt hashes (never plaintext)
   - Soft-delete pattern (IsDeleted BIT) on transactional tables
   - Audit columns (CreatedAt, UpdatedAt, CreatedBy, UpdatedBy) everywhere
   ============================================================================ */

USE master;
GO

IF DB_ID('GymDB') IS NOT NULL
BEGIN
    ALTER DATABASE GymDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE GymDB;
END
GO

CREATE DATABASE GymDB
    COLLATE SQL_Latin1_General_CP1_CI_AS;
GO

ALTER DATABASE GymDB SET RECOVERY SIMPLE;
GO

USE GymDB;
GO

/* ------------------------------------------------------------------ */
/* 1. CORE / AUTH                                                     */
/* ------------------------------------------------------------------ */

CREATE TABLE Branches (
    BranchID        INT IDENTITY(1,1) PRIMARY KEY,
    Code            NVARCHAR(20)  NOT NULL UNIQUE,
    Name            NVARCHAR(150) NOT NULL,
    Address         NVARCHAR(500) NULL,
    City            NVARCHAR(100) NULL,
    Phone           NVARCHAR(30)  NULL,
    Email           NVARCHAR(150) NULL,
    ManagerName     NVARCHAR(150) NULL,
    IsActive        BIT NOT NULL DEFAULT 1,
    CreatedAt       DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    UpdatedAt       DATETIME2 NULL,
    CreatedBy       INT NULL,
    UpdatedBy       INT NULL,
    IsDeleted       BIT NOT NULL DEFAULT 0
);
GO

CREATE TABLE Roles (
    RoleID          INT IDENTITY(1,1) PRIMARY KEY,
    Name            NVARCHAR(50) NOT NULL UNIQUE,  -- Super Admin / Owner / Manager / Receptionist / Trainer / Accountant / Staff
    Description     NVARCHAR(300) NULL,
    IsSystem        BIT NOT NULL DEFAULT 0,         -- system roles cannot be deleted
    CreatedAt       DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    UpdatedAt       DATETIME2 NULL
);
GO

CREATE TABLE Permissions (
    PermissionID    INT IDENTITY(1,1) PRIMARY KEY,
    Module          NVARCHAR(50) NOT NULL,  -- members, memberships, attendance, fees, finance, ...
    Action          NVARCHAR(20) NOT NULL,  -- view / add / edit / delete / print / export
    Code            AS (Module + '.' + Action) PERSISTED UNIQUE,
    Description     NVARCHAR(200) NULL
);
GO

CREATE TABLE RolePermissions (
    RoleID          INT NOT NULL FOREIGN KEY REFERENCES Roles(RoleID),
    PermissionID    INT NOT NULL FOREIGN KEY REFERENCES Permissions(PermissionID),
    CONSTRAINT PK_RolePermissions PRIMARY KEY (RoleID, PermissionID)
);
GO

CREATE TABLE Users (
    UserID              INT IDENTITY(1,1) PRIMARY KEY,
    Username            NVARCHAR(50)  NOT NULL UNIQUE,
    Email               NVARCHAR(150) NULL UNIQUE,
    FullName            NVARCHAR(150) NOT NULL,
    PasswordHash        NVARCHAR(255) NOT NULL,    -- bcrypt hash
    RoleID              INT NOT NULL FOREIGN KEY REFERENCES Roles(RoleID),
    BranchID            INT NULL FOREIGN KEY REFERENCES Branches(BranchID),
    Phone               NVARCHAR(30) NULL,
    Photo               NVARCHAR(500) NULL,
    IsActive            BIT NOT NULL DEFAULT 1,
    FailedLoginCount    INT NOT NULL DEFAULT 0,
    LastLoginAt         DATETIME2 NULL,
    MustChangePassword  BIT NOT NULL DEFAULT 0,
    CreatedAt           DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    UpdatedAt           DATETIME2 NULL,
    CreatedBy           INT NULL,
    UpdatedBy           INT NULL,
    IsDeleted           BIT NOT NULL DEFAULT 0
);
GO

-- self-FK fixups (CreatedBy/UpdatedBy refer to Users)
ALTER TABLE Branches  ADD CONSTRAINT FK_Branches_CreatedBy  FOREIGN KEY (CreatedBy)  REFERENCES Users(UserID);
ALTER TABLE Branches  ADD CONSTRAINT FK_Branches_UpdatedBy  FOREIGN KEY (UpdatedBy)  REFERENCES Users(UserID);
ALTER TABLE Users     ADD CONSTRAINT FK_Users_CreatedBy     FOREIGN KEY (CreatedBy)  REFERENCES Users(UserID);
ALTER TABLE Users     ADD CONSTRAINT FK_Users_UpdatedBy     FOREIGN KEY (UpdatedBy)  REFERENCES Users(UserID);
GO

CREATE INDEX IX_Users_RoleID   ON Users(RoleID);
CREATE INDEX IX_Users_BranchID ON Users(BranchID);
CREATE INDEX IX_Users_Username ON Users(Username) WHERE IsDeleted = 0;
GO

CREATE TABLE UserSessions (
    SessionID       BIGINT IDENTITY(1,1) PRIMARY KEY,
    UserID          INT NOT NULL FOREIGN KEY REFERENCES Users(UserID),
    RefreshToken    NVARCHAR(500) NOT NULL,
    IPAddress       NVARCHAR(50)  NULL,
    UserAgent       NVARCHAR(500) NULL,
    Location        NVARCHAR(200) NULL,   -- "lat,lng" or city string
    LoginAt         DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    LogoutAt        DATETIME2 NULL,
    LastActivityAt  DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    Status          NVARCHAR(20) NOT NULL DEFAULT 'Active'  -- Active / LoggedOut / Expired / Revoked
);
GO
CREATE INDEX IX_UserSessions_UserID   ON UserSessions(UserID);
CREATE INDEX IX_UserSessions_Token    ON UserSessions(RefreshToken);
CREATE INDEX IX_UserSessions_LoginAt  ON UserSessions(LoginAt);
GO

CREATE TABLE PasswordResets (
    ResetID     INT IDENTITY(1,1) PRIMARY KEY,
    UserID      INT NOT NULL FOREIGN KEY REFERENCES Users(UserID),
    Token       NVARCHAR(500) NOT NULL UNIQUE,
    ExpiresAt   DATETIME2 NOT NULL,
    UsedAt      DATETIME2 NULL,
    IPAddress   NVARCHAR(50) NULL,
    CreatedAt   DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO
CREATE INDEX IX_PasswordResets_Token ON PasswordResets(Token) WHERE UsedAt IS NULL;
GO

CREATE TABLE AuditLogs (
    LogID       BIGINT IDENTITY(1,1) PRIMARY KEY,
    UserID      INT NULL,                       -- nullable: pre-login actions
    Action      NVARCHAR(50) NOT NULL,          -- LOGIN / LOGOUT / CREATE / UPDATE / DELETE / PRINT / EXPORT / SETTINGS_CHANGE
    Module      NVARCHAR(50) NOT NULL,          -- members / fees / expenses / staff / settings / auth / ...
    EntityID    INT NULL,
    Details     NVARCHAR(MAX) NULL,             -- JSON: { before: {...}, after: {...} }
    IPAddress   NVARCHAR(50)  NULL,
    Location    NVARCHAR(200) NULL,
    CreatedAt   DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO
CREATE INDEX IX_AuditLogs_UserID    ON AuditLogs(UserID);
CREATE INDEX IX_AuditLogs_Module    ON AuditLogs(Module);
CREATE INDEX IX_AuditLogs_Action    ON AuditLogs(Action);
CREATE INDEX IX_AuditLogs_CreatedAt ON AuditLogs(CreatedAt);
GO

CREATE TABLE Settings (
    SettingID   INT IDENTITY(1,1) PRIMARY KEY,
    [Key]       NVARCHAR(100) NOT NULL UNIQUE,
    Value       NVARCHAR(MAX) NULL,
    Category    NVARCHAR(50) NULL,        -- general / finance / receipt / theme / backup
    UpdatedAt   DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    UpdatedBy   INT NULL FOREIGN KEY REFERENCES Users(UserID)
);
GO

CREATE TABLE Notifications (
    NotificationID  BIGINT IDENTITY(1,1) PRIMARY KEY,
    Type        NVARCHAR(50) NOT NULL,    -- membership_expiry / payment_due / birthday / equipment_maintenance
    Title       NVARCHAR(200) NOT NULL,
    Message     NVARCHAR(1000) NULL,
    UserID      INT NULL FOREIGN KEY REFERENCES Users(UserID),   -- recipient; NULL = broadcast
    EntityID    INT NULL,
    IsRead      BIT NOT NULL DEFAULT 0,
    CreatedAt   DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO
CREATE INDEX IX_Notifications_UserID    ON Notifications(UserID);
CREATE INDEX IX_Notifications_IsRead    ON Notifications(IsRead);
CREATE INDEX IX_Notifications_CreatedAt ON Notifications(CreatedAt);
GO

/* ------------------------------------------------------------------ */
/* 2. MEMBER / MEMBERSHIP                                             */
/* ------------------------------------------------------------------ */

CREATE TABLE MembershipPlans (
    PlanID          INT IDENTITY(1,1) PRIMARY KEY,
    Name            NVARCHAR(100) NOT NULL,
    DurationMonths  INT NOT NULL,             -- 0 = lifetime
    Price           DECIMAL(18,2) NOT NULL,
    JoiningFee      DECIMAL(18,2) NOT NULL DEFAULT 0,
    Discount        DECIMAL(5,2)  NOT NULL DEFAULT 0,   -- percentage
    Description     NVARCHAR(500) NULL,
    IsActive        BIT NOT NULL DEFAULT 1,
    CreatedAt       DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    UpdatedAt       DATETIME2 NULL,
    CreatedBy       INT NULL FOREIGN KEY REFERENCES Users(UserID),
    UpdatedBy       INT NULL FOREIGN KEY REFERENCES Users(UserID),
    IsDeleted       BIT NOT NULL DEFAULT 0
);
GO

CREATE TABLE Members (
    MemberID        INT IDENTITY(1,1) PRIMARY KEY,
    BranchID        INT NOT NULL FOREIGN KEY REFERENCES Branches(BranchID),
    Code            NVARCHAR(30) NOT NULL UNIQUE,    -- M-00001
    FullName        NVARCHAR(150) NOT NULL,
    FatherName      NVARCHAR(150) NULL,
    Gender          NVARCHAR(10)  NULL,   -- Male / Female / Other
    DOB             DATE NULL,
    CNIC            NVARCHAR(20)  NULL,
    Mobile          NVARCHAR(30)  NULL,
    WhatsApp        NVARCHAR(30)  NULL,
    Email           NVARCHAR(150) NULL,
    Address         NVARCHAR(500) NULL,
    EmergencyContact NVARCHAR(30) NULL,
    Photo           NVARCHAR(500) NULL,
    JoiningDate     DATE NOT NULL,
    TrainerID       INT NULL,           -- FK to Trainers added later (forward ref)
    Height          DECIMAL(5,2) NULL,  -- cm
    Weight          DECIMAL(5,2) NULL,  -- kg
    MedicalNotes    NVARCHAR(1000) NULL,
    Status          NVARCHAR(20) NOT NULL DEFAULT 'Active',  -- Active / Inactive / Frozen / Expired
    CreatedAt       DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    UpdatedAt       DATETIME2 NULL,
    CreatedBy       INT NULL FOREIGN KEY REFERENCES Users(UserID),
    UpdatedBy       INT NULL FOREIGN KEY REFERENCES Users(UserID),
    IsDeleted       BIT NOT NULL DEFAULT 0
);
GO
CREATE INDEX IX_Members_BranchID   ON Members(BranchID);
CREATE INDEX IX_Members_Status     ON Members(Status);
CREATE INDEX IX_Members_Code       ON Members(Code);
CREATE INDEX IX_Members_Mobile     ON Members(Mobile);
CREATE INDEX IX_Members_TrainerID  ON Members(TrainerID);
GO

CREATE TABLE MemberMemberships (
    MemberMembershipID  INT IDENTITY(1,1) PRIMARY KEY,
    MemberID            INT NOT NULL FOREIGN KEY REFERENCES Members(MemberID),
    PlanID              INT NOT NULL FOREIGN KEY REFERENCES MembershipPlans(PlanID),
    StartDate           DATE NOT NULL,
    EndDate             DATE NOT NULL,
    Status              NVARCHAR(20) NOT NULL DEFAULT 'Active',  -- Active / Expired / Frozen / Cancelled
    FrozenDays          INT NOT NULL DEFAULT 0,
    AmountPaid          DECIMAL(18,2) NOT NULL DEFAULT 0,
    Notes               NVARCHAR(500) NULL,
    CreatedAt           DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    UpdatedAt           DATETIME2 NULL,
    CreatedBy           INT NULL FOREIGN KEY REFERENCES Users(UserID),
    IsDeleted           BIT NOT NULL DEFAULT 0
);
GO
CREATE INDEX IX_MemberMemberships_MemberID ON MemberMemberships(MemberID);
CREATE INDEX IX_MemberMemberships_Status   ON MemberMemberships(Status);
CREATE INDEX IX_MemberMemberships_EndDate  ON MemberMemberships(EndDate);
GO

CREATE TABLE MembershipFreezes (
    FreezeID    INT IDENTITY(1,1) PRIMARY KEY,
    MemberMembershipID INT NOT NULL FOREIGN KEY REFERENCES MemberMemberships(MemberMembershipID),
    StartDate   DATE NOT NULL,
    EndDate     DATE NOT NULL,
    Reason      NVARCHAR(500) NULL,
    CreatedAt   DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy   INT NULL FOREIGN KEY REFERENCES Users(UserID)
);
GO

CREATE TABLE MemberDocuments (
    DocID       INT IDENTITY(1,1) PRIMARY KEY,
    MemberID    INT NOT NULL FOREIGN KEY REFERENCES Members(MemberID),
    FileName    NVARCHAR(255) NOT NULL,
    FilePath    NVARCHAR(500) NOT NULL,
    FileType    NVARCHAR(50) NULL,
    UploadedAt  DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    UploadedBy  INT NULL FOREIGN KEY REFERENCES Users(UserID)
);
GO

/* ------------------------------------------------------------------ */
/* 3. ATTENDANCE                                                      */
/* ------------------------------------------------------------------ */

CREATE TABLE Attendance (
    AttendanceID    BIGINT IDENTITY(1,1) PRIMARY KEY,
    MemberID        INT NOT NULL FOREIGN KEY REFERENCES Members(MemberID),
    BranchID        INT NOT NULL FOREIGN KEY REFERENCES Branches(BranchID),
    CheckInTime     DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CheckOutTime    DATETIME2 NULL,
    Method          NVARCHAR(20) NOT NULL DEFAULT 'Manual',  -- Manual / QR / Barcode / RFID / Biometric
    IPAddress       NVARCHAR(50) NULL,
    CreatedBy       INT NULL FOREIGN KEY REFERENCES Users(UserID)
);
GO
CREATE INDEX IX_Attendance_MemberID    ON Attendance(MemberID);
CREATE INDEX IX_Attendance_BranchID    ON Attendance(BranchID);
CREATE INDEX IX_Attendance_CheckInTime ON Attendance(CheckInTime);
GO

/* ------------------------------------------------------------------ */
/* 4. FINANCE                                                         */
/* ------------------------------------------------------------------ */

CREATE TABLE PaymentMethods (
    MethodID    INT IDENTITY(1,1) PRIMARY KEY,
    Name        NVARCHAR(50) NOT NULL UNIQUE,   -- Cash / Bank / Card / JazzCash / EasyPaisa
    IsActive    BIT NOT NULL DEFAULT 1
);
GO

CREATE TABLE Invoices (
    InvoiceID       INT IDENTITY(1,1) PRIMARY KEY,
    InvoiceNo       NVARCHAR(30) NOT NULL UNIQUE,
    MemberID        INT NOT NULL FOREIGN KEY REFERENCES Members(MemberID),
    MemberMembershipID INT NULL FOREIGN KEY REFERENCES MemberMemberships(MemberMembershipID),
    TotalAmount     DECIMAL(18,2) NOT NULL,
    Discount        DECIMAL(18,2) NOT NULL DEFAULT 0,
    LateFee         DECIMAL(18,2) NOT NULL DEFAULT 0,
    Tax             DECIMAL(18,2) NOT NULL DEFAULT 0,
    NetAmount       DECIMAL(18,2) NOT NULL,
    PaidAmount      DECIMAL(18,2) NOT NULL DEFAULT 0,
    Status          NVARCHAR(20) NOT NULL DEFAULT 'Unpaid',  -- Unpaid / Partial / Paid / Refunded / Cancelled
    DueDate         DATE NULL,
    IssueDate       DATE NOT NULL DEFAULT CAST(GETDATE() AS DATE),
    Notes           NVARCHAR(500) NULL,
    CreatedAt       DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy       INT NULL FOREIGN KEY REFERENCES Users(UserID),
    IsDeleted       BIT NOT NULL DEFAULT 0
);
GO
CREATE INDEX IX_Invoices_MemberID ON Invoices(MemberID);
CREATE INDEX IX_Invoices_Status   ON Invoices(Status);
CREATE INDEX IX_Invoices_IssueDate ON Invoices(IssueDate);
GO

CREATE TABLE FeeCollections (
    CollectionID    BIGINT IDENTITY(1,1) PRIMARY KEY,
    InvoiceID       INT NULL FOREIGN KEY REFERENCES Invoices(InvoiceID),
    MemberID        INT NOT NULL FOREIGN KEY REFERENCES Members(MemberID),
    Amount          DECIMAL(18,2) NOT NULL,
    MethodID        INT NOT NULL FOREIGN KEY REFERENCES PaymentMethods(MethodID),
    TransactionRef  NVARCHAR(100) NULL,
    CollectedBy     INT NULL FOREIGN KEY REFERENCES Users(UserID),
    BranchID        INT NOT NULL FOREIGN KEY REFERENCES Branches(BranchID),
    CollectedAt     DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    Notes           NVARCHAR(500) NULL,
    IsDeleted       BIT NOT NULL DEFAULT 0
);
GO
CREATE INDEX IX_FeeCollections_MemberID    ON FeeCollections(MemberID);
CREATE INDEX IX_FeeCollections_InvoiceID   ON FeeCollections(InvoiceID);
CREATE INDEX IX_FeeCollections_CollectedAt ON FeeCollections(CollectedAt);
GO

CREATE TABLE Refunds (
    RefundID    INT IDENTITY(1,1) PRIMARY KEY,
    CollectionID BIGINT NOT NULL FOREIGN KEY REFERENCES FeeCollections(CollectionID),
    Amount      DECIMAL(18,2) NOT NULL,
    Reason      NVARCHAR(500) NULL,
    RefundedBy  INT NULL FOREIGN KEY REFERENCES Users(UserID),
    RefundedAt  DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE IncomeCategories (
    CatID       INT IDENTITY(1,1) PRIMARY KEY,
    Name        NVARCHAR(50) NOT NULL UNIQUE,  -- Membership / Personal Training / Product Sales / Misc
    IsActive    BIT NOT NULL DEFAULT 1
);
GO

CREATE TABLE Expenses (
    ExpenseID   INT IDENTITY(1,1) PRIMARY KEY,
    BranchID    INT NOT NULL FOREIGN KEY REFERENCES Branches(BranchID),
    Category    NVARCHAR(50) NOT NULL,  -- Salary / Rent / Electricity / Internet / Water / Maintenance / Misc
    Amount      DECIMAL(18,2) NOT NULL,
    ExpenseDate DATE NOT NULL DEFAULT CAST(GETDATE() AS DATE),
    Notes       NVARCHAR(500) NULL,
    CreatedAt   DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy   INT NULL FOREIGN KEY REFERENCES Users(UserID),
    IsDeleted   BIT NOT NULL DEFAULT 0
);
GO
CREATE INDEX IX_Expenses_BranchID    ON Expenses(BranchID);
CREATE INDEX IX_Expenses_Category    ON Expenses(Category);
CREATE INDEX IX_Expenses_ExpenseDate ON Expenses(ExpenseDate);
GO

CREATE TABLE IncomeRecords (
    IncomeID    INT IDENTITY(1,1) PRIMARY KEY,
    BranchID    INT NOT NULL FOREIGN KEY REFERENCES Branches(BranchID),
    CategoryID  INT NOT NULL FOREIGN KEY REFERENCES IncomeCategories(CatID),
    Source      NVARCHAR(100) NULL,   -- description
    Amount      DECIMAL(18,2) NOT NULL,
    IncomeDate  DATE NOT NULL DEFAULT CAST(GETDATE() AS DATE),
    Notes       NVARCHAR(500) NULL,
    CreatedAt   DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy   INT NULL FOREIGN KEY REFERENCES Users(UserID),
    IsDeleted   BIT NOT NULL DEFAULT 0
);
GO
CREATE INDEX IX_Income_BranchID   ON IncomeRecords(BranchID);
CREATE INDEX IX_Income_IncomeDate ON IncomeRecords(IncomeDate);
GO

/* ------------------------------------------------------------------ */
/* 5. STAFF / PAYROLL                                                 */
/* ------------------------------------------------------------------ */

CREATE TABLE Departments (
    DepartmentID    INT IDENTITY(1,1) PRIMARY KEY,
    Name            NVARCHAR(50) NOT NULL UNIQUE,  -- Reception / Trainers / Accountant / Cleaner / Security
    Description     NVARCHAR(300) NULL
);
GO

CREATE TABLE Staff (
    StaffID         INT IDENTITY(1,1) PRIMARY KEY,
    StaffCode       NVARCHAR(20) NULL,               -- <BranchID>/0001 (see 09_master_files_staff_code.sql)
    BranchID        INT NOT NULL FOREIGN KEY REFERENCES Branches(BranchID),
    DepartmentID    INT NOT NULL FOREIGN KEY REFERENCES Departments(DepartmentID),
    UserID          INT NULL FOREIGN KEY REFERENCES Users(UserID),
    FullName        NVARCHAR(150) NOT NULL,
    FatherName      NVARCHAR(150) NULL,
    CNIC            NVARCHAR(20)  NULL,
    Mobile          NVARCHAR(30)  NULL,
    Email           NVARCHAR(150) NULL,
    Address         NVARCHAR(500) NULL,
    Photo           NVARCHAR(500) NULL,
    JoiningDate     DATE NOT NULL,
    Designation     NVARCHAR(100) NULL,
    BaseSalary      DECIMAL(18,2) NOT NULL DEFAULT 0,
    Status          NVARCHAR(20) NOT NULL DEFAULT 'Active',  -- Active / OnLeave / Resigned / Terminated
    CreatedAt       DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    UpdatedAt       DATETIME2 NULL,
    CreatedBy       INT NULL FOREIGN KEY REFERENCES Users(UserID),
    UpdatedBy       INT NULL FOREIGN KEY REFERENCES Users(UserID),
    IsDeleted       BIT NOT NULL DEFAULT 0
);
GO
CREATE INDEX IX_Staff_BranchID     ON Staff(BranchID);
CREATE INDEX IX_Staff_DepartmentID ON Staff(DepartmentID);
GO

/* Master Files — metadata-driven master data (see 10_master_files_module.sql).
   Definitions: Designation (01), Education (02), Currency (03), ...
   Items: ItemCode = <MasterCode><0001> e.g. 010001, 020001. */
CREATE TABLE MasterDefinitions (
    MasterDefinitionID INT IDENTITY(1,1) PRIMARY KEY,
    MasterCode         NVARCHAR(5)  NOT NULL UNIQUE,
    Name               NVARCHAR(50) NOT NULL UNIQUE,
    Scope              NVARCHAR(10) NOT NULL DEFAULT 'Global' CHECK (Scope IN ('Global','Branch')),
    IsActive           BIT NOT NULL DEFAULT 1,
    CreatedAt          DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    UpdatedAt          DATETIME2 NULL,
    CreatedBy          INT NULL FOREIGN KEY REFERENCES Users(UserID),
    UpdatedBy          INT NULL FOREIGN KEY REFERENCES Users(UserID)
);
GO

CREATE TABLE MasterItems (
    MasterItemID       INT IDENTITY(1,1) PRIMARY KEY,
    MasterDefinitionID INT NOT NULL FOREIGN KEY REFERENCES MasterDefinitions(MasterDefinitionID),
    ItemCode           NVARCHAR(20) NOT NULL,
    Name               NVARCHAR(50) NOT NULL,
    IsActive           BIT NOT NULL DEFAULT 1,
    BranchID           INT NULL FOREIGN KEY REFERENCES Branches(BranchID),   -- NULL for Global masters
    CreatedAt          DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    UpdatedAt          DATETIME2 NULL,
    CreatedBy          INT NULL FOREIGN KEY REFERENCES Users(UserID),
    UpdatedBy          INT NULL FOREIGN KEY REFERENCES Users(UserID),
    CONSTRAINT UQ_MasterItems_Def_Code UNIQUE (MasterDefinitionID, ItemCode)
);
GO
CREATE INDEX IX_MasterItems_Def ON MasterItems(MasterDefinitionID, IsActive);
GO

CREATE TABLE StaffAttendance (
    StaffAttendanceID   BIGINT IDENTITY(1,1) PRIMARY KEY,
    StaffID         INT NOT NULL FOREIGN KEY REFERENCES Staff(StaffID),
    [Date]          DATE NOT NULL,
    CheckIn         DATETIME2 NULL,
    CheckOut        DATETIME2 NULL,
    Status          NVARCHAR(20) NOT NULL DEFAULT 'Present',  -- Present / Absent / Late / HalfDay / Leave
    Notes           NVARCHAR(300) NULL
);
GO
CREATE UNIQUE INDEX UX_StaffAttendance_Staff_Date ON StaffAttendance(StaffID, [Date]);
GO

CREATE TABLE StaffLeaves (
    LeaveID     INT IDENTITY(1,1) PRIMARY KEY,
    StaffID     INT NOT NULL FOREIGN KEY REFERENCES Staff(StaffID),
    LeaveType   NVARCHAR(30) NOT NULL,  -- Casual / Sick / Annual / Unpaid
    StartDate   DATE NOT NULL,
    EndDate     DATE NOT NULL,
    Reason      NVARCHAR(500) NULL,
    Status      NVARCHAR(20) NOT NULL DEFAULT 'Pending',  -- Pending / Approved / Rejected
    ApprovedBy  INT NULL FOREIGN KEY REFERENCES Users(UserID),
    CreatedAt   DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE Payroll (
    PayrollID       INT IDENTITY(1,1) PRIMARY KEY,
    StaffID         INT NOT NULL FOREIGN KEY REFERENCES Staff(StaffID),
    BranchID        INT NOT NULL FOREIGN KEY REFERENCES Branches(BranchID),
    [Month]         INT NOT NULL,    -- 1..12
    [Year]          INT NOT NULL,
    BaseSalary      DECIMAL(18,2) NOT NULL,
    Bonus           DECIMAL(18,2) NOT NULL DEFAULT 0,
    Overtime        DECIMAL(18,2) NOT NULL DEFAULT 0,
    LeaveDeduction  DECIMAL(18,2) NOT NULL DEFAULT 0,
    Commission      DECIMAL(18,2) NOT NULL DEFAULT 0,
    NetSalary       DECIMAL(18,2) NOT NULL,
    Status          NVARCHAR(20) NOT NULL DEFAULT 'Generated',  -- Generated / Paid
    PaidAt          DATETIME2 NULL,
    GeneratedBy     INT NULL FOREIGN KEY REFERENCES Users(UserID),
    GeneratedAt     DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO
CREATE UNIQUE INDEX UX_Payroll_Staff_Month_Year ON Payroll(StaffID, [Month], [Year]);
GO

CREATE TABLE SalarySlips (
    SlipID      INT IDENTITY(1,1) PRIMARY KEY,
    PayrollID   INT NOT NULL FOREIGN KEY REFERENCES Payroll(PayrollID),
    FilePath    NVARCHAR(500) NULL,
    GeneratedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

/* ------------------------------------------------------------------ */
/* 6. TRAINER / WORKOUT / DIET / PROGRESS                             */
/* ------------------------------------------------------------------ */

CREATE TABLE Trainers (
    TrainerID   INT IDENTITY(1,1) PRIMARY KEY,
    StaffID     INT NOT NULL FOREIGN KEY REFERENCES Staff(StaffID),
    Specialization NVARCHAR(200) NULL,
    Experience  NVARCHAR(100) NULL,
    IsActive    BIT NOT NULL DEFAULT 1,
    CreatedAt   DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

-- Now link Members.TrainerID -> Trainers.TrainerID
ALTER TABLE Members ADD CONSTRAINT FK_Members_TrainerID
    FOREIGN KEY (TrainerID) REFERENCES Trainers(TrainerID);
GO

CREATE TABLE WorkoutPlans (
    PlanID      INT IDENTITY(1,1) PRIMARY KEY,
    TrainerID   INT NOT NULL FOREIGN KEY REFERENCES Trainers(TrainerID),
    MemberID    INT NOT NULL FOREIGN KEY REFERENCES Members(MemberID),
    Title       NVARCHAR(200) NOT NULL,
    DayOfWeek   NVARCHAR(20) NULL,    -- Monday / Tuesday / ... or Daily
    StartDate   DATE NULL,
    EndDate     DATE NULL,
    Notes       NVARCHAR(1000) NULL,
    CreatedAt   DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    UpdatedAt   DATETIME2 NULL
);
GO

CREATE TABLE WorkoutPlanItems (
    ItemID      INT IDENTITY(1,1) PRIMARY KEY,
    PlanID      INT NOT NULL FOREIGN KEY REFERENCES WorkoutPlans(PlanID),
    Exercise    NVARCHAR(200) NOT NULL,
    [Sets]      INT NULL,
    Reps        NVARCHAR(20) NULL,    -- "12" or "30s"
    Weight      NVARCHAR(50) NULL,    -- "20kg" or "Bodyweight"
    RestPeriod  NVARCHAR(20) NULL,    -- "60s"
    Notes       NVARCHAR(500) NULL,
    SortOrder   INT NOT NULL DEFAULT 0
);
GO

CREATE TABLE DietPlans (
    PlanID      INT IDENTITY(1,1) PRIMARY KEY,
    TrainerID   INT NOT NULL FOREIGN KEY REFERENCES Trainers(TrainerID),
    MemberID    INT NOT NULL FOREIGN KEY REFERENCES Members(MemberID),
    Title       NVARCHAR(200) NOT NULL,
    StartDate   DATE NULL,
    EndDate     DATE NULL,
    Notes       NVARCHAR(1000) NULL,
    CreatedAt   DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE DietPlanItems (
    ItemID      INT IDENTITY(1,1) PRIMARY KEY,
    PlanID      INT NOT NULL FOREIGN KEY REFERENCES DietPlans(PlanID),
    Meal        NVARCHAR(50) NOT NULL,    -- Breakfast / Lunch / Snack / Dinner
    Food        NVARCHAR(300) NOT NULL,
    Calories    DECIMAL(10,2) NULL,
    Protein     DECIMAL(10,2) NULL,    -- grams
    Carbs       DECIMAL(10,2) NULL,
    Fat         DECIMAL(10,2) NULL,
    Notes       NVARCHAR(500) NULL,
    SortOrder   INT NOT NULL DEFAULT 0
);
GO

CREATE TABLE ProgressTracking (
    ProgressID  INT IDENTITY(1,1) PRIMARY KEY,
    MemberID    INT NOT NULL FOREIGN KEY REFERENCES Members(MemberID),
    [Date]      DATE NOT NULL,
    Weight      DECIMAL(5,2) NULL,
    BMI         DECIMAL(5,2) NULL,
    BodyFat     DECIMAL(5,2) NULL,
    Waist       DECIMAL(5,2) NULL,
    Chest       DECIMAL(5,2) NULL,
    Arms        DECIMAL(5,2) NULL,
    Legs        DECIMAL(5,2) NULL,
    Notes       NVARCHAR(1000) NULL,
    CreatedAt   DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy   INT NULL FOREIGN KEY REFERENCES Users(UserID)
);
GO
CREATE INDEX IX_Progress_MemberID ON ProgressTracking(MemberID);
CREATE INDEX IX_Progress_Date     ON ProgressTracking([Date]);
GO

CREATE TABLE ProgressPhotos (
    PhotoID     INT IDENTITY(1,1) PRIMARY KEY,
    ProgressID  INT NOT NULL FOREIGN KEY REFERENCES ProgressTracking(ProgressID),
    FilePath    NVARCHAR(500) NOT NULL,
    TakenAt     DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

/* ------------------------------------------------------------------ */
/* 7. EQUIPMENT / INVENTORY                                           */
/* ------------------------------------------------------------------ */

CREATE TABLE Equipment (
    EquipmentID     INT IDENTITY(1,1) PRIMARY KEY,
    BranchID        INT NOT NULL FOREIGN KEY REFERENCES Branches(BranchID),
    Name            NVARCHAR(200) NOT NULL,
    Brand           NVARCHAR(100) NULL,
    SerialNo        NVARCHAR(100) NULL,
    PurchaseDate    DATE NULL,
    PurchasePrice   DECIMAL(18,2) NULL,
    WarrantyExpiry  DATE NULL,
    Status          NVARCHAR(20) NOT NULL DEFAULT 'Active',  -- Active / Maintenance / Broken / Sold
    Notes           NVARCHAR(500) NULL,
    CreatedAt       DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    UpdatedAt       DATETIME2 NULL,
    CreatedBy       INT NULL FOREIGN KEY REFERENCES Users(UserID),
    IsDeleted       BIT NOT NULL DEFAULT 0
);
GO
CREATE INDEX IX_Equipment_BranchID ON Equipment(BranchID);
CREATE INDEX IX_Equipment_Status   ON Equipment(Status);
GO

CREATE TABLE EquipmentMaintenance (
    MaintID     INT IDENTITY(1,1) PRIMARY KEY,
    EquipmentID INT NOT NULL FOREIGN KEY REFERENCES Equipment(EquipmentID),
    Type        NVARCHAR(50) NULL,        -- Routine / Repair / Inspection
    Cost        DECIMAL(18,2) NOT NULL DEFAULT 0,
    StartDate   DATE NOT NULL,
    EndDate     DATE NULL,
    Notes       NVARCHAR(500) NULL,
    CreatedAt   DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy   INT NULL FOREIGN KEY REFERENCES Users(UserID)
);
GO

CREATE TABLE Suppliers (
    SupplierID  INT IDENTITY(1,1) PRIMARY KEY,
    Name        NVARCHAR(150) NOT NULL,
    Contact     NVARCHAR(100) NULL,
    Phone       NVARCHAR(30) NULL,
    Email       NVARCHAR(150) NULL,
    Address     NVARCHAR(500) NULL,
    IsActive    BIT NOT NULL DEFAULT 1,
    CreatedAt   DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE InventoryItems (
    ItemID          INT IDENTITY(1,1) PRIMARY KEY,
    BranchID        INT NOT NULL FOREIGN KEY REFERENCES Branches(BranchID),
    Name            NVARCHAR(200) NOT NULL,
    Category        NVARCHAR(50) NOT NULL,    -- Supplement / Drink / Accessory
    SKU             NVARCHAR(50) NULL,
    StockQty        DECIMAL(18,2) NOT NULL DEFAULT 0,
    ReorderLevel    DECIMAL(18,2) NOT NULL DEFAULT 0,
    SalePrice       DECIMAL(18,2) NOT NULL DEFAULT 0,
    PurchasePrice   DECIMAL(18,2) NOT NULL DEFAULT 0,
    IsActive        BIT NOT NULL DEFAULT 1,
    CreatedAt       DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    UpdatedAt       DATETIME2 NULL,
    CreatedBy       INT NULL FOREIGN KEY REFERENCES Users(UserID),
    IsDeleted       BIT NOT NULL DEFAULT 0
);
GO
CREATE INDEX IX_Inventory_BranchID ON InventoryItems(BranchID);
CREATE INDEX IX_Inventory_Category ON InventoryItems(Category);
GO

CREATE TABLE InventoryTransactions (
    TxnID       BIGINT IDENTITY(1,1) PRIMARY KEY,
    ItemID      INT NOT NULL FOREIGN KEY REFERENCES InventoryItems(ItemID),
    Type        NVARCHAR(20) NOT NULL,  -- Purchase / Sale / Adjustment
    Qty         DECIMAL(18,2) NOT NULL,
    UnitPrice   DECIMAL(18,2) NOT NULL DEFAULT 0,
    SupplierID  INT NULL FOREIGN KEY REFERENCES Suppliers(SupplierID),
    TxnDate     DATE NOT NULL DEFAULT CAST(GETDATE() AS DATE),
    Notes       NVARCHAR(500) NULL,
    CreatedAt   DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy   INT NULL FOREIGN KEY REFERENCES Users(UserID)
);
GO
CREATE INDEX IX_InvTxn_ItemID ON InventoryTransactions(ItemID);
CREATE INDEX IX_InvTxn_Date   ON InventoryTransactions(TxnDate);
GO

PRINT 'Schema created successfully.';
GO

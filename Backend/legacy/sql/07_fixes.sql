/* ============================================================================
   CONTOURA LABS — GYM MANAGEMENT SYSTEM
   FIX SCRIPT (07_fixes.sql) — Run AFTER all other scripts
   ----------------------------------------------------------------------------
   Fixes 4 issues discovered during install:
   1. sp_Dashboard_Stats: ambiguous BaseSalary column (Payroll vs Staff)
   2. sp_Trainers_List / sp_Trainers_Get: 'Phone' should be 'Mobile' on Staff
   3. PaymentMethods / IncomeCategories: IDs ended up as 0-4 instead of 1-5
      (caused by DBCC CHECKIDENT on empty tables)
   4. Attendance sample data: DATEADD(MINUTE, ...) on DATE column fails
   ============================================================================ */

USE GymDB;
GO

/* ================================================================== */
/* FIX 1: sp_Dashboard_Stats — qualify BaseSalary as p.BaseSalary     */
/* ================================================================== */

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

    -- FIX: qualify BaseSalary as p.BaseSalary (Payroll table)
    SELECT @SalaryDue = ISNULL(SUM(p.BaseSalary + p.Bonus + p.Overtime + p.Commission - p.LeaveDeduction),0)
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

/* ================================================================== */
/* FIX 2: sp_Trainers_List / sp_Trainers_Get — s.Phone → s.Mobile     */
/* ================================================================== */

CREATE OR ALTER PROCEDURE sp_Trainers_List
    @BranchID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  t.TrainerID, t.StaffID, t.Specialization, t.Experience, t.IsActive,
            s.FullName AS StaffName, s.Mobile AS Phone, s.Photo, s.Email,
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
    SELECT  t.*, s.FullName AS StaffName, s.Mobile AS Phone, s.Photo, s.Email, s.Designation,
            s.BranchID, b.Name AS BranchName
    FROM    Trainers t
    JOIN    Staff s ON s.StaffID = t.StaffID
    LEFT JOIN Branches b ON b.BranchID = s.BranchID
    WHERE   t.TrainerID = @TrainerID;
END;
GO

/* ================================================================== */
/* FIX 3: Re-seed PaymentMethods and IncomeCategories with correct IDs*/
/* ================================================================== */

-- PaymentMethods: reset to IDs 1-5
DELETE FROM FeeCollections WHERE MethodID NOT IN (SELECT MethodID FROM PaymentMethods);
DELETE FROM PaymentMethods;
DBCC CHECKIDENT ('PaymentMethods', RESEED, 0);
SET IDENTITY_INSERT PaymentMethods ON;
INSERT INTO PaymentMethods (MethodID, Name, IsActive) VALUES
(1, 'Cash',     1),
(2, 'Bank',     1),
(3, 'Card',     1),
(4, 'JazzCash', 1),
(5, 'EasyPaisa',1);
SET IDENTITY_INSERT PaymentMethods OFF;
GO

-- IncomeCategories: reset to IDs 1-4
DELETE FROM IncomeRecords WHERE CategoryID NOT IN (SELECT CatID FROM IncomeCategories);
DELETE FROM IncomeCategories;
DBCC CHECKIDENT ('IncomeCategories', RESEED, 0);
SET IDENTITY_INSERT IncomeCategories ON;
INSERT INTO IncomeCategories (CatID, Name, IsActive) VALUES
(1, 'Membership',        1),
(2, 'Personal Training', 1),
(3, 'Product Sales',     1),
(4, 'Miscellaneous',     1);
SET IDENTITY_INSERT IncomeCategories OFF;
GO

/* ================================================================== */
/* FIX 4: Re-insert the FeeCollections that failed (FK violation)     */
/* ================================================================== */

-- Clean up any partial inserts first
DELETE FROM FeeCollections;
DBCC CHECKIDENT ('FeeCollections', RESEED, 0);
SET IDENTITY_INSERT FeeCollections ON;
INSERT INTO FeeCollections (CollectionID, InvoiceID, MemberID, Amount, MethodID, TransactionRef, CollectedBy, BranchID, CollectedAt, Notes) VALUES
(1,  1, 1, 28000.00, 1, NULL,         4, 1, '2024-01-10 11:20:00', NULL),
(2,  2, 2, 3000.00,  4, 'JC998877',   4, 1, '2024-01-15 14:05:00', NULL),
(3,  3, 3, 8000.00,  2, 'TR-552211',  4, 1, '2024-02-01 10:00:00', NULL),
(4,  4, 4, 3000.00,  1, NULL,         4, 1, '2024-02-12 16:30:00', NULL),
(5,  5, 5, 28000.00, 3, 'CARD-XXXX1234', 4, 1, '2024-03-01 12:15:00', NULL),
(6,  6, 6, 15000.00, 1, NULL,         4, 1, '2024-03-15 09:45:00', NULL),
(7,  7, 7, 1500.00,  1, NULL,         4, 1, '2024-04-05 15:00:00', 'Partial payment'),
(8,  8, 8, 8000.00,  5, 'EP-778899',  4, 1, '2024-04-20 13:20:00', NULL),
(9, 10,10, 3000.00,  1, NULL,         4, 1, '2024-05-12 17:10:00', NULL),
(10,11,11, 28000.00, 2, 'TR-998877',  4, 1, '2024-06-01 11:00:00', NULL),
(11,13,13, 8000.00,  1, NULL,         4, 1, '2024-07-01 14:00:00', NULL),
(12,14,14, 3000.00,  4, 'JC-556677',  4, 1, '2024-07-15 16:30:00', NULL),
(13,15,15, 15000.00, 1, NULL,         4, 1, '2024-08-01 10:00:00', NULL),
(14,17,17, 28000.00, 3, 'CARD-XXXX5678', 4, 1, '2024-09-01 11:45:00', NULL),
(15,18,18, 3000.00,  1, NULL,         4, 1, '2024-09-15 15:30:00', NULL),
(16,19,19, 4000.00,  1, NULL,         4, 1, '2024-10-01 12:00:00', 'Partial payment'),
(17,20,20, 3000.00,  5, 'EP-112233',  4, 1, '2024-10-15 14:30:00', NULL);
SET IDENTITY_INSERT FeeCollections OFF;
GO

-- Sync invoices PaidAmount + Status with the now-inserted collections
UPDATE Invoices SET PaidAmount = 28000.00, Status = 'Paid'    WHERE InvoiceID = 1;
UPDATE Invoices SET PaidAmount = 3000.00,  Status = 'Paid'    WHERE InvoiceID = 2;
UPDATE Invoices SET PaidAmount = 8000.00,  Status = 'Paid'    WHERE InvoiceID = 3;
UPDATE Invoices SET PaidAmount = 3000.00,  Status = 'Paid'    WHERE InvoiceID = 4;
UPDATE Invoices SET PaidAmount = 28000.00, Status = 'Paid'    WHERE InvoiceID = 5;
UPDATE Invoices SET PaidAmount = 15000.00, Status = 'Paid'    WHERE InvoiceID = 6;
UPDATE Invoices SET PaidAmount = 1500.00,  Status = 'Partial' WHERE InvoiceID = 7;
UPDATE Invoices SET PaidAmount = 8000.00,  Status = 'Paid'    WHERE InvoiceID = 8;
UPDATE Invoices SET PaidAmount = 3000.00,  Status = 'Paid'    WHERE InvoiceID = 10;
UPDATE Invoices SET PaidAmount = 28000.00, Status = 'Paid'    WHERE InvoiceID = 11;
UPDATE Invoices SET PaidAmount = 8000.00,  Status = 'Paid'    WHERE InvoiceID = 13;
UPDATE Invoices SET PaidAmount = 3000.00,  Status = 'Paid'    WHERE InvoiceID = 14;
UPDATE Invoices SET PaidAmount = 15000.00, Status = 'Paid'    WHERE InvoiceID = 15;
UPDATE Invoices SET PaidAmount = 28000.00, Status = 'Paid'    WHERE InvoiceID = 17;
UPDATE Invoices SET PaidAmount = 3000.00,  Status = 'Paid'    WHERE InvoiceID = 18;
UPDATE Invoices SET PaidAmount = 4000.00,  Status = 'Partial' WHERE InvoiceID = 19;
UPDATE Invoices SET PaidAmount = 3000.00,  Status = 'Paid'    WHERE InvoiceID = 20;
GO

/* ================================================================== */
/* FIX 5: Re-insert the IncomeRecords that failed                     */
/* ================================================================== */

DELETE FROM IncomeRecords;
DBCC CHECKIDENT ('IncomeRecords', RESEED, 0);
SET IDENTITY_INSERT IncomeRecords ON;
INSERT INTO IncomeRecords (IncomeID, BranchID, CategoryID, Source, Amount, IncomeDate, Notes, CreatedBy) VALUES
(1, 1, 2, 'Personal training — Hamza (5 sessions)', 5000.00, '2024-08-15','PT package', 6),
(2, 1, 2, 'Personal training — Ahmed (10 sessions)', 10000.00, '2024-09-05','PT package', 6),
(3, 1, 3, 'Whey protein sales', 8000.00, '2024-09-20','Supplement sales', 6),
(4, 1, 3, 'Towel + bottle sales', 2500.00, '2024-10-12','Accessories', 6),
(5, 1, 4, 'Locker rental', 1500.00, '2024-10-15','Misc income', 6);
SET IDENTITY_INSERT IncomeRecords OFF;
GO

/* ================================================================== */
/* FIX 6: Attendance — cast DATE to DATETIME before DATEADD(MINUTE)   */
/* ================================================================== */

DELETE FROM Attendance;
DBCC CHECKIDENT ('Attendance', RESEED, 0);

;WITH days AS (
    SELECT TOP (14) DATEADD(DAY, -1 * (ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1), CAST(GETDATE() AS DATE)) AS d
    FROM master..spt_values
),
visitPairs AS (
    SELECT d.d AS CheckDate, m.MemberID
    FROM days d
    CROSS JOIN (VALUES (1),(2),(3),(4),(5),(7),(8),(9),(11),(13),(15),(17),(19),(20)) AS m(MemberID)
)
INSERT INTO Attendance (MemberID, BranchID, CheckInTime, CheckOutTime, Method, CreatedBy)
SELECT  v.MemberID, 1,
        DATEADD(MINUTE, 360 + CAST(RAND(CHECKSUM(NEWID()))*720 AS INT), CAST(v.CheckDate AS DATETIME2)),
        DATEADD(MINUTE, 540 + CAST(RAND(CHECKSUM(NEWID()))*720 AS INT), CAST(v.CheckDate AS DATETIME2)),
        'Manual', 4
FROM    visitPairs v;
GO

/* ================================================================== */
/* VERIFY                                                              */
/* ================================================================== */

PRINT '=== VERIFICATION ===';
PRINT '';

SELECT 'PaymentMethods' AS TableName, COUNT(*) AS [RowCount] FROM PaymentMethods
UNION ALL SELECT 'IncomeCategories', COUNT(*) FROM IncomeCategories
UNION ALL SELECT 'FeeCollections', COUNT(*) FROM FeeCollections
UNION ALL SELECT 'IncomeRecords', COUNT(*) FROM IncomeRecords
UNION ALL SELECT 'Attendance', COUNT(*) FROM Attendance;

PRINT '';
PRINT '=== All fixes applied successfully. ===';
GO

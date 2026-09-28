-- =====================================================================
-- Contoura Gym ERP — Migration 07 of 10
-- Master file seeds (gym + payroll + finance) and LeaveType migration:
-- LeaveType rows move into MasterFile(masterType='LeaveType'), the
-- [LeaveType] table is dropped, Leave gets leaveNo/branchId and
-- backfills LV-0001 business ids.
-- Idempotent: guarded inserts/updates.
-- =====================================================================
SET NOCOUNT ON;
GO
PRINT '=== 07: master files + leave types ===';

-- 1. Universal master file defaults
IF OBJECT_ID('dbo.MasterFile') IS NOT NULL
BEGIN
    INSERT INTO [dbo].[MasterFile] ([id],[masterType],[code],[name],[branchId],[description],[isActive],[extra],[createdAt],[updatedAt])
    SELECT LOWER(REPLACE(NEWID(),'-','')), t.[masterType], t.[code], t.[name], NULL, NULL, 1, t.[extra], SYSDATETIME(), SYSDATETIME()
    FROM (VALUES
        ('Department','001','Management',NULL),('Department','002','Operations',NULL),('Department','003','Trainers',NULL),
        ('Department','004','Reception',NULL),('Department','005','Housekeeping',NULL),('Department','006','Finance',NULL),('Department','007','Sales',NULL),
        ('Designation','001','Manager',NULL),('Designation','002','Trainer',NULL),('Designation','003','Receptionist',NULL),
        ('Designation','004','Accountant',NULL),('Designation','005','Cleaner',NULL),('Designation','006','Salesperson',NULL),
        ('Education','001','Matric',NULL),('Education','002','Intermediate',NULL),('Education','003','Bachelor',NULL),
        ('Education','004','Master',NULL),('Education','005','Certification',NULL),
        ('Currency','001','PKR',NULL),('Currency','002','USD',NULL),('Currency','003','EUR',NULL),('Currency','004','GBP',NULL),
        ('Equipment','001','Treadmill',NULL),('Equipment','002','Exercise Bike',NULL),('Equipment','003','Elliptical',NULL),
        ('Equipment','004','Rowing Machine',NULL),('Equipment','005','Dumbbells',NULL),('Equipment','006','Bench Press',NULL),
        ('Equipment','007','Squat Rack',NULL),('Equipment','008','Leg Press',NULL),
        ('CardTypes','001','Credit Card',NULL),('CardTypes','002','Debit Card',NULL),
        ('Banks','001','HBL',NULL),('Banks','002','UBL',NULL),('Banks','003','MCB',NULL),
        ('Banks','004','Allied Bank',NULL),('Banks','005','Bank Alfalah',NULL),('Banks','006','Meezan Bank',NULL)
    ) t([masterType],[code],[name],[extra])
    WHERE NOT EXISTS (SELECT 1 FROM [dbo].[MasterFile] mf WHERE mf.[masterType]=t.[masterType] AND mf.[name]=t.[name]);
    PRINT '  master file defaults seeded.';
END
GO

-- 2. Leave types: legacy [LeaveType] -> MasterFile(masterType='LeaveType')
IF OBJECT_ID('dbo.LeaveType') IS NOT NULL AND OBJECT_ID('dbo.MasterFile') IS NOT NULL
BEGIN
    INSERT INTO [dbo].[MasterFile] ([id],[masterType],[code],[name],[branchId],[description],[isActive],[extra],[createdAt],[updatedAt])
    SELECT LOWER(REPLACE(NEWID(),'-','')), 'LeaveType', UPPER(LEFT(lt.[name],3)), lt.[name], NULL, NULL, 1,
           CONCAT('{"name":"',lt.[name],'","allowedDays":',lt.[allowedDays],',"isPaid":', CASE WHEN lt.[isPaid]=1 THEN 'true' ELSE 'false' END, '}'),
           SYSDATETIME(), SYSDATETIME()
    FROM [dbo].[LeaveType] lt
    WHERE NOT EXISTS (SELECT 1 FROM [dbo].[MasterFile] mf WHERE mf.[masterType]='LeaveType' AND mf.[name]=lt.[name]);
    PRINT '  leave types migrated to MasterFile.';
END
ELSE
BEGIN
    -- seed defaults when no legacy table exists
    IF OBJECT_ID('dbo.MasterFile') IS NOT NULL
    BEGIN
        INSERT INTO [dbo].[MasterFile] ([id],[masterType],[code],[name],[isActive],[extra],[createdAt],[updatedAt])
        SELECT LOWER(REPLACE(NEWID(),'-','')), 'LeaveType', UPPER(LEFT(t.[name],3)), t.[name], 1, t.[extra], SYSDATETIME(), SYSDATETIME()
        FROM (VALUES
            ('Casual','{"name":"Casual","allowedDays":10,"isPaid":true}'),
            ('Sick','{"name":"Sick","allowedDays":10,"isPaid":true}'),
            ('Paid','{"name":"Paid","allowedDays":5,"isPaid":true}'),
            ('Unpaid','{"name":"Unpaid","allowedDays":0,"isPaid":false}')
        ) t([name],[extra])
        WHERE NOT EXISTS (SELECT 1 FROM [dbo].[MasterFile] mf WHERE mf.[masterType]='LeaveType' AND mf.[name]=t.[name]);
    END
END
GO

-- 3. Payroll master file defaults
IF OBJECT_ID('dbo.PayrollMasterFile') IS NULL
CREATE TABLE [dbo].[PayrollMasterFile] (
    [id]        NVARCHAR(50)  NOT NULL PRIMARY KEY DEFAULT REPLACE(NEWID(),'-',''),
    [code]      NVARCHAR(50)  NOT NULL UNIQUE,
    [name]      NVARCHAR(255) NOT NULL,
    [type]      NVARCHAR(255) NOT NULL,               -- Earning | Deduction
    [calcType]  NVARCHAR(255) NOT NULL DEFAULT 'Fixed', -- Fixed | Percent
    [amount]    FLOAT         NOT NULL DEFAULT 0,
    [isActive]  BIT           NOT NULL DEFAULT 1,
    [branchId]  NVARCHAR(50)  NULL,
    [createdAt] DATETIME2     NOT NULL CONSTRAINT DF_PMF_created DEFAULT SYSDATETIME(),
    [updatedAt] DATETIME2     NOT NULL CONSTRAINT DF_PMF_updated DEFAULT SYSDATETIME()
);
GO
INSERT INTO [dbo].[PayrollMasterFile] ([id],[code],[name],[type],[calcType],[amount],[isActive],[createdAt],[updatedAt])
SELECT LOWER(REPLACE(NEWID(),'-','')), t.[code], t.[name], t.[type], t.[calcType], t.[amount], 1, SYSDATETIME(), SYSDATETIME()
FROM (VALUES
    ('PMF-001','Basic Salary','Earning','Fixed',0),
    ('PMF-002','Fuel Allowance','Earning','Fixed',0),
    ('PMF-003','House Rent Allowance','Earning','Fixed',0),
    ('PMF-004','Overtime','Earning','Percent',0),
    ('PMF-005','SESSI','Deduction','Percent',6),
    ('PMF-006','EOBI','Deduction','Fixed',1000),
    ('PMF-007','Advance Recovery','Deduction','Fixed',0)
) t([code],[name],[type],[calcType],[amount])
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[PayrollMasterFile] p WHERE p.[code]=t.[code]);
GO

-- 4. Leave: add leaveNo + branchId, backfill LV-0001
IF OBJECT_ID('dbo.Leave') IS NOT NULL
BEGIN
    IF COL_LENGTH('dbo.Leave','leaveNo') IS NULL
        ALTER TABLE [dbo].[Leave] ADD [leaveNo] NVARCHAR(50) NULL;
    IF COL_LENGTH('dbo.Leave','branchId') IS NULL
        ALTER TABLE [dbo].[Leave] ADD [branchId] NVARCHAR(50) NULL;

    -- branch from staff
    UPDATE l SET l.[branchId] = s.[branchId] FROM [dbo].[Leave] l JOIN [dbo].[Staff] s ON s.[id] = l.[staffId] WHERE l.[branchId] IS NULL;

    -- backfill leave numbers
    ;WITH R AS (
        SELECT [id], ROW_NUMBER() OVER (ORDER BY [fromDate], [createdAt]) AS rn
        FROM [dbo].[Leave] WHERE [leaveNo] IS NULL
    )
    UPDATE l SET l.[leaveNo] = CONCAT('LV-', FORMAT(r.rn, '0004'))
    FROM [dbo].[Leave] l JOIN R r ON r.[id] = l.[id];

    -- dedupe any pre-existing numbers colliding with the new range
    ;WITH D AS (
        SELECT [id], [leaveNo], ROW_NUMBER() OVER (PARTITION BY [leaveNo] ORDER BY [createdAt]) rn
        FROM [dbo].[Leave] WHERE [leaveNo] LIKE 'LV-%'
    )
    UPDATE l SET l.[leaveNo] = CONCAT('LV-', FORMAT(9000 + D.rn, '0004'))
    FROM [dbo].[Leave] l JOIN D ON D.[id] = l.[id] WHERE D.rn > 1;

    DECLARE @lvpk sysname = (SELECT name FROM sys.key_constraints WHERE type='PK' AND parent_object_id=OBJECT_ID('dbo.Leave'));
    IF @lvpk IS NOT NULL AND COL_LENGTH('dbo.Leave','leaveNo') IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE type='UQ' AND parent_object_id=OBJECT_ID('dbo.Leave') AND name LIKE '%leaveNo%')
        EXEC ('CREATE UNIQUE INDEX UQ_Leave_leaveNo ON [dbo].[Leave]([leaveNo]) WHERE [leaveNo] IS NOT NULL');

    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name='FK_Leave_branch')
        ALTER TABLE [dbo].[Leave] ADD CONSTRAINT FK_Leave_branch FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]);

    -- sequence after backfill
    IF EXISTS (SELECT 1 FROM [dbo].[Leave] WHERE [leaveNo] LIKE 'LV-%')
        MERGE [dbo].[IdSequence] AS t
        USING (SELECT 'LEAVE' AS k, MAX(CAST(SUBSTRING([leaveNo],4,10) AS INT))+1 AS n FROM [dbo].[Leave] WHERE [leaveNo] LIKE 'LV-%') AS s
        ON t.[key]=s.k
        WHEN MATCHED AND t.[next] < s.n THEN UPDATE SET t.[next]=s.n
        WHEN NOT MATCHED THEN INSERT ([key],[next]) VALUES (s.k, s.n);
END
GO
PRINT '=== 07 done ===';

/* ============================================================================
   CONTOURA LABS — GYM MANAGEMENT SYSTEM
   SQL Server 2022 — SEED DATA (04_seed.sql)
   ----------------------------------------------------------------------------
   - System roles + permissions
   - Super user: username = contouralabs  | password = Contoura@2024
   - Demo users per role (passwords given in comments)
   - 2 branches, 6 membership plans, payment methods, departments
   - Income categories, settings defaults
   ============================================================================ */

USE GymDB;
GO

-- Clean slate (only run on a fresh DB!)
DELETE FROM RolePermissions;
DELETE FROM AuditLogs;
DELETE FROM UserSessions;
DELETE FROM PasswordResets;
DELETE FROM Notifications;
DELETE FROM SalarySlips;
DELETE FROM Payroll;
DELETE FROM StaffLeaves;
DELETE FROM StaffAttendance;
DELETE FROM Staff;
DELETE FROM Departments;
DELETE FROM ProgressPhotos;
DELETE FROM ProgressTracking;
DELETE FROM DietPlanItems;
DELETE FROM DietPlans;
DELETE FROM WorkoutPlanItems;
DELETE FROM WorkoutPlans;
DELETE FROM Trainers;
DELETE FROM InventoryTransactions;
DELETE FROM InventoryItems;
DELETE FROM Suppliers;
DELETE FROM EquipmentMaintenance;
DELETE FROM Equipment;
DELETE FROM Refunds;
DELETE FROM FeeCollections;
DELETE FROM Invoices;
DELETE FROM MemberDocuments;
IF OBJECT_ID('dbo.MembershipFreezes','U') IS NOT NULL DELETE FROM MembershipFreezes; -- table dropped by 08_phase9_changes.sql
DELETE FROM MemberMemberships;
DELETE FROM Members;
DELETE FROM MembershipPlans;
DELETE FROM Attendance;
DELETE FROM IncomeRecords;
DELETE FROM IncomeCategories;
DELETE FROM Expenses;
DELETE FROM PaymentMethods;
DELETE FROM Settings;
DELETE FROM Users;
DELETE FROM Permissions;
DELETE FROM Roles;
DELETE FROM Branches;

DBCC CHECKIDENT ('Branches',            RESEED, 0);
DBCC CHECKIDENT ('Roles',               RESEED, 0);
DBCC CHECKIDENT ('Permissions',         RESEED, 0);
DBCC CHECKIDENT ('Users',               RESEED, 0);
DBCC CHECKIDENT ('MembershipPlans',     RESEED, 0);
DBCC CHECKIDENT ('Departments',         RESEED, 0);
DBCC CHECKIDENT ('Staff',               RESEED, 0);
DBCC CHECKIDENT ('Trainers',            RESEED, 0);
DBCC CHECKIDENT ('PaymentMethods',      RESEED, 0);
DBCC CHECKIDENT ('IncomeCategories',    RESEED, 0);
GO

/* ------------------------------------------------------------------ */
/* BRANCHES (insert before Users because Users FK to Branches)         */
/* ------------------------------------------------------------------ */

SET IDENTITY_INSERT Branches ON;
INSERT INTO Branches (BranchID, Code, Name, Address, City, Phone, Email, ManagerName, IsActive) VALUES
(1, 'HQ',     'Contoura Fitness HQ',      'Main Boulevard, Gulberg III',   'Lahore',  '+92 42 111 222 333', 'hq@contourafitness.com',   'Mr. Ahmed Raza',     1),
(2, 'DHA',    'Contoura Fitness DHA',     'Street 12, Y Block, DHA Phase 4','Lahore',  '+92 42 111 444 555', 'dha@contourafitness.com',  'Ms. Sana Khan',      1);
SET IDENTITY_INSERT Branches OFF;
GO

/* ------------------------------------------------------------------ */
/* ROLES                                                               */
/* ------------------------------------------------------------------ */

SET IDENTITY_INSERT Roles ON;
INSERT INTO Roles (RoleID, Name, Description, IsSystem) VALUES
(1, 'Super Admin',   'Full system access. Bypasses all permission checks.', 1),
(2, 'Owner',         'Branch owner. Full access except system-level settings.', 1),
(3, 'Manager',       'Day-to-day operations management.', 1),
(4, 'Receptionist',  'Front desk: members, attendance, fees collection.', 1),
(5, 'Trainer',       'Member workouts, diet, progress.', 1),
(6, 'Accountant',    'Finance, payroll, expenses, reports.', 1),
(7, 'Staff',         'General staff — limited view-only access.', 1);
SET IDENTITY_INSERT Roles OFF;
GO

/* ------------------------------------------------------------------ */
/* PERMISSIONS                                                         */
/* Module list: dashboard, members, memberships, attendance, fees,
   finance, payroll, staff, masters, workouts, diet, progress,
   equipment, inventory, reports, branches, settings, users, audit   */
/* ------------------------------------------------------------------ */

SET IDENTITY_INSERT Permissions ON;
INSERT INTO Permissions (PermissionID, Module, Action, Description) VALUES
-- dashboard
(1,  'dashboard',   'view',   'View dashboard'),
-- members
(2,  'members',     'view',   'View members list'),
(3,  'members',     'add',    'Add new member'),
(4,  'members',     'edit',   'Edit member'),
(5,  'members',     'delete', 'Delete member'),
(6,  'members',     'print',  'Print member profile'),
(7,  'members',     'export', 'Export members to Excel'),
-- memberships
(8,  'memberships', 'view',   'View membership plans'),
(9,  'memberships', 'add',    'Add membership plans / active memberships'),
(10, 'memberships', 'edit',   'Edit / renew / freeze / cancel'),
(11, 'memberships', 'delete', 'Delete membership plan'),
(12, 'memberships', 'export', 'Export memberships'),
-- attendance
(13, 'attendance',  'view',   'View attendance'),
(14, 'attendance',  'add',    'Mark attendance'),
(15, 'attendance',  'edit',   'Edit attendance'),
(16, 'attendance',  'delete', 'Delete attendance'),
(17, 'attendance',  'export', 'Export attendance'),
-- fees
(18, 'fees',        'view',   'View fees / invoices'),
(19, 'fees',        'add',    'Collect fees / create invoice'),
(20, 'fees',        'edit',   'Edit fee records'),
(21, 'fees',        'delete', 'Delete fee records'),
(22, 'fees',        'print',  'Print receipts / invoices'),
(23, 'fees',        'export', 'Export fees'),
-- finance
(24, 'finance',     'view',   'View income / expenses'),
(25, 'finance',     'add',    'Add income / expense'),
(26, 'finance',     'edit',   'Edit finance records'),
(27, 'finance',     'delete', 'Delete finance records'),
(28, 'finance',     'export', 'Export finance reports'),
-- payroll
(29, 'payroll',     'view',   'View payroll'),
(30, 'payroll',     'add',    'Generate payroll'),
(31, 'payroll',     'edit',   'Edit payroll'),
(32, 'payroll',     'print',  'Print salary slips'),
(33, 'payroll',     'export', 'Export payroll'),
-- staff
(34, 'staff',       'view',   'View staff'),
(35, 'staff',       'add',    'Add staff'),
(36, 'staff',       'edit',   'Edit staff'),
(37, 'staff',       'delete', 'Delete staff'),
(38, 'staff',       'export', 'Export staff'),
-- trainers module merged into staff (08_phase9_changes.sql) — no trainers.* permissions
-- workouts
(43, 'workouts',    'view',   'View workout plans'),
(44, 'workouts',    'add',    'Create workout plans'),
(45, 'workouts',    'edit',   'Edit workout plans'),
(46, 'workouts',    'delete', 'Delete workout plans'),
-- diet
(47, 'diet',        'view',   'View diet plans'),
(48, 'diet',        'add',    'Create diet plans'),
(49, 'diet',        'edit',   'Edit diet plans'),
(50, 'diet',        'delete', 'Delete diet plans'),
-- progress
(51, 'progress',    'view',   'View progress'),
(52, 'progress',    'add',    'Add progress entry'),
(53, 'progress',    'edit',   'Edit progress'),
(54, 'progress',    'delete', 'Delete progress'),
-- equipment
(55, 'equipment',   'view',   'View equipment'),
(56, 'equipment',   'add',    'Add equipment'),
(57, 'equipment',   'edit',   'Edit equipment'),
(58, 'equipment',   'delete', 'Delete equipment'),
-- inventory
(59, 'inventory',   'view',   'View inventory'),
(60, 'inventory',   'add',    'Add inventory items / transactions'),
(61, 'inventory',   'edit',   'Edit inventory'),
(62, 'inventory',   'delete', 'Delete inventory'),
(63, 'inventory',   'export', 'Export inventory'),
-- reports
(64, 'reports',     'view',   'View reports'),
(65, 'reports',     'print',  'Print reports'),
(66, 'reports',     'export', 'Export reports'),
-- branches
(67, 'branches',    'view',   'View branches'),
(68, 'branches',    'add',    'Add branch'),
(69, 'branches',    'edit',   'Edit branch'),
(70, 'branches',    'delete', 'Delete branch'),
-- settings
(71, 'settings',    'view',   'View settings'),
(72, 'settings',    'edit',   'Edit settings'),
-- users
(73, 'users',       'view',   'View users'),
(74, 'users',       'add',    'Add user'),
(75, 'users',       'edit',   'Edit user'),
(76, 'users',       'delete', 'Delete user'),
-- audit
(77, 'audit',       'view',   'View audit logs'),
(78, 'audit',       'export', 'Export audit logs'),
-- master files
(79, 'masters',     'view',   'View master files'),
(80, 'masters',     'add',    'Add master file data'),
(81, 'masters',     'edit',   'Edit master file data'),
(82, 'masters',     'delete', 'Delete master file data'),
(83, 'masters',     'status', 'Activate / deactivate master file data');
SET IDENTITY_INSERT Permissions OFF;
GO

/* ------------------------------------------------------------------ */
/* ROLE PERMISSIONS                                                    */
/* Super Admin (RoleID=1) bypasses all checks — no rows needed, but we
   insert all 79 for completeness.                                     */
/* ------------------------------------------------------------------ */

INSERT INTO RolePermissions (RoleID, PermissionID)
SELECT 1, PermissionID FROM Permissions;

-- Owner (2): everything except branches add/edit/delete + users delete + audit export
INSERT INTO RolePermissions (RoleID, PermissionID)
SELECT 2, PermissionID FROM Permissions
WHERE PermissionID NOT IN (68,69,70,76);

-- Manager (3): operations; no settings, no branches, no users delete, no audit export, no masters delete
INSERT INTO RolePermissions (RoleID, PermissionID)
SELECT 3, PermissionID FROM Permissions
WHERE PermissionID NOT IN (68,69,70,71,72,76,78,82);

-- Receptionist (4): dashboard view + members full + memberships view/add/edit + attendance full + fees full + staff view
INSERT INTO RolePermissions (RoleID, PermissionID)
VALUES (4,1),(4,2),(4,3),(4,4),(4,5),(4,6),(4,7),
       (4,8),(4,9),(4,10),(4,12),
       (4,13),(4,14),(4,15),(4,16),(4,17),
       (4,18),(4,19),(4,20),(4,22),(4,23),
       (4,34),(4,51),(4,52),(4,53),(4,64),(4,65),
       (4,79);

-- Trainer (5): dashboard view, members view, attendance view+add, workouts full, diet full, progress full, staff view
INSERT INTO RolePermissions (RoleID, PermissionID)
VALUES (5,1),(5,2),(5,3),(5,4),(5,6),(5,7),
       (5,13),(5,14),
       (5,34),(5,43),(5,44),(5,45),(5,46),
       (5,79),
       (5,47),(5,48),(5,49),(5,50),
       (5,51),(5,52),(5,53),(5,54);

-- Accountant (6): dashboard view, members view, fees full, finance full, payroll full, reports full
INSERT INTO RolePermissions (RoleID, PermissionID)
VALUES (6,1),(6,2),(6,18),(6,19),(6,20),(6,21),(6,22),(6,23),
       (6,24),(6,25),(6,26),(6,27),(6,28),
       (6,29),(6,30),(6,31),(6,32),(6,33),
       (6,34),(6,64),(6,65),(6,66),
       (6,79);

-- Staff (7): dashboard view + members view + attendance view only
INSERT INTO RolePermissions (RoleID, PermissionID)
VALUES (7,1),(7,2),(7,13),(7,79);
GO

/* ------------------------------------------------------------------ */
/* USERS                                                               */
/* Passwords are stored as plain text using the pattern username + 123 */
/* Example: contouralabs / contouralabs123                              */
/* ------------------------------------------------------------------ */

DECLARE @HashSuper   NVARCHAR(255) = 'contouralabs123';
DECLARE @HashOwner   NVARCHAR(255) = 'owner.ahmed123';
DECLARE @HashManager NVARCHAR(255) = 'manager.sana123';
DECLARE @HashReception NVARCHAR(255) = 'reception.ali123';
DECLARE @HashTrainer NVARCHAR(255) = 'trainer.bilal123';
DECLARE @HashAccountant NVARCHAR(255) = 'acc.fatima123';
DECLARE @HashStaff   NVARCHAR(255) = 'staff.zohaib123';

SET IDENTITY_INSERT Users ON;
INSERT INTO Users (UserID, Username, Email, FullName, PasswordHash, RoleID, BranchID, Phone, IsActive, CreatedBy) VALUES
(1, 'contouralabs', 'contouralabs@gmail.com',        'Contoura Labs Super Admin', @HashSuper,   1, NULL, '+92 342 2642366', 1, 1),
(2, 'owner.ahmed',  'owner@contourafitness.com',     'Ahmed Raza (Owner)',        @HashOwner,   2, 1,    '+92 300 1234567', 1, 1),
(3, 'manager.sana', 'manager@contourafitness.com',   'Sana Khan (Manager)',       @HashManager, 3, 1,    '+92 300 2222222', 1, 1),
(4, 'reception.ali','reception@contourafitness.com', 'Ali Hassan (Receptionist)', @HashReception, 4, 1, '+92 300 3333333', 1, 1),
(5, 'trainer.bilal','trainer@contourafitness.com',   'Bilal Ahmed (Trainer)',     @HashTrainer, 5, 1,    '+92 300 4444444', 1, 1),
(6, 'acc.fatima',   'accounts@contourafitness.com',  'Fatima Noor (Accountant)',  @HashAccountant, 6, 1, '+92 300 5555555', 1, 1),
(7, 'staff.zohaib', 'staff@contourafitness.com',     'Zohaib Khan (Staff)',       @HashStaff,   7, 1,    '+92 300 6666666', 1, 1);
SET IDENTITY_INSERT Users OFF;
GO

/* ------------------------------------------------------------------ */
/* MEMBERSHIP PLANS                                                    */
/* ------------------------------------------------------------------ */

SET IDENTITY_INSERT MembershipPlans ON;
INSERT INTO MembershipPlans (PlanID, Name, DurationMonths, Price, JoiningFee, Discount, Description, IsActive, CreatedBy) VALUES
(1, 'Monthly',     1,   3000.00,  500.00, 0.00,  'Standard monthly membership',       1, 1),
(2, 'Quarterly',   3,   8000.00,  500.00, 5.00,  '3-month membership — 5% off',       1, 1),
(3, 'Half Year',   6,  15000.00,  500.00, 10.00, '6-month membership — 10% off',      1, 1),
(4, 'Annual',     12,  28000.00,  0.00,    15.00, '12-month membership — 15% off + no joining fee', 1, 1),
(5, 'Lifetime',    0, 100000.00,  0.00,    0.00,  'Lifetime membership (one-time)',    1, 1),
(6, 'Student',     1,   2000.00,  300.00, 0.00,  'Discounted monthly plan for students', 1, 1);
SET IDENTITY_INSERT MembershipPlans OFF;
GO

/* ------------------------------------------------------------------ */
/* PAYMENT METHODS                                                     */
/* ------------------------------------------------------------------ */

INSERT INTO PaymentMethods (Name) VALUES
('Cash'), ('Bank'), ('Card'), ('JazzCash'), ('EasyPaisa');
GO

/* ------------------------------------------------------------------ */
/* DEPARTMENTS                                                         */
/* ------------------------------------------------------------------ */

SET IDENTITY_INSERT Departments ON;
INSERT INTO Departments (DepartmentID, Name, Description) VALUES
(1, 'Reception',  'Front desk operations'),
(2, 'Trainers',   'Fitness trainers'),
(3, 'Accountant', 'Finance and accounts'),
(4, 'Cleaner',    'Cleaning and housekeeping'),
(5, 'Security',   'Building security');
SET IDENTITY_INSERT Departments OFF;
GO

/* ------------------------------------------------------------------ */
/* STAFF + TRAINERS                                                    */
/* ------------------------------------------------------------------ */

SET IDENTITY_INSERT Staff ON;
INSERT INTO Staff (StaffID, BranchID, DepartmentID, UserID, FullName, FatherName, CNIC, Mobile, Email, Address, JoiningDate, Designation, BaseSalary, Status, StaffCode, CreatedBy) VALUES
(1, 1, 2, 5, 'Bilal Ahmed',     'Muhammad Ahmed',  '35201-1234567-1', '+92 300 4444444', 'trainer.bilal@contourafitness.com',  'Gulberg, Lahore', '2023-01-15', 'Senior Trainer',     45000.00, 'Active', '1/0001', 1),
(2, 1, 1, 4, 'Ali Hassan',      'Hassan Mahmood',  '35201-2345678-2', '+92 300 3333333', 'reception.ali@contourafitness.com',  'Model Town, Lahore','2023-03-01', 'Receptionist',        30000.00, 'Active', '1/0002', 1),
(3, 1, 3, 6, 'Fatima Noor',     'Noor Muhammad',   '35201-3456789-3', '+92 300 5555555', 'acc.fatima@contourafitness.com',     'Johar Town, Lahore','2022-11-10', 'Accountant',          55000.00, 'Active', '1/0003', 1),
(4, 1, 4, 7, 'Zohaib Khan',     'Khan Bahadur',    '35201-4567890-4', '+92 300 6666666', 'staff.zohaib@contourafitness.com',   'Iqbal Town, Lahore','2023-06-20', 'Cleaner',             20000.00, 'Active', '1/0004', 1),
(5, 1, 5, NULL,'Imran Saleem',   'Saleem Akhtar',   '35201-5678901-5', '+92 300 7777777', NULL,                                  'Cantt, Lahore',     '2023-02-05', 'Security Guard',      25000.00, 'Active', '1/0005', 1),
(6, 2, 2, NULL,'Usman Tariq',    'Tariq Mehmood',   '35202-6789012-6', '+92 300 8888888', NULL,                                  'DHA Phase 4, Lahore','2023-04-12','Trainer',             40000.00, 'Active', '2/0001', 1);
SET IDENTITY_INSERT Staff OFF;
GO

SET IDENTITY_INSERT Trainers ON;
INSERT INTO Trainers (TrainerID, StaffID, Specialization, Experience, IsActive) VALUES
(1, 1, 'Strength & Conditioning, Powerlifting', '7 years', 1),
(2, 6, 'Bodybuilding, Nutrition',               '5 years', 1);
SET IDENTITY_INSERT Trainers OFF;
GO

/* ------------------------------------------------------------------ */
/* INCOME CATEGORIES                                                   */
/* ------------------------------------------------------------------ */

INSERT INTO IncomeCategories (Name) VALUES
('Membership'), ('Personal Training'), ('Product Sales'), ('Miscellaneous');
GO

/* ------------------------------------------------------------------ */
/* SETTINGS                                                            */
/* ------------------------------------------------------------------ */

INSERT INTO Settings ([Key], Value, Category, UpdatedBy) VALUES
('GymName',          'Contoura Fitness',                     'general', 1),
('GymAddress',       'Main Boulevard, Gulberg III, Lahore',  'general', 1),
('GymPhone',         '+92 42 111 222 333',                   'general', 1),
('GymEmail',         'info@contourafitness.com',             'general', 1),
('Currency',         'PKR',                                  'general', 1),
('CurrencySymbol',   'Rs',                                   'general', 1),
('TaxPercent',       '0',                                    'finance', 1),
('LateFeeAmount',    '200',                                  'finance', 1),
('ReceiptFooter',    'Thank you for your business!',         'receipt', 1),
('DefaultTheme',     'light',                                'theme',   1),
('LogoPath',         '/assets/contoura-logo.svg',            'general', 1),
('DeveloperName',    'Contoura Labs',                        'general', 1),
('DeveloperEmail',   'contouralabs@gmail.com',               'general', 1),
('DeveloperPhone',   '+92 342 2642366',                      'general', 1),
('DeveloperWebsite', 'https://contoura-labs.vercel.app/',    'general', 1),
('MultiBranchEnabled','1',                                   'general', 1);
GO

PRINT 'Seed data inserted successfully.';
GO

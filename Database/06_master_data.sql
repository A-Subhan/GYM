-- ============================================================================
-- Contoura Gym Management System - STEP 6: Master Data (required to run)
-- ============================================================================
-- Seeds everything the application needs to boot and to pass authentication,
-- against the FINAL schema:
--   Defaults (company settings, write-once name), Branches (hierarchy
--   00 Contoura Gym > 01 Head Office > 01001 / 01002, id = code),
--   Roles, Permissions (150), RolePermission grants, the admin user
--   (login: admin / admin123), Chart of Accounts ([charts], id = account
--   code, parentCode='ROOT' for tree roots), Financial Years + periods,
--   Tax Heads, Account Mappings + Finance Defaults, Membership plans
--   (business ids BR-001/SEP26/000xx), Shifts 001/002/003, payrollmaster
--   heads 001-005 (Country, Education, Leave Type, Department, Designation),
--   gymmaster heads 001-004 (Exercise, Equipment, Exercise Type, Trainer
--   Specializations) with details, financemaster heads 001-003 (Banks,
--   Card Types, Currency) with details, payrollmasterfile Leave Types,
--   Allowances, MasterFile departments/designations/educations, base
--   staff (trainer EMP-0001) and Food items.
--
-- Plain INSERTs intended for an EMPTY database created by steps 01-05.
-- Account ids ARE the account codes; AccountMapping/FinanceDefaults
-- reference codes directly.
-- ===========================================================================

USE [GymDB];
GO

SET NOCOUNT ON;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET XACT_ABORT ON;

-- Error tracking + skip flag (temp tables survive across GO batches).
IF OBJECT_ID(N'tempdb..#sql_errors') IS NOT NULL DROP TABLE #sql_errors;
CREATE TABLE #sql_errors (step nvarchar(100) NOT NULL, message nvarchar(2048) NOT NULL);
IF OBJECT_ID(N'tempdb..#skip') IS NOT NULL DROP TABLE #skip;
CREATE TABLE #skip (reason nvarchar(200) NOT NULL);

-- Re-run guard: if master data is already seeded, this file does nothing.
IF EXISTS (SELECT 1 FROM dbo.[Defaults])
    INSERT INTO #skip VALUES (N'master data already present');
GO

-- ============================================================================
-- Main seed: ONE transaction. Any statement failure rolls back everything and
-- is recorded in #sql_errors, so the success message at the end cannot lie.
-- ============================================================================
IF NOT EXISTS (SELECT 1 FROM #skip) AND NOT EXISTS (SELECT 1 FROM #sql_errors)
BEGIN
    BEGIN TRAN;

    BEGIN TRY
-- Company (1 rows)
INSERT INTO [Defaults] ([id], [companyName], [address], [phone], [email], [website], [logo], [strn], [ntn], [fbr], [financeType], [coaLevelDigits], [coaLocked], [createdAt], [updatedAt]) VALUES ('CMP-001', 'Contoura Gym', 'Main Boulevard, Karachi', '+92 21 0000000', 'info@contouragym.com', NULL, NULL, NULL, NULL, NULL, 'FIFO', '2', 0, '2026-09-22T20:53:50.332Z', '2026-09-22T20:53:50.332Z');

-- Branch (hierarchy, id = code): 00 Contoura Gym > 01 Head Office > 01001 Head Office / 01002 DHA Branch
INSERT INTO [Branch] ([id], [code], [name], [parentId], [nodeType], [address], [city], [phone], [email], [strn], [ntn], [logo], [isActive], [createdAt], [updatedAt], [isDeleted]) VALUES ('00', '00', 'Contoura Gym', NULL, 'Control', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 1, '2026-09-22T20:53:50.333Z', '2026-09-22T20:53:50.333Z', 0);
INSERT INTO [Branch] ([id], [code], [name], [parentId], [nodeType], [address], [city], [phone], [email], [strn], [ntn], [logo], [isActive], [createdAt], [updatedAt], [isDeleted]) VALUES ('01', '01', 'Head Office', '00', 'Control', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 1, '2026-09-22T20:53:50.333Z', '2026-09-22T20:53:50.333Z', 0);
INSERT INTO [Branch] ([id], [code], [name], [parentId], [nodeType], [address], [city], [phone], [email], [strn], [ntn], [logo], [isActive], [createdAt], [updatedAt], [isDeleted]) VALUES ('01001', '01001', 'Head Office', '01', 'Detail', NULL, 'Karachi', '+92 21 0000000', 'hq@contouragym.com', NULL, NULL, NULL, 1, '2026-09-22T20:53:50.333Z', '2026-09-22T20:53:50.333Z', 0);
INSERT INTO [Branch] ([id], [code], [name], [parentId], [nodeType], [address], [city], [phone], [email], [strn], [ntn], [logo], [isActive], [createdAt], [updatedAt], [isDeleted]) VALUES ('01002', '01002', 'DHA Branch', '01', 'Detail', 'Sector 5, DHA', 'Karachi', '+92 21 111222333', 'dha@contouragym.com', NULL, NULL, NULL, 1, '2026-01-05T00:00:00.000Z', '2026-01-05T00:00:00.000Z', 0);

-- Role (7 rows)
INSERT INTO [Role] ([id], [name], [description], [isSystem], [createdAt], [updatedAt]) VALUES ('ROL-001', 'Super Admin', 'Super Admin role (system)', 1, '2026-09-22T20:53:50.005Z', '2026-09-23T15:35:43.697Z');
INSERT INTO [Role] ([id], [name], [description], [isSystem], [createdAt], [updatedAt]) VALUES ('ROL-002', 'Owner', 'Owner role (system)', 1, '2026-09-22T20:53:50.110Z', '2026-09-23T15:35:43.806Z');
INSERT INTO [Role] ([id], [name], [description], [isSystem], [createdAt], [updatedAt]) VALUES ('ROL-003', 'Manager', 'Manager role (system)', 1, '2026-09-22T20:53:50.220Z', '2026-09-23T15:35:43.914Z');
INSERT INTO [Role] ([id], [name], [description], [isSystem], [createdAt], [updatedAt]) VALUES ('ROL-004', 'Accountant', 'Accountant role (system)', 1, '2026-09-22T20:53:50.271Z', '2026-09-23T15:35:43.988Z');
INSERT INTO [Role] ([id], [name], [description], [isSystem], [createdAt], [updatedAt]) VALUES ('ROL-005', 'Receptionist', 'Receptionist role (system)', 1, '2026-09-22T20:53:50.312Z', '2026-09-23T15:35:44.008Z');
INSERT INTO [Role] ([id], [name], [description], [isSystem], [createdAt], [updatedAt]) VALUES ('ROL-006', 'Trainer', 'Trainer role (system)', 1, '2026-09-22T20:53:50.321Z', '2026-09-23T15:35:44.020Z');
INSERT INTO [Role] ([id], [name], [description], [isSystem], [createdAt], [updatedAt]) VALUES ('ROL-007', 'Staff', 'Staff role (system)', 1, '2026-09-22T20:53:50.329Z', '2026-09-23T15:35:44.029Z');

-- Permission (148 rows)
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0001', 'dashboard', 'view', 'dashboard.view', 'View dashboard');
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0002', 'members', 'view', 'members.view', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0003', 'members', 'add', 'members.add', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0004', 'members', 'edit', 'members.edit', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0005', 'members', 'delete', 'members.delete', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0006', 'members', 'print', 'members.print', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0007', 'members', 'export', 'members.export', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0008', 'members', 'status', 'members.status', 'Change member status (bulk)');
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0009', 'memberships', 'view', 'memberships.view', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0010', 'memberships', 'add', 'memberships.add', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0011', 'memberships', 'edit', 'memberships.edit', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0012', 'memberships', 'delete', 'memberships.delete', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0013', 'memberships', 'export', 'memberships.export', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0014', 'attendance', 'view', 'attendance.view', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0015', 'attendance', 'add', 'attendance.add', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0016', 'attendance', 'edit', 'attendance.edit', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0017', 'attendance', 'delete', 'attendance.delete', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0018', 'attendance', 'export', 'attendance.export', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0019', 'fees', 'view', 'fees.view', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0020', 'fees', 'add', 'fees.add', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0021', 'fees', 'edit', 'fees.edit', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0022', 'fees', 'delete', 'fees.delete', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0023', 'fees', 'print', 'fees.print', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0024', 'fees', 'export', 'fees.export', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0025', 'fees', 'post', 'fees.post', 'Post fee payment (auto-voucher)');
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0026', 'finance', 'view', 'finance.view', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0027', 'finance', 'add', 'finance.add', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0028', 'finance', 'edit', 'finance.edit', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0029', 'finance', 'delete', 'finance.delete', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0030', 'finance', 'export', 'finance.export', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0031', 'finance', 'post', 'finance.post', 'Post voucher');
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0032', 'finance', 'reverse', 'finance.reverse', 'Reverse voucher');
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0033', 'finance', 'periods', 'finance.periods', 'Manage accounting periods');
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0034', 'finance', 'reconcile', 'finance.reconcile', 'Bank reconciliation');
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0035', 'finance', 'settings', 'finance.settings', 'Finance defaults');
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0036', 'finance', 'coa', 'finance.coa', 'Chart of Accounts');
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0037', 'finance', 'reports', 'finance.reports', 'Finance reports');
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0038', 'finance', 'configure', 'finance.config', 'Configure finance mappings');
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0039', 'vouchers', 'view', 'vouchers.view', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0040', 'vouchers', 'add', 'vouchers.add', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0041', 'vouchers', 'edit', 'vouchers.edit', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0042', 'vouchers', 'delete', 'vouchers.delete', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0043', 'vouchers', 'print', 'vouchers.print', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0044', 'vouchers', 'post', 'vouchers.post', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0045', 'vouchers', 'reverse', 'vouchers.reverse', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0046', 'vouchers', 'export', 'vouchers.export', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0047', 'cheques', 'view', 'cheques.view', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0048', 'cheques', 'status', 'cheques.status', 'Update cheque status (bulk)');
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0049', 'cheques', 'export', 'cheques.export', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0050', 'tax', 'view', 'tax.view', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0051', 'tax', 'add', 'tax.add', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0052', 'tax', 'edit', 'tax.edit', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0053', 'tax', 'delete', 'tax.delete', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0054', 'prospects', 'view', 'prospects.view', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0055', 'prospects', 'add', 'prospects.add', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0056', 'prospects', 'edit', 'prospects.edit', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0057', 'prospects', 'delete', 'prospects.delete', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0058', 'prospects', 'convert', 'prospects.convert', 'Convert prospect to member');
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0059', 'prospects', 'export', 'prospects.export', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0060', 'freeze', 'view', 'freeze.view', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0061', 'freeze', 'add', 'freeze.add', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0062', 'freeze', 'edit', 'freeze.edit', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0063', 'freeze', 'delete', 'freeze.delete', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0064', 'followups', 'view', 'followups.view', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0065', 'followups', 'add', 'followups.add', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0066', 'followups', 'delete', 'followups.delete', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0067', 'workouts', 'view', 'workouts.view', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0068', 'workouts', 'add', 'workouts.add', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0069', 'workouts', 'edit', 'workouts.edit', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0070', 'workouts', 'delete', 'workouts.delete', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0071', 'workouts', 'assign', 'workouts.assign', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0072', 'diet', 'view', 'diet.view', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0073', 'diet', 'add', 'diet.add', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0074', 'diet', 'edit', 'diet.edit', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0075', 'diet', 'delete', 'diet.delete', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0076', 'diet', 'assign', 'diet.assign', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0077', 'progress', 'view', 'progress.view', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0078', 'progress', 'add', 'progress.add', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0079', 'progress', 'edit', 'progress.edit', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0080', 'progress', 'delete', 'progress.delete', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0081', 'equipment', 'view', 'equipment.view', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0082', 'equipment', 'add', 'equipment.add', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0083', 'equipment', 'edit', 'equipment.edit', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0084', 'equipment', 'delete', 'equipment.delete', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0085', 'equipment', 'status', 'equipment.status', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0086', 'equipment', 'maintenance', 'equipment.maintenance', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0087', 'inventory', 'view', 'inventory.view', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0088', 'inventory', 'add', 'inventory.add', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0089', 'inventory', 'edit', 'inventory.edit', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0090', 'inventory', 'delete', 'inventory.delete', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0091', 'inventory', 'export', 'inventory.export', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0092', 'pos', 'view', 'pos.view', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0093', 'pos', 'add', 'pos.add', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0094', 'pos', 'edit', 'pos.edit', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0095', 'pos', 'delete', 'pos.delete', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0096', 'pos', 'export', 'pos.export', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0097', 'staff', 'view', 'staff.view', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0098', 'staff', 'add', 'staff.add', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0099', 'staff', 'edit', 'staff.edit', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0100', 'staff', 'delete', 'staff.delete', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0101', 'staff', 'export', 'staff.export', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0102', 'shifts', 'view', 'shifts.view', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0103', 'shifts', 'add', 'shifts.add', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0104', 'shifts', 'edit', 'shifts.edit', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0105', 'shifts', 'delete', 'shifts.delete', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0106', 'calendar', 'view', 'calendar.view', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0107', 'calendar', 'edit', 'calendar.edit', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0108', 'leaves', 'view', 'leaves.view', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0109', 'leaves', 'add', 'leaves.add', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0110', 'leaves', 'approve', 'leaves.approve', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0111', 'leaves', 'delete', 'leaves.delete', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0112', 'overtime', 'view', 'overtime.view', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0113', 'overtime', 'add', 'overtime.add', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0114', 'overtime', 'approve', 'overtime.approve', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('perm-overtime-edit', 'overtime', 'edit', 'overtime.edit', N'Edit overtime entries');
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('perm-overtime-delete', 'overtime', 'delete', 'overtime.delete', N'Delete overtime entries');
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0115', 'payroll', 'view', 'payroll.view', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0116', 'payroll', 'add', 'payroll.add', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0117', 'payroll', 'edit', 'payroll.edit', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0118', 'payroll', 'post', 'payroll.post', 'Post payroll payment');
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0119', 'payroll', 'export', 'payroll.export', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0120', 'branches', 'view', 'branches.view', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0121', 'branches', 'add', 'branches.add', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0122', 'branches', 'edit', 'branches.edit', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0123', 'branches', 'delete', 'branches.delete', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0124', 'users', 'view', 'users.view', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0125', 'users', 'add', 'users.add', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0126', 'users', 'edit', 'users.edit', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0127', 'users', 'delete', 'users.delete', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0128', 'roles', 'view', 'roles.view', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0129', 'roles', 'add', 'roles.add', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0130', 'roles', 'edit', 'roles.edit', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0131', 'roles', 'delete', 'roles.delete', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0132', 'roles', 'configure', 'roles.config', 'Assign permissions to role');
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0133', 'audit', 'view', 'audit.view', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0134', 'audit', 'export', 'audit.export', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0135', 'company', 'view', 'company.view', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0136', 'company', 'edit', 'company.edit', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0137', 'accountMappings', 'view', 'accountMappings.view', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0138', 'accountMappings', 'edit', 'accountMappings.edit', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0139', 'reports', 'view', 'reports.view', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0140', 'reports', 'export', 'reports.export', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0141', 'reports', 'customize', 'reports.customize', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0142', 'backup', 'view', 'backup.view', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0143', 'backup', 'add', 'backup.run', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0144', 'masters', 'view', 'masters.view', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0145', 'masters', 'add', 'masters.add', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0146', 'masters', 'edit', 'masters.edit', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0147', 'masters', 'delete', 'masters.delete', NULL);
INSERT INTO [Permission] ([id], [module], [action], [code], [description]) VALUES ('PRM-0148', 'masters', 'status', 'masters.status', 'Change master record status');

-- RolePermission (460 rows)
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0138');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0137');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'perm-overtime-edit');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'perm-overtime-delete');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0015');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0017');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0016');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0018');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0014');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0134');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0133');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0143');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0142');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0121');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0123');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0122');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0120');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0107');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0106');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0049');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0048');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0047');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0136');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0135');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0001');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0073');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0076');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0075');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0074');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0072');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0082');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0084');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0083');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0086');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0085');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0081');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0020');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0022');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0021');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0024');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0025');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0023');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0019');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0027');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0036');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0038');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0029');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0028');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0030');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0033');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0031');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0034');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0037');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0032');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0035');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0026');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0065');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0066');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0064');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0061');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0063');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0062');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0060');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0088');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0090');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0089');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0091');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0087');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0109');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0110');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0111');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0108');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0145');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0147');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0146');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0148');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0144');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0003');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0005');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0004');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0007');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0006');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0008');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0002');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0010');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0012');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0011');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0013');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0009');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0113');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0114');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0112');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0116');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0117');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0119');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0118');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0115');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0093');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0095');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0094');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0096');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0092');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0078');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0080');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0079');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0077');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0055');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0058');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0057');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0056');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0059');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0054');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0141');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0140');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0139');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0129');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0132');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0131');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0130');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0128');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0103');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0105');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0104');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0102');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0098');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0100');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0099');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0101');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0097');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0051');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0053');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0052');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0050');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0125');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0127');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0126');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0124');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0040');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0042');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0041');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0046');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0044');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0043');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0045');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0039');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0068');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0071');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0070');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0069');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-001', 'PRM-0067');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0138');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0137');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0015');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0017');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0016');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0018');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0014');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0134');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0133');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0143');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0142');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0121');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0123');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0122');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0120');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0107');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0106');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0049');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0048');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0047');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0136');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0135');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0001');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0073');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0076');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0075');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0074');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0072');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0082');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0084');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0083');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0086');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0085');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0081');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0020');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0022');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0021');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0024');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0025');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0023');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0019');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0027');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0036');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0038');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0029');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0028');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0030');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0033');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0031');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0034');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0037');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0032');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0035');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0026');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0065');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0066');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0064');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0061');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0063');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0062');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0060');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0088');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0090');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0089');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0091');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0087');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0109');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0110');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0111');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0108');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0145');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0147');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0146');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0148');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0144');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0003');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0005');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0004');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0007');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0006');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0008');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0002');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0010');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0012');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0011');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0013');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0009');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0113');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0114');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0112');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0116');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0117');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0119');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0118');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0115');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0093');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0095');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0094');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0096');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0092');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0078');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0080');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0079');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0077');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0055');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0058');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0057');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0056');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0059');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0054');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0141');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0140');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0139');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0129');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0132');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0131');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0130');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0128');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0103');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0105');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0104');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0102');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0098');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0100');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0099');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0101');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0097');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0051');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0053');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0052');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0050');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0125');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0127');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0126');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0124');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0040');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0042');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0041');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0046');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0044');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0043');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0045');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0039');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0068');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0071');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0070');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0069');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-002', 'PRM-0067');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0015');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0016');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0018');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0014');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0120');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0107');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0106');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0049');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0048');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0047');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0001');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0073');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0076');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0074');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0072');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0082');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0083');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0086');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0085');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0081');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0020');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0021');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0024');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0025');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0023');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0019');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0027');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0028');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0030');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0037');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0026');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0065');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0066');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0064');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0061');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0062');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0060');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0088');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0089');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0091');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0087');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0110');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0108');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0145');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0147');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0146');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0148');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0144');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0003');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0004');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0007');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0006');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0008');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0002');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0010');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0011');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0009');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0114');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0112');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0116');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0117');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0119');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0115');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0093');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0094');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0096');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0092');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0078');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0079');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0077');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0055');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0058');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0056');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0059');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0054');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0140');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0139');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0102');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0098');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0099');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0097');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0050');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0040');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0041');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0046');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0044');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0043');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0039');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0068');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0071');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0069');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-003', 'PRM-0067');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-004', 'PRM-0049');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-004', 'PRM-0048');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-004', 'PRM-0047');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-004', 'PRM-0001');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-004', 'PRM-0024');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-004', 'PRM-0025');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-004', 'PRM-0023');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-004', 'PRM-0019');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-004', 'PRM-0027');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-004', 'PRM-0036');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-004', 'PRM-0028');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-004', 'PRM-0030');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-004', 'PRM-0033');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-004', 'PRM-0031');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-004', 'PRM-0034');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-004', 'PRM-0037');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-004', 'PRM-0032');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-004', 'PRM-0035');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-004', 'PRM-0026');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-004', 'PRM-0119');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-004', 'PRM-0115');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-004', 'PRM-0096');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-004', 'PRM-0092');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-004', 'PRM-0140');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-004', 'PRM-0139');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-004', 'PRM-0051');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-004', 'PRM-0052');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-004', 'PRM-0050');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-004', 'PRM-0040');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-004', 'PRM-0041');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-004', 'PRM-0046');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-004', 'PRM-0044');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-004', 'PRM-0043');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-004', 'PRM-0045');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-004', 'PRM-0039');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-005', 'PRM-0015');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-005', 'PRM-0014');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-005', 'PRM-0001');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-005', 'PRM-0020');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-005', 'PRM-0025');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-005', 'PRM-0023');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-005', 'PRM-0019');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-005', 'PRM-0065');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-005', 'PRM-0064');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-005', 'PRM-0003');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-005', 'PRM-0004');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-005', 'PRM-0006');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-005', 'PRM-0002');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-005', 'PRM-0009');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-005', 'PRM-0093');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-005', 'PRM-0092');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-005', 'PRM-0055');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-005', 'PRM-0058');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-005', 'PRM-0056');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-005', 'PRM-0054');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-006', 'PRM-0014');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-006', 'PRM-0001');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-006', 'PRM-0073');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-006', 'PRM-0076');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-006', 'PRM-0074');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-006', 'PRM-0072');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-006', 'PRM-0002');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-006', 'PRM-0078');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-006', 'PRM-0079');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-006', 'PRM-0077');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-006', 'PRM-0068');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-006', 'PRM-0071');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-006', 'PRM-0069');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-006', 'PRM-0067');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-007', 'PRM-0014');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-007', 'PRM-0001');
INSERT INTO [RolePermission] ([roleId], [permissionId]) VALUES ('ROL-007', 'PRM-0002');

-- User (1 rows)
INSERT INTO [User] ([id], [username], [email], [fullName], [passwordHash], [userType], [roleId], [branchId], [accessibleBranchIds], [phone], [photo], [isActive], [failedLoginCount], [lastLoginAt], [mustChangePassword], [createdAt], [updatedAt], [isDeleted]) VALUES ('USR-0001', 'admin', 'admin@contouragym.com', 'System Administrator', '$2b$10$4sWId8YdsNlr39HgQ51wE.5rFtEFE3l5APRnRO6rYlE15bOUryvpy', 'Admin', 'ROL-001', '01001', '*', NULL, NULL, 1, 0, '2026-09-23T11:58:33.500Z', 0, '2026-09-22T20:53:50.473Z', '2026-09-23T15:35:44.137Z', 0);

-- Account (13 rows: 1 ROOT anchor + 5 control roots + 7 detail accounts)
-- The 'ROOT' anchor row is REQUIRED: parentCode is NOT NULL and carries a
-- self-referencing FK to charts.id, while the application uses the sentinel
-- value 'ROOT' for tree roots (Backend/src/app/api/charts/route.ts and
-- Backend/tools/seed.ts). Without this row, charts_parentCode_fkey rejects
-- every root account and the whole seed cascades into FK failures.
INSERT INTO [charts] ([id], [name], [parentCode], [accountType], [bookType], [accountTag], [isControl], [isDetail], [isActive], [branchId], [contactName], [phone], [email], [address], [bankName], [bankAccountNo], [bankBranch], [cnic], [ntn], [strn], [fbr], [otherName], [referenceNumber], [faxNumber], [city], [country], [website], [paymentTerms], [registrationNumber], [description], [createdAt], [updatedAt]) VALUES ('ROOT', 'Chart of Accounts Root', 'ROOT', 'Asset', NULL, NULL, 1, 0, 1, '01001', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, N'Sentinel parent for top-level accounts', '2026-09-22T20:54:10.390Z', '2026-09-22T20:54:10.390Z');
INSERT INTO [charts] ([id], [name], [parentCode], [accountType], [bookType], [accountTag], [isControl], [isDetail], [isActive], [branchId], [contactName], [phone], [email], [address], [bankName], [bankAccountNo], [bankBranch], [cnic], [ntn], [strn], [fbr], [otherName], [referenceNumber], [faxNumber], [city], [country], [website], [paymentTerms], [registrationNumber], [description], [createdAt], [updatedAt]) VALUES ('01', 'Assets', 'ROOT', 'Asset', NULL, NULL, 1, 0, 1, '01001', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-09-22T20:54:10.391Z', '2026-09-22T20:54:10.391Z');
INSERT INTO [charts] ([id], [name], [parentCode], [accountType], [bookType], [accountTag], [isControl], [isDetail], [isActive], [branchId], [contactName], [phone], [email], [address], [bankName], [bankAccountNo], [bankBranch], [cnic], [ntn], [strn], [fbr], [otherName], [referenceNumber], [faxNumber], [city], [country], [website], [paymentTerms], [registrationNumber], [description], [createdAt], [updatedAt]) VALUES ('02', 'Liabilities', 'ROOT', 'Liability', NULL, NULL, 1, 0, 1, '01001', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-09-22T20:54:10.392Z', '2026-09-22T20:54:10.392Z');
INSERT INTO [charts] ([id], [name], [parentCode], [accountType], [bookType], [accountTag], [isControl], [isDetail], [isActive], [branchId], [contactName], [phone], [email], [address], [bankName], [bankAccountNo], [bankBranch], [cnic], [ntn], [strn], [fbr], [otherName], [referenceNumber], [faxNumber], [city], [country], [website], [paymentTerms], [registrationNumber], [description], [createdAt], [updatedAt]) VALUES ('03', 'Capital / Equity', 'ROOT', 'Equity', NULL, NULL, 1, 0, 1, '01001', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-09-22T20:54:10.393Z', '2026-09-22T20:54:10.393Z');
INSERT INTO [charts] ([id], [name], [parentCode], [accountType], [bookType], [accountTag], [isControl], [isDetail], [isActive], [branchId], [contactName], [phone], [email], [address], [bankName], [bankAccountNo], [bankBranch], [cnic], [ntn], [strn], [fbr], [otherName], [referenceNumber], [faxNumber], [city], [country], [website], [paymentTerms], [registrationNumber], [description], [createdAt], [updatedAt]) VALUES ('04', 'Revenue', 'ROOT', 'Revenue', NULL, NULL, 1, 0, 1, '01001', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-09-22T20:54:10.394Z', '2026-09-22T20:54:10.394Z');
INSERT INTO [charts] ([id], [name], [parentCode], [accountType], [bookType], [accountTag], [isControl], [isDetail], [isActive], [branchId], [contactName], [phone], [email], [address], [bankName], [bankAccountNo], [bankBranch], [cnic], [ntn], [strn], [fbr], [otherName], [referenceNumber], [faxNumber], [city], [country], [website], [paymentTerms], [registrationNumber], [description], [createdAt], [updatedAt]) VALUES ('05', 'Expense', 'ROOT', 'Expense', NULL, NULL, 1, 0, 1, '01001', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-09-22T20:54:10.395Z', '2026-09-22T20:54:10.395Z');
INSERT INTO [charts] ([id], [name], [parentCode], [accountType], [bookType], [accountTag], [isControl], [isDetail], [isActive], [branchId], [contactName], [phone], [email], [address], [bankName], [bankAccountNo], [bankBranch], [cnic], [ntn], [strn], [fbr], [otherName], [referenceNumber], [faxNumber], [city], [country], [website], [paymentTerms], [registrationNumber], [description], [createdAt], [updatedAt]) VALUES ('01002', 'Bank - Current A/C', '01', 'Asset', 'Bank', 'Bank', 0, 1, 1, '01001', NULL, NULL, NULL, NULL, 'HBL', '0000000000000000', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-09-22T20:54:10.398Z', '2026-09-23T11:40:02.202Z');
INSERT INTO [charts] ([id], [name], [parentCode], [accountType], [bookType], [accountTag], [isControl], [isDetail], [isActive], [branchId], [contactName], [phone], [email], [address], [bankName], [bankAccountNo], [bankBranch], [cnic], [ntn], [strn], [fbr], [otherName], [referenceNumber], [faxNumber], [city], [country], [website], [paymentTerms], [registrationNumber], [description], [createdAt], [updatedAt]) VALUES ('01003', 'Membership Receivable', '01', 'Asset', NULL, 'Customer', 0, 1, 1, '01001', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-09-22T20:54:10.400Z', '2026-09-23T11:40:02.205Z');
INSERT INTO [charts] ([id], [name], [parentCode], [accountType], [bookType], [accountTag], [isControl], [isDetail], [isActive], [branchId], [contactName], [phone], [email], [address], [bankName], [bankAccountNo], [bankBranch], [cnic], [ntn], [strn], [fbr], [otherName], [referenceNumber], [faxNumber], [city], [country], [website], [paymentTerms], [registrationNumber], [description], [createdAt], [updatedAt]) VALUES ('04001', 'Membership Fee Income', '04', 'Revenue', NULL, NULL, 0, 1, 1, '01001', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-09-22T20:54:10.401Z', '2026-09-23T11:40:02.207Z');
INSERT INTO [charts] ([id], [name], [parentCode], [accountType], [bookType], [accountTag], [isControl], [isDetail], [isActive], [branchId], [contactName], [phone], [email], [address], [bankName], [bankAccountNo], [bankBranch], [cnic], [ntn], [strn], [fbr], [otherName], [referenceNumber], [faxNumber], [city], [country], [website], [paymentTerms], [registrationNumber], [description], [createdAt], [updatedAt]) VALUES ('04002', 'POS Sales Income', '04', 'Revenue', NULL, NULL, 0, 1, 1, '01001', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-09-22T20:54:10.403Z', '2026-09-23T11:40:02.208Z');
INSERT INTO [charts] ([id], [name], [parentCode], [accountType], [bookType], [accountTag], [isControl], [isDetail], [isActive], [branchId], [contactName], [phone], [email], [address], [bankName], [bankAccountNo], [bankBranch], [cnic], [ntn], [strn], [fbr], [otherName], [referenceNumber], [faxNumber], [city], [country], [website], [paymentTerms], [registrationNumber], [description], [createdAt], [updatedAt]) VALUES ('02001', 'Sales Tax Payable', '02', 'Liability', NULL, NULL, 0, 1, 1, '01001', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-09-22T20:54:10.405Z', '2026-09-23T11:40:02.206Z');
INSERT INTO [charts] ([id], [name], [parentCode], [accountType], [bookType], [accountTag], [isControl], [isDetail], [isActive], [branchId], [contactName], [phone], [email], [address], [bankName], [bankAccountNo], [bankBranch], [cnic], [ntn], [strn], [fbr], [otherName], [referenceNumber], [faxNumber], [city], [country], [website], [paymentTerms], [registrationNumber], [description], [createdAt], [updatedAt]) VALUES ('01004', 'Equipment Supplier', '01', 'Asset', NULL, 'Vendor', 0, 1, 1, '01001', 'ABC Supplies', '+92 21 9999999', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-09-23T10:46:19.066Z', '2026-09-23T11:40:02.206Z');
INSERT INTO [charts] ([id], [name], [parentCode], [accountType], [bookType], [accountTag], [isControl], [isDetail], [isActive], [branchId], [contactName], [phone], [email], [address], [bankName], [bankAccountNo], [bankBranch], [cnic], [ntn], [strn], [fbr], [otherName], [referenceNumber], [faxNumber], [city], [country], [website], [paymentTerms], [registrationNumber], [description], [createdAt], [updatedAt]) VALUES ('01001', 'Cash in Hand', '01', 'Asset', 'Cash', 'Cash', 0, 1, 1, '01001', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-09-23T15:35:44.142Z', '2026-09-23T15:35:44.142Z');

-- TaxHead (2 rows)
INSERT INTO [TaxHead] ([id], [code], [shortName], [name], [taxType], [rate], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('TAX-001', '001', 'ST-00', 'Sales Tax 0%', 'Sales', 0, '01001', 1, '2026-09-22T20:55:25.821Z', '2026-09-22T20:55:25.821Z');
INSERT INTO [TaxHead] ([id], [code], [shortName], [name], [taxType], [rate], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('TAX-002', '002', 'ST-18', 'Sales Tax 18%', 'Sales', 18, '01001', 1, '2026-09-22T20:55:25.822Z', '2026-09-22T20:55:25.822Z');

-- AccountMapping (8 rows)
INSERT INTO [AccountMapping] ([id], [branchId], [key], [accountId], [description], [createdAt], [updatedAt])VALUES ('ACM-001', NULL, 'bankAccount', '01002', NULL, '2026-09-22T20:55:34.781Z', '2026-09-23T15:35:44.149Z');
INSERT INTO [AccountMapping] ([id], [branchId], [key], [accountId], [description], [createdAt], [updatedAt])VALUES ('ACM-002', NULL, 'feeIncome', '04001', NULL, '2026-09-22T20:55:34.782Z', '2026-09-23T15:35:44.150Z');
INSERT INTO [AccountMapping] ([id], [branchId], [key], [accountId], [description], [createdAt], [updatedAt])VALUES ('ACM-003', NULL, 'posIncome', '04002', NULL, '2026-09-22T20:55:34.783Z', '2026-09-23T15:35:44.151Z');
INSERT INTO [AccountMapping] ([id], [branchId], [key], [accountId], [description], [createdAt], [updatedAt])VALUES ('ACM-004', NULL, 'taxAccount', '02001', NULL, '2026-09-22T20:55:34.783Z', '2026-09-23T15:35:44.152Z');
INSERT INTO [AccountMapping] ([id], [branchId], [key], [accountId], [description], [createdAt], [updatedAt])VALUES ('ACM-005', NULL, 'feeReceivable', '01003', NULL, '2026-09-22T20:55:34.784Z', '2026-09-23T15:35:44.153Z');
INSERT INTO [AccountMapping] ([id], [branchId], [key], [accountId], [description], [createdAt], [updatedAt])VALUES ('ACM-006', NULL, 'posBank', '01002', NULL, '2026-09-22T20:55:34.785Z', '2026-09-23T15:35:44.155Z');
INSERT INTO [AccountMapping] ([id], [branchId], [key], [accountId], [description], [createdAt], [updatedAt])VALUES ('ACM-007', NULL, 'cashAccount', '01001', NULL, '2026-09-23T15:35:44.148Z', '2026-09-23T15:35:44.148Z');
INSERT INTO [AccountMapping] ([id], [branchId], [key], [accountId], [description], [createdAt], [updatedAt])VALUES ('ACM-008', NULL, 'posCash', '01001', NULL, '2026-09-23T15:35:44.155Z', '2026-09-23T15:35:44.155Z');

-- FinancialYear (1 rows)
INSERT INTO [FinancialYear] ([id], [name], [startDate], [endDate], [isActive], [isClosed], [createdAt]) VALUES ('cmud5lcoy004otzwlgddt2y4r', 'FY-2025', '2025-01-01T00:00:00.000Z', '2025-12-31T00:00:00.000Z', 1, 0, '2026-09-22T20:55:34.786Z');

-- AccountingPeriod (12 rows)
INSERT INTO [AccountingPeriod] ([id], [financialYearId], [name], [startDate], [endDate], [status], [createdAt]) VALUES ('cmud5lcoy004otzwlgddt2y4r-1', 'cmud5lcoy004otzwlgddt2y4r', '2025-01', '2025-01-01T00:00:00.000Z', '2025-01-31T23:59:59.000Z', 'Open', '2026-09-22T20:55:34.787Z');
INSERT INTO [AccountingPeriod] ([id], [financialYearId], [name], [startDate], [endDate], [status], [createdAt]) VALUES ('cmud5lcoy004otzwlgddt2y4r-2', 'cmud5lcoy004otzwlgddt2y4r', '2025-02', '2025-02-01T00:00:00.000Z', '2025-02-28T23:59:59.000Z', 'Open', '2026-09-22T20:55:34.788Z');
INSERT INTO [AccountingPeriod] ([id], [financialYearId], [name], [startDate], [endDate], [status], [createdAt]) VALUES ('cmud5lcoy004otzwlgddt2y4r-3', 'cmud5lcoy004otzwlgddt2y4r', '2025-03', '2025-03-01T00:00:00.000Z', '2025-03-31T23:59:59.000Z', 'Open', '2026-09-22T20:55:34.789Z');
INSERT INTO [AccountingPeriod] ([id], [financialYearId], [name], [startDate], [endDate], [status], [createdAt]) VALUES ('cmud5lcoy004otzwlgddt2y4r-4', 'cmud5lcoy004otzwlgddt2y4r', '2025-04', '2025-04-01T00:00:00.000Z', '2025-04-30T23:59:59.000Z', 'Open', '2026-09-22T20:55:34.790Z');
INSERT INTO [AccountingPeriod] ([id], [financialYearId], [name], [startDate], [endDate], [status], [createdAt]) VALUES ('cmud5lcoy004otzwlgddt2y4r-5', 'cmud5lcoy004otzwlgddt2y4r', '2025-05', '2025-05-01T00:00:00.000Z', '2025-05-31T23:59:59.000Z', 'Open', '2026-09-22T20:55:34.790Z');
INSERT INTO [AccountingPeriod] ([id], [financialYearId], [name], [startDate], [endDate], [status], [createdAt]) VALUES ('cmud5lcoy004otzwlgddt2y4r-6', 'cmud5lcoy004otzwlgddt2y4r', '2025-06', '2025-06-01T00:00:00.000Z', '2025-06-30T23:59:59.000Z', 'Open', '2026-09-22T20:55:34.791Z');
INSERT INTO [AccountingPeriod] ([id], [financialYearId], [name], [startDate], [endDate], [status], [createdAt]) VALUES ('cmud5lcoy004otzwlgddt2y4r-7', 'cmud5lcoy004otzwlgddt2y4r', '2025-07', '2025-07-01T00:00:00.000Z', '2025-07-31T23:59:59.000Z', 'Open', '2026-09-22T20:55:34.791Z');
INSERT INTO [AccountingPeriod] ([id], [financialYearId], [name], [startDate], [endDate], [status], [createdAt]) VALUES ('cmud5lcoy004otzwlgddt2y4r-8', 'cmud5lcoy004otzwlgddt2y4r', '2025-08', '2025-08-01T00:00:00.000Z', '2025-08-31T23:59:59.000Z', 'Open', '2026-09-22T20:55:34.792Z');
INSERT INTO [AccountingPeriod] ([id], [financialYearId], [name], [startDate], [endDate], [status], [createdAt]) VALUES ('cmud5lcoy004otzwlgddt2y4r-9', 'cmud5lcoy004otzwlgddt2y4r', '2025-09', '2025-09-01T00:00:00.000Z', '2025-09-30T23:59:59.000Z', 'Open', '2026-09-22T20:55:34.793Z');
INSERT INTO [AccountingPeriod] ([id], [financialYearId], [name], [startDate], [endDate], [status], [createdAt]) VALUES ('cmud5lcoy004otzwlgddt2y4r-10', 'cmud5lcoy004otzwlgddt2y4r', '2025-10', '2025-10-01T00:00:00.000Z', '2025-10-31T23:59:59.000Z', 'Open', '2026-09-22T20:55:34.793Z');
INSERT INTO [AccountingPeriod] ([id], [financialYearId], [name], [startDate], [endDate], [status], [createdAt]) VALUES ('cmud5lcoy004otzwlgddt2y4r-11', 'cmud5lcoy004otzwlgddt2y4r', '2025-11', '2025-11-01T00:00:00.000Z', '2025-11-30T23:59:59.000Z', 'Open', '2026-09-22T20:55:34.794Z');
INSERT INTO [AccountingPeriod] ([id], [financialYearId], [name], [startDate], [endDate], [status], [createdAt]) VALUES ('cmud5lcoy004otzwlgddt2y4r-12', 'cmud5lcoy004otzwlgddt2y4r', '2025-12', '2025-12-01T00:00:00.000Z', '2025-12-31T23:59:59.000Z', 'Open', '2026-09-22T20:55:34.795Z');

-- MembershipPlan (3 rows)
INSERT INTO [MembershipPlan] ([id], [name], [durationDays], [amount], [description], [isActive], [branchId], [createdAt], [updatedAt]) VALUES ('BR-001/SEP26/00001', 'Monthly', 30, 3000, 'Monthly plan', 1, '01001', '2026-09-22T20:55:34.796Z', '2026-09-22T20:55:34.796Z');
INSERT INTO [MembershipPlan] ([id], [name], [durationDays], [amount], [description], [isActive], [branchId], [createdAt], [updatedAt]) VALUES ('BR-001/SEP26/00002', 'Quarterly', 90, 8000, 'Quarterly plan', 1, '01001', '2026-09-22T20:55:34.797Z', '2026-09-22T20:55:34.797Z');
INSERT INTO [MembershipPlan] ([id], [name], [durationDays], [amount], [description], [isActive], [branchId], [createdAt], [updatedAt]) VALUES ('BR-001/SEP26/00003', 'Annual', 365, 30000, 'Annual plan', 1, '01001', '2026-09-22T20:55:34.798Z', '2026-09-22T20:55:34.798Z');

-- gymmaster + gymmasterdetail (post-migration state: heads 001-004, 16 details)
INSERT INTO [gymmaster] ([id], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('001', 'Exercise', 'Migrated from gymmasterfile', NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [gymmaster] ([id], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('002', 'Equipment', 'Migrated from gymmasterfile', NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [gymmaster] ([id], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('003', 'Exercise Type', 'Migrated from gymmasterfile', NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [gymmaster] ([id], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('004', 'Trainer Specializations', 'Trainer specialization options (from MasterFile)', NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [gymmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('001001', '001', 'Bench Press', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [gymmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('001002', '001', 'Back Squat', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [gymmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('001003', '001', 'Deadlift', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [gymmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('001004', '001', 'Treadmill Run', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [gymmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('001005', '001', 'Plank', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [gymmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('001006', '001', 'Lat Pulldown', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [gymmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('003001', '003', 'Back', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [gymmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('003002', '003', 'Chest', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [gymmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('004001', '004', 'Bodybuilding', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [gymmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('004002', '004', 'Cardio', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [gymmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('004003', '004', 'Cross Training', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [gymmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('004004', '004', 'Functional Training', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [gymmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('004005', '004', 'Muscle Building', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [gymmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('004006', '004', 'Other', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [gymmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('004007', '004', 'Strength Training', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [gymmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('004008', '004', 'Weight Loss', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());

-- financemaster + financemasterdetail (heads 001 Banks, 002 Card Types, 003 Currency)
INSERT INTO [financemaster] ([id], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('001', 'Banks', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [financemaster] ([id], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('002', 'Card Types', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [financemaster] ([id], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('003', 'Currency', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [financemasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('001001', '001', 'HBL', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [financemasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('001002', '001', 'UBL', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [financemasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('002001', '002', 'Visa Card', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [financemasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('002002', '002', 'Master Card', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [financemasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('003001', '003', 'EUR', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [financemasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('003002', '003', 'GBP', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [financemasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('003003', '003', 'PKR', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [financemasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('003004', '003', 'USD', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());

-- payrollmaster + payrollmasterdetail (heads 001-005: Country, Education, Leave Type, Department, Designation)
INSERT INTO [payrollmaster] ([id], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('001', 'Country', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [payrollmaster] ([id], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('002', 'Education', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [payrollmaster] ([id], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('003', 'Leave Type', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [payrollmaster] ([id], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('004', 'Department', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [payrollmaster] ([id], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('005', 'Designation', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [payrollmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('001001', '001', 'Pakistan', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [payrollmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('001002', '001', 'Saudi Arabia', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [payrollmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('001003', '001', 'United Arab Emirates', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [payrollmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('002001', '002', 'Bachelor', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [payrollmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('002002', '002', 'Certification', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [payrollmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('002003', '002', 'Intermediate', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [payrollmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('002004', '002', 'Master', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [payrollmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('002005', '002', 'Matric', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [payrollmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('003001', '003', 'Casual', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [payrollmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('003002', '003', 'Paid', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [payrollmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('003003', '003', 'Sick', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [payrollmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('003004', '003', 'Unpaid', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [payrollmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('004001', '004', 'Finance', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [payrollmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('004002', '004', 'Housekeeping', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [payrollmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('004003', '004', 'Management', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [payrollmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('004004', '004', 'Operations', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [payrollmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('004005', '004', 'Reception', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [payrollmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('004006', '004', 'Sales', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [payrollmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('004007', '004', 'Trainers', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [payrollmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('005001', '005', 'Accountant', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [payrollmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('005002', '005', 'Cleaner', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [payrollmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('005003', '005', 'Manager', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [payrollmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('005004', '005', 'Receptionist', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [payrollmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('005005', '005', 'Salesperson', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [payrollmasterdetail] ([id], [masterId], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('005006', '005', 'Trainer', NULL, NULL, 1, SYSDATETIME(), SYSDATETIME());

-- Shift (3 rows)
INSERT INTO [Shift] ([id], [name], [timeIn], [timeOut], [workingDays], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('001', 'Morning', '06:00', '14:00', 'Mon,Tue,Wed,Thu,Fri,Sat', '01001', 1, '2026-09-22T20:55:34.799Z', '2026-09-22T20:55:34.799Z');
INSERT INTO [Shift] ([id], [name], [timeIn], [timeOut], [workingDays], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('002', 'Evening', '14:00', '22:00', 'Mon,Tue,Wed,Thu,Fri,Sat', '01001', 1, '2026-09-22T20:55:34.800Z', '2026-09-22T20:55:34.800Z');
INSERT INTO [Shift] ([id], [name], [timeIn], [timeOut], [workingDays], [branchId], [isActive], [createdAt], [updatedAt]) VALUES ('003', 'General', '09:00', '17:00', 'Mon,Tue,Wed,Thu,Fri', '01001', 1, '2026-09-22T20:55:34.801Z', '2026-09-22T20:55:34.801Z');

-- LeaveType (4 rows)
INSERT INTO [payrollmasterfile] ([id], [masterType], [name], [description], [extra], [branchId], [isActive], [createdAt], [updatedAt]) VALUES (LOWER(REPLACE(NEWID(),'-','')), 'Leave Type', 'Casual', NULL, '{"allowedDays":10,"isPaid":true}', NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [payrollmasterfile] ([id], [masterType], [name], [description], [extra], [branchId], [isActive], [createdAt], [updatedAt]) VALUES (LOWER(REPLACE(NEWID(),'-','')), 'Leave Type', 'Sick', NULL, '{"allowedDays":10,"isPaid":true}', NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [payrollmasterfile] ([id], [masterType], [name], [description], [extra], [branchId], [isActive], [createdAt], [updatedAt]) VALUES (LOWER(REPLACE(NEWID(),'-','')), 'Leave Type', 'Paid', NULL, '{"allowedDays":5,"isPaid":true}', NULL, 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [payrollmasterfile] ([id], [masterType], [name], [description], [extra], [branchId], [isActive], [createdAt], [updatedAt]) VALUES (LOWER(REPLACE(NEWID(),'-','')), 'Leave Type', 'Unpaid', NULL, '{"allowedDays":0,"isPaid":false}', NULL, 1, SYSDATETIME(), SYSDATETIME());

-- Allowance (4 rows)
INSERT INTO [Allowance] ([id], [name], [description], [isStatutory], [createdAt]) VALUES ('cmud5lcph004wtzwlg51ie4pi', 'Fuel', 'Fuel allowance', 0, '2026-09-22T20:55:34.805Z');
INSERT INTO [Allowance] ([id], [name], [description], [isStatutory], [createdAt]) VALUES ('cmud5lcpi004xtzwlz6t34mm6', 'House Rent', 'House rent allowance', 0, '2026-09-22T20:55:34.807Z');
INSERT INTO [Allowance] ([id], [name], [description], [isStatutory], [createdAt]) VALUES ('cmud5lcpj004ytzwlus8e7m53', 'SESSI', 'Sindh Employees Social Security Institution', 1, '2026-09-22T20:55:34.807Z');
INSERT INTO [Allowance] ([id], [name], [description], [isStatutory], [createdAt]) VALUES ('cmud5lcpk004ztzwlfn270h3l', 'EOBI', 'Employees Old-Age Benefits Institution', 1, '2026-09-22T20:55:34.808Z');

-- Staff (1 rows)
INSERT INTO [Staff] ([id], [firstName], [lastName], [fatherGuardian], [cnic], [photo], [address], [emergencyContact], [emergencyContactNo], [phone], [whatsapp], [telephone], [fax], [email], [joiningDate], [department], [designation], [isTrainer], [branchId], [shiftId], [basicSalary], [fuelAllowance], [rentAllowance], [houseAllowance], [otherAllowance], [sessi], [eobi], [fbrTaxNumber], [overtimeAllowed], [overtimeRate], [isActive], [createdAt], [updatedAt], [isDeleted]) VALUES ('EMP-0001', 'Imran', 'Khan', NULL, NULL, NULL, NULL, NULL, NULL, '03001234567', NULL, NULL, NULL, 'imran@contouragym.com', '2025-01-01T00:00:00.000Z', 'Trainers', 'Senior Trainer', 1, '01001', '001', 40000, 0, 0, 0, 0, 0, 0, NULL, 0, 0, 1, '2026-09-23T10:46:19.064Z', '2026-09-23T10:46:19.064Z', 0);

-- MasterFile (36 rows)
INSERT INTO [MasterFile] ([id], [masterType], [code], [name], [description], [isActive], [extra], [createdAt], [updatedAt]) VALUES ('cmudrom6k0001ot8rruzejl0c', 'Department', '001', 'Management', NULL, 1, NULL, '2026-09-23T07:13:58.605Z', '2026-09-23T07:13:58.605Z');
INSERT INTO [MasterFile] ([id], [masterType], [code], [name], [description], [isActive], [extra], [createdAt], [updatedAt]) VALUES ('cmudrom6n0003ot8r1h2ultw6', 'Department', '002', 'Operations', NULL, 1, NULL, '2026-09-23T07:13:58.607Z', '2026-09-23T07:13:58.607Z');
INSERT INTO [MasterFile] ([id], [masterType], [code], [name], [description], [isActive], [extra], [createdAt], [updatedAt]) VALUES ('cmudrom6q0006ot8rhaioy2le', 'Department', '003', 'Trainers', NULL, 1, NULL, '2026-09-23T07:13:58.610Z', '2026-09-23T07:13:58.610Z');
INSERT INTO [MasterFile] ([id], [masterType], [code], [name], [description], [isActive], [extra], [createdAt], [updatedAt]) VALUES ('cmudrom6x000aot8re7x08jgp', 'Department', '004', 'Reception', NULL, 1, NULL, '2026-09-23T07:13:58.617Z', '2026-09-23T07:13:58.617Z');
INSERT INTO [MasterFile] ([id], [masterType], [code], [name], [description], [isActive], [extra], [createdAt], [updatedAt]) VALUES ('cmudrom71000dot8r177xcynk', 'Department', '005', 'Housekeeping', NULL, 1, NULL, '2026-09-23T07:13:58.622Z', '2026-09-23T07:13:58.622Z');
INSERT INTO [MasterFile] ([id], [masterType], [code], [name], [description], [isActive], [extra], [createdAt], [updatedAt]) VALUES ('cmudrom75000got8rizvbymob', 'Department', '006', 'Finance', NULL, 1, NULL, '2026-09-23T07:13:58.625Z', '2026-09-23T07:13:58.625Z');
INSERT INTO [MasterFile] ([id], [masterType], [code], [name], [description], [isActive], [extra], [createdAt], [updatedAt]) VALUES ('cmudrom78000kot8rmtfm3da4', 'Department', '007', 'Sales', NULL, 1, NULL, '2026-09-23T07:13:58.628Z', '2026-09-23T07:13:58.628Z');
INSERT INTO [MasterFile] ([id], [masterType], [code], [name], [description], [isActive], [extra], [createdAt], [updatedAt]) VALUES ('cmudrom7a000not8rsdco04qa', 'Designation', '001', 'Manager', NULL, 1, NULL, '2026-09-23T07:13:58.630Z', '2026-09-23T07:13:58.630Z');
INSERT INTO [MasterFile] ([id], [masterType], [code], [name], [description], [isActive], [extra], [createdAt], [updatedAt]) VALUES ('cmudrom7d000qot8rkwaum0mx', 'Designation', '002', 'Trainer', NULL, 1, NULL, '2026-09-23T07:13:58.633Z', '2026-09-23T07:13:58.633Z');
INSERT INTO [MasterFile] ([id], [masterType], [code], [name], [description], [isActive], [extra], [createdAt], [updatedAt]) VALUES ('cmudrom7e000tot8rqrwnyexp', 'Designation', '003', 'Receptionist', NULL, 1, NULL, '2026-09-23T07:13:58.634Z', '2026-09-23T07:13:58.634Z');
INSERT INTO [MasterFile] ([id], [masterType], [code], [name], [description], [isActive], [extra], [createdAt], [updatedAt]) VALUES ('cmudrom7f000wot8r07obyatm', 'Designation', '004', 'Accountant', NULL, 1, NULL, '2026-09-23T07:13:58.636Z', '2026-09-23T07:13:58.636Z');
INSERT INTO [MasterFile] ([id], [masterType], [code], [name], [description], [isActive], [extra], [createdAt], [updatedAt]) VALUES ('cmudrom7i000zot8rzpi0szbo', 'Designation', '005', 'Cleaner', NULL, 1, NULL, '2026-09-23T07:13:58.639Z', '2026-09-23T07:13:58.639Z');
INSERT INTO [MasterFile] ([id], [masterType], [code], [name], [description], [isActive], [extra], [createdAt], [updatedAt]) VALUES ('cmudrom7l0011ot8rj1x8tybd', 'Designation', '006', 'Salesperson', NULL, 1, NULL, '2026-09-23T07:13:58.641Z', '2026-09-23T07:13:58.641Z');
INSERT INTO [MasterFile] ([id], [masterType], [code], [name], [description], [isActive], [extra], [createdAt], [updatedAt]) VALUES ('cmudrom7n0014ot8r09u5qaq0', 'Education', '001', 'Matric', NULL, 1, NULL, '2026-09-23T07:13:58.643Z', '2026-09-23T07:13:58.643Z');
INSERT INTO [MasterFile] ([id], [masterType], [code], [name], [description], [isActive], [extra], [createdAt], [updatedAt]) VALUES ('cmudrom7p0017ot8r6yi7znbc', 'Education', '002', 'Intermediate', NULL, 1, NULL, '2026-09-23T07:13:58.645Z', '2026-09-23T07:13:58.645Z');
INSERT INTO [MasterFile] ([id], [masterType], [code], [name], [description], [isActive], [extra], [createdAt], [updatedAt]) VALUES ('cmudrom7q0019ot8rurnshnra', 'Education', '003', 'Bachelor', NULL, 1, NULL, '2026-09-23T07:13:58.646Z', '2026-09-23T07:13:58.646Z');
INSERT INTO [MasterFile] ([id], [masterType], [code], [name], [description], [isActive], [extra], [createdAt], [updatedAt]) VALUES ('cmudrom7s001bot8rebmeowuh', 'Education', '004', 'Master', NULL, 1, NULL, '2026-09-23T07:13:58.649Z', '2026-09-23T07:13:58.649Z');
INSERT INTO [MasterFile] ([id], [masterType], [code], [name], [description], [isActive], [extra], [createdAt], [updatedAt]) VALUES ('cmudrom7t001eot8rrggujv2k', 'Education', '005', 'Certification', NULL, 1, NULL, '2026-09-23T07:13:58.650Z', '2026-09-23T07:13:58.650Z');
INSERT INTO [MasterFile] ([id], [masterType], [code], [name], [description], [isActive], [extra], [createdAt], [updatedAt]) VALUES ('cmudrom7u001hot8r271bgiol', 'Currency', '001', 'PKR', NULL, 1, NULL, '2026-09-23T07:13:58.651Z', '2026-09-23T07:13:58.651Z');
INSERT INTO [MasterFile] ([id], [masterType], [code], [name], [description], [isActive], [extra], [createdAt], [updatedAt]) VALUES ('cmudrom7w001jot8rndmo6bwz', 'Currency', '002', 'USD', NULL, 1, NULL, '2026-09-23T07:13:58.652Z', '2026-09-23T07:13:58.652Z');
INSERT INTO [MasterFile] ([id], [masterType], [code], [name], [description], [isActive], [extra], [createdAt], [updatedAt]) VALUES ('cmudrom7x001lot8rb903izkt', 'Currency', '003', 'EUR', NULL, 1, NULL, '2026-09-23T07:13:58.653Z', '2026-09-23T07:13:58.653Z');
INSERT INTO [MasterFile] ([id], [masterType], [code], [name], [description], [isActive], [extra], [createdAt], [updatedAt]) VALUES ('cmudrom7z001not8rzz4bpaok', 'Currency', '004', 'GBP', NULL, 1, NULL, '2026-09-23T07:13:58.656Z', '2026-09-23T07:13:58.656Z');
INSERT INTO [MasterFile] ([id], [masterType], [code], [name], [description], [isActive], [extra], [createdAt], [updatedAt]) VALUES ('cmue1bbzu001dot9vi3efyyfc', 'Banks', '001', 'HBL', NULL, 1, NULL, '2026-09-23T11:43:35.034Z', '2026-09-23T11:43:35.034Z');
INSERT INTO [MasterFile] ([id], [masterType], [code], [name], [description], [isActive], [extra], [createdAt], [updatedAt]) VALUES ('cmue1bc0f001got9vhhxv32a1', 'Banks', '002', 'UBL', NULL, 1, NULL, '2026-09-23T11:43:35.055Z', '2026-09-23T11:43:35.055Z');
INSERT INTO [MasterFile] ([id], [masterType], [code], [name], [description], [isActive], [extra], [createdAt], [updatedAt]) VALUES ('cmue1bc0y001jot9vi9ys60lg', 'CardTypes', '001', 'Visa Card', NULL, 1, NULL, '2026-09-23T11:43:35.074Z', '2026-09-23T11:43:35.074Z');
INSERT INTO [MasterFile] ([id], [masterType], [code], [name], [description], [isActive], [extra], [createdAt], [updatedAt]) VALUES ('cmue1bc1f001mot9vl86iayxq', 'CardTypes', '002', 'Master Card', NULL, 1, NULL, '2026-09-23T11:43:35.092Z', '2026-09-23T11:43:35.092Z');
INSERT INTO [MasterFile] ([id], [masterType], [code], [name], [description], [isActive], [extra], [createdAt], [updatedAt]) VALUES ('cmue1bc1x001pot9vmksya90r', 'ExerciseCategories', '001', 'Chest', NULL, 1, NULL, '2026-09-23T11:43:35.110Z', '2026-09-23T11:43:35.110Z');
INSERT INTO [MasterFile] ([id], [masterType], [code], [name], [description], [isActive], [extra], [createdAt], [updatedAt]) VALUES ('cmue1bc2h001sot9vabdyozkq', 'ExerciseCategories', '002', 'Back', NULL, 1, NULL, '2026-09-23T11:43:35.130Z', '2026-09-23T11:43:35.130Z');
INSERT INTO [MasterFile] ([id], [masterType], [code], [name], [description], [isActive], [extra], [createdAt], [updatedAt]) VALUES ('cmue9lvd4000tottthvr5ze5j', 'TrainerSpecializations', '001', 'Weight Loss', NULL, 1, NULL, '2026-09-23T15:35:43.625Z', '2026-09-23T15:35:43.625Z');
INSERT INTO [MasterFile] ([id], [masterType], [code], [name], [description], [isActive], [extra], [createdAt], [updatedAt]) VALUES ('cmue9lvd6000votttotvcqqn9', 'TrainerSpecializations', '002', 'Muscle Building', NULL, 1, NULL, '2026-09-23T15:35:43.626Z', '2026-09-23T15:35:43.626Z');
INSERT INTO [MasterFile] ([id], [masterType], [code], [name], [description], [isActive], [extra], [createdAt], [updatedAt]) VALUES ('cmue9lvd9000xotttcfjlpcbc', 'TrainerSpecializations', '003', 'Strength Training', NULL, 1, NULL, '2026-09-23T15:35:43.629Z', '2026-09-23T15:35:43.629Z');
INSERT INTO [MasterFile] ([id], [masterType], [code], [name], [description], [isActive], [extra], [createdAt], [updatedAt]) VALUES ('cmue9lvdb0010otttt6cd30ha', 'TrainerSpecializations', '004', 'Bodybuilding', NULL, 1, NULL, '2026-09-23T15:35:43.632Z', '2026-09-23T15:35:43.632Z');
INSERT INTO [MasterFile] ([id], [masterType], [code], [name], [description], [isActive], [extra], [createdAt], [updatedAt]) VALUES ('cmue9lvdd0013otttinptpx5a', 'TrainerSpecializations', '005', 'Functional Training', NULL, 1, NULL, '2026-09-23T15:35:43.633Z', '2026-09-23T15:35:43.633Z');
INSERT INTO [MasterFile] ([id], [masterType], [code], [name], [description], [isActive], [extra], [createdAt], [updatedAt]) VALUES ('cmue9lvde0015ottto9gbelgm', 'TrainerSpecializations', '006', 'Cardio', NULL, 1, NULL, '2026-09-23T15:35:43.634Z', '2026-09-23T15:35:43.634Z');
INSERT INTO [MasterFile] ([id], [masterType], [code], [name], [description], [isActive], [extra], [createdAt], [updatedAt]) VALUES ('cmue9lvdf0017otttyjepq7qd', 'TrainerSpecializations', '007', 'Cross Training', NULL, 1, NULL, '2026-09-23T15:35:43.635Z', '2026-09-23T15:35:43.635Z');
INSERT INTO [MasterFile] ([id], [masterType], [code], [name], [description], [isActive], [extra], [createdAt], [updatedAt]) VALUES ('cmue9lvdh001bottthwl2npiy', 'TrainerSpecializations', '008', 'Other', NULL, 1, NULL, '2026-09-23T15:35:43.637Z', '2026-09-23T15:35:43.637Z');

-- NOTE: no GO here - the BEGIN TRAN/BEGIN TRY opened above must stay in the
-- same batch as its END TRY/BEGIN CATCH below (TRY cannot span batches).

-- ============================================================================
-- Done. The database is ready.
-- Login: admin / admin123
-- ============================================================================

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        INSERT INTO #sql_errors VALUES (N'06 main seed', ERROR_MESSAGE());
        ;THROW;
    END CATCH
END
GO

-- ============================================================================
-- ADDITIONAL MASTER DATA (extends the seed above)
-- Runs only if the main seed succeeded; same transaction.
-- ============================================================================
IF NOT EXISTS (SELECT 1 FROM #skip) AND NOT EXISTS (SELECT 1 FROM #sql_errors)
BEGIN
    BEGIN TRY

-- Expense detail accounts used by payroll / purchase vouchers
INSERT INTO [charts] ([id], [name], [parentCode], [accountType], [bookType], [accountTag], [isControl], [isDetail], [isActive], [branchId], [contactName], [phone], [email], [address], [bankName], [bankAccountNo], [bankBranch], [cnic], [ntn], [strn], [fbr], [otherName], [referenceNumber], [faxNumber], [city], [country], [website], [paymentTerms], [registrationNumber], [description], [createdAt], [updatedAt]) VALUES ('05001', 'Salaries Expense', '05', 'Expense', NULL, NULL, 0, 1, 1, '01001', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Staff salaries and wages', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z');
INSERT INTO [charts] ([id], [name], [parentCode], [accountType], [bookType], [accountTag], [isControl], [isDetail], [isActive], [branchId], [contactName], [phone], [email], [address], [bankName], [bankAccountNo], [bankBranch], [cnic], [ntn], [strn], [fbr], [otherName], [referenceNumber], [faxNumber], [city], [country], [website], [paymentTerms], [registrationNumber], [description], [createdAt], [updatedAt]) VALUES ('05002', 'Utilities Expense', '05', 'Expense', NULL, NULL, 0, 1, 1, '01001', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Electricity, water, internet', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z');
INSERT INTO [charts] ([id], [name], [parentCode], [accountType], [bookType], [accountTag], [isControl], [isDetail], [isActive], [branchId], [contactName], [phone], [email], [address], [bankName], [bankAccountNo], [bankBranch], [cnic], [ntn], [strn], [fbr], [otherName], [referenceNumber], [faxNumber], [city], [country], [website], [paymentTerms], [registrationNumber], [description], [createdAt], [updatedAt]) VALUES ('05003', 'Rent Expense', '05', 'Expense', NULL, NULL, 0, 1, 1, '01001', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Premises rent', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z');
INSERT INTO [charts] ([id], [name], [parentCode], [accountType], [bookType], [accountTag], [isControl], [isDetail], [isActive], [branchId], [contactName], [phone], [email], [address], [bankName], [bankAccountNo], [bankBranch], [cnic], [ntn], [strn], [fbr], [otherName], [referenceNumber], [faxNumber], [city], [country], [website], [paymentTerms], [registrationNumber], [description], [createdAt], [updatedAt]) VALUES ('05004', 'Gym Supplies Expense', '05', 'Expense', NULL, NULL, 0, 1, 1, '01001', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Consumables and shop stock purchases', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z');

-- Financial Year 2026 + monthly periods (sample data lives here)
INSERT INTO [FinancialYear] ([id], [name], [startDate], [endDate], [isActive], [isClosed], [createdAt]) VALUES ('fy-2026', 'FY-2026', '2026-01-01T00:00:00.000Z', '2026-12-31T00:00:00.000Z', 1, 0, '2026-01-01T00:00:00.000Z');
INSERT INTO [AccountingPeriod] ([id], [financialYearId], [name], [startDate], [endDate], [status], [createdAt]) VALUES ('fyp-2026-01', 'fy-2026', 'Jan 2026', '2026-01-01T00:00:00.000Z', '2026-01-31T00:00:00.000Z', 'Open', '2026-01-01T00:00:00.000Z');
INSERT INTO [AccountingPeriod] ([id], [financialYearId], [name], [startDate], [endDate], [status], [createdAt]) VALUES ('fyp-2026-02', 'fy-2026', 'Feb 2026', '2026-02-01T00:00:00.000Z', '2026-02-28T00:00:00.000Z', 'Open', '2026-02-01T00:00:00.000Z');
INSERT INTO [AccountingPeriod] ([id], [financialYearId], [name], [startDate], [endDate], [status], [createdAt]) VALUES ('fyp-2026-03', 'fy-2026', 'Mar 2026', '2026-03-01T00:00:00.000Z', '2026-03-31T00:00:00.000Z', 'Open', '2026-03-01T00:00:00.000Z');
INSERT INTO [AccountingPeriod] ([id], [financialYearId], [name], [startDate], [endDate], [status], [createdAt]) VALUES ('fyp-2026-04', 'fy-2026', 'Apr 2026', '2026-04-01T00:00:00.000Z', '2026-04-30T00:00:00.000Z', 'Open', '2026-04-01T00:00:00.000Z');
INSERT INTO [AccountingPeriod] ([id], [financialYearId], [name], [startDate], [endDate], [status], [createdAt]) VALUES ('fyp-2026-05', 'fy-2026', 'May 2026', '2026-05-01T00:00:00.000Z', '2026-05-31T00:00:00.000Z', 'Open', '2026-05-01T00:00:00.000Z');
INSERT INTO [AccountingPeriod] ([id], [financialYearId], [name], [startDate], [endDate], [status], [createdAt]) VALUES ('fyp-2026-06', 'fy-2026', 'Jun 2026', '2026-06-01T00:00:00.000Z', '2026-06-30T00:00:00.000Z', 'Open', '2026-06-01T00:00:00.000Z');
INSERT INTO [AccountingPeriod] ([id], [financialYearId], [name], [startDate], [endDate], [status], [createdAt]) VALUES ('fyp-2026-07', 'fy-2026', 'Jul 2026', '2026-07-01T00:00:00.000Z', '2026-07-31T00:00:00.000Z', 'Open', '2026-07-01T00:00:00.000Z');
INSERT INTO [AccountingPeriod] ([id], [financialYearId], [name], [startDate], [endDate], [status], [createdAt]) VALUES ('fyp-2026-08', 'fy-2026', 'Aug 2026', '2026-08-01T00:00:00.000Z', '2026-08-31T00:00:00.000Z', 'Open', '2026-08-01T00:00:00.000Z');
INSERT INTO [AccountingPeriod] ([id], [financialYearId], [name], [startDate], [endDate], [status], [createdAt]) VALUES ('fyp-2026-09', 'fy-2026', 'Sep 2026', '2026-09-01T00:00:00.000Z', '2026-09-30T00:00:00.000Z', 'Open', '2026-09-01T00:00:00.000Z');
INSERT INTO [AccountingPeriod] ([id], [financialYearId], [name], [startDate], [endDate], [status], [createdAt]) VALUES ('fyp-2026-10', 'fy-2026', 'Oct 2026', '2026-10-01T00:00:00.000Z', '2026-10-31T00:00:00.000Z', 'Open', '2026-10-01T00:00:00.000Z');
INSERT INTO [AccountingPeriod] ([id], [financialYearId], [name], [startDate], [endDate], [status], [createdAt]) VALUES ('fyp-2026-11', 'fy-2026', 'Nov 2026', '2026-11-01T00:00:00.000Z', '2026-11-30T00:00:00.000Z', 'Open', '2026-11-01T00:00:00.000Z');
INSERT INTO [AccountingPeriod] ([id], [financialYearId], [name], [startDate], [endDate], [status], [createdAt]) VALUES ('fyp-2026-12', 'fy-2026', 'Dec 2026', '2026-12-01T00:00:00.000Z', '2026-12-31T00:00:00.000Z', 'Open', '2026-12-01T00:00:00.000Z');

-- Second branch (multi-branch demo): now part of the hierarchy above (01002)

-- Finance defaults (accounting bootstrap for each branch)
INSERT INTO [FinanceDefaults] ([id], [branchId], [defaultCashAccountId], [defaultBankAccountId], [defaultTaxHeadId], [financialYearId], [createdAt], [updatedAt]) VALUES ('FDF-001', NULL, '01001', '01002', 'TAX-001', 'fy-2026', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z');
INSERT INTO [FinanceDefaults] ([id], [branchId], [defaultCashAccountId], [defaultBankAccountId], [defaultTaxHeadId], [financialYearId], [createdAt], [updatedAt])VALUES ('FDF-002', '01001', '01001', '01002', 'TAX-001', 'fy-2026', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z');
INSERT INTO [FinanceDefaults] ([id], [branchId], [defaultCashAccountId], [defaultBankAccountId], [defaultTaxHeadId], [financialYearId], [createdAt], [updatedAt])VALUES ('FDF-003', '01002', '01001', '01002', 'TAX-001', 'fy-2026', '2026-01-05T00:00:00.000Z', '2026-01-05T00:00:00.000Z');

-- Food items (diet planner catalog)
INSERT INTO [FoodItem] ([id], [code], [name], [category], [calories], [protein], [carbs], [fat], [servingSize], [unit], [status], [createdAt], [updatedAt]) VALUES ('food-0001', 'FOOD-0001', 'Chicken Breast (Grilled)', 'Protein', 165, 31, 0, 3.6, '100 g', 'g', 'Active', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z');
INSERT INTO [FoodItem] ([id], [code], [name], [category], [calories], [protein], [carbs], [fat], [servingSize], [unit], [status], [createdAt], [updatedAt]) VALUES ('food-0002', 'FOOD-0002', 'Brown Rice (Cooked)', 'Carbs', 123, 2.7, 25.6, 1, '100 g', 'g', 'Active', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z');
INSERT INTO [FoodItem] ([id], [code], [name], [category], [calories], [protein], [carbs], [fat], [servingSize], [unit], [status], [createdAt], [updatedAt]) VALUES ('food-0003', 'FOOD-0003', 'Banana', 'Fruit', 89, 1.1, 22.8, 0.3, '1 medium', 'pc', 'Active', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z');
INSERT INTO [FoodItem] ([id], [code], [name], [category], [calories], [protein], [carbs], [fat], [servingSize], [unit], [status], [createdAt], [updatedAt]) VALUES ('food-0004', 'FOOD-0004', 'Whey Protein Scoop', 'Supplement', 120, 24, 3, 1.5, '1 scoop (30 g)', 'scoop', 'Active', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z');

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        INSERT INTO #sql_errors VALUES (N'06 additional master', ERROR_MESSAGE());
        ;THROW;
    END CATCH
END
GO

-- ============================================================================
-- Final master rows (owner capital account, exercise catalog, gym/payroll
-- master files). Runs only if everything above succeeded; same transaction.
-- ============================================================================
IF NOT EXISTS (SELECT 1 FROM #skip) AND NOT EXISTS (SELECT 1 FROM #sql_errors)
BEGIN
    BEGIN TRY
-- Owner Capital detail account (equity) for opening-balance entries
INSERT INTO [charts] ([id], [name], [parentCode], [accountType], [bookType], [accountTag], [isControl], [isDetail], [isActive], [branchId], [contactName], [phone], [email], [address], [bankName], [bankAccountNo], [bankBranch], [cnic], [ntn], [strn], [fbr], [otherName], [referenceNumber], [faxNumber], [city], [country], [website], [paymentTerms], [registrationNumber], [description], [createdAt], [updatedAt]) VALUES ('03001', 'Owner Capital', '03', 'Equity', NULL, NULL, 0, 1, 1, '01001', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Owners'' equity contribution', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z');

-- Master file seeds: the THREE identical master/detail pairs
-- (gymmaster, financemaster, payrollmaster) are seeded in the post-migration
-- layout right after the MembershipPlan block above (heads 001-004 gym,
-- 001-003 finance, 001-005 payroll with live detail sets).

-- ---------------------------------------------------------------------
-- Final-schema master seeds (gymmasterfile + payrollmasterfile defaults)
-- ---------------------------------------------------------------------
INSERT INTO [gymmasterfile] ([id], [name], [level], [parentCode], [branchId], [description], [isActive], [createdAt], [updatedAt]) VALUES ('001', 'Exercise', 1, NULL, NULL, 'Exercise master category', 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [gymmasterfile] ([id], [name], [level], [parentCode], [branchId], [description], [isActive], [createdAt], [updatedAt]) VALUES ('002', 'Equipment', 1, NULL, NULL, 'Equipment master category (items are branch-wise)', 1, SYSDATETIME(), SYSDATETIME());
INSERT INTO [gymmasterfile] ([id], [name], [level], [parentCode], [branchId], [description], [isActive], [createdAt], [updatedAt]) VALUES ('003', 'Exercise Type', 1, NULL, NULL, 'Exercise Type master category', 1, SYSDATETIME(), SYSDATETIME());

INSERT INTO [payrollmasterfile] ([id], [masterType], [name], [description], [extra], [branchId], [isActive], [createdAt], [updatedAt])
SELECT LOWER(REPLACE(NEWID(),'-','')), 'Education', t.name, NULL, NULL, NULL, 1, SYSDATETIME(), SYSDATETIME()
FROM (VALUES ('Matric'),('Intermediate'),('Bachelor'),('Master'),('Certification')) t(name)
WHERE NOT EXISTS (SELECT 1 FROM [payrollmasterfile] p WHERE p.masterType = 'Education' AND p.name = t.name);

INSERT INTO [payrollmasterfile] ([id], [masterType], [name], [description], [extra], [branchId], [isActive], [createdAt], [updatedAt])
SELECT LOWER(REPLACE(NEWID(),'-','')), 'Country', t.name, NULL, NULL, NULL, 1, SYSDATETIME(), SYSDATETIME()
FROM (VALUES ('Pakistan'),('United Arab Emirates'),('Saudi Arabia')) t(name)
WHERE NOT EXISTS (SELECT 1 FROM [payrollmasterfile] p WHERE p.masterType = 'Country' AND p.name = t.name);
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        INSERT INTO #sql_errors VALUES (N'06 final master rows', ERROR_MESSAGE());
        ;THROW;
    END CATCH
END
GO

-- ============================================================================
-- Final gate: the success message prints ONLY if nothing failed.
-- ============================================================================
IF EXISTS (SELECT 1 FROM #sql_errors)
BEGIN
    ;THROW 51906, N'Step 06 FAILED: master data seeding was rolled back. Review the errors above, then re-run this file on a clean database.', 1;
END

IF NOT EXISTS (SELECT 1 FROM #skip)
BEGIN
    COMMIT TRAN;
    PRINT N'Step 06 complete: master data seeded (login: admin / admin123).';
END
ELSE
BEGIN
    PRINT N'Step 06: master data already present - skipped.';
END
GO

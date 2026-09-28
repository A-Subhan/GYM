-- ============================================================================
-- Contoura Gym Management System — STEP 7: Realistic Sample Data
-- ============================================================================
-- A coherent, financially-consistent month of gym operations (Aug–Sep 2026):
--   staff, members, attendance, fee invoices + payments, accounting vouchers
--   (balanced Dr=Cr), prospects, follow-ups, freezes, classes + enrollments,
--   workout/diet plans + assignments, progress, fitness goals/assessments,
--   PT sessions, leaves, overtime, payroll (with payable vouchers), suppliers,
--   purchases, stock movements, POS sales, equipment + maintenance, cheques,
--   documents, calendar days and audit entries.
--
-- All foreign keys and document numbering match the backend's formats
-- (BR-001/JAN26/00001, F-00001, CRV-00001, PAY-2026-08-EMP-0002, ...).
-- Run AFTER 06_master_data.sql. Safe to re-run on a fresh database.
-- ============================================================================

USE [GymDB];
GO

SET NOCOUNT ON;

-- ---------------------------------------------------------------------
-- Anchors (resolve ids created by step 06)
-- ---------------------------------------------------------------------
DECLARE @BR1      NVARCHAR(50) = (SELECT id FROM dbo.Branch    WHERE code  = 'BR-001');
DECLARE @BR2      NVARCHAR(50) = (SELECT id FROM dbo.Branch    WHERE code  = 'BR-002');
DECLARE @CASH     NVARCHAR(50) = (SELECT id FROM dbo.charts WHERE code  = '01001');
DECLARE @BANK     NVARCHAR(50) = (SELECT id FROM dbo.charts WHERE code  = '01002');
DECLARE @CAPITAL  NVARCHAR(50) = (SELECT id FROM dbo.charts WHERE code  = '03001');
DECLARE @FEE_INC  NVARCHAR(50) = (SELECT id FROM dbo.charts WHERE code  = '04001');
DECLARE @POS_INC  NVARCHAR(50) = (SELECT id FROM dbo.charts WHERE code  = '04002');
DECLARE @SAL_EXP  NVARCHAR(50) = (SELECT id FROM dbo.charts WHERE code  = '05001');
DECLARE @UTL_EXP  NVARCHAR(50) = (SELECT id FROM dbo.charts WHERE code  = '05002');
DECLARE @RENT_EXP NVARCHAR(50) = (SELECT id FROM dbo.charts WHERE code  = '05003');
DECLARE @SUP_EXP  NVARCHAR(50) = (SELECT id FROM dbo.charts WHERE code  = '05004');
DECLARE @ADMIN    NVARCHAR(50) = (SELECT id FROM dbo.[User]    WHERE username = 'admin');
DECLARE @TRAINER1 NVARCHAR(50) = (SELECT id FROM dbo.Staff     WHERE employeeId = 'EMP-0001');
DECLARE @PLAN_M   NVARCHAR(50) = (SELECT id FROM dbo.MembershipPlan WHERE code = 'MP-001');
DECLARE @PLAN_Q   NVARCHAR(50) = (SELECT id FROM dbo.MembershipPlan WHERE code = 'MP-002');
DECLARE @PLAN_Y   NVARCHAR(50) = (SELECT id FROM dbo.MembershipPlan WHERE code = 'MP-003');
DECLARE @ROLE_REC NVARCHAR(50) = (SELECT id FROM dbo.[Role]    WHERE name = 'Receptionist');
GO
GO

-- ---------------------------------------------------------------------
-- 1) Additional application user (reception desk — password: admin123)
-- ---------------------------------------------------------------------
INSERT INTO [User] ([id], [username], [email], [fullName], [passwordHash], [roleId], [branchId], [accessibleBranchIds], [phone], [photo], [isActive], [failedLoginCount], [lastLoginAt], [mustChangePassword], [createdAt], [updatedAt], [isDeleted])
VALUES ('user-reception', 'reception', 'reception@contouragym.com', N'Nida Kamran', '$2b$10$4sWId8YdsNlr39HgQ51wE.5rFtEFE3l5APRnRO6rYlE15bOUryvpy', (SELECT TOP 1 id FROM dbo.[Role] WHERE name = N'Receptionist'), (SELECT id FROM dbo.Branch WHERE code = N'BR-001'), (SELECT id FROM dbo.Branch WHERE code = N'BR-001'), '+92 300 7654321', NULL, 1, 0, NULL, 0, '2026-02-01T09:00:00.000Z', '2026-02-01T09:00:00.000Z', 0);
GO

-- ---------------------------------------------------------------------
-- 2) Staff (5 more employees)
-- ---------------------------------------------------------------------
INSERT INTO Staff ([id], [employeeId], [firstName], [lastName], [fatherGuardian], [cnic], [photo], [address], [emergencyContact], [emergencyContactNo], [phone], [whatsapp], [telephone], [fax], [email], [joiningDate], [department], [designation], [isTrainer], [branchId], [shiftId], [basicSalary], [fuelAllowance], [rentAllowance], [houseAllowance], [otherAllowance], [sessi], [eobi], [fbrTaxNumber], [overtimeAllowed], [overtimeRate], [isActive], [createdAt], [updatedAt], [isDeleted]) VALUES
('staff-0002', 'EMP-0002', N'Sana', N'Ahmed', N'M. Ahmed', N'42101-1234567-2', NULL, N'Gulshan-e-Iqbal, Karachi', N'Brother', N'+92 321 1111111', N'+92 321 2222222', N'+92 321 2222222', NULL, NULL, 'sana@contouragym.com', '2026-01-05T00:00:00.000Z', N'Management', N'Branch Manager', 0, (SELECT id FROM dbo.Branch WHERE code='BR-001'), 'shift-general-default', 80000, 5000, 10000, 0, 0, 0, 0, NULL, 0, 0, 1, '2026-01-05T00:00:00.000Z', '2026-01-05T00:00:00.000Z', 0),
('staff-0003', 'EMP-0003', N'Bilal', N'Hussain', N'A. Hussain', N'42101-2345678-3', NULL, N'North Nazimabad, Karachi', N'Father', N'+92 333 3333333', N'+92 333 4444444', N'+92 333 4444444', NULL, NULL, 'bilal@contouragym.com', '2026-01-10T00:00:00.000Z', N'Reception', N'Receptionist', 0, (SELECT id FROM dbo.Branch WHERE code='BR-001'), 'shift-evening-default', 35000, 0, 0, 0, 0, 0, 0, NULL, 1, 667, 1, '2026-01-10T00:00:00.000Z', '2026-01-10T00:00:00.000Z', 0),
('staff-0004', 'EMP-0004', N'Ayesha', N'Malik', N'R. Malik', N'42101-3456789-4', NULL, N'Clifton, Karachi', N'Husband', N'+92 345 5555555', N'+92 345 6666666', N'+92 345 6666666', NULL, NULL, 'ayesha@contouragym.com', '2026-02-01T00:00:00.000Z', N'Finance', N'Accountant', 0, (SELECT id FROM dbo.Branch WHERE code='BR-001'), 'shift-general-default', 60000, 0, 0, 0, 0, 0, 0, NULL, 0, 0, 1, '2026-02-01T00:00:00.000Z', '2026-02-01T00:00:00.000Z', 0),
('staff-0005', 'EMP-0005', N'Usman', N'Tariq', N'M. Tariq', N'42101-4567890-5', NULL, N'DHA Phase 6, Karachi', N'Brother', N'+92 347 7777777', N'+92 347 8888888', N'+92 347 8888888', NULL, NULL, 'usman@contouragym.com', '2026-03-15T00:00:00.000Z', N'Trainers', N'Senior Trainer', 1, (SELECT id FROM dbo.Branch WHERE code='BR-002'), 'shift-evening-default', 45000, 0, 0, 0, 0, 0, 0, NULL, 1, 500, 1, '2026-03-15T00:00:00.000Z', '2026-03-15T00:00:00.000Z', 0),
('staff-0006', 'EMP-0006', N'Fatima', N'Noor', N'K. Noor', N'42101-5678901-6', NULL, N'Gulistan-e-Johar, Karachi', N'Father', N'+92 302 9999999', N'+92 302 1212121', N'+92 302 1212121', NULL, NULL, 'fatima@contouragym.com', '2026-04-01T00:00:00.000Z', N'Housekeeping', N'Cleaner', 0, (SELECT id FROM dbo.Branch WHERE code='BR-001'), 'shift-morning-default', 25000, 0, 0, 0, 0, 0, 0, NULL, 0, 0, 1, '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z', 0);
GO

-- ---------------------------------------------------------------------
-- 3) Members (12)
-- ---------------------------------------------------------------------
INSERT INTO [Member] ([id], [firstName], [lastName], [gender], [dob], [phone], [whatsapp], [email], [address], [emergencyContact], [emergencyContactNo], [photo], [cnic], [joiningDate], [billingStartDate], [feeRelaxationDays], [status], [membershipPlanId], [branchId], [assignedTrainerId], [notes], [isActive], [createdAt], [updatedAt], [isDeleted]) VALUES
('BR-001/JAN26/00001', N'Ahmed', N'Raza', N'Male', '1998-04-12T00:00:00.000Z', N'+92 300 1110001', N'+92 300 1110001', 'ahmed.raza@gmail.com', N'Block 6, Gulshan, Karachi', N'Father', N'+92 300 1110002', NULL, N'42101-1111111-1', '2026-01-10T00:00:00.000Z', '2026-01-10T00:00:00.000Z', 0, N'Active', (SELECT id FROM dbo.MembershipPlan WHERE name = 'Monthly'), (SELECT id FROM dbo.Branch WHERE code='BR-001'), (SELECT id FROM dbo.Staff WHERE employeeId='EMP-0001'), N'Wants to lose 8 kg', 1, '2026-01-10T00:00:00.000Z', '2026-01-10T00:00:00.000Z', 0),
('BR-001/FEB26/00001', N'Sara', N'Khan', N'Female', '1995-09-25T00:00:00.000Z', N'+92 301 2220001', N'+92 301 2220001', 'sara.khan@gmail.com', N'PECHS Block 2, Karachi', N'Husband', N'+92 301 2220002', NULL, N'42101-2222222-2', '2026-02-15T00:00:00.000Z', '2026-02-15T00:00:00.000Z', 0, N'Active', (SELECT id FROM dbo.MembershipPlan WHERE name = 'Quarterly'), (SELECT id FROM dbo.Branch WHERE code='BR-001'), (SELECT id FROM dbo.Staff WHERE employeeId='EMP-0001'), NULL, 1, '2026-02-15T00:00:00.000Z', '2026-02-15T00:00:00.000Z', 0),
('BR-001/MAR26/00001', N'Bilal', N'Ahmed', N'Male', '2000-01-30T00:00:00.000Z', N'+92 302 3330001', N'+92 302 3330001', 'bilal.ahmed@gmail.com', N'North Nazimabad, Karachi', N'Brother', N'+92 302 3330002', NULL, N'42101-3333333-3', '2026-03-01T00:00:00.000Z', '2026-03-01T00:00:00.000Z', 3, N'Active', (SELECT id FROM dbo.MembershipPlan WHERE name = 'Monthly'), (SELECT id FROM dbo.Branch WHERE code='BR-001'), NULL, NULL, 1, '2026-03-01T00:00:00.000Z', '2026-03-01T00:00:00.000Z', 0),
('BR-002/APR26/00001', N'Ayesha', N'Siddiqui', N'Female', '1997-11-05T00:00:00.000Z', N'+92 303 4440001', N'+92 303 4440001', 'ayesha.s@gmail.com', N'DHA Phase 5, Karachi', N'Husband', N'+92 303 4440002', NULL, N'42101-4444444-4', '2026-04-20T00:00:00.000Z', '2026-04-20T00:00:00.000Z', 0, N'Active', (SELECT id FROM dbo.MembershipPlan WHERE name = 'Monthly'), (SELECT id FROM dbo.Branch WHERE code='BR-002'), (SELECT id FROM dbo.Staff WHERE employeeId='EMP-0005'), N'Prefers evening slots', 1, '2026-04-20T00:00:00.000Z', '2026-04-20T00:00:00.000Z', 0),
('BR-001/MAY26/00001', N'Omar', N'Farooq', N'Male', '1992-07-19T00:00:00.000Z', N'+92 304 5550001', N'+92 304 5550001', 'omar.farooq@gmail.com', N'Bahadurabad, Karachi', N'Wife', N'+92 304 5550002', NULL, N'42101-5555555-5', '2026-05-05T00:00:00.000Z', '2026-05-05T00:00:00.000Z', 0, N'Active', (SELECT id FROM dbo.MembershipPlan WHERE name = 'Monthly'), (SELECT id FROM dbo.Branch WHERE code='BR-001'), NULL, NULL, 1, '2026-05-05T00:00:00.000Z', '2026-05-05T00:00:00.000Z', 0),
('BR-001/JUN26/00001', N'Fatima', N'Zahra', N'Female', '1999-03-08T00:00:00.000Z', N'+92 305 6660001', N'+92 305 6660001', 'fatima.z@gmail.com', N'Scheme 33, Karachi', N'Father', N'+92 305 6660002', NULL, N'42101-6666666-6', '2026-06-12T00:00:00.000Z', '2026-06-12T00:00:00.000Z', 0, N'Active', (SELECT id FROM dbo.MembershipPlan WHERE name = 'Annual'), (SELECT id FROM dbo.Branch WHERE code='BR-001'), (SELECT id FROM dbo.Staff WHERE employeeId='EMP-0001'), N'Annual member — paid by cheque', 1, '2026-06-12T00:00:00.000Z', '2026-06-12T00:00:00.000Z', 0),
('BR-002/JUL26/00001', N'Hassan', N'Ali', N'Male', '2001-06-22T00:00:00.000Z', N'+92 306 7770001', N'+92 306 7770001', 'hassan.ali@gmail.com', N'Malir, Karachi', N'Father', N'+92 306 7770002', NULL, N'42101-7777777-7', '2026-07-01T00:00:00.000Z', '2026-07-01T00:00:00.000Z', 0, N'Active', (SELECT id FROM dbo.MembershipPlan WHERE name = 'Monthly'), (SELECT id FROM dbo.Branch WHERE code='BR-002'), NULL, NULL, 1, '2026-07-01T00:00:00.000Z', '2026-07-01T00:00:00.000Z', 0),
('BR-001/JUL26/00001', N'Zainab', N'Fatima', N'Female', '1996-12-14T00:00:00.000Z', N'+92 307 8880001', N'+92 307 8880001', 'zainab.f@gmail.com', N'Saddar, Karachi', N'Brother', N'+92 307 8880002', NULL, N'42101-8888888-8', '2026-07-18T00:00:00.000Z', '2026-07-18T00:00:00.000Z', 0, N'Inactive', (SELECT id FROM dbo.MembershipPlan WHERE name = 'Monthly'), (SELECT id FROM dbo.Branch WHERE code='BR-001'), NULL, N'Membership cancelled — relocated', 0, '2026-07-18T00:00:00.000Z', '2026-09-01T00:00:00.000Z', 0),
('BR-001/AUG26/00001', N'Usman', N'Ghani', N'Male', '1989-02-17T00:00:00.000Z', N'+92 308 9990001', N'+92 308 9990001', 'usman.ghani@gmail.com', N'Nazimabad, Karachi', N'Wife', N'+92 308 9990002', NULL, N'42101-9999999-9', '2026-08-01T00:00:00.000Z', '2026-08-01T00:00:00.000Z', 0, N'Active', (SELECT id FROM dbo.MembershipPlan WHERE name = 'Quarterly'), (SELECT id FROM dbo.Branch WHERE code='BR-001'), NULL, NULL, 1, '2026-08-01T00:00:00.000Z', '2026-08-01T00:00:00.000Z', 0),
('BR-002/AUG26/00001', N'Maryam', N'Aslam', N'Female', '1994-10-02T00:00:00.000Z', N'+92 309 1010001', N'+92 309 1010001', 'maryam.aslam@gmail.com', N'Korangi, Karachi', N'Husband', N'+92 309 1010002', NULL, N'42101-1010101-0', '2026-08-10T00:00:00.000Z', '2026-08-10T00:00:00.000Z', 0, N'Active', (SELECT id FROM dbo.MembershipPlan WHERE name = 'Monthly'), (SELECT id FROM dbo.Branch WHERE code='BR-002'), (SELECT id FROM dbo.Staff WHERE employeeId='EMP-0005'), NULL, 1, '2026-08-10T00:00:00.000Z', '2026-08-10T00:00:00.000Z', 0),
('BR-001/SEP26/00001', N'Ali', N'Raza', N'Male', '1998-08-30T00:00:00.000Z', N'+92 310 1111111', N'+92 310 1111111', 'ali.raza@gmail.com', N'Gulshan 13-D, Karachi', N'Father', N'+92 310 1111112', NULL, N'42101-1112111-1', '2026-09-01T00:00:00.000Z', '2026-09-01T00:00:00.000Z', 0, N'Active', (SELECT id FROM dbo.MembershipPlan WHERE name = 'Monthly'), (SELECT id FROM dbo.Branch WHERE code='BR-001'), (SELECT id FROM dbo.Staff WHERE employeeId='EMP-0001'), N'Converted from walk-in prospect', 1, '2026-09-01T00:00:00.000Z', '2026-09-01T00:00:00.000Z', 0),
('BR-002/SEP26/00001', N'Hira', N'Bashir', N'Female', '2002-05-21T00:00:00.000Z', N'+92 311 1210001', N'+92 311 1210001', 'hira.bashir@gmail.com', N'DHA Phase 8, Karachi', N'Mother', N'+92 311 1210002', NULL, N'42101-1212121-2', '2026-09-15T00:00:00.000Z', '2026-09-15T00:00:00.000Z', 0, N'Active', (SELECT id FROM dbo.MembershipPlan WHERE name = 'Monthly'), (SELECT id FROM dbo.Branch WHERE code='BR-002'), NULL, N'New joiner — first invoice pending', 1, '2026-09-15T00:00:00.000Z', '2026-09-15T00:00:00.000Z', 0);
GO

-- ---------------------------------------------------------------------
-- 4) Prospects and follow-ups
-- ---------------------------------------------------------------------
INSERT INTO Prospect ([id], [name], [phone], [whatsapp], [gender], [age], [dob], [interestedMembership], [branchId], [source], [status], [inquiryDate], [followUpDate], [assignedTo], [notes], [convertedMemberId], [createdAt], [updatedAt]) VALUES
('BR-001/p-00001', N'Junaid Akhtar', N'+92 312 2220001', N'+92 312 2220001', N'Male', 27, '1999-03-10T00:00:00.000Z', N'Monthly', (SELECT id FROM dbo.Branch WHERE code='BR-001'), N'Walk-in', N'New', '2026-09-18T00:00:00.000Z', '2026-09-22T00:00:00.000Z', (SELECT id FROM dbo.[User] WHERE username='admin'), N'Asked about student discount', NULL, '2026-09-18T00:00:00.000Z', '2026-09-18T00:00:00.000Z'),
('BR-001/p-00002', N'Kiran Shah', N'+92 313 3330001', N'+92 313 3330001', N'Female', 31, '1995-04-02T00:00:00.000Z', N'Quarterly', (SELECT id FROM dbo.Branch WHERE code='BR-001'), N'Instagram', N'FollowUp', '2026-09-05T00:00:00.000Z', '2026-09-25T00:00:00.000Z', (SELECT id FROM dbo.[User] WHERE username='reception'), N'Wants ladies-only timings detail', NULL, '2026-09-05T00:00:00.000Z', '2026-09-20T00:00:00.000Z'),
('BR-001/p-00003', N'Ali Raza', N'+92 310 1111111', N'+92 310 1111111', N'Male', 28, '1998-08-30T00:00:00.000Z', N'Monthly', (SELECT id FROM dbo.Branch WHERE code='BR-001'), N'Walk-in', N'Converted', '2026-08-28T00:00:00.000Z', '2026-09-01T00:00:00.000Z', (SELECT id FROM dbo.[User] WHERE username='reception'), N'Joined as BR-001/SEP26/00001', 'BR-001/SEP26/00001', '2026-08-28T00:00:00.000Z', '2026-09-01T00:00:00.000Z'),
('BR-002/p-00001', N'Danish Iqbal', N'+92 314 4440001', N'+92 314 4440001', N'Male', 35, '1991-01-15T00:00:00.000Z', N'Annual', (SELECT id FROM dbo.Branch WHERE code='BR-002'), N'Referral', N'New', '2026-09-21T00:00:00.000Z', '2026-09-28T00:00:00.000Z', (SELECT id FROM dbo.[User] WHERE username='admin'), N'Referred by BR-002/APR26/00001', NULL, '2026-09-21T00:00:00.000Z', '2026-09-21T00:00:00.000Z');
GO

INSERT INTO FollowUp ([id], [memberId], [prospectId], [branchId], [date], [type], [userId], [notes], [outcome], [nextFollowUpDate], [createdAt]) VALUES
('BR-001/fw-000001', 'BR-001/MAR26/00001', NULL, (SELECT id FROM dbo.Branch WHERE code='BR-001'), '2026-09-02T00:00:00.000Z', N'Call', (SELECT id FROM dbo.[User] WHERE username='admin'), N'Reminded about pending invoice balance', N'Promised to pay by Friday', '2026-09-26T00:00:00.000Z', '2026-09-02T00:00:00.000Z'),
('BR-002/fw-000001', 'BR-002/JUL26/00001', NULL, (SELECT id FROM dbo.Branch WHERE code='BR-002'), '2026-09-10T00:00:00.000Z', N'WhatsApp', (SELECT id FROM dbo.[User] WHERE username='admin'), N'Checked in after missed week', N'Will resume next week', '2026-09-24T00:00:00.000Z', '2026-09-10T00:00:00.000Z'),
('BR-001/fw-000002', NULL, 'BR-001/p-00002', (SELECT id FROM dbo.Branch WHERE code='BR-001'), '2026-09-20T00:00:00.000Z', N'Call', (SELECT id FROM dbo.[User] WHERE username='reception'), N'Shared ladies timetable', N'Interested — visit scheduled', '2026-09-25T00:00:00.000Z', '2026-09-20T00:00:00.000Z');
GO

-- ---------------------------------------------------------------------
-- 5) Membership freeze (1)
-- ---------------------------------------------------------------------
INSERT INTO MembershipFreeze ([id], [memberId], [branchId], [freezeFrom], [freezeTo], [days], [reason], [approvedBy], [status], [createdAt], [updatedAt]) VALUES
('f-000001', 'BR-001/MAR26/00001', (SELECT id FROM dbo.Branch WHERE code='BR-001'), '2026-09-10T00:00:00.000Z', '2026-09-17T00:00:00.000Z', 7, N'Out of city — work trip', (SELECT id FROM dbo.[User] WHERE username='admin'), N'Approved', '2026-09-08T00:00:00.000Z', '2026-09-08T00:00:00.000Z');
GO

-- ---------------------------------------------------------------------
-- 6) Book vouchers (final schema): OpenTB + CashBook (CRV/CPV)
-- Voucher id = voucher number {TYPE}/{branch}/{MMMyy}/{000001}
GO

-- Opening trial balance (01 Jan 2026) — OTV allows unbalanced saves
INSERT INTO OpenTB ([id], [voucherType], [voucherDate], [branchId], [description], [reference], [totalDebit], [totalCredit], [difference], [isBalanced], [status], [postedById], [reversedById], [reversedAt], [reversalReason], [createdAt], [updatedAt]) VALUES
(('OTV/BR-001/JAN26/000001', 'OTV', '2026-01-01T00:00:00.000Z', (SELECT id FROM dbo.Branch WHERE code='BR-001'), N'Opening balances as of 01 Jan 2026', NULL, 700000, 700000, 0, 1, 'Posted', (SELECT id FROM dbo.[User] WHERE username='admin'), NULL, NULL, NULL, '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z'));
GO

INSERT INTO OpenTBLine ([voucherId], [accountId], [debit], [credit], [amount], [lineDescription], [reference], [status], [createdAt]) VALUES
(('OTV/BR-001/JAN26/000001', (SELECT id FROM dbo.charts WHERE code='01001'), 200000, 0, 200000, N'Cash in hand at opening', NULL, 'Active', '2026-01-01T00:00:00.000Z'),
('OTV/BR-001/JAN26/000001', (SELECT id FROM dbo.charts WHERE code='01002'), 500000, 0, 500000, N'Bank balance at opening', NULL, 'Active', '2026-01-01T00:00:00.000Z'),
('OTV/BR-001/JAN26/000001', (SELECT id FROM dbo.charts WHERE code='03001'), 0, 700000, 700000, N'Owner capital at opening', NULL, 'Active', '2026-01-01T00:00:00.000Z'));
GO

-- Cash receipts (CRV) and payments (CPV); POS receipts posted as CRV
INSERT INTO CashBook ([id], [voucherType], [voucherDate], [branchId], [bookChartId], [description], [reference], [paymentMode], [totalAmount], [status], [reversedById], [reversedAt], [reversalReason], [postedById], [createdAt], [updatedAt]) VALUES
(('CRV/BR-001/AUG26/000001', 'CRV', '2026-08-05T00:00:00.000Z', (SELECT id FROM dbo.Branch WHERE code='BR-001'), (SELECT id FROM dbo.charts WHERE code='01001'), N'Fee received — BR-001/JAN26/00001 Ahmed Raza (Aug 2026)', N'F-00001', NULL, 3000, 'Posted', NULL, NULL, NULL, (SELECT id FROM dbo.[User] WHERE username='admin'), '2026-08-05T00:00:00.000Z', '2026-08-05T00:00:00.000Z'),
('CRV/BR-001/AUG26/000002', 'CRV', '2026-08-08T00:00:00.000Z', (SELECT id FROM dbo.Branch WHERE code='BR-001'), (SELECT id FROM dbo.charts WHERE code='01002'), N'Fee received — BR-001/FEB26/00001 Sara Khan (Aug–Oct 2026)', N'F-00002', NULL, 8000, 'Posted', NULL, NULL, NULL, (SELECT id FROM dbo.[User] WHERE username='admin'), '2026-08-08T00:00:00.000Z', '2026-08-08T00:00:00.000Z'),
('CRV/BR-001/SEP26/000004', 'CRV', '2026-09-06T00:00:00.000Z', (SELECT id FROM dbo.Branch WHERE code='BR-001'), (SELECT id FROM dbo.charts WHERE code='01001'), N'Partial fee received — BR-001/MAR26/00001 Bilal Ahmed (Sep 2026)', N'F-00003', NULL, 1500, 'Posted', NULL, NULL, NULL, (SELECT id FROM dbo.[User] WHERE username='reception'), '2026-09-06T00:00:00.000Z', '2026-09-06T00:00:00.000Z'),
('CRV/BR-001/JUN26/000001', 'CRV', '2026-06-12T00:00:00.000Z', (SELECT id FROM dbo.Branch WHERE code='BR-001'), (SELECT id FROM dbo.charts WHERE code='01002'), N'Annual fee received by cheque — BR-001/JUN26/00001 Fatima Zahra', N'F-00006', NULL, 30000, 'Posted', NULL, NULL, NULL, (SELECT id FROM dbo.[User] WHERE username='admin'), '2026-06-12T00:00:00.000Z', '2026-06-12T00:00:00.000Z'),
('CRV/BR-001/SEP26/000002', 'CRV', '2026-09-03T00:00:00.000Z', (SELECT id FROM dbo.Branch WHERE code='BR-001'), (SELECT id FROM dbo.charts WHERE code='01001'), N'Fee received — BR-001/JAN26/00001 Ahmed Raza (Sep 2026)', N'F-00007', NULL, 3000, 'Posted', NULL, NULL, NULL, (SELECT id FROM dbo.[User] WHERE username='admin'), '2026-09-03T00:00:00.000Z', '2026-09-03T00:00:00.000Z'),
('CRV/BR-001/AUG26/000003', 'CRV', '2026-08-20T00:00:00.000Z', (SELECT id FROM dbo.Branch WHERE code='BR-001'), (SELECT id FROM dbo.charts WHERE code='01001'), N'Fee received — BR-001/JUL26/00001 Zainab Fatima (Aug 2026)', N'F-00009', NULL, 3000, 'Posted', NULL, NULL, NULL, (SELECT id FROM dbo.[User] WHERE username='reception'), '2026-08-20T00:00:00.000Z', '2026-08-20T00:00:00.000Z'),
('CRV/BR-002/SEP26/000001', 'CRV', '2026-09-12T00:00:00.000Z', (SELECT id FROM dbo.Branch WHERE code='BR-002'), (SELECT id FROM dbo.charts WHERE code='01001'), N'Fee received — BR-002/AUG26/00001 Maryam Aslam (Sep 2026)', N'F-00011', NULL, 3000, 'Posted', NULL, NULL, NULL, (SELECT id FROM dbo.[User] WHERE username='admin'), '2026-09-12T00:00:00.000Z', '2026-09-12T00:00:00.000Z'),
('CRV/BR-001/SEP26/000001', 'CRV', '2026-09-01T00:00:00.000Z', (SELECT id FROM dbo.Branch WHERE code='BR-001'), (SELECT id FROM dbo.charts WHERE code='01002'), N'Fee received by card — BR-001/SEP26/00001 Ali Raza (Sep 2026)', N'F-00012', NULL, 3000, 'Posted', NULL, NULL, NULL, (SELECT id FROM dbo.[User] WHERE username='reception'), '2026-09-01T00:00:00.000Z', '2026-09-01T00:00:00.000Z'),
('CPV/BR-001/AUG26/000004', 'CPV', '2026-08-28T00:00:00.000Z', (SELECT id FROM dbo.Branch WHERE code='BR-001'), (SELECT id FROM dbo.charts WHERE code='01001'), N'K-Electric bill — August 2026', N'KE-88412', NULL, 25000, 'Posted', NULL, NULL, NULL, (SELECT id FROM dbo.[User] WHERE username='admin'), '2026-08-28T00:00:00.000Z', '2026-08-28T00:00:00.000Z'),
('CPV/BR-001/AUG26/000001', 'CPV', '2026-08-01T00:00:00.000Z', (SELECT id FROM dbo.Branch WHERE code='BR-001'), (SELECT id FROM dbo.charts WHERE code='01002'), N'Building rent — August 2026', N'RENT-AUG26', NULL, 120000, 'Posted', NULL, NULL, NULL, (SELECT id FROM dbo.[User] WHERE username='admin'), '2026-08-01T00:00:00.000Z', '2026-08-01T00:00:00.000Z'),
('CPV/BR-001/AUG26/000002', 'CPV', '2026-08-15T00:00:00.000Z', (SELECT id FROM dbo.Branch WHERE code='BR-001'), (SELECT id FROM dbo.charts WHERE code='01002'), N'Stock purchase — Nutrifit Suppliers', N'PUR-00001', NULL, 430000, 'Posted', NULL, NULL, NULL, (SELECT id FROM dbo.[User] WHERE username='admin'), '2026-08-15T00:00:00.000Z', '2026-08-15T00:00:00.000Z'),
('CPV/BR-001/AUG26/000003', 'CPV', '2026-08-25T00:00:00.000Z', (SELECT id FROM dbo.Branch WHERE code='BR-001'), (SELECT id FROM dbo.charts WHERE code='01001'), N'Stock purchase — FitGear Trading', N'PUR-00002', NULL, 57000, 'Posted', NULL, NULL, NULL, (SELECT id FROM dbo.[User] WHERE username='admin'), '2026-08-25T00:00:00.000Z', '2026-08-25T00:00:00.000Z'),
('CPV/BR-001/SEP26/000001', 'CPV', '2026-09-10T00:00:00.000Z', (SELECT id FROM dbo.Branch WHERE code='BR-001'), (SELECT id FROM dbo.charts WHERE code='01002'), N'Stock purchase — Nutrifit Suppliers', N'PUR-00003', NULL, 69000, 'Posted', NULL, NULL, NULL, (SELECT id FROM dbo.[User] WHERE username='admin'), '2026-09-10T00:00:00.000Z', '2026-09-10T00:00:00.000Z'),
('CRV/BR-001/SEP26/000003', 'CRV', '2026-09-05T00:00:00.000Z', (SELECT id FROM dbo.Branch WHERE code='BR-001'), (SELECT id FROM dbo.charts WHERE code='01001'), N'POS sale — cash', N'POS-00001', NULL, 17800, 'Posted', NULL, NULL, NULL, (SELECT id FROM dbo.[User] WHERE username='reception'), '2026-09-05T00:00:00.000Z', '2026-09-05T00:00:00.000Z'),
('CRV/BR-001/SEP26/000005', 'CRV', '2026-09-12T00:00:00.000Z', (SELECT id FROM dbo.Branch WHERE code='BR-001'), (SELECT id FROM dbo.charts WHERE code='01002'), N'POS sale — card', N'POS-00002', NULL, 7150, 'Posted', NULL, NULL, NULL, (SELECT id FROM dbo.[User] WHERE username='reception'), '2026-09-12T00:00:00.000Z', '2026-09-12T00:00:00.000Z'),
('CRV/BR-001/SEP26/000006', 'CRV', '2026-09-18T00:00:00.000Z', (SELECT id FROM dbo.Branch WHERE code='BR-001'), (SELECT id FROM dbo.charts WHERE code='01001'), N'POS sale — cash', N'POS-00003', NULL, 5000, 'Posted', NULL, NULL, NULL, (SELECT id FROM dbo.[User] WHERE username='reception'), '2026-09-18T00:00:00.000Z', '2026-09-18T00:00:00.000Z'));
GO

INSERT INTO CashBookLine ([voucherId], [accountId], [debit], [credit], [amount], [taxPercent], [taxAmount], [total], [lineDescription], [title], [reference], [billType], [chequeNo], [chequeAmount], [chequeBankName], [chequeStatus], [status], [createdAt]) VALUES
(('CRV/BR-001/AUG26/000001', (SELECT id FROM dbo.charts WHERE code='01001'), 3000, 0, 3000, 0, 0, 3000, N'Cash received', N'Cash in Hand', N'F-00001', NULL, NULL, 3000, NULL, NULL, 'Active', '2026-08-05T00:00:00.000Z'),
('CRV/BR-001/AUG26/000001', (SELECT id FROM dbo.charts WHERE code='04001'), 0, 3000, 3000, 0, 0, 3000, N'Membership fee — Aug 2026', N'Membership Fee Income', N'BR-001/JAN26/00001', NULL, NULL, 3000, NULL, NULL, 'Active', '2026-08-05T00:00:00.000Z'),
('CRV/BR-001/AUG26/000002', (SELECT id FROM dbo.charts WHERE code='01002'), 8000, 0, 8000, 0, 0, 8000, N'Card payment received', N'Bank', N'F-00002', NULL, NULL, 8000, NULL, NULL, 'Active', '2026-08-08T00:00:00.000Z'),
('CRV/BR-001/AUG26/000002', (SELECT id FROM dbo.charts WHERE code='04001'), 0, 8000, 8000, 0, 0, 8000, N'Membership fee — Aug–Oct 2026', N'Membership Fee Income', N'BR-001/FEB26/00001', NULL, NULL, 8000, NULL, NULL, 'Active', '2026-08-08T00:00:00.000Z'),
('CRV/BR-001/SEP26/000004', (SELECT id FROM dbo.charts WHERE code='01001'), 1500, 0, 1500, 0, 0, 1500, N'Partial cash received', N'Cash in Hand', N'F-00003', NULL, NULL, 1500, NULL, NULL, 'Active', '2026-09-06T00:00:00.000Z'),
('CRV/BR-001/SEP26/000004', (SELECT id FROM dbo.charts WHERE code='04001'), 0, 1500, 1500, 0, 0, 1500, N'Membership fee — Sep 2026 (partial)', N'Membership Fee Income', N'BR-001/MAR26/00001', NULL, NULL, 1500, NULL, NULL, 'Active', '2026-09-06T00:00:00.000Z'),
('CRV/BR-001/JUN26/000001', (SELECT id FROM dbo.charts WHERE code='01002'), 30000, 0, 30000, 0, 0, 30000, N'Cheque received — MCB 4471/2026', N'Bank', N'F-00006', NULL, N'44712026', 30000, N'MCB Bank', N'Cleared', 'Active', '2026-06-12T00:00:00.000Z'),
('CRV/BR-001/JUN26/000001', (SELECT id FROM dbo.charts WHERE code='04001'), 0, 30000, 30000, 0, 0, 30000, N'Annual membership fee', N'Membership Fee Income', N'BR-001/JUN26/00001', NULL, NULL, 30000, NULL, NULL, 'Active', '2026-06-12T00:00:00.000Z'),
('CRV/BR-001/SEP26/000002', (SELECT id FROM dbo.charts WHERE code='01001'), 3000, 0, 3000, 0, 0, 3000, N'Cash received', N'Cash in Hand', N'F-00007', NULL, NULL, 3000, NULL, NULL, 'Active', '2026-09-03T00:00:00.000Z'),
('CRV/BR-001/SEP26/000002', (SELECT id FROM dbo.charts WHERE code='04001'), 0, 3000, 3000, 0, 0, 3000, N'Membership fee — Sep 2026', N'Membership Fee Income', N'BR-001/JAN26/00001', NULL, NULL, 3000, NULL, NULL, 'Active', '2026-09-03T00:00:00.000Z'),
('CRV/BR-001/AUG26/000003', (SELECT id FROM dbo.charts WHERE code='01001'), 3000, 0, 3000, 0, 0, 3000, N'Cash received', N'Cash in Hand', N'F-00009', NULL, NULL, 3000, NULL, NULL, 'Active', '2026-08-20T00:00:00.000Z'),
('CRV/BR-001/AUG26/000003', (SELECT id FROM dbo.charts WHERE code='04001'), 0, 3000, 3000, 0, 0, 3000, N'Membership fee — Aug 2026', N'Membership Fee Income', N'BR-001/JUL26/00001', NULL, NULL, 3000, NULL, NULL, 'Active', '2026-08-20T00:00:00.000Z'),
('CRV/BR-002/SEP26/000001', (SELECT id FROM dbo.charts WHERE code='01001'), 3000, 0, 3000, 0, 0, 3000, N'Cash received', N'Cash in Hand', N'F-00011', NULL, NULL, 3000, NULL, NULL, 'Active', '2026-09-12T00:00:00.000Z'),
('CRV/BR-002/SEP26/000001', (SELECT id FROM dbo.charts WHERE code='04001'), 0, 3000, 3000, 0, 0, 3000, N'Membership fee — Sep 2026', N'Membership Fee Income', N'BR-002/AUG26/00001', NULL, NULL, 3000, NULL, NULL, 'Active', '2026-09-12T00:00:00.000Z'),
('CRV/BR-001/SEP26/000001', (SELECT id FROM dbo.charts WHERE code='01002'), 3000, 0, 3000, 0, 0, 3000, N'Debit card received', N'Bank', N'F-00012', NULL, NULL, 3000, NULL, NULL, 'Active', '2026-09-01T00:00:00.000Z'),
('CRV/BR-001/SEP26/000001', (SELECT id FROM dbo.charts WHERE code='04001'), 0, 3000, 3000, 0, 0, 3000, N'Membership fee — Sep 2026', N'Membership Fee Income', N'BR-001/SEP26/00001', NULL, NULL, 3000, NULL, NULL, 'Active', '2026-09-01T00:00:00.000Z'),
('CPV/BR-001/AUG26/000004', (SELECT id FROM dbo.charts WHERE code='05002'), 25000, 0, 25000, 0, 0, 25000, N'K-Electric August bill', N'Utilities Expense', N'KE-88412', NULL, NULL, 25000, NULL, NULL, 'Active', '2026-08-28T00:00:00.000Z'),
('CPV/BR-001/AUG26/000004', (SELECT id FROM dbo.charts WHERE code='01001'), 0, 25000, 25000, 0, 0, 25000, N'Paid in cash', N'Cash in Hand', NULL, NULL, NULL, 25000, NULL, NULL, 'Active', '2026-08-28T00:00:00.000Z'),
('CPV/BR-001/AUG26/000001', (SELECT id FROM dbo.charts WHERE code='05003'), 120000, 0, 120000, 0, 0, 120000, N'August rent', N'Rent Expense', N'RENT-AUG26', NULL, NULL, 120000, NULL, NULL, 'Active', '2026-08-01T00:00:00.000Z'),
('CPV/BR-001/AUG26/000001', (SELECT id FROM dbo.charts WHERE code='01002'), 0, 120000, 120000, 0, 0, 120000, N'Paid from bank', N'Bank', NULL, NULL, NULL, 120000, NULL, NULL, 'Active', '2026-08-01T00:00:00.000Z'),
('CPV/BR-001/AUG26/000002', (SELECT id FROM dbo.charts WHERE code='05004'), 430000, 0, 430000, 0, 0, 430000, N'Whey protein + creatine stock', N'Gym Supplies Expense', N'PUR-00001', NULL, NULL, 430000, NULL, NULL, 'Active', '2026-08-15T00:00:00.000Z'),
('CPV/BR-001/AUG26/000002', (SELECT id FROM dbo.charts WHERE code='01002'), 0, 430000, 430000, 0, 0, 430000, N'Paid from bank', N'Bank', NULL, NULL, NULL, 430000, NULL, NULL, 'Active', '2026-08-15T00:00:00.000Z'),
('CPV/BR-001/AUG26/000003', (SELECT id FROM dbo.charts WHERE code='05004'), 57000, 0, 57000, 0, 0, 57000, N'Gloves + shaker bottles', N'Gym Supplies Expense', N'PUR-00002', NULL, NULL, 57000, NULL, NULL, 'Active', '2026-08-25T00:00:00.000Z'),
('CPV/BR-001/AUG26/000003', (SELECT id FROM dbo.charts WHERE code='01001'), 0, 57000, 57000, 0, 0, 57000, N'Paid in cash', N'Cash in Hand', NULL, NULL, NULL, 57000, NULL, NULL, 'Active', '2026-08-25T00:00:00.000Z'),
('CPV/BR-001/SEP26/000001', (SELECT id FROM dbo.charts WHERE code='05004'), 69000, 0, 69000, 0, 0, 69000, N'T-shirts + energy drinks', N'Gym Supplies Expense', N'PUR-00003', NULL, NULL, 69000, NULL, NULL, 'Active', '2026-09-10T00:00:00.000Z'),
('CPV/BR-001/SEP26/000001', (SELECT id FROM dbo.charts WHERE code='01002'), 0, 69000, 69000, 0, 0, 69000, N'Paid from bank', N'Bank', NULL, NULL, NULL, 69000, NULL, NULL, 'Active', '2026-09-10T00:00:00.000Z'),
('CRV/BR-001/SEP26/000003', (SELECT id FROM dbo.charts WHERE code='01001'), 17800, 0, 17800, 0, 0, 17800, N'Cash sale', N'Cash in Hand', N'POS-00001', NULL, NULL, 17800, NULL, NULL, 'Active', '2026-09-05T00:00:00.000Z'),
('CRV/BR-001/SEP26/000003', (SELECT id FROM dbo.charts WHERE code='04002'), 0, 17800, 17800, 0, 0, 17800, N'Supplements & accessories sold', N'POS Sales Income', N'POS-00001', NULL, NULL, 17800, NULL, NULL, 'Active', '2026-09-05T00:00:00.000Z'),
('CRV/BR-001/SEP26/000005', (SELECT id FROM dbo.charts WHERE code='01002'), 7150, 0, 7150, 0, 0, 7150, N'Card sale', N'Bank', N'POS-00002', NULL, NULL, 7150, NULL, NULL, 'Active', '2026-09-12T00:00:00.000Z'),
('CRV/BR-001/SEP26/000005', (SELECT id FROM dbo.charts WHERE code='04002'), 0, 7150, 7150, 0, 0, 7150, N'Supplements sold', N'POS Sales Income', N'POS-00002', NULL, NULL, 7150, NULL, NULL, 'Active', '2026-09-12T00:00:00.000Z'),
('CRV/BR-001/SEP26/000006', (SELECT id FROM dbo.charts WHERE code='01001'), 5000, 0, 5000, 0, 0, 5000, N'Cash sale', N'Cash in Hand', N'POS-00003', NULL, NULL, 5000, NULL, NULL, 'Active', '2026-09-18T00:00:00.000Z'),
('CRV/BR-001/SEP26/000006', (SELECT id FROM dbo.charts WHERE code='04002'), 0, 5000, 5000, 0, 0, 5000, N'Apparel & drinks sold', N'POS Sales Income', N'POS-00003', NULL, NULL, 5000, NULL, NULL, 'Active', '2026-09-18T00:00:00.000Z'));
GO

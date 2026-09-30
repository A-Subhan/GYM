-- ============================================================================
-- Contoura Gym Management System - STEP 7: Sample Data (FINAL design, optional)
-- ============================================================================
-- A small, coherent month of demo operations (October 2026) for branch BR-001
-- (+ one member at BR-002), built entirely on top of 06_master_data.sql.
--
-- Everything follows the FINAL business-ID contract of Backend/src/lib/ids.ts:
--   Book vouchers : CRV|CPV|BRV|BPV|JV|OTV/BR-001/OCT26/000001
--   Knock-off     : OTB-BR-001/0000001
--   Member / Fee / Attendance : BR-001/OCT26/00001
--   Prospect      : BR-001/p-00001      Follow-up : BR-001/fw-000001
--   Progress      : BR-001/Pg-000001    Freeze    : f-000001
--   Workout/Diet  : WO-000001 / DP-000001          Leave : LV-0001
--   POS sale      : POS/BR-001/OCT26/00001         Payroll run : PAY/BR-001/OCT26/00001
-- IdSequence rows are initialised just past every sample id so the
-- application continues numbering without collisions.
--
-- The accounting vouchers are balanced (Dr = Cr); OpenTB is deliberately kept
-- balanced here too, but the schema itself allows unbalanced opening TBs.
--
-- Re-run behaviour: if the sample already exists the script prints a notice
-- and skips everything (safe on repeat runs).
-- Run AFTER 06_master_data.sql on GymDB. Login used for anchors: admin/admin123.
-- ============================================================================

USE [GymDB];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF NOT EXISTS (SELECT 1 FROM dbo.Member WHERE id = N'BR-001/OCT26/00001')
BEGIN
    -- ---------------------------------------------------------------------
    -- Anchors (resolve ids created by step 06)
    -- ---------------------------------------------------------------------
    DECLARE @BR1      NVARCHAR(50) = (SELECT id FROM dbo.Branch WHERE code = N'BR-001');
    DECLARE @BR2      NVARCHAR(50) = (SELECT id FROM dbo.Branch WHERE code = N'BR-002');
    DECLARE @ADMIN    NVARCHAR(50) = (SELECT id FROM dbo.[User] WHERE username = N'admin');
    DECLARE @TRAINER1 NVARCHAR(50) = (SELECT id FROM dbo.Staff  WHERE id = N'EMP-0001');
    DECLARE @PLAN_M   NVARCHAR(50) = (SELECT id FROM dbo.MembershipPlan WHERE name = N'Monthly');
    DECLARE @PLAN_Q   NVARCHAR(50) = (SELECT id FROM dbo.MembershipPlan WHERE name = N'Quarterly');
    DECLARE @PLAN_Y   NVARCHAR(50) = (SELECT id FROM dbo.MembershipPlan WHERE name = N'Annual');
    DECLARE @ROLE_REC NVARCHAR(50) = (SELECT id FROM dbo.[Role] WHERE name = N'Receptionist');

    IF @BR1 IS NULL OR @BR2 IS NULL OR @ADMIN IS NULL OR @TRAINER1 IS NULL
       OR @PLAN_M IS NULL OR @PLAN_Q IS NULL OR @PLAN_Y IS NULL OR @ROLE_REC IS NULL
    BEGIN
        ;THROW 55101, 'Step 07: anchor rows missing (branch/role/plan/staff) - run 06_master_data.sql first.', 1;
    END

    BEGIN TRAN;

    BEGIN TRY

    -- ---------------------------------------------------------------------
    -- 1) Additional application user (reception desk - password: admin123)
    -- ---------------------------------------------------------------------
    INSERT INTO [User] ([id], [username], [email], [fullName], [passwordHash], [roleId], [branchId], [accessibleBranchIds], [phone], [isActive], [failedLoginCount], [mustChangePassword], [createdAt], [updatedAt], [isDeleted])
    VALUES ('user-reception', 'reception', 'reception@contouragym.com', N'Nida Kamran', '$2b$10$4sWId8YdsNlr39HgQ51wE.5rFtEFE3l5APRnRO6rYlE15bOUryvpy', @ROLE_REC, @BR1, N'*', N'+92 321 0000001', 1, 0, 0, SYSDATETIME(), SYSDATETIME(), 0);

    -- ---------------------------------------------------------------------
    -- 2) Staff (four more employees; EMP-0001 already seeded by step 06)
    -- ---------------------------------------------------------------------
    INSERT INTO dbo.Staff ([id], [firstName], [lastName], [fatherGuardian], [cnic], [phone], [email], [joiningDate], [department], [designation], [isTrainer], [branchId], [shiftId], [basicSalary], [overtimeAllowed], [overtimeRate], [isActive], [createdAt], [updatedAt], [isDeleted]) VALUES
    ('EMP-0002', N'Sana',    N'Ahmed',   N'M. Ahmed',   N'42101-1234567-2', N'+92 321 2222222', 'sana@contouragym.com',   '2026-01-05T00:00:00', N'Reception', N'Receptionist', 0, @BR1, '001',  25000, 0, 0, 1, SYSDATETIME(), SYSDATETIME(), 0),
    ('EMP-0003', N'Bilal',   N'Hussain', N'A. Hussain', N'42101-2345678-3', N'+92 333 3333333', 'bilal@contouragym.com',  '2026-02-01T00:00:00', N'Trainers',  N'Trainer',      1, @BR1, '002',  35000, 1, 250, 1, SYSDATETIME(), SYSDATETIME(), 0),
    ('EMP-0004', N'Ayesha',  N'Malik',   N'R. Malik',   N'42101-3456789-4', N'+92 345 5555555', 'ayesha@contouragym.com', '2026-03-15T00:00:00', N'Housekeeping', N'Cleaner',   0, @BR1, '003',  20000, 0, 0, 1, SYSDATETIME(), SYSDATETIME(), 0),
    ('EMP-0005', N'Usman',   N'Tariq',   N'M. Tariq',   N'42101-4567890-5', N'+92 347 7777777', 'usman@contouragym.com',  '2026-04-10T00:00:00', N'Finance',   N'Accountant',   0, @BR1, '003',  45000, 0, 0, 1, SYSDATETIME(), SYSDATETIME(), 0);

    -- ---------------------------------------------------------------------
    -- 3) Members (4 at BR-001, 1 at BR-002)
    -- ---------------------------------------------------------------------
    INSERT INTO dbo.Member ([id], [firstName], [lastName], [gender], [phone], [whatsapp], [email], [joiningDate], [billingStartDate], [feeRelaxationDays], [status], [membershipPlanId], [branchId], [assignedTrainerId], [isActive], [isDeleted], [createdAt], [updatedAt]) VALUES
    ('BR-001/OCT26/00001', N'Ali',     N'Raza',    N'Male',   N'+92 300 1111111', N'+92 300 1111111', 'ali@example.com',    '2026-10-01T00:00:00', '2026-10-01T00:00:00', 0, 'Active', @PLAN_M, @BR1, @TRAINER1, 1, 0, SYSDATETIME(), SYSDATETIME()),
    ('BR-001/OCT26/00002', N'Sara',    N'Khan',    N'Female', N'+92 300 2222222', N'+92 300 2222222', 'sara@example.com',   '2026-10-02T00:00:00', '2026-10-02T00:00:00', 0, 'Active', @PLAN_Q, @BR1, NULL,      1, 0, SYSDATETIME(), SYSDATETIME()),
    ('BR-001/OCT26/00003', N'Hamza',   N'Iqbal',   N'Male',   N'+92 300 3333333', N'+92 300 3333333', 'hamza@example.com',  '2026-10-03T00:00:00', '2026-10-03T00:00:00', 0, 'Active', @PLAN_Y, @BR1, @TRAINER1, 1, 0, SYSDATETIME(), SYSDATETIME()),
    ('BR-001/OCT26/00004', N'Ayesha',  N'Siddiqui',N'Female', N'+92 300 4444444', NULL,               'ayesha@example.com', '2026-10-04T00:00:00', '2026-10-04T00:00:00', 3, 'Active', NULL,    @BR1, NULL,      1, 0, SYSDATETIME(), SYSDATETIME()),
    ('BR-002/OCT26/00001', N'Bilal',   N'Ahmad',   N'Male',   N'+92 301 5555555', NULL,               'bilal.a@example.com','2026-10-05T00:00:00', '2026-10-05T00:00:00', 0, 'Active', NULL,    @BR2, NULL,      1, 0, SYSDATETIME(), SYSDATETIME());

    -- ---------------------------------------------------------------------
    -- 4) Attendance (unique per member + date)
    -- ---------------------------------------------------------------------
    INSERT INTO dbo.Attendance ([id], [memberId], [branchId], [date], [checkIn], [checkOut], [createdAt]) VALUES
    ('BR-001/OCT26/00001', 'BR-001/OCT26/00001', @BR1, '2026-10-05T00:00:00', '2026-10-05T06:12:00', '2026-10-05T07:40:00', SYSDATETIME()),
    ('BR-001/OCT26/00002', 'BR-001/OCT26/00001', @BR1, '2026-10-06T00:00:00', '2026-10-06T06:05:00', '2026-10-06T07:30:00', SYSDATETIME()),
    ('BR-001/OCT26/00003', 'BR-001/OCT26/00002', @BR1, '2026-10-05T00:00:00', '2026-10-05T17:20:00', '2026-10-05T18:50:00', SYSDATETIME());

    -- ---------------------------------------------------------------------
    -- 5) Fees + one cash payment (fee 1 paid via CRV below; fee 2 outstanding)
    -- ---------------------------------------------------------------------
    INSERT INTO dbo.Fee ([id], [memberId], [branchId], [billingPeriodStart], [billingPeriodEnd], [amount], [discount], [paidAmount], [balance], [dueDate], [status], [paymentMethod], [paymentAccountId], [paymentDate], [reference], [bookVoucherId], [createdAt], [updatedAt]) VALUES
    ('BR-001/OCT26/00001', 'BR-001/OCT26/00001', @BR1, '2026-10-01T00:00:00', '2026-10-31T00:00:00', 5000, 0, 5000, 0,    '2026-10-05T00:00:00', 'Paid',   'Cash', '01001', '2026-10-05T00:00:00', N'Oct monthly fee', 'CRV/BR-001/OCT26/000001', SYSDATETIME(), SYSDATETIME()),
    ('BR-001/OCT26/00002', 'BR-001/OCT26/00002', @BR1, '2026-10-01T00:00:00', '2026-11-30T00:00:00', 8000, 2000, 0, 6000, '2026-10-10T00:00:00', 'Unpaid', NULL,   NULL,    NULL,                  N'Quarterly (discount 2000)', NULL, SYSDATETIME(), SYSDATETIME());

    INSERT INTO dbo.FeePayment ([id], [feeId], [bookVoucherId], [amount], [method], [accountId], [createdAt]) VALUES
    ('fp-0001', 'BR-001/OCT26/00001', 'CRV/BR-001/OCT26/000001', 5000, N'Cash', '01001', SYSDATETIME());

    -- ---------------------------------------------------------------------
    -- 6) Opening trial balance (balanced) - OTV/BR-001/OCT26/000001
    -- ---------------------------------------------------------------------
    INSERT INTO dbo.OpenTB ([id], [voucherType], [voucherDate], [branchId], [description], [reference], [totalDebit], [totalCredit], [difference], [isBalanced], [status], [postedById], [createdAt], [updatedAt]) VALUES
    ('OTV/BR-001/OCT26/000001', 'OTV', '2026-10-01T00:00:00', @BR1, N'Opening balances for October 2026', NULL, 78000, 78000, 0, 1, 'Posted', @ADMIN, SYSDATETIME(), SYSDATETIME());

    INSERT INTO dbo.OpenTBLine ([id], [voucherId], [accountId], [debit], [credit], [amount], [lineDescription], [status], [createdAt]) VALUES
    ('otl-0001', 'OTV/BR-001/OCT26/000001', '01001', 20000, 0, 20000, N'Cash in hand',  'Active', SYSDATETIME()),
    ('otl-0002', 'OTV/BR-001/OCT26/000001', '01002', 50000, 0, 50000, N'Bank balance',  'Active', SYSDATETIME()),
    ('otl-0003', 'OTV/BR-001/OCT26/000001', '01003',  8000, 0,  8000, N'Members receivable', 'Active', SYSDATETIME()),
    ('otl-0004', 'OTV/BR-001/OCT26/000001', '03001', 0, 78000, 78000, N'Owner capital', 'Active', SYSDATETIME());

    -- ---------------------------------------------------------------------
    -- 7) Cash receipts / payments
    -- ---------------------------------------------------------------------
    -- CRV: cash received from member 1 against the October fee
    INSERT INTO dbo.CashBook ([id], [voucherType], [voucherDate], [branchId], [bookChartId], [description], [reference], [paymentMode], [totalAmount], [status], [postedById], [createdAt], [updatedAt]) VALUES
    ('CRV/BR-001/OCT26/000001', 'CRV', '2026-10-05T00:00:00', @BR1, '01001', N'October monthly fee received', N'RCPT-1001', 'Cash', 5000, 'Posted', @ADMIN, SYSDATETIME(), SYSDATETIME());

    INSERT INTO dbo.CashBookLine ([id], [voucherId], [accountId], [debit], [credit], [amount], [taxPercent], [taxAmount], [total], [lineDescription], [title], [reference], [billType], [status], [createdAt]) VALUES
    ('cbl-0001', 'CRV/BR-001/OCT26/000001', '01001', 5000, 0,    5000, 0, 0, 5000, N'Fee received from BR-001/OCT26/00001', N'Ali Raza',  N'RCPT-1001', N'Sales Bill', 'Active', SYSDATETIME()),
    ('cbl-0002', 'CRV/BR-001/OCT26/000001', '04001', 0,    5000, 5000, 0, 0, 5000, N'Membership fee income',               N'Ali Raza',  N'RCPT-1001', N'Sales Bill', 'Active', SYSDATETIME());

    -- CPV: utilities paid in cash
    INSERT INTO dbo.CashBook ([id], [voucherType], [voucherDate], [branchId], [bookChartId], [description], [reference], [paymentMode], [totalAmount], [status], [postedById], [createdAt], [updatedAt]) VALUES
    ('CPV/BR-001/OCT26/000001', 'CPV', '2026-10-07T00:00:00', @BR1, '01001', N'Electricity bill paid', N'BILL-K-E-2210', 'Cash', 2500, 'Posted', @ADMIN, SYSDATETIME(), SYSDATETIME());

    INSERT INTO dbo.CashBookLine ([id], [voucherId], [accountId], [debit], [credit], [amount], [taxPercent], [taxAmount], [total], [lineDescription], [reference], [status], [createdAt]) VALUES
    ('cbl-0003', 'CPV/BR-001/OCT26/000001', '05002', 2500, 0,    2500, 0, 0, 2500, N'K-Electric October', N'BILL-K-E-2210', 'Active', SYSDATETIME()),
    ('cbl-0004', 'CPV/BR-001/OCT26/000001', '01001', 0,    2500, 2500, 0, 0, 2500, N'Paid in cash',       N'BILL-K-E-2210', 'Active', SYSDATETIME());

    -- ---------------------------------------------------------------------
    -- 8) Bank payment (rent by cheque) - BPV/BR-001/OCT26/000001
    -- ---------------------------------------------------------------------
    INSERT INTO dbo.BankBook ([id], [voucherType], [voucherDate], [branchId], [bookChartId], [description], [reference], [paymentMode], [totalAmount], [status], [postedById], [createdAt], [updatedAt]) VALUES
    ('BPV/BR-001/OCT26/000001', 'BPV', '2026-10-08T00:00:00', @BR1, '01002', N'Branch rent paid by cheque', N'RENT-OCT-26', 'Cheque', 15000, 'Posted', @ADMIN, SYSDATETIME(), SYSDATETIME());

    INSERT INTO dbo.BankBookLine ([id], [voucherId], [accountId], [debit], [credit], [amount], [taxPercent], [taxAmount], [total], [lineDescription], [reference], [chequeNo], [chequeAmount], [chequeBankName], [chequeStatus], [status], [createdAt]) VALUES
    ('bbl-0001', 'BPV/BR-001/OCT26/000001', '05003', 0,    15000, 15000, 0, 0, 15000, N'October rent', N'RENT-OCT-26', 'CH-100234', 15000, N'Meezan Bank', N'Pending', 'Active', SYSDATETIME()),
    ('bbl-0002', 'BPV/BR-001/OCT26/000001', '01002', 15000, 0,   15000, 0, 0, 15000, N'Cheque issued', N'RENT-OCT-26', 'CH-100234', 15000, N'Meezan Bank', N'Pending', 'Active', SYSDATETIME());

    -- ---------------------------------------------------------------------
    -- 9) Journal voucher (supplies bought on account) - JV/BR-001/OCT26/000001
    -- ---------------------------------------------------------------------
    INSERT INTO dbo.JV ([id], [voucherType], [voucherDate], [branchId], [description], [reference], [totalDebit], [totalCredit], [status], [postedById], [createdAt], [updatedAt]) VALUES
    ('JV/BR-001/OCT26/000001', 'JV', '2026-10-09T00:00:00', @BR1, N'Gym supplies purchased on account', N'INV-7723', 1200, 1200, 'Posted', @ADMIN, SYSDATETIME(), SYSDATETIME());

    INSERT INTO dbo.JVLine ([id], [voucherId], [accountId], [debit], [credit], [amount], [taxPercent], [taxAmount], [total], [lineDescription], [reference], [status], [createdAt]) VALUES
    ('jvl-0001', 'JV/BR-001/OCT26/000001', '05004', 1200, 0, 1200, 0, 0, 1200, N'Cleaning supplies', N'INV-7723', 'Active', SYSDATETIME()),
    ('jvl-0002', 'JV/BR-001/OCT26/000001', '01004', 0, 1200, 1200, 0, 0, 1200, N'Due to supplier',   N'INV-7723', 'Active', SYSDATETIME());

    -- ---------------------------------------------------------------------
    -- 10) Knock-off (bill-wise receivable for the outstanding fee)
    -- ---------------------------------------------------------------------
    INSERT INTO dbo.KnockOff ([id], [billId], [billNumber], [referenceNumber], [billType], [amount], [dcFlag], [referenceDate], [dueDate], [description], [accountId], [branchId], [createdById], [createdAt], [updatedAt]) VALUES
    ('ko-0001', 'OTB-BR-001/0000001', 'BR-001/OCT26/00002', N'Q3-QTR-FEE', N'Membership Fee', 6000, 'Debit', '2026-10-02T00:00:00', '2026-10-10T00:00:00', N'Fee receivable', '01003', @BR1, @ADMIN, SYSDATETIME(), SYSDATETIME());

    -- ---------------------------------------------------------------------
    -- 11) Prospects, follow-up, freeze, progress
    -- ---------------------------------------------------------------------
    INSERT INTO dbo.Prospect ([id], [name], [phone], [whatsapp], [gender], [age], [interestedMembership], [branchId], [source], [status], [inquiryDate], [followUpDate], [assignedTo], [notes], [createdAt], [updatedAt]) VALUES
    ('BR-001/p-00001', N'Zain Abbas',   N'+92 302 6666666', NULL, N'Male',   26, N'Monthly',   @BR1, N'WalkIn',   'New',       '2026-10-05T00:00:00', '2026-10-12T00:00:00', N'Nida Kamran', N'Wants evening slot', SYSDATETIME(), SYSDATETIME()),
    ('BR-002/p-00001', N'Mariam Nawaz', N'+92 302 7777777', NULL, N'Female', 31, N'Quarterly', @BR2, N'Instagram','Contacted', '2026-10-06T00:00:00', '2026-10-13T00:00:00', N'Nida Kamran', N'Asked about ladies timings', SYSDATETIME(), SYSDATETIME());

    INSERT INTO dbo.FollowUp ([id], [prospectId], [branchId], [date], [type], [userId], [notes], [outcome], [nextFollowUpDate], [createdAt]) VALUES
    ('BR-001/fw-000001', 'BR-001/p-00001', @BR1, '2026-10-06T00:00:00', N'Call', @ADMIN, N'Called and shared plan rates', N'Interested', '2026-10-12T00:00:00', SYSDATETIME());

    INSERT INTO dbo.MembershipFreeze ([id], [memberId], [branchId], [freezeFrom], [freezeTo], [days], [reason], [status], [createdAt], [updatedAt]) VALUES
    ('f-000001', 'BR-001/OCT26/00002', @BR1, '2026-10-15T00:00:00', '2026-10-25T00:00:00', 10, N'Out of city', 'Active', SYSDATETIME(), SYSDATETIME());

    INSERT INTO dbo.ProgressEntry ([id], [memberId], [branchId], [date], [weight], [chest], [waist], [biceps], [notes], [createdAt]) VALUES
    ('BR-001/Pg-000001', 'BR-001/OCT26/00001', @BR1, '2026-10-06T00:00:00', 82.5, 101, 89, 33, N'Baseline measurement', SYSDATETIME());

    -- ---------------------------------------------------------------------
    -- 12) Workout / diet plans + assignments + goal
    -- ---------------------------------------------------------------------
    INSERT INTO dbo.WorkoutPlan ([id], [name], [description], [isGeneral], [branchId], [isActive], [createdAt], [updatedAt]) VALUES
    ('WO-000001', N'Starter Strength', N'Beginner 3-day strength routine', 1, @BR1, 1, SYSDATETIME(), SYSDATETIME());

    INSERT INTO dbo.WorkoutDay ([id], [planId], [dayName]) VALUES
    ('wd-0001', 'WO-000001', N'Day 1 - Push');

    INSERT INTO dbo.WorkoutDayExercise ([id], [dayId], [exerciseId], [sets], [reps]) VALUES
    ('wde-0001', 'wd-0001', '001001', 3, N'10-12');

    INSERT INTO dbo.WorkoutAssignment ([id], [memberId], [planId], [trainerId], [startDate], [notes], [createdAt]) VALUES
    ('wa-0001', 'BR-001/OCT26/00001', 'WO-000001', @TRAINER1, '2026-10-05T00:00:00', N'First assignment', SYSDATETIME());

    INSERT INTO dbo.DietPlan ([id], [name], [description], [branchId], [isActive], [createdAt], [updatedAt]) VALUES
    ('DP-000001', N'Cutting Plan', N'High protein, calorie deficit', @BR1, 1, SYSDATETIME(), SYSDATETIME());

    INSERT INTO dbo.DietMeal ([id], [planId], [dayOfWeek], [timing], [foods], [quantity], [calories], [protein], [carbs], [fat]) VALUES
    ('dm-0001', 'DP-000001', N'Monday', N'Breakfast', N'Boiled eggs, whole wheat toast', N'2 eggs, 2 slices', 380, 28, 30, 14),
    ('dm-0002', 'DP-000001', N'Monday', N'Lunch',     N'Grilled chicken, brown rice',    N'200g, 1 cup',      520, 42, 55, 10);

    INSERT INTO dbo.DietAssignment ([id], [memberId], [planId], [startDate], [createdAt]) VALUES
    ('da-0001', 'BR-001/OCT26/00001', 'DP-000001', '2026-10-05T00:00:00', SYSDATETIME());

    INSERT INTO dbo.FitnessGoal ([id], [memberId], [goalType], [targetValue], [unit], [startDate], [status], [createdAt], [updatedAt]) VALUES
    ('fg-0001', 'BR-001/OCT26/00001', N'WeightLoss', 75, N'kg', '2026-10-05T00:00:00', 'Active', SYSDATETIME(), SYSDATETIME());

    -- ---------------------------------------------------------------------
    -- 13) HR: leave, overtime, payroll run
    -- ---------------------------------------------------------------------
    INSERT INTO dbo.Leave ([id], [staffId], [branchId], [leaveType], [fromDate], [toDate], [days], [reason], [status], [approvedBy], [approvedAt], [createdAt], [updatedAt]) VALUES
    ('LV-0001', 'EMP-0002', @BR1, N'Casual', '2026-10-12T00:00:00', '2026-10-13T00:00:00', 2, N'Family matter', 'Approved', N'Admin', '2026-10-10T00:00:00', SYSDATETIME(), SYSDATETIME());

    INSERT INTO dbo.Overtime ([id], [staffId], [date], [hours], [rate], [amount], [status], [createdAt], [updatedAt]) VALUES
    ('ot-0001', 'EMP-0003', '2026-10-08T00:00:00', 2, 250, 500, 'Pending', SYSDATETIME(), SYSDATETIME());

    INSERT INTO dbo.Payroll ([id], [payrollNo], [staffId], [branchId], [month], [year], [basicSalary], [totalAllowances], [overtimeAmount], [totalEarnings], [totalDeductions], [netPay], [status], [createdAt], [updatedAt]) VALUES
    ('payroll-0001', 'PAY/BR-001/OCT26/00001', @TRAINER1, @BR1, 10, 2026, 40000, 5000, 0, 45000, 0, 45000, 'Draft', SYSDATETIME(), SYSDATETIME());

    -- ---------------------------------------------------------------------
    -- 14) Inventory, supplier, purchase, stock movement
    -- ---------------------------------------------------------------------
    INSERT INTO dbo.InventoryItem ([id], [code], [name], [category], [unit], [quantity], [reorderLevel], [purchasePrice], [salePrice], [branchId], [status], [createdAt], [updatedAt]) VALUES
    ('inv-0001', 'SKU-0001', N'Whey Protein 1kg', N'Supplements', N'jar',  20, 5, 7000, 9000, @BR1, 'Active', SYSDATETIME(), SYSDATETIME()),
    ('inv-0002', 'SKU-0002', N'Gym Gloves',       N'Accessories', N'pair',  3, 5,  800, 1500, @BR1, 'Active', SYSDATETIME(), SYSDATETIME());

    INSERT INTO dbo.Supplier ([id], [code], [name], [contactPerson], [phone], [branchId], [status], [createdAt], [updatedAt]) VALUES
    ('sup-0001', 'SUP-001', N'Fitness Equipment Co', N'Kamran Sheikh', N'+92 21 34567890', @BR1, 'Active', SYSDATETIME(), SYSDATETIME());

    INSERT INTO dbo.Purchase ([id], [purchaseNo], [supplierId], [branchId], [purchaseDate], [totalAmount], [status], [notes], [createdAt], [updatedAt]) VALUES
    ('pur-0001', 'PO-2026-10-0001', 'sup-0001', @BR1, '2026-10-03T00:00:00', 35000, 'Received', N'Protein restock', SYSDATETIME(), SYSDATETIME());

    INSERT INTO dbo.PurchaseLine ([id], [purchaseId], [inventoryItemId], [itemName], [quantity], [unitPrice], [amount]) VALUES
    ('pur-0001-1', 'pur-0001', 'inv-0001', N'Whey Protein 1kg', 5, 7000, 35000);

    INSERT INTO dbo.StockMovement ([id], [inventoryItemId], [branchId], [movementType], [quantity], [reference], [referenceId], [date], [notes], [createdAt]) VALUES
    ('sm-0001', 'inv-0001', @BR1, 'PurchaseIn', 5, N'PO-2026-10-0001', 'pur-0001', '2026-10-03T00:00:00', N'Restock received', SYSDATETIME());

    -- ---------------------------------------------------------------------
    -- 15) Equipment + maintenance + POS sale + calendar + audit
    -- ---------------------------------------------------------------------
    INSERT INTO dbo.Equipment ([id], [code], [name], [category], [purchaseDate], [purchasePrice], [quantity], [condition], [status], [branchId], [createdAt], [updatedAt]) VALUES
    ('eq-0001', 'EQ-00001', N'Treadmill T-500', N'Cardio', '2025-06-15T00:00:00', 350000, 1, N'Working', 'Active', @BR1, SYSDATETIME(), SYSDATETIME());

    INSERT INTO dbo.EquipmentMaintenance ([id], [equipmentId], [date], [type], [description], [cost], [vendor], [createdAt]) VALUES
    ('em-0001', 'eq-0001', '2026-10-04T00:00:00', N'Service', N'Belt alignment + lubrication', 1500, N'FitServ', SYSDATETIME());

    INSERT INTO dbo.PosSale ([id], [saleNo], [date], [branchId], [cashierId], [total], [paymentMethod], [paymentAccountId], [status], [createdAt], [updatedAt]) VALUES
    ('POS/BR-001/OCT26/00001', 'POS/BR-001/OCT26/00001', '2026-10-06T00:00:00', @BR1, @ADMIN, 18000, N'Cash', '01001', 'Completed', SYSDATETIME(), SYSDATETIME());

    INSERT INTO dbo.PosSaleLine ([id], [saleId], [inventoryItemId], [quantity], [unitPrice], [amount]) VALUES
    ('pos-0001-1', 'POS/BR-001/OCT26/00001', 'inv-0001', 2, 9000, 18000);

    INSERT INTO dbo.CalendarDay ([id], [date], [branchId], [dayType], [notes], [createdAt], [updatedAt]) VALUES
    ('001', '2026-10-25T00:00:00', @BR1, N'Holiday', N'Branch maintenance day', SYSDATETIME(), SYSDATETIME());

    INSERT INTO dbo.AuditLog ([id], [action], [module], [details], [createdAt]) VALUES
    ('audit-0001', N'SEED', N'database', N'Sample data (step 07) installed', SYSDATETIME());

    -- ---------------------------------------------------------------------
    -- 16) IdSequence initialisation - counters just past every sample id
    --     (keys per Backend/src/lib/ids.ts)
    -- ---------------------------------------------------------------------
    UPDATE s
       SET s.[next] = d.nextVal, s.updatedAt = SYSDATETIME()
    FROM dbo.IdSequence s
    INNER JOIN (VALUES
        (N'CRV/BR-001/OCT26',      2), (N'CPV/BR-001/OCT26',   2),
        (N'BPV/BR-001/OCT26',      2), (N'JV/BR-001/OCT26',    2),
        (N'OTV/BR-001/OCT26',      2), (N'KOFF/BR-001',        2),
        (N'MEMBER/BR-001/OCT26',   5), (N'MEMBER/BR-002/OCT26',2),
        (N'FEE/BR-001/OCT26',      3), (N'ATTENDANCE/BR-001/OCT26', 4),
        (N'PROSPECT/BR-001',       2), (N'PROSPECT/BR-002',    2),
        (N'FOLLOWUP/BR-001',       2), (N'PROGRESS/BR-001',    2),
        (N'FREEZE',                2), (N'WORKOUTPLAN',        2),
        (N'DIETPLAN',              2), (N'LEAVE',              2),
        (N'POS/BR-001/OCT26',      2), (N'PAY/BR-001/OCT26',   2),
        (N'EQUIPMENT',             2), (N'EMPLOYEE',           6)
    ) d([key], nextVal) ON d.[key] = s.[key];

    INSERT INTO dbo.IdSequence ([key], [next], [updatedAt])
    SELECT d.[key], d.nextVal, SYSDATETIME()
    FROM (VALUES
        (N'CRV/BR-001/OCT26',      2), (N'CPV/BR-001/OCT26',   2),
        (N'BPV/BR-001/OCT26',      2), (N'JV/BR-001/OCT26',    2),
        (N'OTV/BR-001/OCT26',      2), (N'KOFF/BR-001',        2),
        (N'MEMBER/BR-001/OCT26',   5), (N'MEMBER/BR-002/OCT26',2),
        (N'FEE/BR-001/OCT26',      3), (N'ATTENDANCE/BR-001/OCT26', 4),
        (N'PROSPECT/BR-001',       2), (N'PROSPECT/BR-002',    2),
        (N'FOLLOWUP/BR-001',       2), (N'PROGRESS/BR-001',    2),
        (N'FREEZE',                2), (N'WORKOUTPLAN',        2),
        (N'DIETPLAN',              2), (N'LEAVE',              2),
        (N'POS/BR-001/OCT26',      2), (N'PAY/BR-001/OCT26',   2),
        (N'EQUIPMENT',             2), (N'EMPLOYEE',           6)
    ) d([key], nextVal)
    WHERE NOT EXISTS (SELECT 1 FROM dbo.IdSequence s WHERE s.[key] = d.[key]);
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        ;THROW;
    END CATCH

    COMMIT TRAN;

    PRINT 'Step 07 complete: sample data installed (October 2026 demo month).';

    -- ---------------------------------------------------------------------
    -- Quick verification counts
    -- ---------------------------------------------------------------------
    SELECT N'User'              AS [table], COUNT(*) AS [rows] FROM dbo.[User]
    UNION ALL SELECT N'Staff',             COUNT(*) FROM dbo.Staff
    UNION ALL SELECT N'Member',            COUNT(*) FROM dbo.Member
    UNION ALL SELECT N'Attendance',        COUNT(*) FROM dbo.Attendance
    UNION ALL SELECT N'Fee',               COUNT(*) FROM dbo.Fee
    UNION ALL SELECT N'FeePayment',        COUNT(*) FROM dbo.FeePayment
    UNION ALL SELECT N'OpenTB',            COUNT(*) FROM dbo.OpenTB
    UNION ALL SELECT N'OpenTBLine',        COUNT(*) FROM dbo.OpenTBLine
    UNION ALL SELECT N'CashBook',          COUNT(*) FROM dbo.CashBook
    UNION ALL SELECT N'CashBookLine',      COUNT(*) FROM dbo.CashBookLine
    UNION ALL SELECT N'BankBook',          COUNT(*) FROM dbo.BankBook
    UNION ALL SELECT N'BankBookLine',      COUNT(*) FROM dbo.BankBookLine
    UNION ALL SELECT N'JV',                COUNT(*) FROM dbo.JV
    UNION ALL SELECT N'JVLine',            COUNT(*) FROM dbo.JVLine
    UNION ALL SELECT N'KnockOff',          COUNT(*) FROM dbo.KnockOff
    UNION ALL SELECT N'Prospect',          COUNT(*) FROM dbo.Prospect
    UNION ALL SELECT N'FollowUp',          COUNT(*) FROM dbo.FollowUp
    UNION ALL SELECT N'MembershipFreeze',  COUNT(*) FROM dbo.MembershipFreeze
    UNION ALL SELECT N'ProgressEntry',     COUNT(*) FROM dbo.ProgressEntry
    UNION ALL SELECT N'WorkoutPlan',       COUNT(*) FROM dbo.WorkoutPlan
    UNION ALL SELECT N'DietPlan',          COUNT(*) FROM dbo.DietPlan
    UNION ALL SELECT N'FitnessGoal',       COUNT(*) FROM dbo.FitnessGoal
    UNION ALL SELECT N'Leave',             COUNT(*) FROM dbo.Leave
    UNION ALL SELECT N'Overtime',          COUNT(*) FROM dbo.Overtime
    UNION ALL SELECT N'Payroll',           COUNT(*) FROM dbo.Payroll
    UNION ALL SELECT N'InventoryItem',     COUNT(*) FROM dbo.InventoryItem
    UNION ALL SELECT N'Purchase',          COUNT(*) FROM dbo.Purchase
    UNION ALL SELECT N'StockMovement',     COUNT(*) FROM dbo.StockMovement
    UNION ALL SELECT N'Equipment',         COUNT(*) FROM dbo.Equipment
    UNION ALL SELECT N'PosSale',           COUNT(*) FROM dbo.PosSale
    UNION ALL SELECT N'IdSequence',        COUNT(*) FROM dbo.IdSequence;
END
ELSE
BEGIN
    PRINT 'Step 07: sample data already present - skipped.';
END
GO

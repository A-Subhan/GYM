-- ============================================================================
-- Contoura Gym Management System — STEP 2: Schema (all 63 tables + relations)
-- ============================================================================
-- Creates the complete GymDB schema: 63 tables, primary keys, unique
-- constraints and 78 foreign-key relationships, exactly matching the
-- application's Prisma schema (D:\GYM\Backend\prisma\schema.prisma).
-- Idempotent-safe on a FRESH database created by 01_create_database.sql.
-- ============================================================================

USE [GymDB];
GO

BEGIN TRY

BEGIN TRAN;

-- CreateSchema
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = N'dbo') EXEC sp_executesql N'CREATE SCHEMA [dbo];';

-- CreateTable
CREATE TABLE [dbo].[Company] (
    [id] NVARCHAR(50) NOT NULL,
    [companyId] NVARCHAR(50) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [address] NVARCHAR(max),
    [phone] NVARCHAR(255),
    [email] NVARCHAR(255),
    [website] NVARCHAR(255),
    [logo] NVARCHAR(255),
    [accountingType] NVARCHAR(255) NOT NULL CONSTRAINT [Company_accountingType_df] DEFAULT 'FIFO',
    [strn] NVARCHAR(255),
    [ntn] NVARCHAR(255),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Company_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [Company_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [Company_companyId_key] UNIQUE NONCLUSTERED ([companyId])
);

-- CreateTable
CREATE TABLE [dbo].[Branch] (
    [id] NVARCHAR(50) NOT NULL,
    [code] NVARCHAR(191) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [address] NVARCHAR(max),
    [city] NVARCHAR(255),
    [phone] NVARCHAR(255),
    [email] NVARCHAR(255),
    [strn] NVARCHAR(255),
    [ntn] NVARCHAR(255),
    [logo] NVARCHAR(255),
    [isActive] BIT NOT NULL CONSTRAINT [Branch_isActive_df] DEFAULT 1,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Branch_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    [isDeleted] BIT NOT NULL CONSTRAINT [Branch_isDeleted_df] DEFAULT 0,
    CONSTRAINT [Branch_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [Branch_code_key] UNIQUE NONCLUSTERED ([code])
);

-- CreateTable
CREATE TABLE [dbo].[Role] (
    [id] NVARCHAR(50) NOT NULL,
    [name] NVARCHAR(191) NOT NULL,
    [description] NVARCHAR(max),
    [isSystem] BIT NOT NULL CONSTRAINT [Role_isSystem_df] DEFAULT 0,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Role_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [Role_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [Role_name_key] UNIQUE NONCLUSTERED ([name])
);

-- CreateTable
CREATE TABLE [dbo].[Permission] (
    [id] NVARCHAR(50) NOT NULL,
    [module] NVARCHAR(255) NOT NULL,
    [action] NVARCHAR(255) NOT NULL,
    [code] NVARCHAR(191) NOT NULL,
    [description] NVARCHAR(max),
    CONSTRAINT [Permission_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [Permission_code_key] UNIQUE NONCLUSTERED ([code])
);

-- CreateTable
CREATE TABLE [dbo].[RolePermission] (
    [roleId] NVARCHAR(50) NOT NULL,
    [permissionId] NVARCHAR(50) NOT NULL,
    CONSTRAINT [RolePermission_pkey] PRIMARY KEY CLUSTERED ([roleId],[permissionId])
);

-- CreateTable
CREATE TABLE [dbo].[User] (
    [id] NVARCHAR(50) NOT NULL,
    [username] NVARCHAR(191) NOT NULL,
    [email] NVARCHAR(191),
    [fullName] NVARCHAR(255) NOT NULL,
    [passwordHash] NVARCHAR(255) NOT NULL,
    [roleId] NVARCHAR(50) NOT NULL,
    [branchId] NVARCHAR(50),
    [accessibleBranchIds] NVARCHAR(255) NOT NULL CONSTRAINT [User_accessibleBranchIds_df] DEFAULT '*',
    [phone] NVARCHAR(255),
    [photo] NVARCHAR(255),
    [isActive] BIT NOT NULL CONSTRAINT [User_isActive_df] DEFAULT 1,
    [failedLoginCount] INT NOT NULL CONSTRAINT [User_failedLoginCount_df] DEFAULT 0,
    [lastLoginAt] DATETIME2,
    [mustChangePassword] BIT NOT NULL CONSTRAINT [User_mustChangePassword_df] DEFAULT 0,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [User_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    [isDeleted] BIT NOT NULL CONSTRAINT [User_isDeleted_df] DEFAULT 0,
    CONSTRAINT [User_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [User_username_key] UNIQUE NONCLUSTERED ([username]),
    CONSTRAINT [User_email_key] UNIQUE NONCLUSTERED ([email])
);

-- CreateTable
CREATE TABLE [dbo].[Session] (
    [id] NVARCHAR(50) NOT NULL,
    [userId] NVARCHAR(50) NOT NULL,
    [refreshToken] NVARCHAR(255) NOT NULL,
    [ipAddress] NVARCHAR(255),
    [userAgent] NVARCHAR(255),
    [location] NVARCHAR(255),
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [Session_status_df] DEFAULT 'Active',
    [expiresAt] DATETIME2 NOT NULL,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Session_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [Session_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable
CREATE TABLE [dbo].[AuditLog] (
    [id] NVARCHAR(50) NOT NULL,
    [userId] NVARCHAR(50),
    [action] NVARCHAR(255) NOT NULL,
    [module] NVARCHAR(255) NOT NULL,
    [details] NVARCHAR(max),
    [ipAddress] NVARCHAR(255),
    [location] NVARCHAR(255),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [AuditLog_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [AuditLog_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable
CREATE TABLE [dbo].[Account] (
    [id] NVARCHAR(50) NOT NULL,
    [code] NVARCHAR(255) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [parentId] NVARCHAR(50),
    [accountType] NVARCHAR(255) NOT NULL,
    [bookType] NVARCHAR(255),
    [accountTag] NVARCHAR(255),
    [isControl] BIT NOT NULL CONSTRAINT [Account_isControl_df] DEFAULT 0,
    [isDetail] BIT NOT NULL CONSTRAINT [Account_isDetail_df] DEFAULT 1,
    [isActive] BIT NOT NULL CONSTRAINT [Account_isActive_df] DEFAULT 1,
    [branchId] NVARCHAR(50),
    [contactName] NVARCHAR(255),
    [phone] NVARCHAR(255),
    [email] NVARCHAR(255),
    [address] NVARCHAR(max),
    [bankName] NVARCHAR(255),
    [bankAccountNo] NVARCHAR(255),
    [bankBranch] NVARCHAR(255),
    [cnic] NVARCHAR(255),
    [ntn] NVARCHAR(255),
    [description] NVARCHAR(max),
    [openingBalance] FLOAT(53) NOT NULL CONSTRAINT [Account_openingBalance_df] DEFAULT 0,
    [openingBalanceType] NVARCHAR(255),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Account_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [Account_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable
CREATE TABLE [dbo].[FinancialYear] (
    [id] NVARCHAR(50) NOT NULL,
    [name] NVARCHAR(191) NOT NULL,
    [startDate] DATETIME2 NOT NULL,
    [endDate] DATETIME2 NOT NULL,
    [isActive] BIT NOT NULL CONSTRAINT [FinancialYear_isActive_df] DEFAULT 1,
    [isClosed] BIT NOT NULL CONSTRAINT [FinancialYear_isClosed_df] DEFAULT 0,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [FinancialYear_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [FinancialYear_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [FinancialYear_name_key] UNIQUE NONCLUSTERED ([name])
);

-- CreateTable
CREATE TABLE [dbo].[AccountingPeriod] (
    [id] NVARCHAR(50) NOT NULL,
    [financialYearId] NVARCHAR(50) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [startDate] DATETIME2 NOT NULL,
    [endDate] DATETIME2 NOT NULL,
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [AccountingPeriod_status_df] DEFAULT 'Open',
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [AccountingPeriod_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [AccountingPeriod_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable
CREATE TABLE [dbo].[TaxHead] (
    [id] NVARCHAR(50) NOT NULL,
    [code] NVARCHAR(255) NOT NULL,
    [shortName] NVARCHAR(255) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [taxType] NVARCHAR(255) NOT NULL,
    [rate] FLOAT(53) NOT NULL,
    [branchId] NVARCHAR(50),
    [isActive] BIT NOT NULL CONSTRAINT [TaxHead_isActive_df] DEFAULT 1,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [TaxHead_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [TaxHead_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable
CREATE TABLE [dbo].[Voucher] (
    [id] NVARCHAR(50) NOT NULL,
    [voucherNo] NVARCHAR(191) NOT NULL,
    [voucherType] NVARCHAR(255) NOT NULL,
    [voucherDate] DATETIME2 NOT NULL,
    [branchId] NVARCHAR(50) NOT NULL,
    [bookAccountId] NVARCHAR(50),
    [description] NVARCHAR(max),
    [reference] NVARCHAR(255),
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [Voucher_status_df] DEFAULT 'Draft',
    [postedById] NVARCHAR(50),
    [postedAt] DATETIME2,
    [reversedById] NVARCHAR(50),
    [reversedAt] DATETIME2,
    [reversalReason] NVARCHAR(255),
    [totalDebit] FLOAT(53) NOT NULL CONSTRAINT [Voucher_totalDebit_df] DEFAULT 0,
    [totalCredit] FLOAT(53) NOT NULL CONSTRAINT [Voucher_totalCredit_df] DEFAULT 0,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Voucher_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [Voucher_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [Voucher_voucherNo_key] UNIQUE NONCLUSTERED ([voucherNo])
);

-- CreateTable
CREATE TABLE [dbo].[VoucherLine] (
    [id] NVARCHAR(50) NOT NULL,
    [voucherId] NVARCHAR(50) NOT NULL,
    [accountId] NVARCHAR(50) NOT NULL,
    [lineDescription] NVARCHAR(255),
    [title] NVARCHAR(255),
    [reference] NVARCHAR(255),
    [amount] FLOAT(53) NOT NULL CONSTRAINT [VoucherLine_amount_df] DEFAULT 0,
    [debit] FLOAT(53) NOT NULL CONSTRAINT [VoucherLine_debit_df] DEFAULT 0,
    [credit] FLOAT(53) NOT NULL CONSTRAINT [VoucherLine_credit_df] DEFAULT 0,
    [taxAccountId] NVARCHAR(50),
    [taxRate] FLOAT(53) NOT NULL CONSTRAINT [VoucherLine_taxRate_df] DEFAULT 0,
    [taxAmount] FLOAT(53) NOT NULL CONSTRAINT [VoucherLine_taxAmount_df] DEFAULT 0,
    [chequeNo] NVARCHAR(255),
    [chequeAmount] FLOAT(53),
    [chequeBankName] NVARCHAR(255),
    [chequeStatus] NVARCHAR(255),
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [VoucherLine_status_df] DEFAULT 'Active',
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [VoucherLine_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [VoucherLine_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable
CREATE TABLE [dbo].[Cheque] (
    [id] NVARCHAR(50) NOT NULL,
    [voucherId] NVARCHAR(50) NOT NULL,
    [chequeNo] NVARCHAR(255) NOT NULL,
    [chequeDate] DATETIME2 NOT NULL,
    [bankName] NVARCHAR(255),
    [amount] FLOAT(53) NOT NULL,
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [Cheque_status_df] DEFAULT 'Hold',
    [statusChangedAt] DATETIME2,
    [statusChangedBy] NVARCHAR(255),
    [statusHistory] NVARCHAR(255),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Cheque_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [Cheque_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable
CREATE TABLE [dbo].[AccountMapping] (
    [id] NVARCHAR(50) NOT NULL,
    [branchId] NVARCHAR(50),
    [key] NVARCHAR(255) NOT NULL,
    [accountId] NVARCHAR(50) NOT NULL,
    [description] NVARCHAR(max),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [AccountMapping_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [AccountMapping_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [AccountMapping_branchId_key_key] UNIQUE NONCLUSTERED ([branchId],[key])
);

-- CreateTable
CREATE TABLE [dbo].[FinanceDefaults] (
    [id] NVARCHAR(50) NOT NULL,
    [branchId] NVARCHAR(50),
    [defaultCashAccountId] NVARCHAR(50),
    [defaultBankAccountId] NVARCHAR(50),
    [defaultTaxHeadId] NVARCHAR(50),
    [financialYearId] NVARCHAR(50),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [FinanceDefaults_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [FinanceDefaults_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [FinanceDefaults_branchId_key] UNIQUE NONCLUSTERED ([branchId])
);

-- CreateTable
CREATE TABLE [dbo].[UserReportFormat] (
    [id] NVARCHAR(50) NOT NULL,
    [userId] NVARCHAR(50) NOT NULL,
    [reportKey] NVARCHAR(255) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [columns] NVARCHAR(255) NOT NULL,
    [isDefault] BIT NOT NULL CONSTRAINT [UserReportFormat_isDefault_df] DEFAULT 0,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [UserReportFormat_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [UserReportFormat_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UserReportFormat_userId_reportKey_name_key] UNIQUE NONCLUSTERED ([userId],[reportKey],[name])
);

-- CreateTable
CREATE TABLE [dbo].[Member] (
    [id] NVARCHAR(50) NOT NULL,
    [memberId] NVARCHAR(50) NOT NULL,
    [firstName] NVARCHAR(255) NOT NULL,
    [lastName] NVARCHAR(255),
    [gender] NVARCHAR(255),
    [dob] DATETIME2,
    [phone] NVARCHAR(255),
    [whatsapp] NVARCHAR(255),
    [email] NVARCHAR(255),
    [address] NVARCHAR(max),
    [emergencyContact] NVARCHAR(255),
    [emergencyContactNo] NVARCHAR(255),
    [photo] NVARCHAR(255),
    [cnic] NVARCHAR(255),
    [joiningDate] DATETIME2 NOT NULL CONSTRAINT [Member_joiningDate_df] DEFAULT CURRENT_TIMESTAMP,
    [billingStartDate] DATETIME2,
    [feeRelaxationDays] INT NOT NULL CONSTRAINT [Member_feeRelaxationDays_df] DEFAULT 0,
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [Member_status_df] DEFAULT 'Active',
    [membershipPlanId] NVARCHAR(50),
    [branchId] NVARCHAR(50) NOT NULL,
    [assignedTrainerId] NVARCHAR(50),
    [notes] NVARCHAR(max),
    [isActive] BIT NOT NULL CONSTRAINT [Member_isActive_df] DEFAULT 1,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Member_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    [isDeleted] BIT NOT NULL CONSTRAINT [Member_isDeleted_df] DEFAULT 0,
    CONSTRAINT [Member_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [Member_memberId_key] UNIQUE NONCLUSTERED ([memberId])
);

-- CreateTable
CREATE TABLE [dbo].[MembershipPlan] (
    [id] NVARCHAR(50) NOT NULL,
    [code] NVARCHAR(191) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [durationDays] INT NOT NULL,
    [amount] FLOAT(53) NOT NULL,
    [description] NVARCHAR(max),
    [isActive] BIT NOT NULL CONSTRAINT [MembershipPlan_isActive_df] DEFAULT 1,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [MembershipPlan_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [MembershipPlan_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [MembershipPlan_code_key] UNIQUE NONCLUSTERED ([code])
);

-- CreateTable
CREATE TABLE [dbo].[Attendance] (
    [id] NVARCHAR(50) NOT NULL,
    [memberId] NVARCHAR(50) NOT NULL,
    [branchId] NVARCHAR(50) NOT NULL,
    [date] DATETIME2 NOT NULL,
    [checkIn] DATETIME2,
    [checkOut] DATETIME2,
    [notes] NVARCHAR(max),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Attendance_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [Attendance_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [Attendance_memberId_date_key] UNIQUE NONCLUSTERED ([memberId],[date])
);

-- CreateTable
CREATE TABLE [dbo].[Fee] (
    [id] NVARCHAR(50) NOT NULL,
    [feeNo] NVARCHAR(191) NOT NULL,
    [memberId] NVARCHAR(50) NOT NULL,
    [branchId] NVARCHAR(50) NOT NULL,
    [billingPeriodStart] DATETIME2 NOT NULL,
    [billingPeriodEnd] DATETIME2 NOT NULL,
    [amount] FLOAT(53) NOT NULL,
    [discount] FLOAT(53) NOT NULL CONSTRAINT [Fee_discount_df] DEFAULT 0,
    [paidAmount] FLOAT(53) NOT NULL CONSTRAINT [Fee_paidAmount_df] DEFAULT 0,
    [balance] FLOAT(53) NOT NULL CONSTRAINT [Fee_balance_df] DEFAULT 0,
    [dueDate] DATETIME2 NOT NULL,
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [Fee_status_df] DEFAULT 'Unpaid',
    [paymentMethod] NVARCHAR(255),
    [paymentAccountId] NVARCHAR(50),
    [paymentDate] DATETIME2,
    [reference] NVARCHAR(255),
    [voucherId] NVARCHAR(50),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Fee_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [Fee_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [Fee_feeNo_key] UNIQUE NONCLUSTERED ([feeNo])
);

-- CreateTable
CREATE TABLE [dbo].[FeePayment] (
    [id] NVARCHAR(50) NOT NULL,
    [feeId] NVARCHAR(50) NOT NULL,
    [voucherId] NVARCHAR(50) NOT NULL,
    [amount] FLOAT(53) NOT NULL,
    [method] NVARCHAR(255) NOT NULL,
    [accountId] NVARCHAR(50) NOT NULL,
    [cardTypeId] NVARCHAR(50),
    [cardTypeName] NVARCHAR(255),
    [bankMasterId] NVARCHAR(50),
    [bankMasterName] NVARCHAR(255),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [FeePayment_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [FeePayment_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable
CREATE TABLE [dbo].[Prospect] (
    [id] NVARCHAR(50) NOT NULL,
    [prospectId] NVARCHAR(50) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [phone] NVARCHAR(255),
    [whatsapp] NVARCHAR(255),
    [gender] NVARCHAR(255),
    [age] INT,
    [dob] DATETIME2,
    [interestedMembership] NVARCHAR(255),
    [preferredBranchId] NVARCHAR(50),
    [source] NVARCHAR(255) NOT NULL,
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [Prospect_status_df] DEFAULT 'New',
    [inquiryDate] DATETIME2 NOT NULL CONSTRAINT [Prospect_inquiryDate_df] DEFAULT CURRENT_TIMESTAMP,
    [followUpDate] DATETIME2,
    [assignedTo] NVARCHAR(255),
    [notes] NVARCHAR(max),
    [convertedMemberId] NVARCHAR(50),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Prospect_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [Prospect_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [Prospect_prospectId_key] UNIQUE NONCLUSTERED ([prospectId])
);

-- CreateTable
CREATE TABLE [dbo].[MembershipFreeze] (
    [id] NVARCHAR(50) NOT NULL,
    [memberId] NVARCHAR(50) NOT NULL,
    [branchId] NVARCHAR(50) NOT NULL,
    [freezeFrom] DATETIME2 NOT NULL,
    [freezeTo] DATETIME2 NOT NULL,
    [days] INT NOT NULL,
    [reason] NVARCHAR(max),
    [approvedBy] NVARCHAR(255),
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [MembershipFreeze_status_df] DEFAULT 'Active',
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [MembershipFreeze_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [MembershipFreeze_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable
CREATE TABLE [dbo].[FollowUp] (
    [id] NVARCHAR(50) NOT NULL,
    [memberId] NVARCHAR(50),
    [prospectId] NVARCHAR(50),
    [branchId] NVARCHAR(50),
    [date] DATETIME2 NOT NULL CONSTRAINT [FollowUp_date_df] DEFAULT CURRENT_TIMESTAMP,
    [type] NVARCHAR(255) NOT NULL,
    [userId] NVARCHAR(50),
    [notes] NVARCHAR(max),
    [outcome] NVARCHAR(255),
    [nextFollowUpDate] DATETIME2,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [FollowUp_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [FollowUp_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable
CREATE TABLE [dbo].[Exercise] (
    [id] NVARCHAR(50) NOT NULL,
    [code] NVARCHAR(255) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [category] NVARCHAR(255),
    [muscleGroup] NVARCHAR(255),
    [instructions] NVARCHAR(max),
    [sets] INT,
    [reps] NVARCHAR(255),
    [duration] NVARCHAR(255),
    [rest] NVARCHAR(255),
    [equipment] NVARCHAR(255),
    [image] NVARCHAR(255),
    [branchId] NVARCHAR(50),
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [Exercise_status_df] DEFAULT 'Active',
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Exercise_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [Exercise_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable
CREATE TABLE [dbo].[WorkoutPlan] (
    [id] NVARCHAR(50) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [description] NVARCHAR(max),
    [isGeneral] BIT NOT NULL CONSTRAINT [WorkoutPlan_isGeneral_df] DEFAULT 1,
    [branchId] NVARCHAR(50),
    [isActive] BIT NOT NULL CONSTRAINT [WorkoutPlan_isActive_df] DEFAULT 1,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [WorkoutPlan_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [WorkoutPlan_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable
CREATE TABLE [dbo].[WorkoutDay] (
    [id] NVARCHAR(50) NOT NULL,
    [planId] NVARCHAR(50) NOT NULL,
    [dayName] NVARCHAR(255) NOT NULL,
    [notes] NVARCHAR(max),
    CONSTRAINT [WorkoutDay_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable
CREATE TABLE [dbo].[WorkoutDayExercise] (
    [id] NVARCHAR(50) NOT NULL,
    [dayId] NVARCHAR(50) NOT NULL,
    [exerciseId] NVARCHAR(50) NOT NULL,
    [sets] INT,
    [reps] NVARCHAR(255),
    [duration] NVARCHAR(255),
    [rest] NVARCHAR(255),
    [notes] NVARCHAR(max),
    CONSTRAINT [WorkoutDayExercise_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable
CREATE TABLE [dbo].[WorkoutAssignment] (
    [id] NVARCHAR(50) NOT NULL,
    [memberId] NVARCHAR(50) NOT NULL,
    [planId] NVARCHAR(50),
    [trainerId] NVARCHAR(50),
    [startDate] DATETIME2 NOT NULL CONSTRAINT [WorkoutAssignment_startDate_df] DEFAULT CURRENT_TIMESTAMP,
    [endDate] DATETIME2,
    [notes] NVARCHAR(max),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [WorkoutAssignment_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [WorkoutAssignment_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable
CREATE TABLE [dbo].[DietPlan] (
    [id] NVARCHAR(50) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [description] NVARCHAR(max),
    [branchId] NVARCHAR(50),
    [isActive] BIT NOT NULL CONSTRAINT [DietPlan_isActive_df] DEFAULT 1,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [DietPlan_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [DietPlan_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable
CREATE TABLE [dbo].[DietMeal] (
    [id] NVARCHAR(50) NOT NULL,
    [planId] NVARCHAR(50) NOT NULL,
    [dayOfWeek] NVARCHAR(255) NOT NULL,
    [timing] NVARCHAR(255) NOT NULL,
    [foods] NVARCHAR(255),
    [quantity] NVARCHAR(255),
    [calories] FLOAT(53),
    [protein] FLOAT(53),
    [carbs] FLOAT(53),
    [fat] FLOAT(53),
    [notes] NVARCHAR(max),
    CONSTRAINT [DietMeal_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable
CREATE TABLE [dbo].[DietAssignment] (
    [id] NVARCHAR(50) NOT NULL,
    [memberId] NVARCHAR(50) NOT NULL,
    [planId] NVARCHAR(50) NOT NULL,
    [startDate] DATETIME2 NOT NULL CONSTRAINT [DietAssignment_startDate_df] DEFAULT CURRENT_TIMESTAMP,
    [endDate] DATETIME2,
    [notes] NVARCHAR(max),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [DietAssignment_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [DietAssignment_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable
CREATE TABLE [dbo].[ProgressEntry] (
    [id] NVARCHAR(50) NOT NULL,
    [memberId] NVARCHAR(50) NOT NULL,
    [date] DATETIME2 NOT NULL CONSTRAINT [ProgressEntry_date_df] DEFAULT CURRENT_TIMESTAMP,
    [weight] FLOAT(53),
    [chest] FLOAT(53),
    [waist] FLOAT(53),
    [hips] FLOAT(53),
    [biceps] FLOAT(53),
    [thighs] FLOAT(53),
    [notes] NVARCHAR(max),
    [photo] NVARCHAR(255),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [ProgressEntry_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [ProgressEntry_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable
CREATE TABLE [dbo].[Equipment] (
    [id] NVARCHAR(50) NOT NULL,
    [code] NVARCHAR(255) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [category] NVARCHAR(255) NOT NULL,
    [description] NVARCHAR(max),
    [purchaseDate] DATETIME2,
    [purchasePrice] FLOAT(53),
    [quantity] INT NOT NULL CONSTRAINT [Equipment_quantity_df] DEFAULT 1,
    [condition] NVARCHAR(max) NOT NULL CONSTRAINT [Equipment_condition_df] DEFAULT 'Working',
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [Equipment_status_df] DEFAULT 'Active',
    [branchId] NVARCHAR(50) NOT NULL,
    [billReference] NVARCHAR(255),
    [billImage] NVARCHAR(255),
    [image] NVARCHAR(255),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Equipment_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [Equipment_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable
CREATE TABLE [dbo].[EquipmentMaintenance] (
    [id] NVARCHAR(50) NOT NULL,
    [equipmentId] NVARCHAR(50) NOT NULL,
    [date] DATETIME2 NOT NULL CONSTRAINT [EquipmentMaintenance_date_df] DEFAULT CURRENT_TIMESTAMP,
    [type] NVARCHAR(255) NOT NULL,
    [description] NVARCHAR(max),
    [cost] FLOAT(53) NOT NULL CONSTRAINT [EquipmentMaintenance_cost_df] DEFAULT 0,
    [vendor] NVARCHAR(255),
    [notes] NVARCHAR(max),
    [attachment] NVARCHAR(255),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [EquipmentMaintenance_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [EquipmentMaintenance_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable
CREATE TABLE [dbo].[InventoryItem] (
    [id] NVARCHAR(50) NOT NULL,
    [code] NVARCHAR(255) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [category] NVARCHAR(255),
    [description] NVARCHAR(max),
    [unit] NVARCHAR(255),
    [quantity] INT NOT NULL CONSTRAINT [InventoryItem_quantity_df] DEFAULT 0,
    [reorderLevel] INT NOT NULL CONSTRAINT [InventoryItem_reorderLevel_df] DEFAULT 0,
    [purchasePrice] FLOAT(53),
    [salePrice] FLOAT(53),
    [branchId] NVARCHAR(50) NOT NULL,
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [InventoryItem_status_df] DEFAULT 'Active',
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [InventoryItem_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [InventoryItem_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable
CREATE TABLE [dbo].[PosSale] (
    [id] NVARCHAR(50) NOT NULL,
    [saleNo] NVARCHAR(191) NOT NULL,
    [date] DATETIME2 NOT NULL CONSTRAINT [PosSale_date_df] DEFAULT CURRENT_TIMESTAMP,
    [branchId] NVARCHAR(50) NOT NULL,
    [cashierId] NVARCHAR(50),
    [total] FLOAT(53) NOT NULL,
    [paymentMethod] NVARCHAR(255) NOT NULL,
    [paymentAccountId] NVARCHAR(50),
    [voucherId] NVARCHAR(50),
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [PosSale_status_df] DEFAULT 'Completed',
    [notes] NVARCHAR(max),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [PosSale_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [PosSale_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [PosSale_saleNo_key] UNIQUE NONCLUSTERED ([saleNo])
);

-- CreateTable
CREATE TABLE [dbo].[PosSaleLine] (
    [id] NVARCHAR(50) NOT NULL,
    [saleId] NVARCHAR(50) NOT NULL,
    [inventoryItemId] NVARCHAR(50) NOT NULL,
    [quantity] INT NOT NULL,
    [unitPrice] FLOAT(53) NOT NULL,
    [amount] FLOAT(53) NOT NULL,
    CONSTRAINT [PosSaleLine_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable
CREATE TABLE [dbo].[Staff] (
    [id] NVARCHAR(50) NOT NULL,
    [employeeId] NVARCHAR(50) NOT NULL,
    [firstName] NVARCHAR(255) NOT NULL,
    [lastName] NVARCHAR(255),
    [fatherGuardian] NVARCHAR(255),
    [cnic] NVARCHAR(255),
    [photo] NVARCHAR(255),
    [address] NVARCHAR(max),
    [emergencyContact] NVARCHAR(255),
    [emergencyContactNo] NVARCHAR(255),
    [phone] NVARCHAR(255),
    [whatsapp] NVARCHAR(255),
    [telephone] NVARCHAR(255),
    [fax] NVARCHAR(255),
    [email] NVARCHAR(255),
    [joiningDate] DATETIME2 NOT NULL CONSTRAINT [Staff_joiningDate_df] DEFAULT CURRENT_TIMESTAMP,
    [department] NVARCHAR(255),
    [designation] NVARCHAR(255),
    [isTrainer] BIT NOT NULL CONSTRAINT [Staff_isTrainer_df] DEFAULT 0,
    [branchId] NVARCHAR(50) NOT NULL,
    [shiftId] NVARCHAR(50),
    [basicSalary] FLOAT(53) NOT NULL CONSTRAINT [Staff_basicSalary_df] DEFAULT 0,
    [fuelAllowance] FLOAT(53) NOT NULL CONSTRAINT [Staff_fuelAllowance_df] DEFAULT 0,
    [rentAllowance] FLOAT(53) NOT NULL CONSTRAINT [Staff_rentAllowance_df] DEFAULT 0,
    [houseAllowance] FLOAT(53) NOT NULL CONSTRAINT [Staff_houseAllowance_df] DEFAULT 0,
    [otherAllowance] FLOAT(53) NOT NULL CONSTRAINT [Staff_otherAllowance_df] DEFAULT 0,
    [sessi] FLOAT(53) NOT NULL CONSTRAINT [Staff_sessi_df] DEFAULT 0,
    [eobi] FLOAT(53) NOT NULL CONSTRAINT [Staff_eobi_df] DEFAULT 0,
    [fbrTaxNumber] NVARCHAR(255),
    [overtimeAllowed] BIT NOT NULL CONSTRAINT [Staff_overtimeAllowed_df] DEFAULT 0,
    [overtimeRate] FLOAT(53) NOT NULL CONSTRAINT [Staff_overtimeRate_df] DEFAULT 0,
    [isActive] BIT NOT NULL CONSTRAINT [Staff_isActive_df] DEFAULT 1,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Staff_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    [isDeleted] BIT NOT NULL CONSTRAINT [Staff_isDeleted_df] DEFAULT 0,
    CONSTRAINT [Staff_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [Staff_employeeId_key] UNIQUE NONCLUSTERED ([employeeId])
);

-- CreateTable
CREATE TABLE [dbo].[Shift] (
    [id] NVARCHAR(50) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [timeIn] NVARCHAR(255) NOT NULL,
    [timeOut] NVARCHAR(255) NOT NULL,
    [workingDays] NVARCHAR(255) NOT NULL,
    [branchId] NVARCHAR(50),
    [isActive] BIT NOT NULL CONSTRAINT [Shift_isActive_df] DEFAULT 1,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Shift_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [Shift_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable
CREATE TABLE [dbo].[CalendarDay] (
    [id] NVARCHAR(50) NOT NULL,
    [date] DATETIME2 NOT NULL,
    [branchId] NVARCHAR(50),
    [dayType] NVARCHAR(255) NOT NULL,
    [notes] NVARCHAR(max),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [CalendarDay_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [CalendarDay_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [CalendarDay_date_key] UNIQUE NONCLUSTERED ([date])
);

-- CreateTable
CREATE TABLE [dbo].[Leave] (
    [id] NVARCHAR(50) NOT NULL,
    [staffId] NVARCHAR(50) NOT NULL,
    [leaveType] NVARCHAR(255) NOT NULL,
    [fromDate] DATETIME2 NOT NULL,
    [toDate] DATETIME2 NOT NULL,
    [days] INT NOT NULL,
    [reason] NVARCHAR(max),
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [Leave_status_df] DEFAULT 'Pending',
    [approvedBy] NVARCHAR(255),
    [approvedAt] DATETIME2,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Leave_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [Leave_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable
CREATE TABLE [dbo].[Overtime] (
    [id] NVARCHAR(50) NOT NULL,
    [staffId] NVARCHAR(50) NOT NULL,
    [date] DATETIME2 NOT NULL,
    [hours] FLOAT(53) NOT NULL,
    [rate] FLOAT(53) NOT NULL,
    [amount] FLOAT(53) NOT NULL,
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [Overtime_status_df] DEFAULT 'Pending',
    [approvedBy] NVARCHAR(255),
    [approvedAt] DATETIME2,
    [notes] NVARCHAR(max),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Overtime_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [Overtime_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable
CREATE TABLE [dbo].[Payroll] (
    [id] NVARCHAR(50) NOT NULL,
    [payrollNo] NVARCHAR(191) NOT NULL,
    [staffId] NVARCHAR(50) NOT NULL,
    [branchId] NVARCHAR(50) NOT NULL,
    [month] INT NOT NULL,
    [year] INT NOT NULL,
    [basicSalary] FLOAT(53) NOT NULL,
    [totalAllowances] FLOAT(53) NOT NULL,
    [overtimeAmount] FLOAT(53) NOT NULL,
    [totalEarnings] FLOAT(53) NOT NULL,
    [totalDeductions] FLOAT(53) NOT NULL,
    [netPay] FLOAT(53) NOT NULL,
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [Payroll_status_df] DEFAULT 'Draft',
    [voucherId] NVARCHAR(50),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Payroll_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [Payroll_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [Payroll_payrollNo_key] UNIQUE NONCLUSTERED ([payrollNo]),
    CONSTRAINT [Payroll_staffId_month_year_key] UNIQUE NONCLUSTERED ([staffId],[month],[year])
);

-- CreateTable
CREATE TABLE [dbo].[LeaveType] (
    [id] NVARCHAR(50) NOT NULL,
    [name] NVARCHAR(191) NOT NULL,
    [allowedDays] INT NOT NULL,
    [isPaid] BIT NOT NULL CONSTRAINT [LeaveType_isPaid_df] DEFAULT 0,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [LeaveType_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [LeaveType_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [LeaveType_name_key] UNIQUE NONCLUSTERED ([name])
);

-- CreateTable
CREATE TABLE [dbo].[Allowance] (
    [id] NVARCHAR(50) NOT NULL,
    [name] NVARCHAR(191) NOT NULL,
    [description] NVARCHAR(max),
    [isStatutory] BIT NOT NULL CONSTRAINT [Allowance_isStatutory_df] DEFAULT 0,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Allowance_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [Allowance_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [Allowance_name_key] UNIQUE NONCLUSTERED ([name])
);

-- CreateTable
CREATE TABLE [dbo].[MasterFile] (
    [id] NVARCHAR(50) NOT NULL,
    [masterType] NVARCHAR(255) NOT NULL,
    [code] NVARCHAR(255) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [description] NVARCHAR(max),
    [isActive] BIT NOT NULL CONSTRAINT [MasterFile_isActive_df] DEFAULT 1,
    [extra] NVARCHAR(255),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [MasterFile_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [MasterFile_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [MasterFile_masterType_code_key] UNIQUE NONCLUSTERED ([masterType],[code]),
    CONSTRAINT [MasterFile_masterType_name_key] UNIQUE NONCLUSTERED ([masterType],[name])
);

-- CreateTable
CREATE TABLE [dbo].[FitnessGoal] (
    [id] NVARCHAR(50) NOT NULL,
    [memberId] NVARCHAR(50) NOT NULL,
    [goalType] NVARCHAR(255) NOT NULL,
    [targetValue] FLOAT(53),
    [unit] NVARCHAR(255),
    [startDate] DATETIME2 NOT NULL CONSTRAINT [FitnessGoal_startDate_df] DEFAULT CURRENT_TIMESTAMP,
    [targetDate] DATETIME2,
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [FitnessGoal_status_df] DEFAULT 'Active',
    [notes] NVARCHAR(max),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [FitnessGoal_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [FitnessGoal_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable
CREATE TABLE [dbo].[FitnessAssessment] (
    [id] NVARCHAR(50) NOT NULL,
    [memberId] NVARCHAR(50) NOT NULL,
    [trainerId] NVARCHAR(50),
    [branchId] NVARCHAR(50),
    [assessmentDate] DATETIME2 NOT NULL CONSTRAINT [FitnessAssessment_assessmentDate_df] DEFAULT CURRENT_TIMESTAMP,
    [height] FLOAT(53),
    [weight] FLOAT(53),
    [bmi] FLOAT(53),
    [bodyFat] FLOAT(53),
    [chest] FLOAT(53),
    [waist] FLOAT(53),
    [arms] FLOAT(53),
    [thighs] FLOAT(53),
    [fitnessLevel] NVARCHAR(255),
    [goal] NVARCHAR(255),
    [notes] NVARCHAR(max),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [FitnessAssessment_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [FitnessAssessment_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable
CREATE TABLE [dbo].[PersonalTrainingSession] (
    [id] NVARCHAR(50) NOT NULL,
    [memberId] NVARCHAR(50) NOT NULL,
    [trainerId] NVARCHAR(50) NOT NULL,
    [branchId] NVARCHAR(50),
    [sessionsPurchased] INT NOT NULL CONSTRAINT [PersonalTrainingSession_sessionsPurchased_df] DEFAULT 0,
    [sessionsUsed] INT NOT NULL CONSTRAINT [PersonalTrainingSession_sessionsUsed_df] DEFAULT 0,
    [sessionsRemaining] INT NOT NULL CONSTRAINT [PersonalTrainingSession_sessionsRemaining_df] DEFAULT 0,
    [sessionDate] DATETIME2,
    [sessionStatus] NVARCHAR(255) NOT NULL CONSTRAINT [PersonalTrainingSession_sessionStatus_df] DEFAULT 'Scheduled',
    [startDate] DATETIME2,
    [endDate] DATETIME2,
    [notes] NVARCHAR(max),
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [PersonalTrainingSession_status_df] DEFAULT 'Active',
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [PersonalTrainingSession_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [PersonalTrainingSession_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable
CREATE TABLE [dbo].[GymClass] (
    [id] NVARCHAR(50) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [trainerId] NVARCHAR(50),
    [branchId] NVARCHAR(50) NOT NULL,
    [capacity] INT NOT NULL CONSTRAINT [GymClass_capacity_df] DEFAULT 20,
    [dayOfWeek] NVARCHAR(255) NOT NULL,
    [startTime] NVARCHAR(255) NOT NULL,
    [endTime] NVARCHAR(255) NOT NULL,
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [GymClass_status_df] DEFAULT 'Active',
    [notes] NVARCHAR(max),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [GymClass_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [GymClass_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable
CREATE TABLE [dbo].[ClassEnrollment] (
    [id] NVARCHAR(50) NOT NULL,
    [classId] NVARCHAR(50) NOT NULL,
    [memberId] NVARCHAR(50) NOT NULL,
    [enrollmentDate] DATETIME2 NOT NULL CONSTRAINT [ClassEnrollment_enrollmentDate_df] DEFAULT CURRENT_TIMESTAMP,
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [ClassEnrollment_status_df] DEFAULT 'Enrolled',
    [attended] BIT NOT NULL CONSTRAINT [ClassEnrollment_attended_df] DEFAULT 0,
    [notes] NVARCHAR(max),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [ClassEnrollment_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [ClassEnrollment_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable
CREATE TABLE [dbo].[TrainerAvailability] (
    [id] NVARCHAR(50) NOT NULL,
    [staffId] NVARCHAR(50) NOT NULL,
    [dayOfWeek] NVARCHAR(255) NOT NULL,
    [startTime] NVARCHAR(255) NOT NULL,
    [endTime] NVARCHAR(255) NOT NULL,
    [branchId] NVARCHAR(50),
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [TrainerAvailability_status_df] DEFAULT 'Available',
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [TrainerAvailability_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [TrainerAvailability_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable
CREATE TABLE [dbo].[TrainerSchedule] (
    [id] NVARCHAR(50) NOT NULL,
    [staffId] NVARCHAR(50) NOT NULL,
    [branchId] NVARCHAR(50),
    [date] DATETIME2 NOT NULL,
    [dayOfWeek] NVARCHAR(255) NOT NULL,
    [startTime] NVARCHAR(255) NOT NULL,
    [endTime] NVARCHAR(255) NOT NULL,
    [sessionType] NVARCHAR(255) NOT NULL,
    [memberId] NVARCHAR(50),
    [classId] NVARCHAR(50),
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [TrainerSchedule_status_df] DEFAULT 'Scheduled',
    [notes] NVARCHAR(max),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [TrainerSchedule_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [TrainerSchedule_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable
CREATE TABLE [dbo].[MemberDocument] (
    [id] NVARCHAR(50) NOT NULL,
    [memberId] NVARCHAR(50) NOT NULL,
    [documentType] NVARCHAR(255) NOT NULL,
    [documentName] NVARCHAR(255) NOT NULL,
    [fileUrl] NVARCHAR(255) NOT NULL,
    [issueDate] DATETIME2,
    [expiryDate] DATETIME2,
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [MemberDocument_status_df] DEFAULT 'Active',
    [notes] NVARCHAR(max),
    [uploadedBy] NVARCHAR(255),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [MemberDocument_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [MemberDocument_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable
CREATE TABLE [dbo].[StaffDocument] (
    [id] NVARCHAR(50) NOT NULL,
    [staffId] NVARCHAR(50) NOT NULL,
    [documentType] NVARCHAR(255) NOT NULL,
    [documentName] NVARCHAR(255) NOT NULL,
    [fileUrl] NVARCHAR(255) NOT NULL,
    [issueDate] DATETIME2,
    [expiryDate] DATETIME2,
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [StaffDocument_status_df] DEFAULT 'Active',
    [notes] NVARCHAR(max),
    [uploadedBy] NVARCHAR(255),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [StaffDocument_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [StaffDocument_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable
CREATE TABLE [dbo].[FoodItem] (
    [id] NVARCHAR(50) NOT NULL,
    [code] NVARCHAR(255) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [category] NVARCHAR(255),
    [calories] FLOAT(53) NOT NULL CONSTRAINT [FoodItem_calories_df] DEFAULT 0,
    [protein] FLOAT(53) NOT NULL CONSTRAINT [FoodItem_protein_df] DEFAULT 0,
    [carbs] FLOAT(53) NOT NULL CONSTRAINT [FoodItem_carbs_df] DEFAULT 0,
    [fat] FLOAT(53) NOT NULL CONSTRAINT [FoodItem_fat_df] DEFAULT 0,
    [servingSize] NVARCHAR(255),
    [unit] NVARCHAR(255),
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [FoodItem_status_df] DEFAULT 'Active',
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [FoodItem_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [FoodItem_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [FoodItem_code_key] UNIQUE NONCLUSTERED ([code])
);

-- CreateTable
CREATE TABLE [dbo].[Supplier] (
    [id] NVARCHAR(50) NOT NULL,
    [code] NVARCHAR(255) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [contactPerson] NVARCHAR(255),
    [phone] NVARCHAR(255),
    [email] NVARCHAR(255),
    [address] NVARCHAR(max),
    [branchId] NVARCHAR(50),
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [Supplier_status_df] DEFAULT 'Active',
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Supplier_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [Supplier_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable
CREATE TABLE [dbo].[Purchase] (
    [id] NVARCHAR(50) NOT NULL,
    [purchaseNo] NVARCHAR(191) NOT NULL,
    [supplierId] NVARCHAR(50),
    [branchId] NVARCHAR(50) NOT NULL,
    [purchaseDate] DATETIME2 NOT NULL CONSTRAINT [Purchase_purchaseDate_df] DEFAULT CURRENT_TIMESTAMP,
    [totalAmount] FLOAT(53) NOT NULL CONSTRAINT [Purchase_totalAmount_df] DEFAULT 0,
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [Purchase_status_df] DEFAULT 'Pending',
    [notes] NVARCHAR(max),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Purchase_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [Purchase_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [Purchase_purchaseNo_key] UNIQUE NONCLUSTERED ([purchaseNo])
);

-- CreateTable
CREATE TABLE [dbo].[PurchaseLine] (
    [id] NVARCHAR(50) NOT NULL,
    [purchaseId] NVARCHAR(50) NOT NULL,
    [inventoryItemId] NVARCHAR(50),
    [itemName] NVARCHAR(255) NOT NULL,
    [quantity] INT NOT NULL CONSTRAINT [PurchaseLine_quantity_df] DEFAULT 0,
    [unitPrice] FLOAT(53) NOT NULL CONSTRAINT [PurchaseLine_unitPrice_df] DEFAULT 0,
    [amount] FLOAT(53) NOT NULL CONSTRAINT [PurchaseLine_amount_df] DEFAULT 0,
    CONSTRAINT [PurchaseLine_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable
CREATE TABLE [dbo].[StockMovement] (
    [id] NVARCHAR(50) NOT NULL,
    [inventoryItemId] NVARCHAR(50) NOT NULL,
    [branchId] NVARCHAR(50) NOT NULL,
    [movementType] NVARCHAR(255) NOT NULL,
    [quantity] INT NOT NULL,
    [reference] NVARCHAR(255),
    [referenceId] NVARCHAR(50),
    [date] DATETIME2 NOT NULL CONSTRAINT [StockMovement_date_df] DEFAULT CURRENT_TIMESTAMP,
    [notes] NVARCHAR(max),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [StockMovement_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [StockMovement_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateIndex
CREATE NONCLUSTERED INDEX [Session_userId_idx] ON [dbo].[Session]([userId]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [Session_refreshToken_idx] ON [dbo].[Session]([refreshToken]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [AuditLog_userId_idx] ON [dbo].[AuditLog]([userId]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [AuditLog_module_idx] ON [dbo].[AuditLog]([module]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [AuditLog_createdAt_idx] ON [dbo].[AuditLog]([createdAt]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [Account_code_idx] ON [dbo].[Account]([code]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [Account_parentId_idx] ON [dbo].[Account]([parentId]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [Account_branchId_idx] ON [dbo].[Account]([branchId]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [AccountingPeriod_financialYearId_idx] ON [dbo].[AccountingPeriod]([financialYearId]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [TaxHead_code_idx] ON [dbo].[TaxHead]([code]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [Voucher_voucherType_idx] ON [dbo].[Voucher]([voucherType]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [Voucher_voucherDate_idx] ON [dbo].[Voucher]([voucherDate]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [Voucher_branchId_idx] ON [dbo].[Voucher]([branchId]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [Voucher_status_idx] ON [dbo].[Voucher]([status]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [VoucherLine_voucherId_idx] ON [dbo].[VoucherLine]([voucherId]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [VoucherLine_accountId_idx] ON [dbo].[VoucherLine]([accountId]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [Cheque_status_idx] ON [dbo].[Cheque]([status]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [Cheque_chequeNo_idx] ON [dbo].[Cheque]([chequeNo]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [AccountMapping_key_idx] ON [dbo].[AccountMapping]([key]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [UserReportFormat_userId_reportKey_idx] ON [dbo].[UserReportFormat]([userId], [reportKey]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [Member_branchId_idx] ON [dbo].[Member]([branchId]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [Member_status_idx] ON [dbo].[Member]([status]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [Member_phone_idx] ON [dbo].[Member]([phone]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [Attendance_branchId_date_idx] ON [dbo].[Attendance]([branchId], [date]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [Fee_memberId_idx] ON [dbo].[Fee]([memberId]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [Fee_branchId_idx] ON [dbo].[Fee]([branchId]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [Fee_status_idx] ON [dbo].[Fee]([status]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [Fee_dueDate_idx] ON [dbo].[Fee]([dueDate]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [FeePayment_feeId_idx] ON [dbo].[FeePayment]([feeId]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [Prospect_status_idx] ON [dbo].[Prospect]([status]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [Prospect_source_idx] ON [dbo].[Prospect]([source]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [MembershipFreeze_memberId_idx] ON [dbo].[MembershipFreeze]([memberId]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [FollowUp_memberId_idx] ON [dbo].[FollowUp]([memberId]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [FollowUp_prospectId_idx] ON [dbo].[FollowUp]([prospectId]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [WorkoutAssignment_memberId_idx] ON [dbo].[WorkoutAssignment]([memberId]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [DietMeal_planId_dayOfWeek_idx] ON [dbo].[DietMeal]([planId], [dayOfWeek]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [DietAssignment_memberId_idx] ON [dbo].[DietAssignment]([memberId]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [ProgressEntry_memberId_date_idx] ON [dbo].[ProgressEntry]([memberId], [date]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [EquipmentMaintenance_equipmentId_idx] ON [dbo].[EquipmentMaintenance]([equipmentId]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [Leave_staffId_idx] ON [dbo].[Leave]([staffId]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [Leave_status_idx] ON [dbo].[Leave]([status]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [Overtime_staffId_idx] ON [dbo].[Overtime]([staffId]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [Overtime_status_idx] ON [dbo].[Overtime]([status]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [Payroll_branchId_idx] ON [dbo].[Payroll]([branchId]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [MasterFile_masterType_idx] ON [dbo].[MasterFile]([masterType]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [FitnessGoal_memberId_idx] ON [dbo].[FitnessGoal]([memberId]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [FitnessAssessment_memberId_assessmentDate_idx] ON [dbo].[FitnessAssessment]([memberId], [assessmentDate]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [PersonalTrainingSession_memberId_idx] ON [dbo].[PersonalTrainingSession]([memberId]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [PersonalTrainingSession_trainerId_idx] ON [dbo].[PersonalTrainingSession]([trainerId]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [ClassEnrollment_classId_idx] ON [dbo].[ClassEnrollment]([classId]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [ClassEnrollment_memberId_idx] ON [dbo].[ClassEnrollment]([memberId]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [TrainerAvailability_staffId_idx] ON [dbo].[TrainerAvailability]([staffId]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [TrainerSchedule_staffId_date_idx] ON [dbo].[TrainerSchedule]([staffId], [date]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [MemberDocument_memberId_idx] ON [dbo].[MemberDocument]([memberId]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [StaffDocument_staffId_idx] ON [dbo].[StaffDocument]([staffId]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [StockMovement_inventoryItemId_idx] ON [dbo].[StockMovement]([inventoryItemId]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [StockMovement_branchId_date_idx] ON [dbo].[StockMovement]([branchId], [date]);

-- AddForeignKey
ALTER TABLE [dbo].[RolePermission] ADD CONSTRAINT [RolePermission_roleId_fkey] FOREIGN KEY ([roleId]) REFERENCES [dbo].[Role]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[RolePermission] ADD CONSTRAINT [RolePermission_permissionId_fkey] FOREIGN KEY ([permissionId]) REFERENCES [dbo].[Permission]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[User] ADD CONSTRAINT [User_roleId_fkey] FOREIGN KEY ([roleId]) REFERENCES [dbo].[Role]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[User] ADD CONSTRAINT [User_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[Session] ADD CONSTRAINT [Session_userId_fkey] FOREIGN KEY ([userId]) REFERENCES [dbo].[User]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[AuditLog] ADD CONSTRAINT [AuditLog_userId_fkey] FOREIGN KEY ([userId]) REFERENCES [dbo].[User]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[Account] ADD CONSTRAINT [Account_parentId_fkey] FOREIGN KEY ([parentId]) REFERENCES [dbo].[Account]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[Account] ADD CONSTRAINT [Account_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[AccountingPeriod] ADD CONSTRAINT [AccountingPeriod_financialYearId_fkey] FOREIGN KEY ([financialYearId]) REFERENCES [dbo].[FinancialYear]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[TaxHead] ADD CONSTRAINT [TaxHead_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[Voucher] ADD CONSTRAINT [Voucher_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[Voucher] ADD CONSTRAINT [Voucher_bookAccountId_fkey] FOREIGN KEY ([bookAccountId]) REFERENCES [dbo].[Account]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[VoucherLine] ADD CONSTRAINT [VoucherLine_voucherId_fkey] FOREIGN KEY ([voucherId]) REFERENCES [dbo].[Voucher]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[VoucherLine] ADD CONSTRAINT [VoucherLine_accountId_fkey] FOREIGN KEY ([accountId]) REFERENCES [dbo].[Account]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[Cheque] ADD CONSTRAINT [Cheque_voucherId_fkey] FOREIGN KEY ([voucherId]) REFERENCES [dbo].[Voucher]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[AccountMapping] ADD CONSTRAINT [AccountMapping_accountId_fkey] FOREIGN KEY ([accountId]) REFERENCES [dbo].[Account]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[Member] ADD CONSTRAINT [Member_membershipPlanId_fkey] FOREIGN KEY ([membershipPlanId]) REFERENCES [dbo].[MembershipPlan]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[Member] ADD CONSTRAINT [Member_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[Attendance] ADD CONSTRAINT [Attendance_memberId_fkey] FOREIGN KEY ([memberId]) REFERENCES [dbo].[Member]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[Attendance] ADD CONSTRAINT [Attendance_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[Fee] ADD CONSTRAINT [Fee_memberId_fkey] FOREIGN KEY ([memberId]) REFERENCES [dbo].[Member]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[Fee] ADD CONSTRAINT [Fee_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[Fee] ADD CONSTRAINT [Fee_voucherId_fkey] FOREIGN KEY ([voucherId]) REFERENCES [dbo].[Voucher]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[FeePayment] ADD CONSTRAINT [FeePayment_feeId_fkey] FOREIGN KEY ([feeId]) REFERENCES [dbo].[Fee]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[FeePayment] ADD CONSTRAINT [FeePayment_voucherId_fkey] FOREIGN KEY ([voucherId]) REFERENCES [dbo].[Voucher]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[Prospect] ADD CONSTRAINT [Prospect_preferredBranchId_fkey] FOREIGN KEY ([preferredBranchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[MembershipFreeze] ADD CONSTRAINT [MembershipFreeze_memberId_fkey] FOREIGN KEY ([memberId]) REFERENCES [dbo].[Member]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[MembershipFreeze] ADD CONSTRAINT [MembershipFreeze_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[FollowUp] ADD CONSTRAINT [FollowUp_memberId_fkey] FOREIGN KEY ([memberId]) REFERENCES [dbo].[Member]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[FollowUp] ADD CONSTRAINT [FollowUp_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[Exercise] ADD CONSTRAINT [Exercise_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[WorkoutPlan] ADD CONSTRAINT [WorkoutPlan_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[WorkoutDay] ADD CONSTRAINT [WorkoutDay_planId_fkey] FOREIGN KEY ([planId]) REFERENCES [dbo].[WorkoutPlan]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[WorkoutDayExercise] ADD CONSTRAINT [WorkoutDayExercise_dayId_fkey] FOREIGN KEY ([dayId]) REFERENCES [dbo].[WorkoutDay]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[WorkoutDayExercise] ADD CONSTRAINT [WorkoutDayExercise_exerciseId_fkey] FOREIGN KEY ([exerciseId]) REFERENCES [dbo].[Exercise]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[WorkoutAssignment] ADD CONSTRAINT [WorkoutAssignment_memberId_fkey] FOREIGN KEY ([memberId]) REFERENCES [dbo].[Member]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[WorkoutAssignment] ADD CONSTRAINT [WorkoutAssignment_planId_fkey] FOREIGN KEY ([planId]) REFERENCES [dbo].[WorkoutPlan]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[DietPlan] ADD CONSTRAINT [DietPlan_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[DietMeal] ADD CONSTRAINT [DietMeal_planId_fkey] FOREIGN KEY ([planId]) REFERENCES [dbo].[DietPlan]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[DietAssignment] ADD CONSTRAINT [DietAssignment_memberId_fkey] FOREIGN KEY ([memberId]) REFERENCES [dbo].[Member]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[DietAssignment] ADD CONSTRAINT [DietAssignment_planId_fkey] FOREIGN KEY ([planId]) REFERENCES [dbo].[DietPlan]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[ProgressEntry] ADD CONSTRAINT [ProgressEntry_memberId_fkey] FOREIGN KEY ([memberId]) REFERENCES [dbo].[Member]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[Equipment] ADD CONSTRAINT [Equipment_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[EquipmentMaintenance] ADD CONSTRAINT [EquipmentMaintenance_equipmentId_fkey] FOREIGN KEY ([equipmentId]) REFERENCES [dbo].[Equipment]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[InventoryItem] ADD CONSTRAINT [InventoryItem_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[PosSale] ADD CONSTRAINT [PosSale_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[PosSaleLine] ADD CONSTRAINT [PosSaleLine_saleId_fkey] FOREIGN KEY ([saleId]) REFERENCES [dbo].[PosSale]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[PosSaleLine] ADD CONSTRAINT [PosSaleLine_inventoryItemId_fkey] FOREIGN KEY ([inventoryItemId]) REFERENCES [dbo].[InventoryItem]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[Staff] ADD CONSTRAINT [Staff_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[Staff] ADD CONSTRAINT [Staff_shiftId_fkey] FOREIGN KEY ([shiftId]) REFERENCES [dbo].[Shift]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[Shift] ADD CONSTRAINT [Shift_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[CalendarDay] ADD CONSTRAINT [CalendarDay_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[Leave] ADD CONSTRAINT [Leave_staffId_fkey] FOREIGN KEY ([staffId]) REFERENCES [dbo].[Staff]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[Overtime] ADD CONSTRAINT [Overtime_staffId_fkey] FOREIGN KEY ([staffId]) REFERENCES [dbo].[Staff]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[Payroll] ADD CONSTRAINT [Payroll_staffId_fkey] FOREIGN KEY ([staffId]) REFERENCES [dbo].[Staff]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[Payroll] ADD CONSTRAINT [Payroll_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[Payroll] ADD CONSTRAINT [Payroll_voucherId_fkey] FOREIGN KEY ([voucherId]) REFERENCES [dbo].[Voucher]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[FitnessGoal] ADD CONSTRAINT [FitnessGoal_memberId_fkey] FOREIGN KEY ([memberId]) REFERENCES [dbo].[Member]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[FitnessAssessment] ADD CONSTRAINT [FitnessAssessment_memberId_fkey] FOREIGN KEY ([memberId]) REFERENCES [dbo].[Member]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[FitnessAssessment] ADD CONSTRAINT [FitnessAssessment_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[PersonalTrainingSession] ADD CONSTRAINT [PersonalTrainingSession_memberId_fkey] FOREIGN KEY ([memberId]) REFERENCES [dbo].[Member]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[PersonalTrainingSession] ADD CONSTRAINT [PersonalTrainingSession_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[GymClass] ADD CONSTRAINT [GymClass_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[ClassEnrollment] ADD CONSTRAINT [ClassEnrollment_classId_fkey] FOREIGN KEY ([classId]) REFERENCES [dbo].[GymClass]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[ClassEnrollment] ADD CONSTRAINT [ClassEnrollment_memberId_fkey] FOREIGN KEY ([memberId]) REFERENCES [dbo].[Member]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[TrainerAvailability] ADD CONSTRAINT [TrainerAvailability_staffId_fkey] FOREIGN KEY ([staffId]) REFERENCES [dbo].[Staff]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[TrainerAvailability] ADD CONSTRAINT [TrainerAvailability_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[TrainerSchedule] ADD CONSTRAINT [TrainerSchedule_staffId_fkey] FOREIGN KEY ([staffId]) REFERENCES [dbo].[Staff]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[TrainerSchedule] ADD CONSTRAINT [TrainerSchedule_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[MemberDocument] ADD CONSTRAINT [MemberDocument_memberId_fkey] FOREIGN KEY ([memberId]) REFERENCES [dbo].[Member]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[StaffDocument] ADD CONSTRAINT [StaffDocument_staffId_fkey] FOREIGN KEY ([staffId]) REFERENCES [dbo].[Staff]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[Supplier] ADD CONSTRAINT [Supplier_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[Purchase] ADD CONSTRAINT [Purchase_supplierId_fkey] FOREIGN KEY ([supplierId]) REFERENCES [dbo].[Supplier]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[Purchase] ADD CONSTRAINT [Purchase_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[PurchaseLine] ADD CONSTRAINT [PurchaseLine_purchaseId_fkey] FOREIGN KEY ([purchaseId]) REFERENCES [dbo].[Purchase]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[PurchaseLine] ADD CONSTRAINT [PurchaseLine_inventoryItemId_fkey] FOREIGN KEY ([inventoryItemId]) REFERENCES [dbo].[InventoryItem]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[StockMovement] ADD CONSTRAINT [StockMovement_inventoryItemId_fkey] FOREIGN KEY ([inventoryItemId]) REFERENCES [dbo].[InventoryItem]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[StockMovement] ADD CONSTRAINT [StockMovement_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

COMMIT TRAN;

END TRY
BEGIN CATCH

IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRAN;
END;
THROW

END CATCH


PRINT 'Step 02 complete: 63 tables + foreign keys created.';
GO

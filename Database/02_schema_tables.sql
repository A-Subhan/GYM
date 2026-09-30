-- ============================================================================
-- Contoura Gym Management System - STEP 2: Schema & Tables (FINAL design)
-- ============================================================================
-- Creates the complete GymDB relational schema, matching
-- Backend/prisma/schema.prisma EXACTLY (table names, columns, types,
-- nullability, defaults, keys, indexes, foreign keys).
--
-- Design highlights:
--   * Chart of Accounts table is [charts] (NOT [Account]); charts.id IS the
--     account code, hierarchy via parentCode ('ROOT' for tree roots).
--   * Dedicated book vouchers: [CashBook]/[CashBookLine], [BankBook]/
--     [BankBookLine], [JV]/[JVLine], [OpenTB]/[OpenTBLine]; the voucher id IS
--     the voucher number. OpenTB allows unbalanced saves (no Dr=Cr trigger).
--   * [KnockOff] bill-wise settlement, [IdSequence] atomic business-ID
--     counters, [Defaults] company settings, [ScreenPermission]/
--     [UserPermission] per-screen security, hierarchical [Branch].
--   * THREE IDENTICAL master/detail pairs: [gymmaster]/[gymmasterdetail],
--     [financemaster]/[financemasterdetail], [payrollmaster]/[payrollmasterdetail]
--     (master.id = 3-digit category code, detail.id = master code + sequence).
--     Exercises live in gymmaster category '001' (the standalone [Exercise]
--     table was merged away). [User].[userType]: Admin | User.
--     Legacy [gymmasterfile]/[payrollmasterfile]/[MasterFile] are kept for
--     pre-upgrade data compatibility.
--
-- Layout (safe to re-run on a partially-built database):
--   SECTION 1  Tables - created WITHOUT foreign keys, in one pass, so no
--              forward references can ever fail. 69 tables.
--   SECTION 2  Nonclustered indexes.
--   SECTION 3  Foreign keys - added only after ALL tables exist.
--
-- Requirements: SQL Server 2016+ on an empty or partial GymDB
-- (run 01_create_database.sql first). No SQLCMD mode required.
-- ===========================================================================

USE [GymDB];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

PRINT 'Step 02: creating schema ...';
GO

-- ===========================================================================
-- SECTION 1 of 3 - TABLES (no FKs; all foreign keys are added in SECTION 3)
-- ===========================================================================

-- ---- table 1/69: Branch ----------------------------------
IF OBJECT_ID(N'dbo.Branch', N'U') IS NULL
CREATE TABLE [dbo].[Branch] (
    [id] NVARCHAR(50) NOT NULL,
    [code] NVARCHAR(191) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [parentId] NVARCHAR(50),
    [nodeType] NVARCHAR(1000) NOT NULL CONSTRAINT [Branch_nodeType_df] DEFAULT 'Detail',
    [address] NVARCHAR(MAX),
    [city] NVARCHAR(255),
    [phone] NVARCHAR(255),
    [email] NVARCHAR(255),
    [strn] NVARCHAR(255),
    [ntn] NVARCHAR(255),
    [trn] NVARCHAR(255),
    [fbr] NVARCHAR(255),
    [logo] NVARCHAR(255),
    [isActive] BIT NOT NULL CONSTRAINT [Branch_isActive_df] DEFAULT 1,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Branch_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    [isDeleted] BIT NOT NULL CONSTRAINT [Branch_isDeleted_df] DEFAULT 0,
    CONSTRAINT [Branch_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [Branch_code_key] UNIQUE NONCLUSTERED ([code])
);
GO

-- ---- table 2/69: Role ------------------------------------
IF OBJECT_ID(N'dbo.Role', N'U') IS NULL
CREATE TABLE [dbo].[Role] (
    [id] NVARCHAR(50) NOT NULL,
    [name] NVARCHAR(191) NOT NULL,
    [description] NVARCHAR(MAX),
    [isSystem] BIT NOT NULL CONSTRAINT [Role_isSystem_df] DEFAULT 0,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Role_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [Role_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [Role_name_key] UNIQUE NONCLUSTERED ([name])
);
GO

-- ---- table 3/69: ScreenPermission ------------------------
IF OBJECT_ID(N'dbo.ScreenPermission', N'U') IS NULL
CREATE TABLE [dbo].[ScreenPermission] (
    [id] NVARCHAR(50) NOT NULL,
    [roleId] NVARCHAR(50) NOT NULL,
    [screenKey] NVARCHAR(255) NOT NULL,
    [canView] BIT NOT NULL CONSTRAINT [ScreenPermission_canView_df] DEFAULT 0,
    [canAdd] BIT NOT NULL CONSTRAINT [ScreenPermission_canAdd_df] DEFAULT 0,
    [canEdit] BIT NOT NULL CONSTRAINT [ScreenPermission_canEdit_df] DEFAULT 0,
    [canDelete] BIT NOT NULL CONSTRAINT [ScreenPermission_canDelete_df] DEFAULT 0,
    [canPrint] BIT NOT NULL CONSTRAINT [ScreenPermission_canPrint_df] DEFAULT 0,
    CONSTRAINT [ScreenPermission_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [ScreenPermission_roleId_screenKey_key] UNIQUE NONCLUSTERED ([roleId],[screenKey])
);
GO

-- ---- table 4/69: UserPermission --------------------------
IF OBJECT_ID(N'dbo.UserPermission', N'U') IS NULL
CREATE TABLE [dbo].[UserPermission] (
    [id] NVARCHAR(50) NOT NULL,
    [userId] NVARCHAR(50) NOT NULL,
    [screenKey] NVARCHAR(255) NOT NULL,
    [canView] BIT NOT NULL CONSTRAINT [UserPermission_canView_df] DEFAULT 0,
    [canAdd] BIT NOT NULL CONSTRAINT [UserPermission_canAdd_df] DEFAULT 0,
    [canEdit] BIT NOT NULL CONSTRAINT [UserPermission_canEdit_df] DEFAULT 0,
    [canDelete] BIT NOT NULL CONSTRAINT [UserPermission_canDelete_df] DEFAULT 0,
    [canPrint] BIT NOT NULL CONSTRAINT [UserPermission_canPrint_df] DEFAULT 0,
    CONSTRAINT [UserPermission_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [UserPermission_userId_screenKey_key] UNIQUE NONCLUSTERED ([userId],[screenKey])
);
GO

-- ---- table 5/69: Permission ------------------------------
IF OBJECT_ID(N'dbo.Permission', N'U') IS NULL
CREATE TABLE [dbo].[Permission] (
    [id] NVARCHAR(50) NOT NULL,
    [module] NVARCHAR(255) NOT NULL,
    [action] NVARCHAR(255) NOT NULL,
    [code] NVARCHAR(191) NOT NULL,
    [description] NVARCHAR(MAX),
    CONSTRAINT [Permission_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [Permission_code_key] UNIQUE NONCLUSTERED ([code])
);
GO

-- ---- table 6/69: RolePermission --------------------------
IF OBJECT_ID(N'dbo.RolePermission', N'U') IS NULL
CREATE TABLE [dbo].[RolePermission] (
    [roleId] NVARCHAR(50) NOT NULL,
    [permissionId] NVARCHAR(50) NOT NULL,
    CONSTRAINT [RolePermission_pkey] PRIMARY KEY CLUSTERED ([roleId],[permissionId])
);
GO

-- ---- table 7/69: User ------------------------------------
IF OBJECT_ID(N'dbo.User', N'U') IS NULL
CREATE TABLE [dbo].[User] (
    [id] NVARCHAR(50) NOT NULL,
    [username] NVARCHAR(191) NOT NULL,
    [email] NVARCHAR(191),
    [fullName] NVARCHAR(255) NOT NULL,
    [passwordHash] NVARCHAR(255) NOT NULL,
    [userType] NVARCHAR(255) NOT NULL CONSTRAINT [User_userType_df] DEFAULT 'User',
    [roleId] NVARCHAR(50),
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
GO

-- ---- table 8/69: Session ---------------------------------
IF OBJECT_ID(N'dbo.Session', N'U') IS NULL
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
GO

-- ---- table 9/69: AuditLog --------------------------------
IF OBJECT_ID(N'dbo.AuditLog', N'U') IS NULL
CREATE TABLE [dbo].[AuditLog] (
    [id] NVARCHAR(50) NOT NULL,
    [userId] NVARCHAR(50),
    [action] NVARCHAR(255) NOT NULL,
    [module] NVARCHAR(255) NOT NULL,
    [details] NVARCHAR(MAX),
    [ipAddress] NVARCHAR(255),
    [location] NVARCHAR(255),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [AuditLog_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [AuditLog_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

-- ---- table 10/69: charts ----------------------------------
IF OBJECT_ID(N'dbo.charts', N'U') IS NULL
CREATE TABLE [dbo].[charts] (
    [id] NVARCHAR(50) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [parentCode] NVARCHAR(50) NOT NULL,
    [accountType] NVARCHAR(255) NOT NULL,
    [bookType] NVARCHAR(255),
    [accountTag] NVARCHAR(255),
    [isControl] BIT NOT NULL CONSTRAINT [charts_isControl_df] DEFAULT 0,
    [isDetail] BIT NOT NULL CONSTRAINT [charts_isDetail_df] DEFAULT 1,
    [isActive] BIT NOT NULL CONSTRAINT [charts_isActive_df] DEFAULT 1,
    [branchId] NVARCHAR(50),
    [contactName] NVARCHAR(255),
    [phone] NVARCHAR(255),
    [email] NVARCHAR(255),
    [address] NVARCHAR(MAX),
    [bankName] NVARCHAR(255),
    [bankAccountNo] NVARCHAR(255),
    [bankBranch] NVARCHAR(255),
    [cnic] NVARCHAR(255),
    [strn] NVARCHAR(255),
    [ntn] NVARCHAR(255),
    [fbr] NVARCHAR(255),
    [otherName] NVARCHAR(255),
    [referenceNumber] NVARCHAR(255),
    [faxNumber] NVARCHAR(255),
    [city] NVARCHAR(255),
    [country] NVARCHAR(255),
    [website] NVARCHAR(255),
    [paymentTerms] NVARCHAR(255),
    [registrationNumber] NVARCHAR(255),
    [description] NVARCHAR(MAX),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [charts_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [charts_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

-- ---- table 11/69: CashBook --------------------------------
IF OBJECT_ID(N'dbo.CashBook', N'U') IS NULL
CREATE TABLE [dbo].[CashBook] (
    [id] NVARCHAR(50) NOT NULL,
    [voucherType] NVARCHAR(10) NOT NULL,
    [voucherDate] DATETIME2 NOT NULL,
    [branchId] NVARCHAR(50) NOT NULL,
    [bookChartId] NVARCHAR(50) NOT NULL,
    [description] NVARCHAR(MAX),
    [reference] NVARCHAR(255),
    [paymentMode] NVARCHAR(255),
    [totalAmount] FLOAT(53) NOT NULL CONSTRAINT [CashBook_totalAmount_df] DEFAULT 0,
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [CashBook_status_df] DEFAULT 'Posted',
    -- SOFT delete (deleted vouchers stay for the audit trail; excluded from
    -- lists/reports/ledgers by the app)
    [isDeleted] BIT NOT NULL CONSTRAINT [CashBook_isDeleted_df] DEFAULT 0,
    [deletedById] NVARCHAR(50),
    [deletedAt] DATETIME2,
    [reversedById] NVARCHAR(50),
    [reversedAt] DATETIME2,
    [reversalReason] NVARCHAR(255),
    [postedById] NVARCHAR(50),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [CashBook_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [CashBook_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

-- ---- table 12/69: CashBookLine ----------------------------
IF OBJECT_ID(N'dbo.CashBookLine', N'U') IS NULL
CREATE TABLE [dbo].[CashBookLine] (
    [id] NVARCHAR(50) NOT NULL,
    [voucherId] NVARCHAR(50) NOT NULL,
    [accountId] NVARCHAR(50) NOT NULL,
    [debit] FLOAT(53) NOT NULL CONSTRAINT [CashBookLine_debit_df] DEFAULT 0,
    [credit] FLOAT(53) NOT NULL CONSTRAINT [CashBookLine_credit_df] DEFAULT 0,
    [amount] FLOAT(53) NOT NULL CONSTRAINT [CashBookLine_amount_df] DEFAULT 0,
    [taxPercent] FLOAT(53) NOT NULL CONSTRAINT [CashBookLine_taxPercent_df] DEFAULT 0,
    [taxAmount] FLOAT(53) NOT NULL CONSTRAINT [CashBookLine_taxAmount_df] DEFAULT 0,
    [total] FLOAT(53) NOT NULL CONSTRAINT [CashBookLine_total_df] DEFAULT 0,
    [lineDescription] NVARCHAR(255),
    [title] NVARCHAR(255),
    [reference] NVARCHAR(255),
    [billType] NVARCHAR(255),
    [chequeNo] NVARCHAR(255),
    [chequeAmount] FLOAT(53),
    [chequeBankName] NVARCHAR(255),
    [chequeStatus] NVARCHAR(255),
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [CashBookLine_status_df] DEFAULT 'Active',
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [CashBookLine_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [CashBookLine_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

-- ---- table 13/69: BankBook --------------------------------
IF OBJECT_ID(N'dbo.BankBook', N'U') IS NULL
CREATE TABLE [dbo].[BankBook] (
    [id] NVARCHAR(50) NOT NULL,
    [voucherType] NVARCHAR(10) NOT NULL,
    [voucherDate] DATETIME2 NOT NULL,
    [branchId] NVARCHAR(50) NOT NULL,
    [bookChartId] NVARCHAR(50) NOT NULL,
    [description] NVARCHAR(MAX),
    [reference] NVARCHAR(255),
    [paymentMode] NVARCHAR(255),
    [totalAmount] FLOAT(53) NOT NULL CONSTRAINT [BankBook_totalAmount_df] DEFAULT 0,
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [BankBook_status_df] DEFAULT 'Posted',
    -- SOFT delete (deleted vouchers stay for the audit trail; excluded from
    -- lists/reports/ledgers by the app)
    [isDeleted] BIT NOT NULL CONSTRAINT [BankBook_isDeleted_df] DEFAULT 0,
    [deletedById] NVARCHAR(50),
    [deletedAt] DATETIME2,
    [reversedById] NVARCHAR(50),
    [reversedAt] DATETIME2,
    [reversalReason] NVARCHAR(255),
    [postedById] NVARCHAR(50),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [BankBook_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [BankBook_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

-- ---- table 14/69: BankBookLine ----------------------------
IF OBJECT_ID(N'dbo.BankBookLine', N'U') IS NULL
CREATE TABLE [dbo].[BankBookLine] (
    [id] NVARCHAR(50) NOT NULL,
    [voucherId] NVARCHAR(50) NOT NULL,
    [accountId] NVARCHAR(50) NOT NULL,
    [debit] FLOAT(53) NOT NULL CONSTRAINT [BankBookLine_debit_df] DEFAULT 0,
    [credit] FLOAT(53) NOT NULL CONSTRAINT [BankBookLine_credit_df] DEFAULT 0,
    [amount] FLOAT(53) NOT NULL CONSTRAINT [BankBookLine_amount_df] DEFAULT 0,
    [taxPercent] FLOAT(53) NOT NULL CONSTRAINT [BankBookLine_taxPercent_df] DEFAULT 0,
    [taxAmount] FLOAT(53) NOT NULL CONSTRAINT [BankBookLine_taxAmount_df] DEFAULT 0,
    [total] FLOAT(53) NOT NULL CONSTRAINT [BankBookLine_total_df] DEFAULT 0,
    [lineDescription] NVARCHAR(255),
    [title] NVARCHAR(255),
    [reference] NVARCHAR(255),
    [billType] NVARCHAR(255),
    [chequeNo] NVARCHAR(255),
    [chequeAmount] FLOAT(53),
    [chequeBankName] NVARCHAR(255),
    [chequeStatus] NVARCHAR(255),
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [BankBookLine_status_df] DEFAULT 'Active',
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [BankBookLine_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [BankBookLine_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

-- ---- table 15/69: JV --------------------------------------
IF OBJECT_ID(N'dbo.JV', N'U') IS NULL
CREATE TABLE [dbo].[JV] (
    [id] NVARCHAR(50) NOT NULL,
    [voucherType] NVARCHAR(10) NOT NULL CONSTRAINT [JV_voucherType_df] DEFAULT 'JV',
    [voucherDate] DATETIME2 NOT NULL,
    [branchId] NVARCHAR(50) NOT NULL,
    [description] NVARCHAR(MAX),
    [reference] NVARCHAR(255),
    [totalDebit] FLOAT(53) NOT NULL CONSTRAINT [JV_totalDebit_df] DEFAULT 0,
    [totalCredit] FLOAT(53) NOT NULL CONSTRAINT [JV_totalCredit_df] DEFAULT 0,
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [JV_status_df] DEFAULT 'Posted',
    -- SOFT delete (deleted vouchers stay for the audit trail; excluded from
    -- lists/reports/ledgers by the app)
    [isDeleted] BIT NOT NULL CONSTRAINT [JV_isDeleted_df] DEFAULT 0,
    [deletedById] NVARCHAR(50),
    [deletedAt] DATETIME2,
    [reversedById] NVARCHAR(50),
    [reversedAt] DATETIME2,
    [reversalReason] NVARCHAR(255),
    [postedById] NVARCHAR(50),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [JV_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [JV_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

-- ---- table 16/69: JVLine ----------------------------------
IF OBJECT_ID(N'dbo.JVLine', N'U') IS NULL
CREATE TABLE [dbo].[JVLine] (
    [id] NVARCHAR(50) NOT NULL,
    [voucherId] NVARCHAR(50) NOT NULL,
    [accountId] NVARCHAR(50) NOT NULL,
    [debit] FLOAT(53) NOT NULL CONSTRAINT [JVLine_debit_df] DEFAULT 0,
    [credit] FLOAT(53) NOT NULL CONSTRAINT [JVLine_credit_df] DEFAULT 0,
    [amount] FLOAT(53) NOT NULL CONSTRAINT [JVLine_amount_df] DEFAULT 0,
    [taxPercent] FLOAT(53) NOT NULL CONSTRAINT [JVLine_taxPercent_df] DEFAULT 0,
    [taxAmount] FLOAT(53) NOT NULL CONSTRAINT [JVLine_taxAmount_df] DEFAULT 0,
    [total] FLOAT(53) NOT NULL CONSTRAINT [JVLine_total_df] DEFAULT 0,
    [lineDescription] NVARCHAR(255),
    [reference] NVARCHAR(255),
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [JVLine_status_df] DEFAULT 'Active',
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [JVLine_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [JVLine_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

-- ---- table 17/69: OpenTB ----------------------------------
IF OBJECT_ID(N'dbo.OpenTB', N'U') IS NULL
CREATE TABLE [dbo].[OpenTB] (
    [id] NVARCHAR(50) NOT NULL,
    [voucherType] NVARCHAR(10) NOT NULL CONSTRAINT [OpenTB_voucherType_df] DEFAULT 'OTV',
    [voucherDate] DATETIME2 NOT NULL,
    [branchId] NVARCHAR(50) NOT NULL,
    [description] NVARCHAR(255),
    [reference] NVARCHAR(255),
    [totalDebit] FLOAT(53) NOT NULL CONSTRAINT [OpenTB_totalDebit_df] DEFAULT 0,
    [totalCredit] FLOAT(53) NOT NULL CONSTRAINT [OpenTB_totalCredit_df] DEFAULT 0,
    [difference] FLOAT(53) NOT NULL CONSTRAINT [OpenTB_difference_df] DEFAULT 0,
    [isBalanced] BIT NOT NULL CONSTRAINT [OpenTB_isBalanced_df] DEFAULT 0,
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [OpenTB_status_df] DEFAULT 'Posted',
    -- SOFT delete (deleted vouchers stay for the audit trail; excluded from
    -- lists/reports/ledgers by the app)
    [isDeleted] BIT NOT NULL CONSTRAINT [OpenTB_isDeleted_df] DEFAULT 0,
    [deletedById] NVARCHAR(50),
    [deletedAt] DATETIME2,
    [reversedById] NVARCHAR(50),
    [reversedAt] DATETIME2,
    [reversalReason] NVARCHAR(255),
    [postedById] NVARCHAR(50),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [OpenTB_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [OpenTB_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

-- ---- table 18/69: OpenTBLine ------------------------------
IF OBJECT_ID(N'dbo.OpenTBLine', N'U') IS NULL
CREATE TABLE [dbo].[OpenTBLine] (
    [id] NVARCHAR(50) NOT NULL,
    [voucherId] NVARCHAR(50) NOT NULL,
    [accountId] NVARCHAR(50) NOT NULL,
    [debit] FLOAT(53) NOT NULL CONSTRAINT [OpenTBLine_debit_df] DEFAULT 0,
    [credit] FLOAT(53) NOT NULL CONSTRAINT [OpenTBLine_credit_df] DEFAULT 0,
    [amount] FLOAT(53) NOT NULL CONSTRAINT [OpenTBLine_amount_df] DEFAULT 0,
    [lineDescription] NVARCHAR(255),
    [reference] NVARCHAR(255),
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [OpenTBLine_status_df] DEFAULT 'Active',
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [OpenTBLine_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [OpenTBLine_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

-- ---- table 19/69: KnockOff --------------------------------
IF OBJECT_ID(N'dbo.KnockOff', N'U') IS NULL
CREATE TABLE [dbo].[KnockOff] (
    [id] NVARCHAR(50) NOT NULL,
    [billId] NVARCHAR(50) NOT NULL,
    [billNumber] NVARCHAR(255),
    [referenceNumber] NVARCHAR(255),
    [billType] NVARCHAR(255),
    [amount] FLOAT(53) NOT NULL,
    [dcFlag] NVARCHAR(10) NOT NULL CONSTRAINT [KnockOff_dcFlag_df] DEFAULT 'Debit',
    [referenceDate] DATETIME2,
    [dueDate] DATETIME2,
    [description] NVARCHAR(20),
    [accountId] NVARCHAR(50) NOT NULL,
    [branchId] NVARCHAR(50) NOT NULL,
    [createdById] NVARCHAR(50),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [KnockOff_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [KnockOff_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [KnockOff_billId_key] UNIQUE NONCLUSTERED ([billId])
);
GO

-- ---- table 20/69: IdSequence ------------------------------
IF OBJECT_ID(N'dbo.IdSequence', N'U') IS NULL
CREATE TABLE [dbo].[IdSequence] (
    [key] NVARCHAR(191) NOT NULL,
    [next] INT NOT NULL CONSTRAINT [IdSequence_next_df] DEFAULT 1,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [IdSequence_pkey] PRIMARY KEY CLUSTERED ([key])
);
GO

-- ---- table 21/69: Defaults --------------------------------
IF OBJECT_ID(N'dbo.Defaults', N'U') IS NULL
CREATE TABLE [dbo].[Defaults] (
    [id] NVARCHAR(50) NOT NULL,
    [companyName] NVARCHAR(255),
    [address] NVARCHAR(MAX),
    [phone] NVARCHAR(255),
    [email] NVARCHAR(255),
    [website] NVARCHAR(255),
    [logo] NVARCHAR(255),
    [strn] NVARCHAR(255),
    [ntn] NVARCHAR(255),
    [fbr] NVARCHAR(255),
    [financeType] NVARCHAR(255) NOT NULL CONSTRAINT [Defaults_financeType_df] DEFAULT 'FIFO',
    [coaLevelDigits] NVARCHAR(100) NOT NULL CONSTRAINT [Defaults_coaLevelDigits_df] DEFAULT '2',
    [coaLocked] BIT NOT NULL CONSTRAINT [Defaults_coaLocked_df] DEFAULT 0,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Defaults_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [Defaults_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

-- ---- table 22/69: FinancialYear ---------------------------
IF OBJECT_ID(N'dbo.FinancialYear', N'U') IS NULL
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
GO

-- ---- table 23/69: AccountingPeriod ------------------------
IF OBJECT_ID(N'dbo.AccountingPeriod', N'U') IS NULL
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
GO

-- ---- table 24/69: TaxHead ---------------------------------
IF OBJECT_ID(N'dbo.TaxHead', N'U') IS NULL
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
GO

-- ---- table 25/69: AccountMapping --------------------------
IF OBJECT_ID(N'dbo.AccountMapping', N'U') IS NULL
CREATE TABLE [dbo].[AccountMapping] (
    [id] NVARCHAR(50) NOT NULL,
    [branchId] NVARCHAR(50),
    [key] NVARCHAR(255) NOT NULL,
    [accountId] NVARCHAR(50) NOT NULL,
    [description] NVARCHAR(MAX),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [AccountMapping_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [AccountMapping_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [AccountMapping_branchId_key_key] UNIQUE NONCLUSTERED ([branchId],[key])
);
GO

-- ---- table 26/69: FinanceDefaults -------------------------
IF OBJECT_ID(N'dbo.FinanceDefaults', N'U') IS NULL
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
GO

-- ---- table 27/69: UserReportFormat ------------------------
IF OBJECT_ID(N'dbo.UserReportFormat', N'U') IS NULL
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
GO

-- ---- table 28/69: Member ----------------------------------
IF OBJECT_ID(N'dbo.Member', N'U') IS NULL
CREATE TABLE [dbo].[Member] (
    [id] NVARCHAR(50) NOT NULL,
    [joiningFee] FLOAT NOT NULL CONSTRAINT [Member_joiningFee_df] DEFAULT 0,
    [firstName] NVARCHAR(255) NOT NULL,
    [lastName] NVARCHAR(255),
    [gender] NVARCHAR(255),
    [dob] DATETIME2,
    [phone] NVARCHAR(255),
    [whatsapp] NVARCHAR(255),
    [email] NVARCHAR(255),
    [address] NVARCHAR(MAX),
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
    [notes] NVARCHAR(MAX),
    [isActive] BIT NOT NULL CONSTRAINT [Member_isActive_df] DEFAULT 1,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Member_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    [isDeleted] BIT NOT NULL CONSTRAINT [Member_isDeleted_df] DEFAULT 0,
    [deletedAt] DATETIME2,
    CONSTRAINT [Member_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

-- ---- table 29/69: MembershipPlan --------------------------
IF OBJECT_ID(N'dbo.MembershipPlan', N'U') IS NULL
CREATE TABLE [dbo].[MembershipPlan] (
    [id] NVARCHAR(50) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [durationDays] INT NOT NULL,
    [amount] FLOAT(53) NOT NULL,
    [description] NVARCHAR(MAX),
    [branchId] NVARCHAR(50) NOT NULL,
    [isActive] BIT NOT NULL CONSTRAINT [MembershipPlan_isActive_df] DEFAULT 1,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [MembershipPlan_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [MembershipPlan_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

-- ---- table 30/69: Attendance ------------------------------
IF OBJECT_ID(N'dbo.Attendance', N'U') IS NULL
CREATE TABLE [dbo].[Attendance] (
    [id] NVARCHAR(50) NOT NULL,
    [memberId] NVARCHAR(50) NOT NULL,
    [branchId] NVARCHAR(50) NOT NULL,
    [date] DATETIME2 NOT NULL,
    [checkIn] DATETIME2,
    [checkOut] DATETIME2,
    [notes] NVARCHAR(MAX),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Attendance_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [Attendance_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [Attendance_memberId_date_key] UNIQUE NONCLUSTERED ([memberId],[date])
);
GO

-- ---- table 31/69: Fee -------------------------------------
IF OBJECT_ID(N'dbo.Fee', N'U') IS NULL
CREATE TABLE [dbo].[Fee] (
    [id] NVARCHAR(50) NOT NULL,
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
    [bookVoucherId] NVARCHAR(50),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Fee_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [Fee_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

-- ---- table 32/69: FeePayment ------------------------------
IF OBJECT_ID(N'dbo.FeePayment', N'U') IS NULL
CREATE TABLE [dbo].[FeePayment] (
    [id] NVARCHAR(50) NOT NULL,
    [feeId] NVARCHAR(50) NOT NULL,
    [bookVoucherId] NVARCHAR(50) NOT NULL,
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
GO

-- ---- table 33/69: Prospect --------------------------------
IF OBJECT_ID(N'dbo.Prospect', N'U') IS NULL
CREATE TABLE [dbo].[Prospect] (
    [id] NVARCHAR(50) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [phone] NVARCHAR(255),
    [whatsapp] NVARCHAR(255),
    [gender] NVARCHAR(255),
    [age] INT,
    [dob] DATETIME2,
    [interestedMembership] NVARCHAR(255),
    [branchId] NVARCHAR(50),
    [source] NVARCHAR(255) NOT NULL,
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [Prospect_status_df] DEFAULT 'New',
    [inquiryDate] DATETIME2 NOT NULL CONSTRAINT [Prospect_inquiryDate_df] DEFAULT CURRENT_TIMESTAMP,
    [followUpDate] DATETIME2,
    [assignedTo] NVARCHAR(255),
    [notes] NVARCHAR(MAX),
    [convertedMemberId] NVARCHAR(50),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Prospect_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [Prospect_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

-- ---- table 34/69: MembershipFreeze ------------------------
IF OBJECT_ID(N'dbo.MembershipFreeze', N'U') IS NULL
CREATE TABLE [dbo].[MembershipFreeze] (
    [id] NVARCHAR(50) NOT NULL,
    [memberId] NVARCHAR(50) NOT NULL,
    [branchId] NVARCHAR(50) NOT NULL,
    [freezeFrom] DATETIME2 NOT NULL,
    [freezeTo] DATETIME2 NOT NULL,
    [days] INT NOT NULL,
    [reason] NVARCHAR(MAX),
    [approvedBy] NVARCHAR(255),
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [MembershipFreeze_status_df] DEFAULT 'Active',
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [MembershipFreeze_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [MembershipFreeze_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

-- ---- table 35/69: FollowUp --------------------------------
IF OBJECT_ID(N'dbo.FollowUp', N'U') IS NULL
CREATE TABLE [dbo].[FollowUp] (
    [id] NVARCHAR(50) NOT NULL,
    [memberId] NVARCHAR(50),
    [prospectId] NVARCHAR(50),
    [branchId] NVARCHAR(50),
    [date] DATETIME2 NOT NULL CONSTRAINT [FollowUp_date_df] DEFAULT CURRENT_TIMESTAMP,
    [type] NVARCHAR(255) NOT NULL,
    [userId] NVARCHAR(50),
    [notes] NVARCHAR(MAX),
    [outcome] NVARCHAR(255),
    [nextFollowUpDate] DATETIME2,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [FollowUp_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [FollowUp_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

-- ---- table 36/69: ProgressEntry ---------------------------
IF OBJECT_ID(N'dbo.ProgressEntry', N'U') IS NULL
CREATE TABLE [dbo].[ProgressEntry] (
    [id] NVARCHAR(50) NOT NULL,
    [memberId] NVARCHAR(50) NOT NULL,
    [branchId] NVARCHAR(50) NOT NULL,
    [date] DATETIME2 NOT NULL CONSTRAINT [ProgressEntry_date_df] DEFAULT CURRENT_TIMESTAMP,
    [weight] FLOAT(53),
    [chest] FLOAT(53),
    [waist] FLOAT(53),
    [hips] FLOAT(53),
    [biceps] FLOAT(53),
    [thighs] FLOAT(53),
    [notes] NVARCHAR(MAX),
    [photo] NVARCHAR(255),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [ProgressEntry_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [ProgressEntry_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

-- ---- table 37/69: gymmasterfile ---------------------------
IF OBJECT_ID(N'dbo.gymmasterfile', N'U') IS NULL
CREATE TABLE [dbo].[gymmasterfile] (
    [id] NVARCHAR(50) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [level] INT NOT NULL,
    [parentCode] NVARCHAR(50),
    [branchId] NVARCHAR(50),
    [description] NVARCHAR(MAX),
    [isActive] BIT NOT NULL CONSTRAINT [gymmasterfile_isActive_df] DEFAULT 1,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [gymmasterfile_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [gymmasterfile_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

-- ---- tables 38-43/74: gymmaster / gymmasterdetail / financemaster /
-- ---- financemasterdetail / payrollmaster / payrollmasterdetail
-- ---- (three IDENTICAL master/detail pairs; master.id = 3-digit category
-- ---- code, detail.id = master code + 3-digit sequence) ---------------
IF OBJECT_ID(N'dbo.gymmaster', N'U') IS NULL
CREATE TABLE [dbo].[gymmaster] (
    [id] NVARCHAR(50) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [description] NVARCHAR(MAX),
    [branchId] NVARCHAR(50),
    [isActive] BIT NOT NULL CONSTRAINT [gymmaster_isActive_df] DEFAULT 1,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [gymmaster_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [gymmaster_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

IF OBJECT_ID(N'dbo.gymmasterdetail', N'U') IS NULL
CREATE TABLE [dbo].[gymmasterdetail] (
    [id] NVARCHAR(50) NOT NULL,
    [masterId] NVARCHAR(50) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [description] NVARCHAR(MAX),
    [branchId] NVARCHAR(50),
    [isActive] BIT NOT NULL CONSTRAINT [gymmasterdetail_isActive_df] DEFAULT 1,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [gymmasterdetail_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [gymmasterdetail_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

IF OBJECT_ID(N'dbo.financemaster', N'U') IS NULL
CREATE TABLE [dbo].[financemaster] (
    [id] NVARCHAR(50) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [description] NVARCHAR(MAX),
    [branchId] NVARCHAR(50),
    [isActive] BIT NOT NULL CONSTRAINT [financemaster_isActive_df] DEFAULT 1,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [financemaster_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [financemaster_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

IF OBJECT_ID(N'dbo.financemasterdetail', N'U') IS NULL
CREATE TABLE [dbo].[financemasterdetail] (
    [id] NVARCHAR(50) NOT NULL,
    [masterId] NVARCHAR(50) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [description] NVARCHAR(MAX),
    [branchId] NVARCHAR(50),
    [isActive] BIT NOT NULL CONSTRAINT [financemasterdetail_isActive_df] DEFAULT 1,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [financemasterdetail_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [financemasterdetail_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

IF OBJECT_ID(N'dbo.payrollmaster', N'U') IS NULL
CREATE TABLE [dbo].[payrollmaster] (
    [id] NVARCHAR(50) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [description] NVARCHAR(MAX),
    [branchId] NVARCHAR(50),
    [isActive] BIT NOT NULL CONSTRAINT [payrollmaster_isActive_df] DEFAULT 1,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [payrollmaster_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [payrollmaster_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

IF OBJECT_ID(N'dbo.payrollmasterdetail', N'U') IS NULL
CREATE TABLE [dbo].[payrollmasterdetail] (
    [id] NVARCHAR(50) NOT NULL,
    [masterId] NVARCHAR(50) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [description] NVARCHAR(MAX),
    [branchId] NVARCHAR(50),
    [isActive] BIT NOT NULL CONSTRAINT [payrollmasterdetail_isActive_df] DEFAULT 1,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [payrollmasterdetail_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [payrollmasterdetail_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

-- ---- table 39/69: WorkoutPlan -----------------------------
IF OBJECT_ID(N'dbo.WorkoutPlan', N'U') IS NULL
CREATE TABLE [dbo].[WorkoutPlan] (
    [id] NVARCHAR(50) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [description] NVARCHAR(MAX),
    [isGeneral] BIT NOT NULL CONSTRAINT [WorkoutPlan_isGeneral_df] DEFAULT 1,
    [branchId] NVARCHAR(50),
    [isActive] BIT NOT NULL CONSTRAINT [WorkoutPlan_isActive_df] DEFAULT 1,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [WorkoutPlan_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [WorkoutPlan_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

-- ---- table 40/69: WorkoutDay ------------------------------
IF OBJECT_ID(N'dbo.WorkoutDay', N'U') IS NULL
CREATE TABLE [dbo].[WorkoutDay] (
    [id] NVARCHAR(50) NOT NULL,
    [planId] NVARCHAR(50) NOT NULL,
    [dayName] NVARCHAR(255) NOT NULL,
    [notes] NVARCHAR(MAX),
    CONSTRAINT [WorkoutDay_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

-- ---- table 41/69: WorkoutDayExercise ----------------------
IF OBJECT_ID(N'dbo.WorkoutDayExercise', N'U') IS NULL
CREATE TABLE [dbo].[WorkoutDayExercise] (
    [id] NVARCHAR(50) NOT NULL,
    [dayId] NVARCHAR(50) NOT NULL,
    [exerciseId] NVARCHAR(50) NOT NULL,
    [sets] INT,
    [reps] NVARCHAR(255),
    [duration] NVARCHAR(255),
    [rest] NVARCHAR(255),
    [notes] NVARCHAR(MAX),
    CONSTRAINT [WorkoutDayExercise_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

-- ---- table 42/69: WorkoutAssignment -----------------------
IF OBJECT_ID(N'dbo.WorkoutAssignment', N'U') IS NULL
CREATE TABLE [dbo].[WorkoutAssignment] (
    [id] NVARCHAR(50) NOT NULL,
    [memberId] NVARCHAR(50) NOT NULL,
    [planId] NVARCHAR(50),
    [trainerId] NVARCHAR(50),
    [startDate] DATETIME2 NOT NULL CONSTRAINT [WorkoutAssignment_startDate_df] DEFAULT CURRENT_TIMESTAMP,
    [endDate] DATETIME2,
    [notes] NVARCHAR(MAX),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [WorkoutAssignment_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [WorkoutAssignment_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

-- ---- table 43/69: DietPlan --------------------------------
IF OBJECT_ID(N'dbo.DietPlan', N'U') IS NULL
CREATE TABLE [dbo].[DietPlan] (
    [id] NVARCHAR(50) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [description] NVARCHAR(MAX),
    [branchId] NVARCHAR(50),
    [isActive] BIT NOT NULL CONSTRAINT [DietPlan_isActive_df] DEFAULT 1,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [DietPlan_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [DietPlan_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

-- ---- table 44/69: DietMeal --------------------------------
IF OBJECT_ID(N'dbo.DietMeal', N'U') IS NULL
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
    [notes] NVARCHAR(MAX),
    CONSTRAINT [DietMeal_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

-- ---- table 45/69: DietAssignment --------------------------
IF OBJECT_ID(N'dbo.DietAssignment', N'U') IS NULL
CREATE TABLE [dbo].[DietAssignment] (
    [id] NVARCHAR(50) NOT NULL,
    [memberId] NVARCHAR(50) NOT NULL,
    [planId] NVARCHAR(50) NOT NULL,
    [startDate] DATETIME2 NOT NULL CONSTRAINT [DietAssignment_startDate_df] DEFAULT CURRENT_TIMESTAMP,
    [endDate] DATETIME2,
    [notes] NVARCHAR(MAX),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [DietAssignment_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [DietAssignment_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

-- ---- table 46/69: Equipment -------------------------------
IF OBJECT_ID(N'dbo.Equipment', N'U') IS NULL
CREATE TABLE [dbo].[Equipment] (
    [id] NVARCHAR(50) NOT NULL,
    [code] NVARCHAR(255) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [category] NVARCHAR(255) NOT NULL,
    [description] NVARCHAR(MAX),
    [purchaseDate] DATETIME2,
    [purchasePrice] FLOAT(53),
    [quantity] INT NOT NULL CONSTRAINT [Equipment_quantity_df] DEFAULT 1,
    [condition] NVARCHAR(MAX) NOT NULL CONSTRAINT [Equipment_condition_df] DEFAULT 'Working',
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [Equipment_status_df] DEFAULT 'Active',
    [branchId] NVARCHAR(50) NOT NULL,
    [billReference] NVARCHAR(255),
    [billImage] NVARCHAR(255),
    [image] NVARCHAR(255),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Equipment_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [Equipment_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

-- ---- table 47/69: EquipmentMaintenance --------------------
IF OBJECT_ID(N'dbo.EquipmentMaintenance', N'U') IS NULL
CREATE TABLE [dbo].[EquipmentMaintenance] (
    [id] NVARCHAR(50) NOT NULL,
    [equipmentId] NVARCHAR(50) NOT NULL,
    [date] DATETIME2 NOT NULL CONSTRAINT [EquipmentMaintenance_date_df] DEFAULT CURRENT_TIMESTAMP,
    [type] NVARCHAR(255) NOT NULL,
    [description] NVARCHAR(MAX),
    [cost] FLOAT(53) NOT NULL CONSTRAINT [EquipmentMaintenance_cost_df] DEFAULT 0,
    [vendor] NVARCHAR(255),
    [notes] NVARCHAR(MAX),
    [attachment] NVARCHAR(255),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [EquipmentMaintenance_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [EquipmentMaintenance_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

-- ---- table 48/69: InventoryItem ---------------------------
IF OBJECT_ID(N'dbo.InventoryItem', N'U') IS NULL
CREATE TABLE [dbo].[InventoryItem] (
    [id] NVARCHAR(50) NOT NULL,
    [code] NVARCHAR(255) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [category] NVARCHAR(255),
    [description] NVARCHAR(MAX),
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
GO

-- ---- table 49/69: PosSale ---------------------------------
IF OBJECT_ID(N'dbo.PosSale', N'U') IS NULL
CREATE TABLE [dbo].[PosSale] (
    [id] NVARCHAR(50) NOT NULL,
    [saleNo] NVARCHAR(191) NOT NULL,
    [date] DATETIME2 NOT NULL CONSTRAINT [PosSale_date_df] DEFAULT CURRENT_TIMESTAMP,
    [branchId] NVARCHAR(50) NOT NULL,
    [cashierId] NVARCHAR(50),
    [total] FLOAT(53) NOT NULL,
    [paymentMethod] NVARCHAR(255) NOT NULL,
    [paymentAccountId] NVARCHAR(50),
    [bookVoucherId] NVARCHAR(50),
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [PosSale_status_df] DEFAULT 'Completed',
    [notes] NVARCHAR(MAX),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [PosSale_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [PosSale_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [PosSale_saleNo_key] UNIQUE NONCLUSTERED ([saleNo])
);
GO

-- ---- table 50/69: PosSaleLine -----------------------------
IF OBJECT_ID(N'dbo.PosSaleLine', N'U') IS NULL
CREATE TABLE [dbo].[PosSaleLine] (
    [id] NVARCHAR(50) NOT NULL,
    [saleId] NVARCHAR(50) NOT NULL,
    [inventoryItemId] NVARCHAR(50) NOT NULL,
    [quantity] INT NOT NULL,
    [unitPrice] FLOAT(53) NOT NULL,
    [amount] FLOAT(53) NOT NULL,
    CONSTRAINT [PosSaleLine_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

-- ---- table 51/69: Staff -----------------------------------
IF OBJECT_ID(N'dbo.Staff', N'U') IS NULL
CREATE TABLE [dbo].[Staff] (
    -- id IS the employee id (EMP-00001) - merged column per 09 upgrade
    [id] NVARCHAR(50) NOT NULL,
    [firstName] NVARCHAR(255) NOT NULL,
    [lastName] NVARCHAR(255),
    [fatherGuardian] NVARCHAR(255),
    [cnic] NVARCHAR(255),
    [photo] NVARCHAR(255),
    [address] NVARCHAR(MAX),
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
    CONSTRAINT [Staff_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

-- ---- table 52/69: Shift -----------------------------------
IF OBJECT_ID(N'dbo.Shift', N'U') IS NULL
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
GO

-- ---- table 53/69: CalendarDay -----------------------------
IF OBJECT_ID(N'dbo.CalendarDay', N'U') IS NULL
CREATE TABLE [dbo].[CalendarDay] (
    [id] NVARCHAR(50) NOT NULL,
    [date] DATETIME2 NOT NULL,
    [branchId] NVARCHAR(50),
    [dayType] NVARCHAR(255) NOT NULL,
    [notes] NVARCHAR(MAX),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [CalendarDay_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [CalendarDay_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [CalendarDay_date_key] UNIQUE NONCLUSTERED ([date])
);
GO

-- ---- table 54/69: Leave -----------------------------------
IF OBJECT_ID(N'dbo.Leave', N'U') IS NULL
CREATE TABLE [dbo].[Leave] (
    [id] NVARCHAR(50) NOT NULL,
    [staffId] NVARCHAR(50) NOT NULL,
    [branchId] NVARCHAR(50) NOT NULL,
    [leaveType] NVARCHAR(255) NOT NULL,
    [fromDate] DATETIME2 NOT NULL,
    [toDate] DATETIME2 NOT NULL,
    [days] INT NOT NULL,
    [reason] NVARCHAR(MAX),
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [Leave_status_df] DEFAULT 'Pending',
    [approvedBy] NVARCHAR(255),
    [approvedAt] DATETIME2,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Leave_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [Leave_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

-- ---- table 55/69: Overtime --------------------------------
IF OBJECT_ID(N'dbo.Overtime', N'U') IS NULL
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
    [notes] NVARCHAR(MAX),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Overtime_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [Overtime_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

-- ---- table 56/69: Payroll ---------------------------------
IF OBJECT_ID(N'dbo.Payroll', N'U') IS NULL
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
    [bookVoucherId] NVARCHAR(50),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Payroll_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [Payroll_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [Payroll_payrollNo_key] UNIQUE NONCLUSTERED ([payrollNo]),
    CONSTRAINT [Payroll_staffId_month_year_key] UNIQUE NONCLUSTERED ([staffId],[month],[year])
);
GO

-- ---- table 57/69: Allowance -------------------------------
IF OBJECT_ID(N'dbo.Allowance', N'U') IS NULL
CREATE TABLE [dbo].[Allowance] (
    [id] NVARCHAR(50) NOT NULL,
    [name] NVARCHAR(191) NOT NULL,
    [description] NVARCHAR(MAX),
    [isStatutory] BIT NOT NULL CONSTRAINT [Allowance_isStatutory_df] DEFAULT 0,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Allowance_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [Allowance_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [Allowance_name_key] UNIQUE NONCLUSTERED ([name])
);
GO

-- ---- table 58/69: payrollmasterfile -----------------------
IF OBJECT_ID(N'dbo.payrollmasterfile', N'U') IS NULL
CREATE TABLE [dbo].[payrollmasterfile] (
    [id] NVARCHAR(50) NOT NULL,
    [masterType] NVARCHAR(255) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [description] NVARCHAR(MAX),
    [extra] NVARCHAR(255),
    [branchId] NVARCHAR(50),
    [isActive] BIT NOT NULL CONSTRAINT [payrollmasterfile_isActive_df] DEFAULT 1,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [payrollmasterfile_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [payrollmasterfile_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [payrollmasterfile_masterType_name_key] UNIQUE NONCLUSTERED ([masterType],[name])
);
GO

-- ---- table 59/69: MasterFile ------------------------------
IF OBJECT_ID(N'dbo.MasterFile', N'U') IS NULL
CREATE TABLE [dbo].[MasterFile] (
    [id] NVARCHAR(50) NOT NULL,
    [masterType] NVARCHAR(255) NOT NULL,
    [code] NVARCHAR(255) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [branchId] NVARCHAR(50),
    [description] NVARCHAR(MAX),
    [isActive] BIT NOT NULL CONSTRAINT [MasterFile_isActive_df] DEFAULT 1,
    [extra] NVARCHAR(255),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [MasterFile_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [MasterFile_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [MasterFile_masterType_code_key] UNIQUE NONCLUSTERED ([masterType],[code]),
    CONSTRAINT [MasterFile_masterType_name_key] UNIQUE NONCLUSTERED ([masterType],[name])
);
GO

-- ---- table 60/69: FitnessGoal -----------------------------
IF OBJECT_ID(N'dbo.FitnessGoal', N'U') IS NULL
CREATE TABLE [dbo].[FitnessGoal] (
    [id] NVARCHAR(50) NOT NULL,
    [memberId] NVARCHAR(50) NOT NULL,
    [goalType] NVARCHAR(255) NOT NULL,
    [targetValue] FLOAT(53),
    [unit] NVARCHAR(255),
    [startDate] DATETIME2 NOT NULL CONSTRAINT [FitnessGoal_startDate_df] DEFAULT CURRENT_TIMESTAMP,
    [targetDate] DATETIME2,
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [FitnessGoal_status_df] DEFAULT 'Active',
    [notes] NVARCHAR(MAX),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [FitnessGoal_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [FitnessGoal_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

-- ---- table 61/69: PersonalTrainingSession -----------------
IF OBJECT_ID(N'dbo.PersonalTrainingSession', N'U') IS NULL
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
    [notes] NVARCHAR(MAX),
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [PersonalTrainingSession_status_df] DEFAULT 'Active',
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [PersonalTrainingSession_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [PersonalTrainingSession_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

-- ---- table 62/69: TrainerAvailability ---------------------
IF OBJECT_ID(N'dbo.TrainerAvailability', N'U') IS NULL
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
GO

-- ---- table 63/69: TrainerSchedule -------------------------
IF OBJECT_ID(N'dbo.TrainerSchedule', N'U') IS NULL
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
    [notes] NVARCHAR(MAX),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [TrainerSchedule_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [TrainerSchedule_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

-- ---- table 64/69: StaffDocument ---------------------------
IF OBJECT_ID(N'dbo.StaffDocument', N'U') IS NULL
CREATE TABLE [dbo].[StaffDocument] (
    [id] NVARCHAR(50) NOT NULL,
    [staffId] NVARCHAR(50) NOT NULL,
    [documentType] NVARCHAR(255) NOT NULL,
    [documentName] NVARCHAR(255) NOT NULL,
    [fileUrl] NVARCHAR(255) NOT NULL,
    [issueDate] DATETIME2,
    [expiryDate] DATETIME2,
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [StaffDocument_status_df] DEFAULT 'Active',
    [notes] NVARCHAR(MAX),
    [uploadedBy] NVARCHAR(255),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [StaffDocument_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [StaffDocument_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

-- ---- table 65/69: FoodItem --------------------------------
IF OBJECT_ID(N'dbo.FoodItem', N'U') IS NULL
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
GO

-- ---- table 66/69: Supplier --------------------------------
IF OBJECT_ID(N'dbo.Supplier', N'U') IS NULL
CREATE TABLE [dbo].[Supplier] (
    [id] NVARCHAR(50) NOT NULL,
    [code] NVARCHAR(255) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [contactPerson] NVARCHAR(255),
    [phone] NVARCHAR(255),
    [email] NVARCHAR(255),
    [address] NVARCHAR(MAX),
    [branchId] NVARCHAR(50),
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [Supplier_status_df] DEFAULT 'Active',
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Supplier_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [Supplier_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO

-- ---- table 67/69: Purchase --------------------------------
IF OBJECT_ID(N'dbo.Purchase', N'U') IS NULL
CREATE TABLE [dbo].[Purchase] (
    [id] NVARCHAR(50) NOT NULL,
    [purchaseNo] NVARCHAR(191) NOT NULL,
    [supplierId] NVARCHAR(50),
    [branchId] NVARCHAR(50) NOT NULL,
    [purchaseDate] DATETIME2 NOT NULL CONSTRAINT [Purchase_purchaseDate_df] DEFAULT CURRENT_TIMESTAMP,
    [totalAmount] FLOAT(53) NOT NULL CONSTRAINT [Purchase_totalAmount_df] DEFAULT 0,
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [Purchase_status_df] DEFAULT 'Pending',
    [notes] NVARCHAR(MAX),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Purchase_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [Purchase_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [Purchase_purchaseNo_key] UNIQUE NONCLUSTERED ([purchaseNo])
);
GO

-- ---- table 68/69: PurchaseLine ----------------------------
IF OBJECT_ID(N'dbo.PurchaseLine', N'U') IS NULL
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
GO

-- ---- table 69/69: StockMovement ---------------------------
IF OBJECT_ID(N'dbo.StockMovement', N'U') IS NULL
CREATE TABLE [dbo].[StockMovement] (
    [id] NVARCHAR(50) NOT NULL,
    [inventoryItemId] NVARCHAR(50) NOT NULL,
    [branchId] NVARCHAR(50) NOT NULL,
    [movementType] NVARCHAR(255) NOT NULL,
    [quantity] INT NOT NULL,
    [reference] NVARCHAR(255),
    [referenceId] NVARCHAR(50),
    [date] DATETIME2 NOT NULL CONSTRAINT [StockMovement_date_df] DEFAULT CURRENT_TIMESTAMP,
    [notes] NVARCHAR(MAX),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [StockMovement_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [StockMovement_pkey] PRIMARY KEY CLUSTERED ([id])
);
GO


-- ===========================================================================
-- SECTION 2 of 3 - NONCLUSTERED INDEXES
-- ===========================================================================

-- indexes on [ScreenPermission]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ScreenPermission_screenKey_idx' AND object_id = OBJECT_ID(N'dbo.ScreenPermission'))
    CREATE NONCLUSTERED INDEX [ScreenPermission_screenKey_idx] ON [dbo].[ScreenPermission]([screenKey]);
GO

-- indexes on [UserPermission]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UserPermission_screenKey_idx' AND object_id = OBJECT_ID(N'dbo.UserPermission'))
    CREATE NONCLUSTERED INDEX [UserPermission_screenKey_idx] ON [dbo].[UserPermission]([screenKey]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'gymmasterdetail_masterId_idx' AND object_id = OBJECT_ID(N'dbo.gymmasterdetail'))
    CREATE NONCLUSTERED INDEX [gymmasterdetail_masterId_idx] ON [dbo].[gymmasterdetail]([masterId]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'financemasterdetail_masterId_idx' AND object_id = OBJECT_ID(N'dbo.financemasterdetail'))
    CREATE NONCLUSTERED INDEX [financemasterdetail_masterId_idx] ON [dbo].[financemasterdetail]([masterId]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'payrollmasterdetail_masterId_idx' AND object_id = OBJECT_ID(N'dbo.payrollmasterdetail'))
    CREATE NONCLUSTERED INDEX [payrollmasterdetail_masterId_idx] ON [dbo].[payrollmasterdetail]([masterId]);
GO

-- indexes on [Session]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'Session_userId_idx' AND object_id = OBJECT_ID(N'dbo.Session'))
    CREATE NONCLUSTERED INDEX [Session_userId_idx] ON [dbo].[Session]([userId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'Session_refreshToken_idx' AND object_id = OBJECT_ID(N'dbo.Session'))
    CREATE NONCLUSTERED INDEX [Session_refreshToken_idx] ON [dbo].[Session]([refreshToken]);
GO

-- indexes on [AuditLog]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'AuditLog_userId_idx' AND object_id = OBJECT_ID(N'dbo.AuditLog'))
    CREATE NONCLUSTERED INDEX [AuditLog_userId_idx] ON [dbo].[AuditLog]([userId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'AuditLog_module_idx' AND object_id = OBJECT_ID(N'dbo.AuditLog'))
    CREATE NONCLUSTERED INDEX [AuditLog_module_idx] ON [dbo].[AuditLog]([module]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'AuditLog_createdAt_idx' AND object_id = OBJECT_ID(N'dbo.AuditLog'))
    CREATE NONCLUSTERED INDEX [AuditLog_createdAt_idx] ON [dbo].[AuditLog]([createdAt]);
GO

-- indexes on [charts]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'charts_parentCode_idx' AND object_id = OBJECT_ID(N'dbo.charts'))
    CREATE NONCLUSTERED INDEX [charts_parentCode_idx] ON [dbo].[charts]([parentCode]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'charts_branchId_idx' AND object_id = OBJECT_ID(N'dbo.charts'))
    CREATE NONCLUSTERED INDEX [charts_branchId_idx] ON [dbo].[charts]([branchId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'charts_accountType_idx' AND object_id = OBJECT_ID(N'dbo.charts'))
    CREATE NONCLUSTERED INDEX [charts_accountType_idx] ON [dbo].[charts]([accountType]);
GO

-- indexes on [CashBook]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'CashBook_voucherType_idx' AND object_id = OBJECT_ID(N'dbo.CashBook'))
    CREATE NONCLUSTERED INDEX [CashBook_voucherType_idx] ON [dbo].[CashBook]([voucherType]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'CashBook_voucherDate_idx' AND object_id = OBJECT_ID(N'dbo.CashBook'))
    CREATE NONCLUSTERED INDEX [CashBook_voucherDate_idx] ON [dbo].[CashBook]([voucherDate]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'CashBook_branchId_idx' AND object_id = OBJECT_ID(N'dbo.CashBook'))
    CREATE NONCLUSTERED INDEX [CashBook_branchId_idx] ON [dbo].[CashBook]([branchId]);
GO

-- indexes on [CashBookLine]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'CashBookLine_voucherId_idx' AND object_id = OBJECT_ID(N'dbo.CashBookLine'))
    CREATE NONCLUSTERED INDEX [CashBookLine_voucherId_idx] ON [dbo].[CashBookLine]([voucherId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'CashBookLine_accountId_idx' AND object_id = OBJECT_ID(N'dbo.CashBookLine'))
    CREATE NONCLUSTERED INDEX [CashBookLine_accountId_idx] ON [dbo].[CashBookLine]([accountId]);
GO

-- indexes on [BankBook]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'BankBook_voucherType_idx' AND object_id = OBJECT_ID(N'dbo.BankBook'))
    CREATE NONCLUSTERED INDEX [BankBook_voucherType_idx] ON [dbo].[BankBook]([voucherType]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'BankBook_voucherDate_idx' AND object_id = OBJECT_ID(N'dbo.BankBook'))
    CREATE NONCLUSTERED INDEX [BankBook_voucherDate_idx] ON [dbo].[BankBook]([voucherDate]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'BankBook_branchId_idx' AND object_id = OBJECT_ID(N'dbo.BankBook'))
    CREATE NONCLUSTERED INDEX [BankBook_branchId_idx] ON [dbo].[BankBook]([branchId]);
GO

-- indexes on [BankBookLine]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'BankBookLine_voucherId_idx' AND object_id = OBJECT_ID(N'dbo.BankBookLine'))
    CREATE NONCLUSTERED INDEX [BankBookLine_voucherId_idx] ON [dbo].[BankBookLine]([voucherId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'BankBookLine_accountId_idx' AND object_id = OBJECT_ID(N'dbo.BankBookLine'))
    CREATE NONCLUSTERED INDEX [BankBookLine_accountId_idx] ON [dbo].[BankBookLine]([accountId]);
GO

-- indexes on [JV]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'JV_voucherDate_idx' AND object_id = OBJECT_ID(N'dbo.JV'))
    CREATE NONCLUSTERED INDEX [JV_voucherDate_idx] ON [dbo].[JV]([voucherDate]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'JV_branchId_idx' AND object_id = OBJECT_ID(N'dbo.JV'))
    CREATE NONCLUSTERED INDEX [JV_branchId_idx] ON [dbo].[JV]([branchId]);
GO

-- indexes on [JVLine]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'JVLine_voucherId_idx' AND object_id = OBJECT_ID(N'dbo.JVLine'))
    CREATE NONCLUSTERED INDEX [JVLine_voucherId_idx] ON [dbo].[JVLine]([voucherId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'JVLine_accountId_idx' AND object_id = OBJECT_ID(N'dbo.JVLine'))
    CREATE NONCLUSTERED INDEX [JVLine_accountId_idx] ON [dbo].[JVLine]([accountId]);
GO

-- indexes on [OpenTB]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'OpenTB_voucherDate_idx' AND object_id = OBJECT_ID(N'dbo.OpenTB'))
    CREATE NONCLUSTERED INDEX [OpenTB_voucherDate_idx] ON [dbo].[OpenTB]([voucherDate]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'OpenTB_branchId_idx' AND object_id = OBJECT_ID(N'dbo.OpenTB'))
    CREATE NONCLUSTERED INDEX [OpenTB_branchId_idx] ON [dbo].[OpenTB]([branchId]);
GO

-- indexes on [OpenTBLine]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'OpenTBLine_voucherId_idx' AND object_id = OBJECT_ID(N'dbo.OpenTBLine'))
    CREATE NONCLUSTERED INDEX [OpenTBLine_voucherId_idx] ON [dbo].[OpenTBLine]([voucherId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'OpenTBLine_accountId_idx' AND object_id = OBJECT_ID(N'dbo.OpenTBLine'))
    CREATE NONCLUSTERED INDEX [OpenTBLine_accountId_idx] ON [dbo].[OpenTBLine]([accountId]);
GO

-- indexes on [KnockOff]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'KnockOff_accountId_idx' AND object_id = OBJECT_ID(N'dbo.KnockOff'))
    CREATE NONCLUSTERED INDEX [KnockOff_accountId_idx] ON [dbo].[KnockOff]([accountId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'KnockOff_branchId_idx' AND object_id = OBJECT_ID(N'dbo.KnockOff'))
    CREATE NONCLUSTERED INDEX [KnockOff_branchId_idx] ON [dbo].[KnockOff]([branchId]);
GO

-- indexes on [AccountingPeriod]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'AccountingPeriod_financialYearId_idx' AND object_id = OBJECT_ID(N'dbo.AccountingPeriod'))
    CREATE NONCLUSTERED INDEX [AccountingPeriod_financialYearId_idx] ON [dbo].[AccountingPeriod]([financialYearId]);
GO

-- indexes on [TaxHead]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'TaxHead_code_idx' AND object_id = OBJECT_ID(N'dbo.TaxHead'))
    CREATE NONCLUSTERED INDEX [TaxHead_code_idx] ON [dbo].[TaxHead]([code]);
GO

-- indexes on [AccountMapping]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'AccountMapping_key_idx' AND object_id = OBJECT_ID(N'dbo.AccountMapping'))
    CREATE NONCLUSTERED INDEX [AccountMapping_key_idx] ON [dbo].[AccountMapping]([key]);
GO

-- indexes on [UserReportFormat]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UserReportFormat_userId_reportKey_idx' AND object_id = OBJECT_ID(N'dbo.UserReportFormat'))
    CREATE NONCLUSTERED INDEX [UserReportFormat_userId_reportKey_idx] ON [dbo].[UserReportFormat]([userId], [reportKey]);
GO

-- indexes on [Member]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'Member_branchId_idx' AND object_id = OBJECT_ID(N'dbo.Member'))
    CREATE NONCLUSTERED INDEX [Member_branchId_idx] ON [dbo].[Member]([branchId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'Member_status_idx' AND object_id = OBJECT_ID(N'dbo.Member'))
    CREATE NONCLUSTERED INDEX [Member_status_idx] ON [dbo].[Member]([status]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'Member_phone_idx' AND object_id = OBJECT_ID(N'dbo.Member'))
    CREATE NONCLUSTERED INDEX [Member_phone_idx] ON [dbo].[Member]([phone]);
GO

-- indexes on [MembershipPlan]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'MembershipPlan_branchId_idx' AND object_id = OBJECT_ID(N'dbo.MembershipPlan'))
    CREATE NONCLUSTERED INDEX [MembershipPlan_branchId_idx] ON [dbo].[MembershipPlan]([branchId]);
GO

-- indexes on [Attendance]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'Attendance_branchId_date_idx' AND object_id = OBJECT_ID(N'dbo.Attendance'))
    CREATE NONCLUSTERED INDEX [Attendance_branchId_date_idx] ON [dbo].[Attendance]([branchId], [date]);
GO

-- indexes on [Fee]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'Fee_memberId_idx' AND object_id = OBJECT_ID(N'dbo.Fee'))
    CREATE NONCLUSTERED INDEX [Fee_memberId_idx] ON [dbo].[Fee]([memberId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'Fee_branchId_idx' AND object_id = OBJECT_ID(N'dbo.Fee'))
    CREATE NONCLUSTERED INDEX [Fee_branchId_idx] ON [dbo].[Fee]([branchId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'Fee_status_idx' AND object_id = OBJECT_ID(N'dbo.Fee'))
    CREATE NONCLUSTERED INDEX [Fee_status_idx] ON [dbo].[Fee]([status]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'Fee_dueDate_idx' AND object_id = OBJECT_ID(N'dbo.Fee'))
    CREATE NONCLUSTERED INDEX [Fee_dueDate_idx] ON [dbo].[Fee]([dueDate]);
GO

-- indexes on [FeePayment]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'FeePayment_feeId_idx' AND object_id = OBJECT_ID(N'dbo.FeePayment'))
    CREATE NONCLUSTERED INDEX [FeePayment_feeId_idx] ON [dbo].[FeePayment]([feeId]);
GO

-- indexes on [Prospect]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'Prospect_status_idx' AND object_id = OBJECT_ID(N'dbo.Prospect'))
    CREATE NONCLUSTERED INDEX [Prospect_status_idx] ON [dbo].[Prospect]([status]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'Prospect_source_idx' AND object_id = OBJECT_ID(N'dbo.Prospect'))
    CREATE NONCLUSTERED INDEX [Prospect_source_idx] ON [dbo].[Prospect]([source]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'Prospect_branchId_idx' AND object_id = OBJECT_ID(N'dbo.Prospect'))
    CREATE NONCLUSTERED INDEX [Prospect_branchId_idx] ON [dbo].[Prospect]([branchId]);
GO

-- indexes on [MembershipFreeze]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'MembershipFreeze_memberId_idx' AND object_id = OBJECT_ID(N'dbo.MembershipFreeze'))
    CREATE NONCLUSTERED INDEX [MembershipFreeze_memberId_idx] ON [dbo].[MembershipFreeze]([memberId]);
GO

-- indexes on [FollowUp]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'FollowUp_memberId_idx' AND object_id = OBJECT_ID(N'dbo.FollowUp'))
    CREATE NONCLUSTERED INDEX [FollowUp_memberId_idx] ON [dbo].[FollowUp]([memberId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'FollowUp_prospectId_idx' AND object_id = OBJECT_ID(N'dbo.FollowUp'))
    CREATE NONCLUSTERED INDEX [FollowUp_prospectId_idx] ON [dbo].[FollowUp]([prospectId]);
GO

-- indexes on [ProgressEntry]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ProgressEntry_memberId_date_idx' AND object_id = OBJECT_ID(N'dbo.ProgressEntry'))
    CREATE NONCLUSTERED INDEX [ProgressEntry_memberId_date_idx] ON [dbo].[ProgressEntry]([memberId], [date]);
GO

-- indexes on [WorkoutAssignment]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'WorkoutAssignment_memberId_idx' AND object_id = OBJECT_ID(N'dbo.WorkoutAssignment'))
    CREATE NONCLUSTERED INDEX [WorkoutAssignment_memberId_idx] ON [dbo].[WorkoutAssignment]([memberId]);
GO

-- indexes on [DietMeal]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'DietMeal_planId_dayOfWeek_idx' AND object_id = OBJECT_ID(N'dbo.DietMeal'))
    CREATE NONCLUSTERED INDEX [DietMeal_planId_dayOfWeek_idx] ON [dbo].[DietMeal]([planId], [dayOfWeek]);
GO

-- indexes on [DietAssignment]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'DietAssignment_memberId_idx' AND object_id = OBJECT_ID(N'dbo.DietAssignment'))
    CREATE NONCLUSTERED INDEX [DietAssignment_memberId_idx] ON [dbo].[DietAssignment]([memberId]);
GO

-- indexes on [EquipmentMaintenance]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'EquipmentMaintenance_equipmentId_idx' AND object_id = OBJECT_ID(N'dbo.EquipmentMaintenance'))
    CREATE NONCLUSTERED INDEX [EquipmentMaintenance_equipmentId_idx] ON [dbo].[EquipmentMaintenance]([equipmentId]);
GO

-- indexes on [Leave]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'Leave_staffId_idx' AND object_id = OBJECT_ID(N'dbo.Leave'))
    CREATE NONCLUSTERED INDEX [Leave_staffId_idx] ON [dbo].[Leave]([staffId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'Leave_branchId_idx' AND object_id = OBJECT_ID(N'dbo.Leave'))
    CREATE NONCLUSTERED INDEX [Leave_branchId_idx] ON [dbo].[Leave]([branchId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'Leave_status_idx' AND object_id = OBJECT_ID(N'dbo.Leave'))
    CREATE NONCLUSTERED INDEX [Leave_status_idx] ON [dbo].[Leave]([status]);
GO

-- indexes on [Overtime]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'Overtime_staffId_idx' AND object_id = OBJECT_ID(N'dbo.Overtime'))
    CREATE NONCLUSTERED INDEX [Overtime_staffId_idx] ON [dbo].[Overtime]([staffId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'Overtime_status_idx' AND object_id = OBJECT_ID(N'dbo.Overtime'))
    CREATE NONCLUSTERED INDEX [Overtime_status_idx] ON [dbo].[Overtime]([status]);
GO

-- indexes on [Payroll]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'Payroll_branchId_idx' AND object_id = OBJECT_ID(N'dbo.Payroll'))
    CREATE NONCLUSTERED INDEX [Payroll_branchId_idx] ON [dbo].[Payroll]([branchId]);
GO

-- indexes on [payrollmasterfile]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'payrollmasterfile_masterType_idx' AND object_id = OBJECT_ID(N'dbo.payrollmasterfile'))
    CREATE NONCLUSTERED INDEX [payrollmasterfile_masterType_idx] ON [dbo].[payrollmasterfile]([masterType]);
GO

-- indexes on [MasterFile]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'MasterFile_masterType_idx' AND object_id = OBJECT_ID(N'dbo.MasterFile'))
    CREATE NONCLUSTERED INDEX [MasterFile_masterType_idx] ON [dbo].[MasterFile]([masterType]);
GO

-- indexes on [FitnessGoal]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'FitnessGoal_memberId_idx' AND object_id = OBJECT_ID(N'dbo.FitnessGoal'))
    CREATE NONCLUSTERED INDEX [FitnessGoal_memberId_idx] ON [dbo].[FitnessGoal]([memberId]);
GO

-- indexes on [PersonalTrainingSession]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'PersonalTrainingSession_memberId_idx' AND object_id = OBJECT_ID(N'dbo.PersonalTrainingSession'))
    CREATE NONCLUSTERED INDEX [PersonalTrainingSession_memberId_idx] ON [dbo].[PersonalTrainingSession]([memberId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'PersonalTrainingSession_trainerId_idx' AND object_id = OBJECT_ID(N'dbo.PersonalTrainingSession'))
    CREATE NONCLUSTERED INDEX [PersonalTrainingSession_trainerId_idx] ON [dbo].[PersonalTrainingSession]([trainerId]);
GO

-- indexes on [TrainerAvailability]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'TrainerAvailability_staffId_idx' AND object_id = OBJECT_ID(N'dbo.TrainerAvailability'))
    CREATE NONCLUSTERED INDEX [TrainerAvailability_staffId_idx] ON [dbo].[TrainerAvailability]([staffId]);
GO

-- indexes on [TrainerSchedule]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'TrainerSchedule_staffId_date_idx' AND object_id = OBJECT_ID(N'dbo.TrainerSchedule'))
    CREATE NONCLUSTERED INDEX [TrainerSchedule_staffId_date_idx] ON [dbo].[TrainerSchedule]([staffId], [date]);
GO

-- indexes on [StaffDocument]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'StaffDocument_staffId_idx' AND object_id = OBJECT_ID(N'dbo.StaffDocument'))
    CREATE NONCLUSTERED INDEX [StaffDocument_staffId_idx] ON [dbo].[StaffDocument]([staffId]);
GO

-- indexes on [StockMovement]
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'StockMovement_inventoryItemId_idx' AND object_id = OBJECT_ID(N'dbo.StockMovement'))
    CREATE NONCLUSTERED INDEX [StockMovement_inventoryItemId_idx] ON [dbo].[StockMovement]([inventoryItemId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'StockMovement_branchId_date_idx' AND object_id = OBJECT_ID(N'dbo.StockMovement'))
    CREATE NONCLUSTERED INDEX [StockMovement_branchId_date_idx] ON [dbo].[StockMovement]([branchId], [date]);
GO


-- ===========================================================================
-- SECTION 3 of 3 - FOREIGN KEYS (all tables now exist)
-- ===========================================================================

-- foreign keys on [dbo].[Branch]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'Branch_parentId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.Branch'))
    ALTER TABLE [dbo].[Branch] ADD CONSTRAINT [Branch_parentId_fkey] FOREIGN KEY ([parentId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[ScreenPermission]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'ScreenPermission_roleId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.ScreenPermission'))
    ALTER TABLE [dbo].[ScreenPermission] ADD CONSTRAINT [ScreenPermission_roleId_fkey] FOREIGN KEY ([roleId]) REFERENCES [dbo].[Role]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[UserPermission]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'UserPermission_userId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.UserPermission'))
    ALTER TABLE [dbo].[UserPermission] ADD CONSTRAINT [UserPermission_userId_fkey] FOREIGN KEY ([userId]) REFERENCES [dbo].[User]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[RolePermission]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'RolePermission_roleId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.RolePermission'))
    ALTER TABLE [dbo].[RolePermission] ADD CONSTRAINT [RolePermission_roleId_fkey] FOREIGN KEY ([roleId]) REFERENCES [dbo].[Role]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'RolePermission_permissionId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.RolePermission'))
    ALTER TABLE [dbo].[RolePermission] ADD CONSTRAINT [RolePermission_permissionId_fkey] FOREIGN KEY ([permissionId]) REFERENCES [dbo].[Permission]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[User]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'User_roleId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.User'))
    ALTER TABLE [dbo].[User] ADD CONSTRAINT [User_roleId_fkey] FOREIGN KEY ([roleId]) REFERENCES [dbo].[Role]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'User_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.User'))
    ALTER TABLE [dbo].[User] ADD CONSTRAINT [User_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[Session]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'Session_userId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.Session'))
    ALTER TABLE [dbo].[Session] ADD CONSTRAINT [Session_userId_fkey] FOREIGN KEY ([userId]) REFERENCES [dbo].[User]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[AuditLog]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'AuditLog_userId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.AuditLog'))
    ALTER TABLE [dbo].[AuditLog] ADD CONSTRAINT [AuditLog_userId_fkey] FOREIGN KEY ([userId]) REFERENCES [dbo].[User]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[charts]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'charts_parentCode_fkey' AND parent_object_id = OBJECT_ID(N'dbo.charts'))
    ALTER TABLE [dbo].[charts] ADD CONSTRAINT [charts_parentCode_fkey] FOREIGN KEY ([parentCode]) REFERENCES [dbo].[charts]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'charts_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.charts'))
    ALTER TABLE [dbo].[charts] ADD CONSTRAINT [charts_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[CashBook]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'CashBook_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.CashBook'))
    ALTER TABLE [dbo].[CashBook] ADD CONSTRAINT [CashBook_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'CashBook_bookChartId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.CashBook'))
    ALTER TABLE [dbo].[CashBook] ADD CONSTRAINT [CashBook_bookChartId_fkey] FOREIGN KEY ([bookChartId]) REFERENCES [dbo].[charts]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[CashBookLine]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'CashBookLine_voucherId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.CashBookLine'))
    ALTER TABLE [dbo].[CashBookLine] ADD CONSTRAINT [CashBookLine_voucherId_fkey] FOREIGN KEY ([voucherId]) REFERENCES [dbo].[CashBook]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'CashBookLine_accountId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.CashBookLine'))
    ALTER TABLE [dbo].[CashBookLine] ADD CONSTRAINT [CashBookLine_accountId_fkey] FOREIGN KEY ([accountId]) REFERENCES [dbo].[charts]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[BankBook]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'BankBook_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.BankBook'))
    ALTER TABLE [dbo].[BankBook] ADD CONSTRAINT [BankBook_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'BankBook_bookChartId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.BankBook'))
    ALTER TABLE [dbo].[BankBook] ADD CONSTRAINT [BankBook_bookChartId_fkey] FOREIGN KEY ([bookChartId]) REFERENCES [dbo].[charts]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[BankBookLine]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'BankBookLine_voucherId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.BankBookLine'))
    ALTER TABLE [dbo].[BankBookLine] ADD CONSTRAINT [BankBookLine_voucherId_fkey] FOREIGN KEY ([voucherId]) REFERENCES [dbo].[BankBook]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'BankBookLine_accountId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.BankBookLine'))
    ALTER TABLE [dbo].[BankBookLine] ADD CONSTRAINT [BankBookLine_accountId_fkey] FOREIGN KEY ([accountId]) REFERENCES [dbo].[charts]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[JV]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'JV_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.JV'))
    ALTER TABLE [dbo].[JV] ADD CONSTRAINT [JV_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[JVLine]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'JVLine_voucherId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.JVLine'))
    ALTER TABLE [dbo].[JVLine] ADD CONSTRAINT [JVLine_voucherId_fkey] FOREIGN KEY ([voucherId]) REFERENCES [dbo].[JV]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'JVLine_accountId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.JVLine'))
    ALTER TABLE [dbo].[JVLine] ADD CONSTRAINT [JVLine_accountId_fkey] FOREIGN KEY ([accountId]) REFERENCES [dbo].[charts]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[OpenTB]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'OpenTB_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.OpenTB'))
    ALTER TABLE [dbo].[OpenTB] ADD CONSTRAINT [OpenTB_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[OpenTBLine]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'OpenTBLine_voucherId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.OpenTBLine'))
    ALTER TABLE [dbo].[OpenTBLine] ADD CONSTRAINT [OpenTBLine_voucherId_fkey] FOREIGN KEY ([voucherId]) REFERENCES [dbo].[OpenTB]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'OpenTBLine_accountId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.OpenTBLine'))
    ALTER TABLE [dbo].[OpenTBLine] ADD CONSTRAINT [OpenTBLine_accountId_fkey] FOREIGN KEY ([accountId]) REFERENCES [dbo].[charts]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[KnockOff]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'KnockOff_accountId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.KnockOff'))
    ALTER TABLE [dbo].[KnockOff] ADD CONSTRAINT [KnockOff_accountId_fkey] FOREIGN KEY ([accountId]) REFERENCES [dbo].[charts]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'KnockOff_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.KnockOff'))
    ALTER TABLE [dbo].[KnockOff] ADD CONSTRAINT [KnockOff_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[AccountingPeriod]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'AccountingPeriod_financialYearId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.AccountingPeriod'))
    ALTER TABLE [dbo].[AccountingPeriod] ADD CONSTRAINT [AccountingPeriod_financialYearId_fkey] FOREIGN KEY ([financialYearId]) REFERENCES [dbo].[FinancialYear]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[TaxHead]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'TaxHead_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.TaxHead'))
    ALTER TABLE [dbo].[TaxHead] ADD CONSTRAINT [TaxHead_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[AccountMapping]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'AccountMapping_accountId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.AccountMapping'))
    ALTER TABLE [dbo].[AccountMapping] ADD CONSTRAINT [AccountMapping_accountId_fkey] FOREIGN KEY ([accountId]) REFERENCES [dbo].[charts]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[Member]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'Member_membershipPlanId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.Member'))
    ALTER TABLE [dbo].[Member] ADD CONSTRAINT [Member_membershipPlanId_fkey] FOREIGN KEY ([membershipPlanId]) REFERENCES [dbo].[MembershipPlan]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'Member_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.Member'))
    ALTER TABLE [dbo].[Member] ADD CONSTRAINT [Member_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[MembershipPlan]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'MembershipPlan_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.MembershipPlan'))
    ALTER TABLE [dbo].[MembershipPlan] ADD CONSTRAINT [MembershipPlan_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[Attendance]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'Attendance_memberId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.Attendance'))
    ALTER TABLE [dbo].[Attendance] ADD CONSTRAINT [Attendance_memberId_fkey] FOREIGN KEY ([memberId]) REFERENCES [dbo].[Member]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'Attendance_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.Attendance'))
    ALTER TABLE [dbo].[Attendance] ADD CONSTRAINT [Attendance_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[Fee]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'Fee_memberId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.Fee'))
    ALTER TABLE [dbo].[Fee] ADD CONSTRAINT [Fee_memberId_fkey] FOREIGN KEY ([memberId]) REFERENCES [dbo].[Member]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'Fee_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.Fee'))
    ALTER TABLE [dbo].[Fee] ADD CONSTRAINT [Fee_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[FeePayment]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FeePayment_feeId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.FeePayment'))
    ALTER TABLE [dbo].[FeePayment] ADD CONSTRAINT [FeePayment_feeId_fkey] FOREIGN KEY ([feeId]) REFERENCES [dbo].[Fee]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[Prospect]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'Prospect_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.Prospect'))
    ALTER TABLE [dbo].[Prospect] ADD CONSTRAINT [Prospect_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[MembershipFreeze]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'MembershipFreeze_memberId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.MembershipFreeze'))
    ALTER TABLE [dbo].[MembershipFreeze] ADD CONSTRAINT [MembershipFreeze_memberId_fkey] FOREIGN KEY ([memberId]) REFERENCES [dbo].[Member]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'MembershipFreeze_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.MembershipFreeze'))
    ALTER TABLE [dbo].[MembershipFreeze] ADD CONSTRAINT [MembershipFreeze_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[FollowUp]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FollowUp_memberId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.FollowUp'))
    ALTER TABLE [dbo].[FollowUp] ADD CONSTRAINT [FollowUp_memberId_fkey] FOREIGN KEY ([memberId]) REFERENCES [dbo].[Member]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FollowUp_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.FollowUp'))
    ALTER TABLE [dbo].[FollowUp] ADD CONSTRAINT [FollowUp_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[ProgressEntry]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'ProgressEntry_memberId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.ProgressEntry'))
    ALTER TABLE [dbo].[ProgressEntry] ADD CONSTRAINT [ProgressEntry_memberId_fkey] FOREIGN KEY ([memberId]) REFERENCES [dbo].[Member]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'ProgressEntry_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.ProgressEntry'))
    ALTER TABLE [dbo].[ProgressEntry] ADD CONSTRAINT [ProgressEntry_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[gymmasterfile]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'gymmasterfile_parentCode_fkey' AND parent_object_id = OBJECT_ID(N'dbo.gymmasterfile'))
    ALTER TABLE [dbo].[gymmasterfile] ADD CONSTRAINT [gymmasterfile_parentCode_fkey] FOREIGN KEY ([parentCode]) REFERENCES [dbo].[gymmasterfile]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'gymmasterfile_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.gymmasterfile'))
    ALTER TABLE [dbo].[gymmasterfile] ADD CONSTRAINT [gymmasterfile_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on the three master/detail pairs
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'gymmaster_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.gymmaster'))
    ALTER TABLE [dbo].[gymmaster] ADD CONSTRAINT [gymmaster_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'gymmasterdetail_masterId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.gymmasterdetail'))
    ALTER TABLE [dbo].[gymmasterdetail] ADD CONSTRAINT [gymmasterdetail_masterId_fkey] FOREIGN KEY ([masterId]) REFERENCES [dbo].[gymmaster]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'gymmasterdetail_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.gymmasterdetail'))
    ALTER TABLE [dbo].[gymmasterdetail] ADD CONSTRAINT [gymmasterdetail_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'financemaster_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.financemaster'))
    ALTER TABLE [dbo].[financemaster] ADD CONSTRAINT [financemaster_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'financemasterdetail_masterId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.financemasterdetail'))
    ALTER TABLE [dbo].[financemasterdetail] ADD CONSTRAINT [financemasterdetail_masterId_fkey] FOREIGN KEY ([masterId]) REFERENCES [dbo].[financemaster]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'financemasterdetail_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.financemasterdetail'))
    ALTER TABLE [dbo].[financemasterdetail] ADD CONSTRAINT [financemasterdetail_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'payrollmaster_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.payrollmaster'))
    ALTER TABLE [dbo].[payrollmaster] ADD CONSTRAINT [payrollmaster_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'payrollmasterdetail_masterId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.payrollmasterdetail'))
    ALTER TABLE [dbo].[payrollmasterdetail] ADD CONSTRAINT [payrollmasterdetail_masterId_fkey] FOREIGN KEY ([masterId]) REFERENCES [dbo].[payrollmaster]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'payrollmasterdetail_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.payrollmasterdetail'))
    ALTER TABLE [dbo].[payrollmasterdetail] ADD CONSTRAINT [payrollmasterdetail_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[WorkoutPlan]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'WorkoutPlan_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.WorkoutPlan'))
    ALTER TABLE [dbo].[WorkoutPlan] ADD CONSTRAINT [WorkoutPlan_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[WorkoutDay]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'WorkoutDay_planId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.WorkoutDay'))
    ALTER TABLE [dbo].[WorkoutDay] ADD CONSTRAINT [WorkoutDay_planId_fkey] FOREIGN KEY ([planId]) REFERENCES [dbo].[WorkoutPlan]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[WorkoutDayExercise]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'WorkoutDayExercise_dayId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.WorkoutDayExercise'))
    ALTER TABLE [dbo].[WorkoutDayExercise] ADD CONSTRAINT [WorkoutDayExercise_dayId_fkey] FOREIGN KEY ([dayId]) REFERENCES [dbo].[WorkoutDay]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'WorkoutDayExercise_exerciseId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.WorkoutDayExercise'))
    ALTER TABLE [dbo].[WorkoutDayExercise] ADD CONSTRAINT [WorkoutDayExercise_exerciseId_fkey] FOREIGN KEY ([exerciseId]) REFERENCES [dbo].[gymmasterdetail]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[WorkoutAssignment]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'WorkoutAssignment_memberId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.WorkoutAssignment'))
    ALTER TABLE [dbo].[WorkoutAssignment] ADD CONSTRAINT [WorkoutAssignment_memberId_fkey] FOREIGN KEY ([memberId]) REFERENCES [dbo].[Member]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'WorkoutAssignment_planId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.WorkoutAssignment'))
    ALTER TABLE [dbo].[WorkoutAssignment] ADD CONSTRAINT [WorkoutAssignment_planId_fkey] FOREIGN KEY ([planId]) REFERENCES [dbo].[WorkoutPlan]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[DietPlan]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'DietPlan_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.DietPlan'))
    ALTER TABLE [dbo].[DietPlan] ADD CONSTRAINT [DietPlan_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[DietMeal]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'DietMeal_planId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.DietMeal'))
    ALTER TABLE [dbo].[DietMeal] ADD CONSTRAINT [DietMeal_planId_fkey] FOREIGN KEY ([planId]) REFERENCES [dbo].[DietPlan]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[DietAssignment]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'DietAssignment_memberId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.DietAssignment'))
    ALTER TABLE [dbo].[DietAssignment] ADD CONSTRAINT [DietAssignment_memberId_fkey] FOREIGN KEY ([memberId]) REFERENCES [dbo].[Member]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'DietAssignment_planId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.DietAssignment'))
    ALTER TABLE [dbo].[DietAssignment] ADD CONSTRAINT [DietAssignment_planId_fkey] FOREIGN KEY ([planId]) REFERENCES [dbo].[DietPlan]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[Equipment]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'Equipment_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.Equipment'))
    ALTER TABLE [dbo].[Equipment] ADD CONSTRAINT [Equipment_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[EquipmentMaintenance]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'EquipmentMaintenance_equipmentId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.EquipmentMaintenance'))
    ALTER TABLE [dbo].[EquipmentMaintenance] ADD CONSTRAINT [EquipmentMaintenance_equipmentId_fkey] FOREIGN KEY ([equipmentId]) REFERENCES [dbo].[Equipment]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[InventoryItem]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'InventoryItem_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.InventoryItem'))
    ALTER TABLE [dbo].[InventoryItem] ADD CONSTRAINT [InventoryItem_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[PosSale]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'PosSale_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.PosSale'))
    ALTER TABLE [dbo].[PosSale] ADD CONSTRAINT [PosSale_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[PosSaleLine]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'PosSaleLine_saleId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.PosSaleLine'))
    ALTER TABLE [dbo].[PosSaleLine] ADD CONSTRAINT [PosSaleLine_saleId_fkey] FOREIGN KEY ([saleId]) REFERENCES [dbo].[PosSale]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'PosSaleLine_inventoryItemId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.PosSaleLine'))
    ALTER TABLE [dbo].[PosSaleLine] ADD CONSTRAINT [PosSaleLine_inventoryItemId_fkey] FOREIGN KEY ([inventoryItemId]) REFERENCES [dbo].[InventoryItem]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[Staff]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'Staff_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.Staff'))
    ALTER TABLE [dbo].[Staff] ADD CONSTRAINT [Staff_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'Staff_shiftId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.Staff'))
    ALTER TABLE [dbo].[Staff] ADD CONSTRAINT [Staff_shiftId_fkey] FOREIGN KEY ([shiftId]) REFERENCES [dbo].[Shift]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[Shift]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'Shift_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.Shift'))
    ALTER TABLE [dbo].[Shift] ADD CONSTRAINT [Shift_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[CalendarDay]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'CalendarDay_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.CalendarDay'))
    ALTER TABLE [dbo].[CalendarDay] ADD CONSTRAINT [CalendarDay_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[Leave]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'Leave_staffId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.Leave'))
    ALTER TABLE [dbo].[Leave] ADD CONSTRAINT [Leave_staffId_fkey] FOREIGN KEY ([staffId]) REFERENCES [dbo].[Staff]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'Leave_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.Leave'))
    ALTER TABLE [dbo].[Leave] ADD CONSTRAINT [Leave_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[Overtime]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'Overtime_staffId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.Overtime'))
    ALTER TABLE [dbo].[Overtime] ADD CONSTRAINT [Overtime_staffId_fkey] FOREIGN KEY ([staffId]) REFERENCES [dbo].[Staff]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[Payroll]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'Payroll_staffId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.Payroll'))
    ALTER TABLE [dbo].[Payroll] ADD CONSTRAINT [Payroll_staffId_fkey] FOREIGN KEY ([staffId]) REFERENCES [dbo].[Staff]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'Payroll_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.Payroll'))
    ALTER TABLE [dbo].[Payroll] ADD CONSTRAINT [Payroll_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[payrollmasterfile]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'payrollmasterfile_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.payrollmasterfile'))
    ALTER TABLE [dbo].[payrollmasterfile] ADD CONSTRAINT [payrollmasterfile_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[MasterFile]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'MasterFile_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.MasterFile'))
    ALTER TABLE [dbo].[MasterFile] ADD CONSTRAINT [MasterFile_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[FitnessGoal]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FitnessGoal_memberId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.FitnessGoal'))
    ALTER TABLE [dbo].[FitnessGoal] ADD CONSTRAINT [FitnessGoal_memberId_fkey] FOREIGN KEY ([memberId]) REFERENCES [dbo].[Member]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[PersonalTrainingSession]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'PersonalTrainingSession_memberId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.PersonalTrainingSession'))
    ALTER TABLE [dbo].[PersonalTrainingSession] ADD CONSTRAINT [PersonalTrainingSession_memberId_fkey] FOREIGN KEY ([memberId]) REFERENCES [dbo].[Member]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'PersonalTrainingSession_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.PersonalTrainingSession'))
    ALTER TABLE [dbo].[PersonalTrainingSession] ADD CONSTRAINT [PersonalTrainingSession_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[TrainerAvailability]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'TrainerAvailability_staffId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.TrainerAvailability'))
    ALTER TABLE [dbo].[TrainerAvailability] ADD CONSTRAINT [TrainerAvailability_staffId_fkey] FOREIGN KEY ([staffId]) REFERENCES [dbo].[Staff]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'TrainerAvailability_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.TrainerAvailability'))
    ALTER TABLE [dbo].[TrainerAvailability] ADD CONSTRAINT [TrainerAvailability_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[TrainerSchedule]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'TrainerSchedule_staffId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.TrainerSchedule'))
    ALTER TABLE [dbo].[TrainerSchedule] ADD CONSTRAINT [TrainerSchedule_staffId_fkey] FOREIGN KEY ([staffId]) REFERENCES [dbo].[Staff]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'TrainerSchedule_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.TrainerSchedule'))
    ALTER TABLE [dbo].[TrainerSchedule] ADD CONSTRAINT [TrainerSchedule_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[StaffDocument]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'StaffDocument_staffId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.StaffDocument'))
    ALTER TABLE [dbo].[StaffDocument] ADD CONSTRAINT [StaffDocument_staffId_fkey] FOREIGN KEY ([staffId]) REFERENCES [dbo].[Staff]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[Supplier]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'Supplier_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.Supplier'))
    ALTER TABLE [dbo].[Supplier] ADD CONSTRAINT [Supplier_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[Purchase]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'Purchase_supplierId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.Purchase'))
    ALTER TABLE [dbo].[Purchase] ADD CONSTRAINT [Purchase_supplierId_fkey] FOREIGN KEY ([supplierId]) REFERENCES [dbo].[Supplier]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'Purchase_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.Purchase'))
    ALTER TABLE [dbo].[Purchase] ADD CONSTRAINT [Purchase_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[PurchaseLine]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'PurchaseLine_purchaseId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.PurchaseLine'))
    ALTER TABLE [dbo].[PurchaseLine] ADD CONSTRAINT [PurchaseLine_purchaseId_fkey] FOREIGN KEY ([purchaseId]) REFERENCES [dbo].[Purchase]([id]) ON DELETE CASCADE ON UPDATE NO ACTION;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'PurchaseLine_inventoryItemId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.PurchaseLine'))
    ALTER TABLE [dbo].[PurchaseLine] ADD CONSTRAINT [PurchaseLine_inventoryItemId_fkey] FOREIGN KEY ([inventoryItemId]) REFERENCES [dbo].[InventoryItem]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

-- foreign keys on [dbo].[StockMovement]
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'StockMovement_inventoryItemId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.StockMovement'))
    ALTER TABLE [dbo].[StockMovement] ADD CONSTRAINT [StockMovement_inventoryItemId_fkey] FOREIGN KEY ([inventoryItemId]) REFERENCES [dbo].[InventoryItem]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'StockMovement_branchId_fkey' AND parent_object_id = OBJECT_ID(N'dbo.StockMovement'))
    ALTER TABLE [dbo].[StockMovement] ADD CONSTRAINT [StockMovement_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO


GO
PRINT 'Step 02 complete: 69 tables, indexes and 90 foreign keys created.';
GO

-- --------------------------------------------------------------------------
-- Post-build sanity check (informational only - no error on empty database)
-- --------------------------------------------------------------------------
SELECT N'tables'    AS [object], COUNT(*) AS [count] FROM sys.tables
UNION ALL SELECT N'views',                  COUNT(*) FROM sys.views
UNION ALL SELECT N'indexes (on tables)',    COUNT(*) FROM sys.indexes WHERE object_id IN (SELECT object_id FROM sys.tables)
UNION ALL SELECT N'foreign keys',           COUNT(*) FROM sys.foreign_keys;
GO

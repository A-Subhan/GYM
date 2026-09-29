BEGIN TRY

BEGIN TRAN;

-- CreateTable Branch
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
    [parentId] NVARCHAR(50),
    [nodeType] NVARCHAR(255) NOT NULL CONSTRAINT [Branch_nodeType_df] DEFAULT 'Detail',
    [trn] NVARCHAR(255),
    [fbr] NVARCHAR(255),
    CONSTRAINT [Branch_pkey] PRIMARY KEY CLUSTERED ([id])
    CONSTRAINT [Branch_code_key] UNIQUE NONCLUSTERED ([code])
);

-- CreateTable Role
CREATE TABLE [dbo].[Role] (
    [id] NVARCHAR(50) NOT NULL,
    [name] NVARCHAR(191) NOT NULL,
    [description] NVARCHAR(max),
    [isSystem] BIT NOT NULL CONSTRAINT [Role_isSystem_df] DEFAULT 0,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Role_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [Role_pkey] PRIMARY KEY CLUSTERED ([id])
    CONSTRAINT [Role_name_key] UNIQUE NONCLUSTERED ([name])
);

-- CreateTable Permission
CREATE TABLE [dbo].[Permission] (
    [id] NVARCHAR(50) NOT NULL,
    [module] NVARCHAR(255) NOT NULL,
    [action] NVARCHAR(255) NOT NULL,
    [code] NVARCHAR(191) NOT NULL,
    [description] NVARCHAR(max),
    CONSTRAINT [Permission_pkey] PRIMARY KEY CLUSTERED ([id])
    CONSTRAINT [Permission_code_key] UNIQUE NONCLUSTERED ([code])
);

-- CreateTable RolePermission
CREATE TABLE [dbo].[RolePermission] (
    [roleId] NVARCHAR(50) NOT NULL,
    [permissionId] NVARCHAR(50) NOT NULL,
    CONSTRAINT [RolePermission_pkey] PRIMARY KEY CLUSTERED ([id])
    CONSTRAINT [RolePermission_roleId_fkey] FOREIGN KEY ([roleId]) REFERENCES [dbo].[Role]([id]) ON DELETE NO ACTION
    CONSTRAINT [RolePermission_permissionId_fkey] FOREIGN KEY ([permissionId]) REFERENCES [dbo].[Permission]([id]) ON DELETE NO ACTION
);

-- CreateTable User
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
    CONSTRAINT [User_pkey] PRIMARY KEY CLUSTERED ([id])
    CONSTRAINT [User_username_key] UNIQUE NONCLUSTERED ([username])
    CONSTRAINT [User_email_key] UNIQUE NONCLUSTERED ([email])
    CONSTRAINT [User_roleId_fkey] FOREIGN KEY ([roleId]) REFERENCES [dbo].[Role]([id]) ON DELETE NO ACTION
    CONSTRAINT [User_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION
);

-- CreateTable Session
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
    CONSTRAINT [Session_userId_fkey] FOREIGN KEY ([userId]) REFERENCES [dbo].[User]([id]) ON DELETE NO ACTION
);

-- CreateTable AuditLog
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
    CONSTRAINT [AuditLog_userId_fkey] FOREIGN KEY ([userId]) REFERENCES [dbo].[User]([id]) ON DELETE NO ACTION
);

-- CreateTable Defaults
CREATE TABLE [dbo].[Defaults] (
    [id] NVARCHAR(50) NOT NULL,
    [companyName] NVARCHAR(255),
    [address] NVARCHAR(max),
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
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Defaults_createdAt_df] DEFAULT SYSDATETIME(),
    [updatedAt] DATETIME2 NOT NULL CONSTRAINT [Defaults_updatedAt_df] DEFAULT SYSDATETIME(),
    CONSTRAINT [Defaults_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable charts
CREATE TABLE [dbo].[charts] (
    [id] NVARCHAR(50) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
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
    [address] NVARCHAR(max),
    [bankName] NVARCHAR(255),
    [bankAccountNo] NVARCHAR(255),
    [bankBranch] NVARCHAR(255),
    [cnic] NVARCHAR(255),
    [ntn] NVARCHAR(255),
    [description] NVARCHAR(max),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [charts_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    [parentCode] NVARCHAR(50) NOT NULL,
    [strn] NVARCHAR(255),
    [fbr] NVARCHAR(255),
    [otherName] NVARCHAR(255),
    [referenceNumber] NVARCHAR(255),
    [faxNumber] NVARCHAR(255),
    [city] NVARCHAR(255),
    [country] NVARCHAR(255),
    [website] NVARCHAR(255),
    [paymentTerms] NVARCHAR(255),
    [registrationNumber] NVARCHAR(255),
    CONSTRAINT [charts_pkey] PRIMARY KEY CLUSTERED ([id])
    CONSTRAINT [FK_charts_parent] FOREIGN KEY ([parentCode]) REFERENCES [dbo].[charts]([id]) ON DELETE NO ACTION
);

-- CreateTable FinancialYear
CREATE TABLE [dbo].[FinancialYear] (
    [id] NVARCHAR(50) NOT NULL,
    [name] NVARCHAR(191) NOT NULL,
    [startDate] DATETIME2 NOT NULL,
    [endDate] DATETIME2 NOT NULL,
    [isActive] BIT NOT NULL CONSTRAINT [FinancialYear_isActive_df] DEFAULT 1,
    [isClosed] BIT NOT NULL CONSTRAINT [FinancialYear_isClosed_df] DEFAULT 0,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [FinancialYear_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [FinancialYear_pkey] PRIMARY KEY CLUSTERED ([id])
    CONSTRAINT [FinancialYear_name_key] UNIQUE NONCLUSTERED ([name])
);

-- CreateTable AccountingPeriod
CREATE TABLE [dbo].[AccountingPeriod] (
    [id] NVARCHAR(50) NOT NULL,
    [financialYearId] NVARCHAR(50) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [startDate] DATETIME2 NOT NULL,
    [endDate] DATETIME2 NOT NULL,
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [AccountingPeriod_status_df] DEFAULT 'Open',
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [AccountingPeriod_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [AccountingPeriod_pkey] PRIMARY KEY CLUSTERED ([id])
    CONSTRAINT [AccountingPeriod_financialYearId_fkey] FOREIGN KEY ([financialYearId]) REFERENCES [dbo].[FinancialYear]([id]) ON DELETE NO ACTION
);

-- CreateTable TaxHead
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
    CONSTRAINT [TaxHead_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION
);

-- CreateTable IdSequence
CREATE TABLE [dbo].[IdSequence] (
    [key] NVARCHAR(191) NOT NULL,
    [next] INT NOT NULL CONSTRAINT [IdSequence_next_df] DEFAULT 1,
    [updatedAt] DATETIME2 NOT NULL CONSTRAINT [IdSequence_updatedAt_df] DEFAULT SYSDATETIME(),
    CONSTRAINT [IdSequence_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable CashBook
CREATE TABLE [dbo].[CashBook] (
    [id] NVARCHAR(50) NOT NULL,
    [voucherType] NVARCHAR(10) NOT NULL,
    [voucherDate] DATETIME2 NOT NULL,
    [branchId] NVARCHAR(50) NOT NULL,
    [bookChartId] NVARCHAR(50) NOT NULL,
    [description] NVARCHAR(max),
    [reference] NVARCHAR(255),
    [totalAmount] FLOAT NOT NULL CONSTRAINT [CashBook_totalAmount_df] DEFAULT 0,
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [CashBook_status_df] DEFAULT 'Posted',
    [reversedById] NVARCHAR(50),
    [reversedAt] DATETIME2,
    [reversalReason] NVARCHAR(255),
    [postedById] NVARCHAR(50),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [CashBook_createdAt_df] DEFAULT SYSDATETIME(),
    [updatedAt] DATETIME2 NOT NULL CONSTRAINT [CashBook_updatedAt_df] DEFAULT SYSDATETIME(),
    CONSTRAINT [CashBook_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable CashBookLine
CREATE TABLE [dbo].[CashBookLine] (
    [id] NVARCHAR(50) NOT NULL,
    [voucherId] NVARCHAR(50) NOT NULL,
    [accountId] NVARCHAR(50) NOT NULL,
    [debit] FLOAT NOT NULL CONSTRAINT [CashBookLine_debit_df] DEFAULT 0,
    [credit] FLOAT NOT NULL CONSTRAINT [CashBookLine_credit_df] DEFAULT 0,
    [amount] FLOAT NOT NULL CONSTRAINT [CashBookLine_amount_df] DEFAULT 0,
    [taxPercent] FLOAT NOT NULL CONSTRAINT [CashBookLine_taxPercent_df] DEFAULT 0,
    [taxAmount] FLOAT NOT NULL CONSTRAINT [CashBookLine_taxAmount_df] DEFAULT 0,
    [total] FLOAT NOT NULL CONSTRAINT [CashBookLine_total_df] DEFAULT 0,
    [lineDescription] NVARCHAR(255),
    [title] NVARCHAR(255),
    [reference] NVARCHAR(255),
    [chequeNo] NVARCHAR(255),
    [chequeAmount] FLOAT,
    [chequeBankName] NVARCHAR(255),
    [chequeStatus] NVARCHAR(255),
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [CashBookLine_status_df] DEFAULT 'Active',
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [CashBookLine_createdAt_df] DEFAULT SYSDATETIME(),
    CONSTRAINT [CashBookLine_pkey] PRIMARY KEY CLUSTERED ([id])
    CONSTRAINT [FK_CashBookLine_voucher] FOREIGN KEY ([voucherId]) REFERENCES [dbo].[CashBook]([id]) ON DELETE CASCADE
);

-- CreateTable BankBook
CREATE TABLE [dbo].[BankBook] (
    [id] NVARCHAR(50) NOT NULL,
    [voucherType] NVARCHAR(10) NOT NULL,
    [voucherDate] DATETIME2 NOT NULL,
    [branchId] NVARCHAR(50) NOT NULL,
    [bookChartId] NVARCHAR(50) NOT NULL,
    [description] NVARCHAR(max),
    [reference] NVARCHAR(255),
    [totalAmount] FLOAT NOT NULL CONSTRAINT [BankBook_totalAmount_df] DEFAULT 0,
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [BankBook_status_df] DEFAULT 'Posted',
    [reversedById] NVARCHAR(50),
    [reversedAt] DATETIME2,
    [reversalReason] NVARCHAR(255),
    [postedById] NVARCHAR(50),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [BankBook_createdAt_df] DEFAULT SYSDATETIME(),
    [updatedAt] DATETIME2 NOT NULL CONSTRAINT [BankBook_updatedAt_df] DEFAULT SYSDATETIME(),
    CONSTRAINT [BankBook_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable BankBookLine
CREATE TABLE [dbo].[BankBookLine] (
    [id] NVARCHAR(50) NOT NULL,
    [voucherId] NVARCHAR(50) NOT NULL,
    [accountId] NVARCHAR(50) NOT NULL,
    [debit] FLOAT NOT NULL CONSTRAINT [BankBookLine_debit_df] DEFAULT 0,
    [credit] FLOAT NOT NULL CONSTRAINT [BankBookLine_credit_df] DEFAULT 0,
    [amount] FLOAT NOT NULL CONSTRAINT [BankBookLine_amount_df] DEFAULT 0,
    [taxPercent] FLOAT NOT NULL CONSTRAINT [BankBookLine_taxPercent_df] DEFAULT 0,
    [taxAmount] FLOAT NOT NULL CONSTRAINT [BankBookLine_taxAmount_df] DEFAULT 0,
    [total] FLOAT NOT NULL CONSTRAINT [BankBookLine_total_df] DEFAULT 0,
    [lineDescription] NVARCHAR(255),
    [title] NVARCHAR(255),
    [reference] NVARCHAR(255),
    [chequeNo] NVARCHAR(255),
    [chequeAmount] FLOAT,
    [chequeBankName] NVARCHAR(255),
    [chequeStatus] NVARCHAR(255),
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [BankBookLine_status_df] DEFAULT 'Active',
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [BankBookLine_createdAt_df] DEFAULT SYSDATETIME(),
    CONSTRAINT [BankBookLine_pkey] PRIMARY KEY CLUSTERED ([id])
    CONSTRAINT [FK_BankBookLine_voucher] FOREIGN KEY ([voucherId]) REFERENCES [dbo].[BankBook]([id]) ON DELETE CASCADE
);

-- CreateTable JV
CREATE TABLE [dbo].[JV] (
    [id] NVARCHAR(50) NOT NULL,
    [voucherType] NVARCHAR(10) NOT NULL CONSTRAINT [JV_voucherType_df] DEFAULT 'JV',
    [voucherDate] DATETIME2 NOT NULL,
    [branchId] NVARCHAR(50) NOT NULL,
    [description] NVARCHAR(max),
    [reference] NVARCHAR(255),
    [totalDebit] FLOAT NOT NULL CONSTRAINT [JV_totalDebit_df] DEFAULT 0,
    [totalCredit] FLOAT NOT NULL CONSTRAINT [JV_totalCredit_df] DEFAULT 0,
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [JV_status_df] DEFAULT 'Posted',
    [reversedById] NVARCHAR(50),
    [reversedAt] DATETIME2,
    [reversalReason] NVARCHAR(255),
    [postedById] NVARCHAR(50),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [JV_createdAt_df] DEFAULT SYSDATETIME(),
    [updatedAt] DATETIME2 NOT NULL CONSTRAINT [JV_updatedAt_df] DEFAULT SYSDATETIME(),
    CONSTRAINT [JV_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable JVLine
CREATE TABLE [dbo].[JVLine] (
    [id] NVARCHAR(50) NOT NULL,
    [voucherId] NVARCHAR(50) NOT NULL,
    [accountId] NVARCHAR(50) NOT NULL,
    [debit] FLOAT NOT NULL CONSTRAINT [JVLine_debit_df] DEFAULT 0,
    [credit] FLOAT NOT NULL CONSTRAINT [JVLine_credit_df] DEFAULT 0,
    [amount] FLOAT NOT NULL CONSTRAINT [JVLine_amount_df] DEFAULT 0,
    [taxPercent] FLOAT NOT NULL CONSTRAINT [JVLine_taxPercent_df] DEFAULT 0,
    [taxAmount] FLOAT NOT NULL CONSTRAINT [JVLine_taxAmount_df] DEFAULT 0,
    [total] FLOAT NOT NULL CONSTRAINT [JVLine_total_df] DEFAULT 0,
    [lineDescription] NVARCHAR(255),
    [reference] NVARCHAR(255),
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [JVLine_status_df] DEFAULT 'Active',
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [JVLine_createdAt_df] DEFAULT SYSDATETIME(),
    CONSTRAINT [JVLine_pkey] PRIMARY KEY CLUSTERED ([id])
    CONSTRAINT [FK_JVLine_voucher] FOREIGN KEY ([voucherId]) REFERENCES [dbo].[JV]([id]) ON DELETE CASCADE
);

-- CreateTable OpenTB
CREATE TABLE [dbo].[OpenTB] (
    [id] NVARCHAR(50) NOT NULL,
    [voucherType] NVARCHAR(10) NOT NULL CONSTRAINT [OpenTB_voucherType_df] DEFAULT 'OTV',
    [voucherDate] DATETIME2 NOT NULL,
    [branchId] NVARCHAR(50) NOT NULL,
    [description] NVARCHAR(max),
    [reference] NVARCHAR(255),
    [totalDebit] FLOAT NOT NULL CONSTRAINT [OpenTB_totalDebit_df] DEFAULT 0,
    [totalCredit] FLOAT NOT NULL CONSTRAINT [OpenTB_totalCredit_df] DEFAULT 0,
    [difference] FLOAT NOT NULL CONSTRAINT [OpenTB_difference_df] DEFAULT 0,
    [isBalanced] BIT NOT NULL CONSTRAINT [OpenTB_isBalanced_df] DEFAULT 0,
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [OpenTB_status_df] DEFAULT 'Posted',
    [reversedById] NVARCHAR(50),
    [reversedAt] DATETIME2,
    [reversalReason] NVARCHAR(255),
    [postedById] NVARCHAR(50),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [OpenTB_createdAt_df] DEFAULT SYSDATETIME(),
    [updatedAt] DATETIME2 NOT NULL CONSTRAINT [OpenTB_updatedAt_df] DEFAULT SYSDATETIME(),
    CONSTRAINT [OpenTB_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable OpenTBLine
CREATE TABLE [dbo].[OpenTBLine] (
    [id] NVARCHAR(50) NOT NULL,
    [voucherId] NVARCHAR(50) NOT NULL,
    [accountId] NVARCHAR(50) NOT NULL,
    [debit] FLOAT NOT NULL CONSTRAINT [OpenTBLine_debit_df] DEFAULT 0,
    [credit] FLOAT NOT NULL CONSTRAINT [OpenTBLine_credit_df] DEFAULT 0,
    [amount] FLOAT NOT NULL CONSTRAINT [OpenTBLine_amount_df] DEFAULT 0,
    [lineDescription] NVARCHAR(255),
    [reference] NVARCHAR(255),
    [status] NVARCHAR(255) NOT NULL CONSTRAINT [OpenTBLine_status_df] DEFAULT 'Active',
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [OpenTBLine_createdAt_df] DEFAULT SYSDATETIME(),
    CONSTRAINT [OpenTBLine_pkey] PRIMARY KEY CLUSTERED ([id])
    CONSTRAINT [FK_OpenTBLine_voucher] FOREIGN KEY ([voucherId]) REFERENCES [dbo].[OpenTB]([id]) ON DELETE CASCADE
);

-- CreateTable KnockOff
CREATE TABLE [dbo].[KnockOff] (
    [id] NVARCHAR(50) NOT NULL,
    [billId] NVARCHAR(50) NOT NULL,
    [billNumber] NVARCHAR(255),
    [referenceNumber] NVARCHAR(255),
    [billType] NVARCHAR(255),
    [amount] FLOAT NOT NULL,
    [dcFlag] NVARCHAR(10) NOT NULL CONSTRAINT [KnockOff_dcFlag_df] DEFAULT 'Debit',
    [referenceDate] DATETIME2,
    [dueDate] DATETIME2,
    [description] NVARCHAR(20),
    [accountId] NVARCHAR(50) NOT NULL,
    [branchId] NVARCHAR(50) NOT NULL,
    [createdById] NVARCHAR(50),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [KnockOff_createdAt_df] DEFAULT SYSDATETIME(),
    [updatedAt] DATETIME2 NOT NULL CONSTRAINT [KnockOff_updatedAt_df] DEFAULT SYSDATETIME(),
    CONSTRAINT [KnockOff_pkey] PRIMARY KEY CLUSTERED ([id])
    CONSTRAINT [UQ_KnockOff_billId] UNIQUE NONCLUSTERED ([billId])
    CONSTRAINT [FK_KnockOff_chart] FOREIGN KEY ([accountId]) REFERENCES [dbo].[charts]([id]) ON DELETE NO ACTION
);

-- CreateTable AccountMapping
CREATE TABLE [dbo].[AccountMapping] (
    [id] NVARCHAR(50) NOT NULL,
    [branchId] NVARCHAR(50),
    [key] NVARCHAR(255) NOT NULL,
    [accountId] NVARCHAR(50) NOT NULL,
    [description] NVARCHAR(max),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [AccountMapping_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [AccountMapping_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable FinanceDefaults
CREATE TABLE [dbo].[FinanceDefaults] (
    [id] NVARCHAR(50) NOT NULL,
    [branchId] NVARCHAR(50),
    [defaultCashAccountId] NVARCHAR(50),
    [defaultBankAccountId] NVARCHAR(50),
    [defaultTaxHeadId] NVARCHAR(50),
    [financialYearId] NVARCHAR(50),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [FinanceDefaults_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [FinanceDefaults_pkey] PRIMARY KEY CLUSTERED ([id])
    CONSTRAINT [FinanceDefaults_branchId_key] UNIQUE NONCLUSTERED ([branchId])
);

-- CreateTable UserReportFormat
CREATE TABLE [dbo].[UserReportFormat] (
    [id] NVARCHAR(50) NOT NULL,
    [userId] NVARCHAR(50) NOT NULL,
    [reportKey] NVARCHAR(255) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [columns] NVARCHAR(255) NOT NULL,
    [isDefault] BIT NOT NULL CONSTRAINT [UserReportFormat_isDefault_df] DEFAULT 0,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [UserReportFormat_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [UserReportFormat_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable MembershipPlan
CREATE TABLE [dbo].[MembershipPlan] (
    [id] NVARCHAR(50) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [durationDays] INT NOT NULL,
    [amount] FLOAT(53) NOT NULL,
    [description] NVARCHAR(max),
    [isActive] BIT NOT NULL CONSTRAINT [MembershipPlan_isActive_df] DEFAULT 1,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [MembershipPlan_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    [branchId] NVARCHAR(50) NOT NULL,
    CONSTRAINT [MembershipPlan_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable Member
CREATE TABLE [dbo].[Member] (
    [id] NVARCHAR(50) NOT NULL,
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
    [deletedAt] DATETIME2,
    CONSTRAINT [Member_pkey] PRIMARY KEY CLUSTERED ([id])
    CONSTRAINT [Member_membershipPlanId_fkey] FOREIGN KEY ([membershipPlanId]) REFERENCES [dbo].[MembershipPlan]([id]) ON DELETE NO ACTION
    CONSTRAINT [Member_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION
);

-- CreateTable Attendance
CREATE TABLE [dbo].[Attendance] (
    [id] NVARCHAR(50) NOT NULL,
    [memberId] NVARCHAR(50) NOT NULL,
    [branchId] NVARCHAR(50) NOT NULL,
    [date] DATETIME2 NOT NULL,
    [checkIn] DATETIME2,
    [checkOut] DATETIME2,
    [notes] NVARCHAR(max),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Attendance_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [Attendance_pkey] PRIMARY KEY CLUSTERED ([id])
    CONSTRAINT [Attendance_memberId_fkey] FOREIGN KEY ([memberId]) REFERENCES [dbo].[Member]([id]) ON DELETE NO ACTION
    CONSTRAINT [Attendance_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION
);

-- CreateTable Fee
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
    CONSTRAINT [Fee_memberId_fkey] FOREIGN KEY ([memberId]) REFERENCES [dbo].[Member]([id]) ON DELETE NO ACTION
    CONSTRAINT [Fee_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION
);

-- CreateTable FeePayment
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
    CONSTRAINT [FeePayment_feeId_fkey] FOREIGN KEY ([feeId]) REFERENCES [dbo].[Fee]([id]) ON DELETE NO ACTION
);

-- CreateTable MembershipFreeze
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
    CONSTRAINT [MembershipFreeze_memberId_fkey] FOREIGN KEY ([memberId]) REFERENCES [dbo].[Member]([id]) ON DELETE NO ACTION
    CONSTRAINT [MembershipFreeze_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION
);

-- CreateTable Prospect
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
    [notes] NVARCHAR(max),
    [convertedMemberId] NVARCHAR(50),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Prospect_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [Prospect_pkey] PRIMARY KEY CLUSTERED ([id])
    CONSTRAINT [Prospect_preferredBranchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION
);

-- CreateTable FollowUp
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
    CONSTRAINT [FollowUp_memberId_fkey] FOREIGN KEY ([memberId]) REFERENCES [dbo].[Member]([id]) ON DELETE NO ACTION
    CONSTRAINT [FollowUp_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION
);

-- CreateTable ProgressEntry
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
    CONSTRAINT [ProgressEntry_memberId_fkey] FOREIGN KEY ([memberId]) REFERENCES [dbo].[Member]([id]) ON DELETE NO ACTION
);

-- CreateTable Exercise
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
    CONSTRAINT [Exercise_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION
);

-- CreateTable Equipment
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
    CONSTRAINT [Equipment_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION
);

-- CreateTable EquipmentMaintenance
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
    CONSTRAINT [EquipmentMaintenance_equipmentId_fkey] FOREIGN KEY ([equipmentId]) REFERENCES [dbo].[Equipment]([id]) ON DELETE NO ACTION
);

-- CreateTable FoodItem
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
    CONSTRAINT [FoodItem_pkey] PRIMARY KEY CLUSTERED ([id])
    CONSTRAINT [FoodItem_code_key] UNIQUE NONCLUSTERED ([code])
);

-- CreateTable WorkoutPlan
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
    CONSTRAINT [WorkoutPlan_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION
);

-- CreateTable WorkoutDay
CREATE TABLE [dbo].[WorkoutDay] (
    [id] NVARCHAR(50) NOT NULL,
    [planId] NVARCHAR(50) NOT NULL,
    [dayName] NVARCHAR(255) NOT NULL,
    [notes] NVARCHAR(max),
    CONSTRAINT [WorkoutDay_pkey] PRIMARY KEY CLUSTERED ([id])
    CONSTRAINT [WorkoutDay_planId_fkey] FOREIGN KEY ([planId]) REFERENCES [dbo].[WorkoutPlan]([id]) ON DELETE NO ACTION
);

-- CreateTable WorkoutDayExercise
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
    CONSTRAINT [WorkoutDayExercise_dayId_fkey] FOREIGN KEY ([dayId]) REFERENCES [dbo].[WorkoutDay]([id]) ON DELETE NO ACTION
    CONSTRAINT [WorkoutDayExercise_exerciseId_fkey] FOREIGN KEY ([exerciseId]) REFERENCES [dbo].[Exercise]([id]) ON DELETE NO ACTION
);

-- CreateTable WorkoutAssignment
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
    CONSTRAINT [WorkoutAssignment_memberId_fkey] FOREIGN KEY ([memberId]) REFERENCES [dbo].[Member]([id]) ON DELETE NO ACTION
    CONSTRAINT [WorkoutAssignment_planId_fkey] FOREIGN KEY ([planId]) REFERENCES [dbo].[WorkoutPlan]([id]) ON DELETE NO ACTION
);

-- CreateTable DietPlan
CREATE TABLE [dbo].[DietPlan] (
    [id] NVARCHAR(50) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [description] NVARCHAR(max),
    [branchId] NVARCHAR(50),
    [isActive] BIT NOT NULL CONSTRAINT [DietPlan_isActive_df] DEFAULT 1,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [DietPlan_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [DietPlan_pkey] PRIMARY KEY CLUSTERED ([id])
    CONSTRAINT [DietPlan_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION
);

-- CreateTable DietMeal
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
    CONSTRAINT [DietMeal_planId_fkey] FOREIGN KEY ([planId]) REFERENCES [dbo].[DietPlan]([id]) ON DELETE NO ACTION
);

-- CreateTable DietAssignment
CREATE TABLE [dbo].[DietAssignment] (
    [id] NVARCHAR(50) NOT NULL,
    [memberId] NVARCHAR(50) NOT NULL,
    [planId] NVARCHAR(50) NOT NULL,
    [startDate] DATETIME2 NOT NULL CONSTRAINT [DietAssignment_startDate_df] DEFAULT CURRENT_TIMESTAMP,
    [endDate] DATETIME2,
    [notes] NVARCHAR(max),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [DietAssignment_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [DietAssignment_pkey] PRIMARY KEY CLUSTERED ([id])
    CONSTRAINT [DietAssignment_memberId_fkey] FOREIGN KEY ([memberId]) REFERENCES [dbo].[Member]([id]) ON DELETE NO ACTION
    CONSTRAINT [DietAssignment_planId_fkey] FOREIGN KEY ([planId]) REFERENCES [dbo].[DietPlan]([id]) ON DELETE NO ACTION
);

-- CreateTable gymmasterfile
CREATE TABLE [dbo].[gymmasterfile] (
    [id] NVARCHAR(50) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [level] INT NOT NULL,
    [parentCode] NVARCHAR(50),
    [branchId] NVARCHAR(50),
    [description] NVARCHAR(max),
    [isActive] BIT NOT NULL CONSTRAINT [gymmasterfile_isActive_df] DEFAULT 1,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [gymmasterfile_createdAt_df] DEFAULT SYSDATETIME(),
    [updatedAt] DATETIME2 NOT NULL CONSTRAINT [gymmasterfile_updatedAt_df] DEFAULT SYSDATETIME(),
    CONSTRAINT [gymmasterfile_pkey] PRIMARY KEY CLUSTERED ([id])
    CONSTRAINT [FK_gymmasterfile_parent] FOREIGN KEY ([parentCode]) REFERENCES [dbo].[gymmasterfile]([id]) ON DELETE NO ACTION
);

-- CreateTable FitnessGoal
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
    CONSTRAINT [FitnessGoal_memberId_fkey] FOREIGN KEY ([memberId]) REFERENCES [dbo].[Member]([id]) ON DELETE NO ACTION
);

-- CreateTable PersonalTrainingSession
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
    CONSTRAINT [PersonalTrainingSession_memberId_fkey] FOREIGN KEY ([memberId]) REFERENCES [dbo].[Member]([id]) ON DELETE NO ACTION
    CONSTRAINT [PersonalTrainingSession_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION
);

-- CreateTable TrainerAvailability
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
    CONSTRAINT [TrainerAvailability_staffId_fkey] FOREIGN KEY ([staffId]) REFERENCES [dbo].[Staff]([id]) ON DELETE NO ACTION
    CONSTRAINT [TrainerAvailability_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION
);

-- CreateTable TrainerSchedule
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
    CONSTRAINT [TrainerSchedule_staffId_fkey] FOREIGN KEY ([staffId]) REFERENCES [dbo].[Staff]([id]) ON DELETE NO ACTION
    CONSTRAINT [TrainerSchedule_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION
);

-- CreateTable InventoryItem
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
    CONSTRAINT [InventoryItem_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION
);

-- CreateTable PosSale
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
    [notes] NVARCHAR(max),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [PosSale_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [PosSale_pkey] PRIMARY KEY CLUSTERED ([id])
    CONSTRAINT [PosSale_saleNo_key] UNIQUE NONCLUSTERED ([saleNo])
    CONSTRAINT [PosSale_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION
);

-- CreateTable PosSaleLine
CREATE TABLE [dbo].[PosSaleLine] (
    [id] NVARCHAR(50) NOT NULL,
    [saleId] NVARCHAR(50) NOT NULL,
    [inventoryItemId] NVARCHAR(50) NOT NULL,
    [quantity] INT NOT NULL,
    [unitPrice] FLOAT(53) NOT NULL,
    [amount] FLOAT(53) NOT NULL,
    CONSTRAINT [PosSaleLine_pkey] PRIMARY KEY CLUSTERED ([id])
    CONSTRAINT [PosSaleLine_saleId_fkey] FOREIGN KEY ([saleId]) REFERENCES [dbo].[PosSale]([id]) ON DELETE NO ACTION
    CONSTRAINT [PosSaleLine_inventoryItemId_fkey] FOREIGN KEY ([inventoryItemId]) REFERENCES [dbo].[InventoryItem]([id]) ON DELETE NO ACTION
);

-- CreateTable Supplier
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
    CONSTRAINT [Supplier_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION
);

-- CreateTable Purchase
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
    CONSTRAINT [Purchase_pkey] PRIMARY KEY CLUSTERED ([id])
    CONSTRAINT [Purchase_purchaseNo_key] UNIQUE NONCLUSTERED ([purchaseNo])
    CONSTRAINT [Purchase_supplierId_fkey] FOREIGN KEY ([supplierId]) REFERENCES [dbo].[Supplier]([id]) ON DELETE NO ACTION
    CONSTRAINT [Purchase_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION
);

-- CreateTable PurchaseLine
CREATE TABLE [dbo].[PurchaseLine] (
    [id] NVARCHAR(50) NOT NULL,
    [purchaseId] NVARCHAR(50) NOT NULL,
    [inventoryItemId] NVARCHAR(50),
    [itemName] NVARCHAR(255) NOT NULL,
    [quantity] INT NOT NULL CONSTRAINT [PurchaseLine_quantity_df] DEFAULT 0,
    [unitPrice] FLOAT(53) NOT NULL CONSTRAINT [PurchaseLine_unitPrice_df] DEFAULT 0,
    [amount] FLOAT(53) NOT NULL CONSTRAINT [PurchaseLine_amount_df] DEFAULT 0,
    CONSTRAINT [PurchaseLine_pkey] PRIMARY KEY CLUSTERED ([id])
    CONSTRAINT [PurchaseLine_purchaseId_fkey] FOREIGN KEY ([purchaseId]) REFERENCES [dbo].[Purchase]([id]) ON DELETE NO ACTION
    CONSTRAINT [PurchaseLine_inventoryItemId_fkey] FOREIGN KEY ([inventoryItemId]) REFERENCES [dbo].[InventoryItem]([id]) ON DELETE NO ACTION
);

-- CreateTable StockMovement
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
    CONSTRAINT [StockMovement_inventoryItemId_fkey] FOREIGN KEY ([inventoryItemId]) REFERENCES [dbo].[InventoryItem]([id]) ON DELETE NO ACTION
    CONSTRAINT [StockMovement_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION
);

-- CreateTable CalendarDay
CREATE TABLE [dbo].[CalendarDay] (
    [id] NVARCHAR(50) NOT NULL,
    [date] DATETIME2 NOT NULL,
    [branchId] NVARCHAR(50),
    [dayType] NVARCHAR(255) NOT NULL,
    [notes] NVARCHAR(max),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [CalendarDay_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [CalendarDay_pkey] PRIMARY KEY CLUSTERED ([id])
    CONSTRAINT [CalendarDay_date_key] UNIQUE NONCLUSTERED ([date])
    CONSTRAINT [CalendarDay_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION
);

-- CreateTable Shift
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
    CONSTRAINT [Shift_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION
);

-- CreateTable Allowance
CREATE TABLE [dbo].[Allowance] (
    [id] NVARCHAR(50) NOT NULL,
    [name] NVARCHAR(191) NOT NULL,
    [description] NVARCHAR(max),
    [isStatutory] BIT NOT NULL CONSTRAINT [Allowance_isStatutory_df] DEFAULT 0,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Allowance_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [Allowance_pkey] PRIMARY KEY CLUSTERED ([id])
    CONSTRAINT [Allowance_name_key] UNIQUE NONCLUSTERED ([name])
);

-- CreateTable Staff
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
    CONSTRAINT [Staff_pkey] PRIMARY KEY CLUSTERED ([id])
    CONSTRAINT [Staff_employeeId_key] UNIQUE NONCLUSTERED ([employeeId])
    CONSTRAINT [Staff_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION
    CONSTRAINT [Staff_shiftId_fkey] FOREIGN KEY ([shiftId]) REFERENCES [dbo].[Shift]([id]) ON DELETE NO ACTION
);

-- CreateTable StaffDocument
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
    CONSTRAINT [StaffDocument_staffId_fkey] FOREIGN KEY ([staffId]) REFERENCES [dbo].[Staff]([id]) ON DELETE NO ACTION
);

-- CreateTable Overtime
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
    CONSTRAINT [Overtime_staffId_fkey] FOREIGN KEY ([staffId]) REFERENCES [dbo].[Staff]([id]) ON DELETE NO ACTION
);

-- CreateTable Leave
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
    [branchId] NVARCHAR(50) NOT NULL,
    CONSTRAINT [Leave_pkey] PRIMARY KEY CLUSTERED ([id])
    CONSTRAINT [Leave_staffId_fkey] FOREIGN KEY ([staffId]) REFERENCES [dbo].[Staff]([id]) ON DELETE NO ACTION
);

-- CreateTable payrollmasterfile
CREATE TABLE [dbo].[payrollmasterfile] (
    [id] NVARCHAR(50) NOT NULL,
    [masterType] NVARCHAR(255) NOT NULL,
    [name] NVARCHAR(255) NOT NULL,
    [description] NVARCHAR(max),
    [extra] NVARCHAR(255),
    [branchId] NVARCHAR(50),
    [isActive] BIT NOT NULL CONSTRAINT [payrollmasterfile_isActive_df] DEFAULT 1,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [payrollmasterfile_createdAt_df] DEFAULT SYSDATETIME(),
    [updatedAt] DATETIME2 NOT NULL CONSTRAINT [payrollmasterfile_updatedAt_df] DEFAULT SYSDATETIME(),
    CONSTRAINT [payrollmasterfile_pkey] PRIMARY KEY CLUSTERED ([id])
    CONSTRAINT [UQ_payrollmasterfile_type_name] UNIQUE NONCLUSTERED ([masterType], [name])
    CONSTRAINT [FK_payrollmasterfile_branch] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION
);

-- CreateTable Payroll
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
    CONSTRAINT [Payroll_pkey] PRIMARY KEY CLUSTERED ([id])
    CONSTRAINT [Payroll_payrollNo_key] UNIQUE NONCLUSTERED ([payrollNo])
    CONSTRAINT [Payroll_staffId_fkey] FOREIGN KEY ([staffId]) REFERENCES [dbo].[Staff]([id]) ON DELETE NO ACTION
    CONSTRAINT [Payroll_branchId_fkey] FOREIGN KEY ([branchId]) REFERENCES [dbo].[Branch]([id]) ON DELETE NO ACTION
);

-- CreateTable MasterFile
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
    CONSTRAINT [MasterFile_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable UserPermission
CREATE TABLE [dbo].[UserPermission] (
    [id] NVARCHAR(50) NOT NULL,
    [userId] NVARCHAR(50) NOT NULL,
    [screenKey] NVARCHAR(255) NOT NULL,
    [canView] BIT NOT NULL CONSTRAINT [UserPermission_canView_df] DEFAULT 0,
    [canAdd] BIT NOT NULL CONSTRAINT [UserPermission_canAdd_df] DEFAULT 0,
    [canEdit] BIT NOT NULL CONSTRAINT [UserPermission_canEdit_df] DEFAULT 0,
    [canDelete] BIT NOT NULL CONSTRAINT [UserPermission_canDelete_df] DEFAULT 0,
    [canPrint] BIT NOT NULL CONSTRAINT [UserPermission_canPrint_df] DEFAULT 0,
    CONSTRAINT [UserPermission_pkey] PRIMARY KEY CLUSTERED ([id])
    CONSTRAINT [UQ_UserPermission_user_screen] UNIQUE NONCLUSTERED ([userId], [screenKey])
    CONSTRAINT [FK_UserPermission_user] FOREIGN KEY ([userId]) REFERENCES [dbo].[User]([id]) ON DELETE CASCADE
);

COMMIT TRAN;
END TRY
BEGIN CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRAN;
THROW;
END CATCH
GO

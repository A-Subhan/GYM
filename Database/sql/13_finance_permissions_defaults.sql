/* ============================================================================
   CONTOURA LABS — GYM MANAGEMENT SYSTEM
   FINANCE & ACCOUNTING MODULE — PERMISSIONS, DEFAULTS & SEED DATA
   (13_finance_permissions_defaults.sql)
   ----------------------------------------------------------------------------
   Idempotent + non-destructive. Run AFTER 12_finance_procedures.sql.

   - Adds the new finance.* permissions (post/reverse/periods/reconcile/
     settings/coa/reports) idempotently and grants them to Owner + Accountant
     (finance.reports also to Manager). Super Admin bypasses all checks.
   - Seeds the COA level structure [1,2,2,3] (4 levels / 8 digits) — the
     client can reconfigure it in Finance Defaults while no accounts conflict.
   - Seeds a starter gym Chart of Accounts (only when Accounts is empty).
   - Seeds the six voucher types (CRV/CPV/BRV/BPV/JPV/OPB).
   - Seeds the FY 2026 financial year + 12 monthly periods (when missing).
   - Seeds Finance settings (company / accounting / numbering / reports).
   - Seeds source → account mappings for future module integrations.
   ============================================================================ */

/* No USE statement — run against the target database (GymDB_Test or GymDB). */
GO

/* ================================================================== */
/* 1. PERMISSIONS                                                     */
/* ================================================================== */

/* Permissions.Code may be a computed persisted column (fresh schema) or a
   stored column (older installs) — insert accordingly. */
IF COLUMNPROPERTY(OBJECT_ID('dbo.Permissions'), 'Code', 'IsComputed') = 1
BEGIN
    INSERT INTO dbo.Permissions (Module, Action, Description)
    SELECT 'finance', a.Action, a.[Description]
    FROM (VALUES
        ('post',      'Post vouchers (journal, cash, bank, opening)'),
        ('reverse',   'Reverse posted vouchers'),
        ('periods',   'Manage financial years and accounting periods'),
        ('reconcile', 'Perform bank reconciliation'),
        ('settings',  'Manage finance settings, defaults and mappings'),
        ('coa',       'Manage the chart of accounts'),
        ('reports',   'Run finance reports (ledger, trial balance, statements, aging)')
    ) a(Action, [Description])
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Permissions p
                      WHERE p.Module = 'finance' AND p.Action = a.Action);
END
ELSE
BEGIN
    /* dynamic SQL so this branch only binds at runtime (Code may be computed) */
    EXEC sp_executesql N'
    INSERT INTO dbo.Permissions (Module, Action, Code, Description)
    SELECT ''finance'', a.Action, ''finance.'' + a.Action, a.[Description]
    FROM (VALUES
        (''post'',      ''Post vouchers (journal, cash, bank, opening)''),
        (''reverse'',   ''Reverse posted vouchers''),
        (''periods'',   ''Manage financial years and accounting periods''),
        (''reconcile'', ''Perform bank reconciliation''),
        (''settings'',  ''Manage finance settings, defaults and mappings''),
        (''coa'',       ''Manage the chart of accounts''),
        (''reports'',   ''Run finance reports (ledger, trial balance, statements, aging)'')
    ) a(Action, [Description])
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Permissions p
                      WHERE p.Module = ''finance'' AND p.Action = a.Action);';
END
GO

/* Owner (2) + Accountant (6): all new finance actions */
INSERT INTO dbo.RolePermissions (RoleID, PermissionID)
SELECT r.RoleID, p.PermissionID
FROM (VALUES (2), (6)) AS r(RoleID)
JOIN dbo.Permissions p ON p.Module = 'finance'
     AND p.Action IN ('post','reverse','periods','reconcile','settings','coa','reports')
WHERE NOT EXISTS (SELECT 1 FROM dbo.RolePermissions x
                  WHERE x.RoleID = r.RoleID AND x.PermissionID = p.PermissionID);
GO

/* Manager (3): finance reports (already holds finance.view/add/edit/delete/export) */
INSERT INTO dbo.RolePermissions (RoleID, PermissionID)
SELECT 3, p.PermissionID
FROM dbo.Permissions p
WHERE p.Module = 'finance' AND p.Action = 'reports'
  AND NOT EXISTS (SELECT 1 FROM dbo.RolePermissions x
                  WHERE x.RoleID = 3 AND x.PermissionID = p.PermissionID);
GO

/* ================================================================== */
/* 2. COA STRUCTURE (default: 4 levels, digits 1+2+2+3 = 8)           */
/* ================================================================== */

IF NOT EXISTS (SELECT 1 FROM dbo.FinanceCoaLevels)
BEGIN
    INSERT INTO dbo.FinanceCoaLevels (LevelNo, Digits) VALUES (1, 1), (2, 2), (3, 2), (4, 3);
    PRINT 'COA level structure seeded: [1,2,2,3] (4 levels, 8 digits).';
END
GO

/* ================================================================== */
/* 3. VOUCHER TYPES                                                   */
/* ================================================================== */

INSERT INTO dbo.VoucherTypes (TypeCode, Title, Prefix, PrefixLocked, TenderTag, Nature)
SELECT v.TypeCode, v.Title, v.Prefix, 0, v.TenderTag, v.Nature
FROM (VALUES
    ('CRV', 'Cash Receipt Voucher',  'CRV', 'Cash', 'Receipt'),
    ('CPV', 'Cash Payment Voucher',  'CPV', 'Cash', 'Payment'),
    ('BRV', 'Bank Receipt Voucher',  'BRV', 'Bank', 'Receipt'),
    ('BPV', 'Bank Payment Voucher',  'BPV', 'Bank', 'Payment'),
    ('JPV', 'Journal Voucher',       'JPV', NULL,   'Journal'),
    ('OPB', 'Opening Trial Balance', 'OPB', NULL,   'Opening')
) v(TypeCode, Title, Prefix, TenderTag, Nature)
WHERE NOT EXISTS (SELECT 1 FROM dbo.VoucherTypes t WHERE t.TypeCode = v.TypeCode);
GO

/* ================================================================== */
/* 4. FINANCIAL YEAR (FY 2026 + 12 monthly periods)                   */
/* ================================================================== */

IF NOT EXISTS (SELECT 1 FROM dbo.FinancialYears
               WHERE '20260101' BETWEEN StartDate AND EndDate)
BEGIN
    EXEC dbo.sp_FinanceYears_Create @Name = 'FY 2026', @StartDate = '2026-01-01', @EndDate = '2026-12-31', @CreatedBy = 1;
    PRINT 'Financial year FY 2026 created with 12 monthly periods.';
END
GO

/* ================================================================== */
/* 5. STARTER CHART OF ACCOUNTS (only when Accounts is empty)         */
/*    Structure: 1|01|01|001 — client can rebuild before go-live.     */
/* ================================================================== */

IF NOT EXISTS (SELECT 1 FROM dbo.Accounts)
BEGIN
    /* ---- Level 1 (1 digit) ---- */
    INSERT INTO dbo.Accounts (Code, Title, AccountType, ParentAccountID, LevelNo, IsControl)
    VALUES
        ('1', 'Assets',     'Asset',     NULL, 1, 1),
        ('2', 'Liabilities','Liability', NULL, 1, 1),
        ('3', 'Capital',    'Capital',   NULL, 1, 1),
        ('4', 'Revenue',    'Revenue',   NULL, 1, 1),
        ('5', 'Expense',    'Expense',   NULL, 1, 1);

    /* ---- Level 2 (2 digits) ---- */
    INSERT INTO dbo.Accounts (Code, Title, AccountType, ParentAccountID, LevelNo, IsControl)
    SELECT v.Code, v.Title, v.Type, p.AccountID, 2, 1
    FROM (VALUES
        ('101', 'Current Assets',     'Asset',     '1'),
        ('102', 'Non-Current Assets', 'Asset',     '1'),
        ('201', 'Current Liabilities','Liability', '2'),
        ('202', 'Non-Current Liabilities', 'Liability', '2'),
        ('301', 'Owner''s Equity',    'Capital',   '3'),
        ('302', 'Retained Earnings',  'Capital',   '3'),
        ('401', 'Membership Revenue', 'Revenue',   '4'),
        ('402', 'Other Revenue',      'Revenue',   '4'),
        ('501', 'Administration Expense', 'Expense', '5'),
        ('502', 'Operating Expense',  'Expense',   '5')
    ) v(Code, Title, Type, ParentCode)
    JOIN dbo.Accounts p ON p.Code = v.ParentCode
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Accounts a WHERE a.Code = v.Code);

    /* ---- Level 3 (2 digits) ---- */
    INSERT INTO dbo.Accounts (Code, Title, AccountType, ParentAccountID, LevelNo, IsControl)
    SELECT v.Code, v.Title, v.Type, p.AccountID, 3, 1
    FROM (VALUES
        ('10101', 'Accounts Receivable', 'Asset', '101'),
        ('10102', 'Cash',                'Asset', '101'),
        ('10103', 'Banks',               'Asset', '101'),
        ('10104', 'Inventory',           'Asset', '101'),
        ('10105', 'Prepaid Expenses',    'Asset', '101'),
        ('10201', 'Fixed Assets',        'Asset', '102'),
        ('20101', 'Accounts Payable',    'Liability', '201'),
        ('20102', 'Tax Payable',         'Liability', '201'),
        ('20103', 'Staff Payables',      'Liability', '201'),
        ('20201', 'Long Term Loans',     'Liability', '202'),
        ('30101', 'Owner Capital',       'Capital',   '301'),
        ('30201', 'Retained Earnings',   'Capital',   '302'),
        ('40101', 'Membership Fees',     'Revenue',   '401'),
        ('40201', 'Personal Training',   'Revenue',   '402'),
        ('40202', 'Product Sales',       'Revenue',   '402'),
        ('40203', 'Other Income',        'Revenue',   '402'),
        ('50101', 'Payroll Expenses',    'Expense',   '501'),
        ('50102', 'Office Expenses',     'Expense',   '501'),
        ('50103', 'Utilities',           'Expense',   '501'),
        ('50201', 'Facility Expenses',   'Expense',   '502'),
        ('50202', 'Marketing',           'Expense',   '502')
    ) v(Code, Title, Type, ParentCode)
    JOIN dbo.Accounts p ON p.Code = v.ParentCode
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Accounts a WHERE a.Code = v.Code);

    /* ---- Level 4 (3 digits) — Detail (posting) accounts ---- */
    INSERT INTO dbo.Accounts (Code, Title, AccountType, ParentAccountID, LevelNo, IsControl)
    SELECT v.Code, v.Title, v.Type, p.AccountID, 4, 0
    FROM (VALUES
        ('10101001', 'Accounts Receivable — Trade',   'Asset',     '10101'),
        ('10102001', 'Cash in Hand',                  'Asset',     '10102'),
        ('10103001', 'Meezan Bank — Current',         'Asset',     '10103'),
        ('10103002', 'JazzCash Wallet',               'Asset',     '10103'),
        ('10104001', 'Inventory — Supplements',       'Asset',     '10104'),
        ('10105001', 'Prepaid Rent',                  'Asset',     '10105'),
        ('10201001', 'Gym Equipment',                 'Asset',     '10201'),
        ('10201002', 'Building & Improvements',       'Asset',     '10201'),
        ('20101001', 'Accounts Payable — Trade',      'Liability', '20101'),
        ('20102001', 'Sales Tax Payable',             'Liability', '20102'),
        ('20103001', 'Staff Salaries Payable',        'Liability', '20103'),
        ('20201001', 'Bank Loan — Long Term',         'Liability', '20201'),
        ('30101001', 'Owner''s Capital Account',      'Capital',   '30101'),
        ('30201001', 'Retained Earnings Account',     'Capital',   '30201'),
        ('40101001', 'Membership Fees Income',        'Revenue',   '40101'),
        ('40101002', 'Joining Fees Income',           'Revenue',   '40101'),
        ('40201001', 'Personal Training Income',      'Revenue',   '40201'),
        ('40202001', 'Supplement Sales Income',       'Revenue',   '40202'),
        ('40203001', 'Miscellaneous Income',          'Revenue',   '40203'),
        ('50101001', 'Salaries Expense',              'Expense',   '50101'),
        ('50101002', 'Staff Welfare Expense',         'Expense',   '50101'),
        ('50102001', 'Stationery & Printing',         'Expense',   '50102'),
        ('50102002', 'Internet & Phone',              'Expense',   '50102'),
        ('50102003', 'Miscellaneous Expense',         'Expense',   '50102'),
        ('50103001', 'Electricity Expense',           'Expense',   '50103'),
        ('50103002', 'Water Expense',                 'Expense',   '50103'),
        ('50201001', 'Rent Expense',                  'Expense',   '50201'),
        ('50201002', 'Repairs & Maintenance',         'Expense',   '50201'),
        ('50202001', 'Advertising Expense',           'Expense',   '50202')
    ) v(Code, Title, Type, ParentCode)
    JOIN dbo.Accounts p ON p.Code = v.ParentCode
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Accounts a WHERE a.Code = v.Code);

    /* ---- Account tags ---- */
    INSERT INTO dbo.AccountTags (AccountID, Tag)
    SELECT a.AccountID, t.Tag
    FROM (VALUES
        ('10101001', 'Customer'),
        ('10102001', 'Cash'),
        ('10103001', 'Bank'),
        ('10103002', 'Bank'),
        ('20101001', 'Vendor'),
        ('20102001', 'Tax'),
        ('20103001', 'Employee'),
        ('30201001', 'Capital')
    ) t(Code, Tag)
    JOIN dbo.Accounts a ON a.Code = t.Code
    WHERE NOT EXISTS (SELECT 1 FROM dbo.AccountTags x WHERE x.AccountID = a.AccountID AND x.Tag = t.Tag);

    PRINT 'Starter chart of accounts seeded.';
END
GO

/* ================================================================== */
/* 6. FINANCE SETTINGS (JSON, category = finance)                     */
/* ================================================================== */

IF NOT EXISTS (SELECT 1 FROM dbo.Settings WHERE [Key] = 'FinanceCompany')
    INSERT INTO dbo.Settings ([Key], Value, Category, UpdatedBy)
    VALUES ('FinanceCompany',
        '{"name":"Contoura Fitness","address":"Main Boulevard, Gulberg III, Lahore","phone":"+92 42 111 222 333","email":"info@contourafitness.com","website":"","ntn":"","strn":"","logoPath":"/assets/contoura-logo.svg"}',
        'finance', 1);
GO

IF NOT EXISTS (SELECT 1 FROM dbo.Settings WHERE [Key] = 'FinanceAccounting')
    INSERT INTO dbo.Settings ([Key], Value, Category, UpdatedBy)
    VALUES ('FinanceAccounting',
        '{"accountingType":"Accrual","billWise":1,"fifo":0,"roundingDigits":2,"branchAccounting":1,"fiscalYearPolicy":"CalendarYear","periodPolicy":"Monthly","defaultCurrency":"PKR","retainedEarningsAccountId":null}',
        'finance', 1);
GO

IF NOT EXISTS (SELECT 1 FROM dbo.Settings WHERE [Key] = 'FinanceVoucherNumbering')
    INSERT INTO dbo.Settings ([Key], Value, Category, UpdatedBy)
    VALUES ('FinanceVoucherNumbering', '{"dateFormat":"ddMMyyyy","seqDigits":4}', 'finance', 1);
GO

IF NOT EXISTS (SELECT 1 FROM dbo.Settings WHERE [Key] = 'FinanceReports')
    INSERT INTO dbo.Settings ([Key], Value, Category, UpdatedBy)
    VALUES ('FinanceReports',
        '{"footer":"Thank you for your business!","printCompanyInfo":1,"showLogo":1,"dateFormat":"dd-MMM-yyyy","currencyDisplay":"symbol","defaultLayout":"standard"}',
        'finance', 1);
GO

/* Point retainedEarningsAccountId at the seeded RE detail account */
DECLARE @REID INT = (SELECT AccountID FROM dbo.Accounts WHERE Code = '30201001' AND IsDeleted = 0);
IF @REID IS NOT NULL
BEGIN
    DECLARE @Acc NVARCHAR(MAX) = (SELECT Value FROM dbo.Settings WHERE [Key] = 'FinanceAccounting');
    IF @Acc IS NOT NULL AND ISNULL(TRY_CAST(JSON_VALUE(@Acc, '$.retainedEarningsAccountId') AS INT), 0) = 0
    BEGIN
        UPDATE dbo.Settings
           SET Value = JSON_MODIFY(@Acc, '$.retainedEarningsAccountId', @REID)
         WHERE [Key] = 'FinanceAccounting';
        PRINT 'Retained earnings account configured: ' + CAST(@REID AS NVARCHAR(10));
    END
END
GO

/* ================================================================== */
/* 7. SOURCE → ACCOUNT MAPPINGS (integration-ready)                   */
/* ================================================================== */

INSERT INTO dbo.FinanceMappings (MappingType, SourceKey, AccountID)
SELECT m.MappingType, m.SourceKey, a.AccountID
FROM (VALUES
    ('PaymentMethod',     '1',              '10102001'),  -- Cash
    ('PaymentMethod',     '2',              '10103001'),  -- Bank transfer
    ('PaymentMethod',     '3',              '10103001'),  -- Card
    ('PaymentMethod',     '4',              '10103002'),  -- JazzCash
    ('PaymentMethod',     '5',              '10103002'),  -- EasyPaisa
    ('IncomeCategory',    '1',              '40101001'),  -- Membership
    ('IncomeCategory',    '2',              '40201001'),  -- Personal Training
    ('IncomeCategory',    '3',              '40202001'),  -- Product Sales
    ('IncomeCategory',    '4',              '40203001'),  -- Miscellaneous
    ('ExpenseCategory',   'Salary',         '50101001'),
    ('ExpenseCategory',   'Rent',           '50201001'),
    ('ExpenseCategory',   'Electricity',    '50103001'),
    ('ExpenseCategory',   'Internet',       '50102002'),
    ('ExpenseCategory',   'Water',          '50103002'),
    ('ExpenseCategory',   'Maintenance',    '50201002'),
    ('ExpenseCategory',   'Misc',           '50102003'),
    ('Payroll',           NULL,             '50101001'),
    ('MembershipRevenue', NULL,             '40101001'),
    ('DefaultCash',       NULL,             '10102001'),
    ('DefaultBank',       NULL,             '10103001')
) m(MappingType, SourceKey, AccountCode)
JOIN dbo.Accounts a ON a.Code = m.AccountCode
WHERE NOT EXISTS (SELECT 1 FROM dbo.FinanceMappings x
                  WHERE x.MappingType = m.MappingType
                    AND ((x.SourceKey IS NULL AND m.SourceKey IS NULL) OR x.SourceKey = m.SourceKey));
GO

/* ================================================================== */
/* VERIFY                                                             */
/* ================================================================== */

SELECT 'Finance permissions' AS CheckName, COUNT(*) AS [Value]
FROM dbo.Permissions WHERE Module = 'finance'
UNION ALL SELECT 'Accounts', COUNT(*) FROM dbo.Accounts
UNION ALL SELECT 'Detail accounts', COUNT(*) FROM dbo.Accounts WHERE IsControl = 0
UNION ALL SELECT 'Account tags', COUNT(*) FROM dbo.AccountTags
UNION ALL SELECT 'Voucher types', COUNT(*) FROM dbo.VoucherTypes
UNION ALL SELECT 'Financial years', COUNT(*) FROM dbo.FinancialYears
UNION ALL SELECT 'Accounting periods', COUNT(*) FROM dbo.AccountingPeriods
UNION ALL SELECT 'Finance mappings', COUNT(*) FROM dbo.FinanceMappings;
GO

PRINT '=== 13_finance_permissions_defaults.sql applied successfully. ===';
GO

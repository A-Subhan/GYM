/* ============================================================================
   CONTOURA LABS — reset_demo_data.sql
   ----------------------------------------------------------------------------
   !!! DESTRUCTIVE — ONE-TIME, USER-APPROVED DATA RESET !!!
   Deletes ALL business data from the current database while keeping the
   schema, stored procedures, Roles / Permissions / RolePermissions and
   Branches. After running this, re-seed with:
       node scripts/run-sql.js sql/13_finance_permissions_defaults.sql <db>
       node scripts/run-sql.js sql/14_finance_rework.sql <db>
       node scripts/run-sql.js sql/15_coa_enhancement.sql <db>
       node scripts/seed-demo-data.js
   NOT part of the migration chain. Never run in a scheduled context.
   ============================================================================ */

/* ---- finance ledger + documents (strict FK order) ---- */
DELETE FROM dbo.BankReconciliationLines;
DELETE FROM dbo.BankReconciliationRuns;
DELETE FROM dbo.VoucherEntries;
DELETE FROM dbo.CashVoucherLines;
DELETE FROM dbo.CashVouchers;
DELETE FROM dbo.BankVoucherLines;
DELETE FROM dbo.BankVouchers;
DELETE FROM dbo.JournalVoucherLines;
DELETE FROM dbo.JournalVouchers;
DELETE FROM dbo.OpeningTBLines;
DELETE FROM dbo.OpeningTrialBalances;
DELETE FROM dbo.Vouchers WHERE ReversalOfVoucherID IS NOT NULL;
DELETE FROM dbo.Vouchers;
DELETE FROM dbo.AccountBalances;
DELETE FROM dbo.FinanceSequences;
DELETE FROM dbo.FinanceMappings;
DELETE FROM dbo.AccountingPeriods;
DELETE FROM dbo.FinancialYears;
DELETE FROM dbo.VoucherTypes;
DELETE FROM dbo.FinanceCoaLevels;
DELETE FROM dbo.AccountTags;
DELETE FROM dbo.Accounts WHERE LevelNo = 7;
DELETE FROM dbo.Accounts WHERE LevelNo = 6;
DELETE FROM dbo.Accounts WHERE LevelNo = 5;
DELETE FROM dbo.Accounts WHERE LevelNo = 4;
DELETE FROM dbo.Accounts WHERE LevelNo = 3;
DELETE FROM dbo.Accounts WHERE LevelNo = 2;
DELETE FROM dbo.Accounts WHERE LevelNo = 1;
DELETE FROM dbo.Accounts;
GO

/* ---- gym operations ---- */
DELETE FROM dbo.ProgressPhotos;
DELETE FROM dbo.ProgressTracking;
DELETE FROM dbo.DietPlanItems;
DELETE FROM dbo.DietPlans;
DELETE FROM dbo.WorkoutPlanItems;
DELETE FROM dbo.WorkoutPlans;
DELETE FROM dbo.Attendance;
DELETE FROM dbo.MemberDocuments;
DELETE FROM dbo.Refunds;
DELETE FROM dbo.FeeCollections;
DELETE FROM dbo.Invoices;
DELETE FROM dbo.MemberMemberships;
DELETE FROM dbo.Members;
DELETE FROM dbo.MembershipPlans;
DELETE FROM dbo.InventoryTransactions;
DELETE FROM dbo.InventoryItems;
DELETE FROM dbo.EquipmentMaintenance;
DELETE FROM dbo.Equipment;
DELETE FROM dbo.Suppliers;
GO

/* ---- staff / payroll ---- */
DELETE FROM dbo.SalarySlips;
DELETE FROM dbo.Payroll;
DELETE FROM dbo.StaffLeaves;
DELETE FROM dbo.StaffAttendance;
DELETE FROM dbo.Trainers;
DELETE FROM dbo.Staff;
DELETE FROM dbo.Departments;
GO

/* ---- master files ---- */
DELETE FROM dbo.MasterItems;
DELETE FROM dbo.MasterDefinitions;
DELETE FROM dbo.PaymentMethods;
IF OBJECT_ID('dbo.IncomeCategories', 'U') IS NOT NULL DELETE FROM dbo.IncomeCategories;
DELETE FROM dbo.TaxHeads;
GO

/* ---- users + logs (Roles / Permissions / RolePermissions / Branches KEPT) ---- */
DELETE FROM dbo.UserReportFormats;
DELETE FROM dbo.UserSessions;
DELETE FROM dbo.PasswordResets;
DELETE FROM dbo.AuditLogs;
DELETE FROM dbo.Notifications;
DELETE FROM dbo.Settings;
DELETE FROM dbo.Users;
GO

DBCC CHECKIDENT ('dbo.Vouchers', RESEED, 0);
DBCC CHECKIDENT ('dbo.VoucherEntries', RESEED, 0);
DBCC CHECKIDENT ('dbo.Users', RESEED, 0);
DBCC CHECKIDENT ('dbo.Members', RESEED, 0);
DBCC CHECKIDENT ('dbo.Staff', RESEED, 0);
DBCC CHECKIDENT ('dbo.MembershipPlans', RESEED, 0);
DBCC CHECKIDENT ('dbo.Departments', RESEED, 0);
DBCC CHECKIDENT ('dbo.PaymentMethods', RESEED, 0);
DBCC CHECKIDENT ('dbo.Trainers', RESEED, 0);
DBCC CHECKIDENT ('dbo.CashVouchers', RESEED, 0);
DBCC CHECKIDENT ('dbo.BankVouchers', RESEED, 0);
DBCC CHECKIDENT ('dbo.JournalVouchers', RESEED, 0);
DBCC CHECKIDENT ('dbo.OpeningTrialBalances', RESEED, 0);
DBCC CHECKIDENT ('dbo.TaxHeads', RESEED, 0);
GO

PRINT '=== Business data cleared. Re-seed with 13/14/15 + seed-demo-data.js ===';
GO

# GymDB Migrations — Contoura Gym ERP `module-updates`

Ordered SQL Server migration scripts for the restructured ERP (finance book
rework, business IDs, master files, branch hierarchy, removed modules).

## ⚠️ BEFORE YOU RUN ANYTHING

1. **Take a full backup first**:
   ```sql
   BACKUP DATABASE [GymDB] TO DISK = 'D:\Backups\GymDB_pre_migration.bak' WITH INIT, COMPRESSION;
   ```
2. Run scripts **in exact order 01 → 10** using `sqlcmd` or SSMS, one file at a
   time, verifying the printed `=== NN done ===` marker after each.
3. Scripts are **idempotent** — safe to re-run if one fails mid-way, but never
   skip ahead.
4. Do **not** run while the application is running (maintenance window required).

## Execution

```bash
sqlcmd -S <server> -d GymDB -i 01_rename_account_to_charts.sql -E
sqlcmd -S <server> -d GymDB -i 02_create_book_voucher_tables.sql -E
sqlcmd -S <server> -d GymDB -i 03_init_sequences.sql -E
sqlcmd -S <server> -d GymDB -i 04_migrate_vouchers.sql -E
sqlcmd -S <server> -d GymDB -i 05_charts_primary_key_and_mappings.sql -E
sqlcmd -S <server> -d GymDB -i 06_regenerate_business_ids.sql -E
sqlcmd -S <server> -d GymDB -i 07_master_files_and_leave_types.sql -E
sqlcmd -S <server> -d GymDB -i 08_branch_hierarchy.sql -E
sqlcmd -S <server> -d GymDB -i 09_drop_removed_modules.sql -E
sqlcmd -S <server> -d GymDB -i 10_views_procedures_rebuild.sql -E
```

## What each script does

| # | Script | Summary |
|---|--------|---------|
| 01 | `01_rename_account_to_charts.sql` | Renames `[Account]` → `[charts]`; adds STRN/NTN/FBR/PaymentTerms; drops OpeningBalance columns; drops dependent FKs; builds `__account_id_map` (old cuid → account code). |
| 02 | `02_create_book_voucher_tables.sql` | Creates `CashbookVoucher` (CRV/CPV), `BankbookVoucher` (BRV/BPV), `JournalVoucher` (JV), `OpenTbVoucher` (OTV — unbalanced allowed), shared `BookVoucherLine`, `KnockOff`, `IdSequence`. Voucher **id = voucher number** `{TYPE}/{branchCode}/{MMMyy}/{000001}`; reversals append `-R`. |
| 03 | `03_init_sequences.sql` | Seeds `IdSequence` counters from existing data (per branch + month) so new IDs never collide with legacy rows. |
| 04 | `04_migrate_vouchers.sql` | Migrates legacy vouchers/lines/cheques into the four book tables with regenerated voucher numbers; remaps Fee/FeePayment/PosSale/Payroll voucher references; drops `[Voucher]`, `[VoucherLine]`, old `[Cheque]`; recreates `[Cheque]` against `BankbookVoucher`. |
| 05 | `05_charts_primary_key_and_mappings.sql` | Rebuilds `[charts]` PK so **id = account code** (duplicates suffixed `-2`, `-3`…); restores hierarchy + mapping/book FKs. |
| 06 | `06_regenerate_business_ids.sql` | Regenerates business IDs: members & fees `{branch}/{MMMyy}/{00001}`, prospects `p-00001`, plans `MP-0001`, equipment `EQ-00001`. Old → new map kept in `__biz_id_map`. |
| 07 | `07_master_files_and_leave_types.sql` | Seeds universal master files (Departments, Designations, Education, Currency, Equipment, CardTypes, Banks); migrates `[LeaveType]` rows into `MasterFile('LeaveType')`; seeds `PayrollMasterFile` heads; adds `Leave.leaveNo` (backfilled `LV-0001`…) + `Leave.branchId`. |
| 08 | `08_branch_hierarchy.sql` | Adds `Branch.parentId` + `nodeType` (Control/Detail); oldest branch becomes root Control. |
| 09 | `09_drop_removed_modules.sql` | Drops `[GymClass]`, `[ClassEnrollment]`, `[FitnessAssessment]`, `[MemberDocument]`, `[LeaveType]`; purges their permission rows. Personal Training is kept. |
| 10 | `10_views_procedures_rebuild.sql` | Rebuilds views (`vw_TrialBalance`, `vw_ActiveMembers`, `vw_AttendanceLog`, `vw_OutstandingFees`, `vw_MonthlyRevenue`, `vw_PayrollRegister`, `vw_StockStatus`, new `vw_BookLedger`), procs (`sp_GetTrialBalance`, `sp_GetIncomeStatement`, `sp_GetDashboardStats`, `sp_GetMemberStatement`, `sp_CalculatePayroll`, `sp_ResetAdminPassword`), touch/audit triggers, JV balance guard; locks company name. Prints final row-count summary. |

## Post-migration checklist

- [ ] Final SELECT summary printed by script 10 shows sane counts.
- [ ] `SELECT * FROM dbo.__biz_id_map` reviewed (kept for audit; can be dropped later).
- [ ] Application login works; Defaults page shows the locked company name.
- [ ] Post one CRV and one JV voucher; confirm numbering `{TYPE}/{branch}/{MMMyy}/{000001}`.
- [ ] Leave screen shows `LV-xxxx` numbers; Branch File shows the tree.

## Rollback

Restore the backup taken before step 01. Do not attempt to hand-roll a reverse
migration — ID regeneration and voucher renumbering are one-way by design.

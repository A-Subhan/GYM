# GymDB Migrations — Contoura Gym ERP (v2, rewritten against the REAL schema)

Ordered, idempotent, transaction-protected SQL Server migration scripts for the
restructured ERP (finance books, business IDs, master files, branch hierarchy,
removed modules). **These scripts were rewritten from the real database
schema (`Database/02_schema_tables.sql`), not from `schema.prisma`.**

## ⚠️ BEFORE YOU RUN ANYTHING

1. **Take a full backup first**:
   ```sql
   BACKUP DATABASE [GymDB] TO DISK = 'D:\Backups\GymDB_pre_migration.bak' WITH INIT, COMPRESSION;
   ```
2. **Run `00_preflight_check.sql` first** — it is READ-ONLY and reports
   PRESENT / MISSING for every table and column the chain expects.
   * `MUST` + `MISSING` → stop and send the output back before continuing.
   * `OPTIONAL` + `MISSING` → fine (legacy `Voucher`/`VoucherLine`/`Cheque`/
     `LeaveType` are handled cleanly when absent).
   * `MUST-NOT` + `PRESENT` → a previous run already applied something;
     check `dbo.__MigrationHistory` or restore the backup.
3. Maintenance window required — do not run while the application is live.
4. Run scripts **in exact order 00 → 12**, one file at a time, with `sqlcmd`
   or SSMS. Every script is wrapped in a transaction and leaves the database
   **exactly as it found it** when it fails (`SET XACT_ABORT ON`).

## Execution

```bash
sqlcmd -S <server> -d GymDB -i 00_preflight_check.sql -E
sqlcmd -S <server> -d GymDB -i 01_bootstrap_history.sql -E
sqlcmd -S <server> -d GymDB -i 02_rename_account_to_charts.sql -E
sqlcmd -S <server> -d GymDB -i 03_create_book_tables.sql -E
sqlcmd -S <server> -d GymDB -i 04_migrate_legacy_vouchers.sql -E
sqlcmd -S <server> -d GymDB -i 05_charts_primary_key_rebuild.sql -E
sqlcmd -S <server> -d GymDB -i 06_init_id_sequences.sql -E
sqlcmd -S <server> -d GymDB -i 07_regenerate_gym_ids.sql -E
sqlcmd -S <server> -d GymDB -i 08_gym_masterfile_and_softdelete.sql -E
sqlcmd -S <server> -d GymDB -i 09_hr_payroll_masterfile.sql -E
sqlcmd -S <server> -d GymDB -i 10_admin_defaults_security.sql -E
sqlcmd -S <server> -d GymDB -i 11_remove_removed_modules.sql -E
sqlcmd -S <server> -d GymDB -i 12_views_procedures_rebuild.sql -E
```

## Safety model (what is different from the failed v1 scripts)

| Rule | How it is enforced |
|---|---|
| Ordering | `dbo.__MigrationHistory` — each script verifies the previous one is `Success`, else `THROW` |
| Skip re-runs | A script recorded `Success` prints *already applied, skipping* and exits |
| Failure = no change | `SET XACT_ABORT ON` + `BEGIN TRY / BEGIN TRAN / ROLLBACK + THROW` per script |
| No hardcoded constraint names | `dbo.__mig_DropColumn` looks up default/check/index/FK dependencies in the catalog and drops them dynamically |
| Key rebuilds | `dbo.__mig_StashFks` / `dbo.__mig_RestoreFks` drop and recreate FKs around data remaps |
| ID regeneration | `ROW_NUMBER` mapping tables `dbo.__idmap_<Entity>` (kept for audit) + duplicate check (`HAVING COUNT(*) > 1` → THROW) before any update |
| Legacy tables missing | `Voucher` / `VoucherLine` / `Cheque` / `LeaveType` are existence-guarded and skipped with a message |
| Batch compilation | Any statement referencing a column created earlier is in a **separate `GO` batch** |
| Destructive ops | Nothing is ever hard-dropped. Removed tables are renamed `zz_backup_<name>_<yyyymmdd>`; row counts are printed first |
| Progress | Each script prints `=== NN: name ===` … `=== NN done ===` (done only on success) |

## Run order, purpose, destructiveness, verification

Run the **verification query** after each script — it must return the shown
result before you continue.

### 00 — `00_preflight_check.sql` (READ-ONLY)
Lists every expected table/column with PRESENT/MISSING and row counts.
**Verify:** no `MUST + MISSING` rows.

### 01 — `01_bootstrap_history.sql`
Creates `dbo.__MigrationHistory` and the helper procs
(`__mig_ScriptGate`, `__mig_Fail`, `__mig_Done`, `__mig_ClearFailed`,
`__mig_StashFks`, `__mig_RestoreFks`, `__mig_DropColumn`, table `__mig_fk_stash`).
Not destructive. Touches: new control objects only.
**Verify:** `SELECT * FROM dbo.__MigrationHistory;` → returns (empty) without error.

### 02 — `02_rename_account_to_charts.sql`
Renames `Account` → `charts`; archives `openingBalance`/`openingBalanceType`
into `zz_backup_charts_opening_<yyyymmdd>`; adds `strn, fbr, otherName,
referenceNumber, faxNumber, city, country, website, paymentTerms,
registrationNumber`; merges `parentId` into a single **NOT NULL** `parentCode`
(root = documented sentinel `'ROOT'`); drops the old columns with dynamic
dependency cleanup. Non-destructive (archive first).
**Verify:** `SELECT COUNT(*) FROM dbo.charts WHERE parentCode IS NULL;` → `0`
and `SELECT COL_LENGTH('dbo.charts','openingBalance');` → `NULL`.

### 03 — `03_create_book_tables.sql`
Creates `CashBook`/`CashBookLine`, `BankBook`/`BankBookLine`, `JV`/`JVLine`,
`OpenTB`/`OpenTBLine` (unbalanced save allowed — **no** balance constraint or
trigger), `KnockOff` (bill id `OTB-{branch}/{0000001}`), `IdSequence`; folds
archived opening balances into per-branch OTV vouchers. Non-destructive.
**Verify:** `SELECT COUNT(*) FROM sys.tables WHERE name IN ('CashBook','BankBook','JV','OpenTB','KnockOff','IdSequence');` → `6`.

### 04 — `04_migrate_legacy_vouchers.sql`
If legacy `Voucher`/`VoucherLine` exist: migrates rows into the four books
with regenerated numbers `{TYPE}/{branch}/{MMMyy}/{000001}` (reversal `-R`),
folds legacy cheques into bank lines, renames the legacy tables to
`zz_backup_*_<yyyymmdd>`. If they don't exist: prints and skips.
**Always** renames `voucherId` → `bookVoucherId` on `Fee`, `FeePayment`,
`PosSale`, `Payroll` (no DB FK — application-level integrity).
Partially destructive: legacy FKs to `Voucher` are permanently dropped
(legacy tables are archived, not dropped).
**Verify:** `SELECT name FROM sys.tables WHERE name LIKE 'zz_backup_Voucher%';` (or the skip message) and
`SELECT COL_LENGTH('dbo.Fee','bookVoucherId');` → not NULL.

### 05 — `05_charts_primary_key_rebuild.sql`
Rebuilds `charts` PK so **id = account code**; remaps every referencing
column (FK-detected + `FeePayment.accountId` +
`FinanceDefaults.defaultCashAccountId/defaultBankAccountId`) via
`dbo.__chart_id_map` (kept for audit); drops the duplicate `code` column;
recreates all FKs. Destructive to the old cuid key values only (mapping
table preserves them).
**Verify:** `SELECT COUNT(*) FROM dbo.charts WHERE id <> code_safe;` — simpler:
`SELECT TOP 5 id FROM dbo.charts;` → codes (e.g. `01`, `1001`), not cuids.

### 06 — `06_init_id_sequences.sql`
Seeds `IdSequence` for book vouchers (`CRV|CPV|BRV|BPV|JV|OTV/{branch}/{MMMyy}`)
and knock-offs (`KOFF/{branch}`) from the highest migrated number.
Non-destructive.
**Verify:** `SELECT TOP 10 * FROM dbo.IdSequence ORDER BY [key];`

### 07 — `07_regenerate_gym_ids.sql`
Regenerates business IDs with zero collisions via mapping tables + duplicate
checks: Member `{branch}/{MMMyy}/{00001}` (drops `memberId`),
MembershipPlan `{branch}/{MMMyy}/{00001}` (adds `branchId`, drops `code`),
Attendance, Fee (drops `feeNo`), MembershipFreeze `f-000001`,
Prospect `{branch}/p-00001` (merges `prospectId`, renames
`preferredBranchId` → `branchId`), FollowUp `{branch}/fw-000001`,
ProgressEntry `{branch}/Pg-000001` (adds `branchId`), WorkoutPlan `WO-000001`,
DietPlan `DP-000001`. Seeds the matching gym sequences.
Partially destructive to old key values (all preserved in `__idmap_*`).
**Verify:**
`SELECT newId, COUNT(*) FROM dbo.__idmap_Member GROUP BY newId HAVING COUNT(*) > 1;` → empty,
and `SELECT TOP 5 id FROM dbo.Member;` → business format.

### 08 — `08_gym_masterfile_and_softdelete.sql`
Creates `gymmasterfile` (master id `001` Exercise, `002` Equipment,
`003` Exercise Type; items `{masterId}{4-digit seq}`; equipment items are
branch-wise) and adds `Member.deletedAt`. Non-destructive.
**Verify:** `SELECT * FROM dbo.gymmasterfile;` → 3 category rows.

### 09 — `09_hr_payroll_masterfile.sql`
Creates `payrollmasterfile` (Education, Designation, Country, Department,
Shift, Leave Type, Allowance) and migrates existing values into it; Leave gets
`branchId` (backfilled from staff) and ids `LV-0001`; legacy `LeaveType` is
renamed `zz_backup_LeaveType_<yyyymmdd>` after migration.
**Verify:** `SELECT masterType, COUNT(*) FROM dbo.payrollmasterfile GROUP BY masterType;`
and `SELECT TOP 5 id FROM dbo.Leave;` → `LV-...`.

### 10 — `10_admin_defaults_security.sql`
Creates `Defaults` (write-once company name via trigger
`trg_Defaults_CompanyNameLock`, company info incl. FBR, financeType
FIFO/BillWise, `coaLevelDigits`, `coaLocked`), seeded from `Company` which is
renamed `zz_backup_Company_<yyyymmdd>`; backfills `AccountMapping.branchId`
per branch; adds Branch `parentId`/`nodeType`/`trn`/`fbr` and builds the
Company → Head Office → branches hierarchy; creates `UserPermission`
(View/Add/Edit/Delete/Print per user per screen).
**Verify:** `SELECT companyName, financeType, coaLocked FROM dbo.Defaults;`,
`SELECT code, nodeType FROM dbo.Branch ORDER BY nodeType;`

### 11 — `11_remove_removed_modules.sql`
Renames removed-module tables to `zz_backup_*_<yyyymmdd>`: `GymClass`,
`ClassEnrollment`, `MemberDocument`, `FitnessAssessment`; drops the obsolete
`vw_ClassEnrollmentSummary`; purges their permission rows. **Does NOT touch**
FitnessGoal, WorkoutAssignment, DietAssignment, TrainerAvailability,
TrainerSchedule, PersonalTrainingSession.
**Verify:** `SELECT name FROM sys.tables WHERE name LIKE 'zz_backup_%';`

### 12 — `12_views_procedures_rebuild.sql`
Drops obsolete objects and rebuilds every view/function/procedure/trigger
against the final schema: `vw_TrialBalance`, `vw_ActiveMembers`,
`vw_OutstandingFees`, `vw_MonthlyRevenue`, `vw_AttendanceLog`,
`vw_PayrollRegister` (now with `bookVoucherId`), `vw_StockStatus`,
`vw_BookLedger`, `fn_CalculateAge`, `fn_MemberOutstanding`,
`fn_AccountBalance` (over the four books), `sp_GetDashboardStats`,
`sp_GetTrialBalance`, `sp_GetIncomeStatement`, `sp_GetMemberStatement`,
`sp_CalculatePayroll`, `sp_ResetAdminPassword`, touch triggers
(+`trg_charts_touchUpdatedAt`), `trg_Payroll_Audit`.
**Verify:** `SELECT COUNT(*) FROM sys.views WHERE name IN ('vw_TrialBalance','vw_BookLedger','vw_PayrollRegister');` → `3`.

## After the chain succeeds

1. `SELECT * FROM dbo.__MigrationHistory;` — 01…12 must be `Success`.
2. Update the backend: `cd Backend && npx prisma generate` (schema.prisma on
   this branch matches the migrated database).
3. Keep `zz_backup_*` tables and `__idmap_*` / `__chart_id_map` mapping tables
   until you have verified the application; drop them manually later:
   ```sql
   -- example
   DROP TABLE dbo.__mig_fk_stash;  -- helpers below can also be dropped
   -- DROP PROC dbo.__mig_ScriptGate, dbo.__mig_Fail, dbo.__mig_Done,
   --          dbo.__mig_ClearFailed, dbo.__mig_StashFks, dbo.__mig_RestoreFks,
   --          dbo.__mig_DropColumn;
   ```

## Conventions

* **MonthYear** = uppercase `MMMyy` (e.g. `SEP26`) everywhere.
* **Voucher id = voucher number**: `{CRV|CPV|BRV|BPV|JV|OTV}/{branchCode}/{MMMyy}/{000001}`, reversals append `-R`.
* **Knock-off bill**: `OTB-{branchCode}/{0000001}`; `Account Tag` (Customer/Supplier) rule is enforced by the application.
* **Bank voucher line**: `chequeAmount` is derived from the line `amount` and kept in sync by the application.
* **Branch code** = `Branch.code` (e.g. `BR-001`); **account id = account code**.
* **Root account** `parentCode` sentinel = `'ROOT'`.

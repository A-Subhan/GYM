# Rollback Notes — GymDB Migrations 00–12

**Primary rollback for every script:** restore the full database backup taken
before running the chain (`GymDB_pre_migration.bak`). Because every script
runs inside a transaction, a *failed* script never leaves partial changes —
restore is only needed after *successful* scripts you decide to undo.

Per-script undo (what changed, and how to reverse it manually):

| # | Script | Changes it makes | Undo (after Success) |
|---|--------|------------------|----------------------|
| 01 | bootstrap | Adds `__MigrationHistory`, `__mig_*` procs, `__mig_fk_stash` | `DROP PROC dbo.__mig_ScriptGate, dbo.__mig_Fail, dbo.__mig_Done, dbo.__mig_ClearFailed, dbo.__mig_StashFks, dbo.__mig_RestoreFks, dbo.__mig_DropColumn; DROP TABLE dbo.__mig_fk_stash, dbo.__MigrationHistory;` |
| 02 | rename Account→charts | Table rename; new columns (`strn, fbr, otherName, referenceNumber, faxNumber, city, country, website, paymentTerms, registrationNumber, parentCode`); drops `openingBalance`, `openingBalanceType`, `parentId` (values archived in `zz_backup_charts_opening_<d>`) | Restore backup. Manual: `EXEC sp_rename 'dbo.charts','Account'; ALTER TABLE dbo.Account ADD openingBalance FLOAT NOT NULL DEFAULT 0, openingBalanceType NVARCHAR(255) NULL, parentId NVARCHAR(50) NULL;` then repopulate from the archive table |
| 03 | book tables | Creates `CashBook/BankBook/JV/OpenTB` + line tables, `KnockOff`, `IdSequence`; inserts OTV opening vouchers | `DROP TABLE dbo.CashBookLine, dbo.CashBook, dbo.BankBookLine, dbo.BankBook, dbo.JVLine, dbo.JV, dbo.OpenTBLine, dbo.OpenTB, dbo.KnockOff, dbo.IdSequence;` (opening data remains in the archive table) |
| 04 | legacy voucher migration | Inserts migrated rows into the books; renames `Voucher`→`zz_backup_Voucher_<d>`, `VoucherLine`→`zz_backup_VoucherLine_<d>`, `Cheque`→`zz_backup_Cheque_<d>`; renames `voucherId`→`bookVoucherId` on Fee/FeePayment/PosSale/Payroll; permanently drops FKs that referenced `Voucher` | Restore backup. Manual partial: rename the `zz_backup_*` tables back; rename `bookVoucherId` columns back to `voucherId` (`EXEC sp_rename 'dbo.Fee.bookVoucherId','voucherId','COLUMN';` etc.) |
| 05 | charts PK rebuild | `charts.id` becomes the account code; `code` column dropped; `AccountMapping`/`FeePayment.accountId`/`FinanceDefaults.*`/book lines remapped; FKs recreated | Restore backup. The old cuids are preserved in `dbo.__chart_id_map` (oldId→newId) if you need to map back manually |
| 06 | init sequences | Inserts/raises `IdSequence` rows for books + knock-offs | `DELETE FROM dbo.IdSequence WHERE [key] LIKE 'CRV/%' OR [key] LIKE 'CPV/%' OR [key] LIKE 'BRV/%' OR [key] LIKE 'BPV/%' OR [key] LIKE 'JV/%' OR [key] LIKE 'OTV/%' OR [key] LIKE 'KOFF/%';` |
| 07 | gym ID regeneration | Member/Plan/Attendance/Fee/Freeze/Prospect/FollowUp/Progress/Workout/Diet ids regenerated; `memberId`,`code`,`feeNo`,`prospectId` columns dropped; `branchId` added to Plan/Progress/Prospect-renamed; child references remapped | Restore backup. Old→new id pairs kept in `dbo.__idmap_*` tables for manual reverse-mapping |
| 08 | gymmasterfile | Creates `gymmasterfile` + seeds 3 categories; adds `Member.deletedAt` | `DROP TABLE dbo.gymmasterfile; ALTER TABLE dbo.Member DROP COLUMN deletedAt;` |
| 09 | HR payroll masterfile | Creates `payrollmasterfile` + migrates values; `Leave` gets `branchId` + `LV-…` ids; `LeaveType` renamed `zz_backup_LeaveType_<d>` | Restore backup. Manual: rename `zz_backup_LeaveType_<d>` back; `ALTER TABLE dbo.Leave DROP COLUMN branchId;` (Leave ids kept in `__idmap_Leave`) |
| 10 | admin defaults/security | Creates `Defaults` (+ company-name lock trigger) seeded from `Company`; renames `Company`→`zz_backup_Company_<d>`; `AccountMapping.branchId` per-branch copies; Branch `parentId/nodeType/trn/fbr` + Company/HO nodes; `UserPermission` table | Restore backup. Manual: rename Company back, `DROP TABLE dbo.UserPermission, dbo.Defaults; DROP TRIGGER dbo.trg_Defaults_CompanyNameLock;` |
| 11 | remove modules | `GymClass/ClassEnrollment/MemberDocument/FitnessAssessment` renamed `zz_backup_*_<d>`; `vw_ClassEnrollmentSummary` dropped; their Permission/RolePermission rows deleted | Restore backup. Manual: rename `zz_backup_*` tables back; re-seed permissions (`Database/06_master_data.sql`) |
| 12 | views/procs/triggers | Drops obsolete objects; rebuilds all views/functions/procs/triggers on the final schema | Restore backup, or re-run the original `Database/03_views_functions.sql`, `04_stored_procedures.sql`, `05_triggers.sql` (pre-migration versions from git) |

## Notes

* `zz_backup_<name>_<yyyymmdd>` tables and the `__idmap_*` / `__chart_id_map`
  mapping tables are deliberately **kept** after the chain succeeds — they are
  your finest-grained audit trail. Drop them only after application
  verification.
* If a script fails, it has already rolled itself back. Fix the cause, run
  `EXEC dbo.__mig_ClearFailed '<script name>';` and re-run that script — every
  script is idempotent and safe to re-run.
* `__MigrationHistory` rows with status `Success` are what the ordering gate
  checks; do not delete them unless you intend to re-run a script.

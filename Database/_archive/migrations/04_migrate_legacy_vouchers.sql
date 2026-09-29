-- ============================================================================
-- Contoura Gym ERP — Migration 04: MIGRATE LEGACY VOUCHERS (optional) +
--                                RENAME voucherId -> bookVoucherId
-- ============================================================================
-- A. If legacy [dbo].[Voucher] / [dbo].[VoucherLine] exist:
--      - rows are migrated into CashBook / BankBook / JV / OpenTB (+ lines)
--        with regenerated voucher numbers {TYPE}/{branch}/{MMMyy UPPER}/{000001}
--      - legacy Cheque rows are folded into BankBookLine cheque columns
--      - the legacy tables are RENAMED to zz_backup_VoucherLine_<yyyymmdd>,
--        zz_backup_Voucher_<yyyymmdd>, zz_backup_Cheque_<yyyymmdd>
--        (never dropped)
--    If they do NOT exist: a clear message is printed and section A skips.
--
-- B. Always: on Fee / FeePayment / PosSale / Payroll the [voucherId] column
--    is renamed to [bookVoucherId] (it now holds book voucher numbers from
--    any of the four books, so it intentionally carries NO database FK —
--    integrity is application-level).
-- ============================================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET LANGUAGE us_english;
GO

DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'03_create_book_tables', @self = N'04_migrate_legacy_vouchers', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    04 already applied, skipping.'; RETURN; END
BEGIN TRY
    BEGIN TRAN;

    IF OBJECT_ID('dbo.Voucher') IS NOT NULL
    BEGIN
        PRINT '  legacy Voucher found - migrating rows into the book tables';

        -- A1. drop (permanently) every FK referencing Voucher — children are
        --     repointed to book vouchers and the legacy tables get archived.
        DECLARE @fk sysname, @fkParent sysname, @sql nvarchar(max);
        DECLARE fkc CURSOR LOCAL FAST_FORWARD FOR
            SELECT fk.name, OBJECT_NAME(fk.parent_object_id)
            FROM sys.foreign_keys fk
            WHERE fk.referenced_object_id = OBJECT_ID('dbo.Voucher');
        OPEN fkc;
        FETCH NEXT FROM fkc INTO @fk, @fkParent;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @sql = N'ALTER TABLE dbo.' + QUOTENAME(@fkParent) + N' DROP CONSTRAINT ' + QUOTENAME(@fk) + N';';
            PRINT '    dropping FK ' + @fk + ' (legacy reference, not recreated)';
            EXEC (@sql);
            FETCH NEXT FROM fkc INTO @fk, @fkParent;
        END
        CLOSE fkc; DEALLOCATE fkc;

        -- A2. numbering map: old voucher id -> new voucher number + target book
        IF OBJECT_ID('dbo.__mig_tmp_vmap') IS NOT NULL DROP TABLE dbo.__mig_tmp_vmap;
        SELECT  v.id AS oldVoucherId,
                CONCAT(v.voucherType, '/', b.code, '/', UPPER(FORMAT(v.voucherDate, 'MMMyy')), '/',
                       FORMAT(ROW_NUMBER() OVER (PARTITION BY v.voucherType, b.code, UPPER(FORMAT(v.voucherDate, 'MMMyy'))
                                                 ORDER BY v.voucherDate, v.createdAt, v.id), '000000')) AS newId,
                CASE WHEN v.voucherType IN ('CRV','CPV') THEN 'CASHBOOK'
                     WHEN v.voucherType IN ('BRV','BPV') THEN 'BANKBOOK'
                     WHEN v.voucherType = 'OTB'          THEN 'OTB'
                     ELSE 'JV' END AS bookType
        INTO dbo.__mig_tmp_vmap
        FROM dbo.Voucher v
        JOIN dbo.Branch b ON b.id = v.branchId;

        -- A3. headers
        INSERT INTO dbo.CashBook (id, voucherType, voucherDate, branchId, bookChartId, description, reference,
                                  paymentMode, totalAmount, status, reversedById, reversedAt, reversalReason,
                                  postedById, createdAt, updatedAt)
        SELECT m.newId, v.voucherType, v.voucherDate, v.branchId, v.bookAccountId, v.description, v.reference,
               'Cash', v.totalDebit, v.status, v.reversedById, v.reversedAt, v.reversalReason,
               v.postedById, v.createdAt, v.updatedAt
        FROM dbo.Voucher v
        JOIN dbo.__mig_tmp_vmap m ON m.oldVoucherId = v.id
        WHERE m.bookType = 'CASHBOOK';

        INSERT INTO dbo.BankBook (id, voucherType, voucherDate, branchId, bookChartId, description, reference,
                                  paymentMode, totalAmount, status, reversedById, reversedAt, reversalReason,
                                  postedById, createdAt, updatedAt)
        SELECT m.newId, v.voucherType, v.voucherDate, v.branchId, v.bookAccountId, v.description, v.reference,
               'Cash', v.totalDebit, v.status, v.reversedById, v.reversedAt, v.reversalReason,
               v.postedById, v.createdAt, v.updatedAt
        FROM dbo.Voucher v
        JOIN dbo.__mig_tmp_vmap m ON m.oldVoucherId = v.id
        WHERE m.bookType = 'BANKBOOK';

        INSERT INTO dbo.JV (id, voucherType, voucherDate, branchId, description, reference,
                            totalDebit, totalCredit, status, reversedById, reversedAt, reversalReason,
                            postedById, createdAt, updatedAt)
        SELECT m.newId, 'JV', v.voucherDate, v.branchId, v.description, v.reference,
               v.totalDebit, v.totalCredit, v.status, v.reversedById, v.reversedAt, v.reversalReason,
               v.postedById, v.createdAt, v.updatedAt
        FROM dbo.Voucher v
        JOIN dbo.__mig_tmp_vmap m ON m.oldVoucherId = v.id
        WHERE m.bookType = 'JV';

        INSERT INTO dbo.OpenTB (id, voucherType, voucherDate, branchId, description, reference,
                                totalDebit, totalCredit, difference, isBalanced, status,
                                reversedById, reversedAt, reversalReason, postedById, createdAt, updatedAt)
        SELECT m.newId, 'OTV', v.voucherDate, v.branchId, LEFT(ISNULL(v.description, ''), 255), v.reference,
               v.totalDebit, v.totalCredit, v.totalDebit - v.totalCredit,
               CASE WHEN ABS(ISNULL(v.totalDebit,0) - ISNULL(v.totalCredit,0)) < 0.005 THEN 1 ELSE 0 END,
               v.status, v.reversedById, v.reversedAt, v.reversalReason, v.postedById, v.createdAt, v.updatedAt
        FROM dbo.Voucher v
        JOIN dbo.__mig_tmp_vmap m ON m.oldVoucherId = v.id
        WHERE m.bookType = 'OTB';

        -- A4. lines (legacy taxRate -> taxPercent; total = amount + taxAmount;
        --     bank lines carry chequeAmount synced = amount)
        INSERT INTO dbo.CashBookLine (voucherId, accountId, debit, credit, amount,
                                      taxPercent, taxAmount, total, lineDescription, title, reference,
                                      billType, chequeNo, chequeAmount, chequeBankName, chequeStatus, status, createdAt)
        SELECT m.newId, l.accountId, l.debit, l.credit, l.amount,
               l.taxRate, l.taxAmount, l.amount + l.taxAmount, l.lineDescription, l.title, l.reference,
               NULL, l.chequeNo, l.chequeAmount, l.chequeBankName, l.chequeStatus, l.status, l.createdAt
        FROM dbo.VoucherLine l
        JOIN dbo.Voucher v ON v.id = l.voucherId
        JOIN dbo.__mig_tmp_vmap m ON m.oldVoucherId = v.id
        WHERE m.bookType = 'CASHBOOK';

        INSERT INTO dbo.BankBookLine (voucherId, accountId, debit, credit, amount,
                                      taxPercent, taxAmount, total, lineDescription, title, reference,
                                      billType, chequeNo, chequeAmount, chequeBankName, chequeStatus, status, createdAt)
        SELECT m.newId, l.accountId, l.debit, l.credit, l.amount,
               l.taxRate, l.taxAmount, l.amount + l.taxAmount, l.lineDescription, l.title, l.reference,
               NULL, l.chequeNo, l.amount, l.chequeBankName, l.chequeStatus, l.status, l.createdAt
        FROM dbo.VoucherLine l
        JOIN dbo.Voucher v ON v.id = l.voucherId
        JOIN dbo.__mig_tmp_vmap m ON m.oldVoucherId = v.id
        WHERE m.bookType = 'BANKBOOK';

        INSERT INTO dbo.JVLine (voucherId, accountId, debit, credit, amount,
                                taxPercent, taxAmount, total, lineDescription, reference, status, createdAt)
        SELECT m.newId, l.accountId, l.debit, l.credit, l.amount,
               l.taxRate, l.taxAmount, l.amount + l.taxAmount, l.lineDescription, l.reference, l.status, l.createdAt
        FROM dbo.VoucherLine l
        JOIN dbo.Voucher v ON v.id = l.voucherId
        JOIN dbo.__mig_tmp_vmap m ON m.oldVoucherId = v.id
        WHERE m.bookType = 'JV';

        INSERT INTO dbo.OpenTBLine (voucherId, accountId, debit, credit, amount, lineDescription, reference, status, createdAt)
        SELECT m.newId, l.accountId, l.debit, l.credit, l.amount, l.lineDescription, l.reference, l.status, l.createdAt
        FROM dbo.VoucherLine l
        JOIN dbo.Voucher v ON v.id = l.voucherId
        JOIN dbo.__mig_tmp_vmap m ON m.oldVoucherId = v.id
        WHERE m.bookType = 'OTB';

        -- A5. fold legacy Cheque rows (mapped BEFORE the legacy renames)
        IF OBJECT_ID('dbo.Cheque') IS NOT NULL
        BEGIN
            IF OBJECT_ID('dbo.__mig_tmp_cheques') IS NOT NULL DROP TABLE dbo.__mig_tmp_cheques;
            SELECT  m.newId AS newVoucherId, c.chequeNo, c.bankName, c.status,
                    ROW_NUMBER() OVER (PARTITION BY m.newId ORDER BY c.chequeDate) AS rn
            INTO dbo.__mig_tmp_cheques
            FROM dbo.Cheque c
            JOIN dbo.Voucher v ON v.id = c.voucherId
            JOIN dbo.__mig_tmp_vmap m ON m.oldVoucherId = v.id
            WHERE m.bookType = 'BANKBOOK';

            UPDATE bl
            SET bl.chequeNo       = q.chequeNo,
                bl.chequeBankName = q.bankName,
                bl.chequeStatus   = q.status,
                bl.chequeAmount   = bl.amount
            FROM dbo.BankBookLine bl
            JOIN dbo.__mig_tmp_cheques q ON q.newVoucherId = bl.voucherId AND q.rn = 1
            WHERE bl.chequeNo IS NULL;

            DROP TABLE dbo.__mig_tmp_cheques;
            PRINT '  legacy cheques folded into bank lines';
        END

        PRINT '  legacy vouchers migrated';

        -- A6. archive legacy tables (rename, never drop)
        DECLARE @d sysname = CONVERT(varchar(8), GETDATE(), 112);
        IF OBJECT_ID('dbo.trg_Voucher_BalanceCheck', 'TR') IS NOT NULL DROP TRIGGER dbo.trg_Voucher_BalanceCheck;
        IF OBJECT_ID('dbo.trg_Voucher_touchUpdatedAt', 'TR') IS NOT NULL DROP TRIGGER dbo.trg_Voucher_touchUpdatedAt;
        EXEC sp_rename 'dbo.VoucherLine', CONCAT('zz_backup_VoucherLine_', @d);
        EXEC sp_rename 'dbo.Voucher',     CONCAT('zz_backup_Voucher_', @d);
        IF OBJECT_ID('dbo.Cheque') IS NOT NULL
            EXEC sp_rename 'dbo.Cheque', CONCAT('zz_backup_Cheque_', @d);
        PRINT '  legacy tables renamed to zz_backup_*_' + @d + ' (drop them manually later if desired)';

        DROP TABLE dbo.__mig_tmp_vmap;
    END
    ELSE
        PRINT '  legacy Voucher table not present - row migration skipped (nothing to do)';
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'04_migrate_legacy_vouchers';
    THROW;
END CATCH
GO

-- B. Rename voucherId -> bookVoucherId on the business tables that reference
--    book vouchers. FKs on those columns are dropped first (dynamic lookup).
DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'03_create_book_tables', @self = N'04_migrate_legacy_vouchers', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    04 already applied, skipping.'; RETURN; END
BEGIN TRY
    DECLARE @t sysname, @c sysname, @sql2 nvarchar(max);
    DECLARE colfk CURSOR LOCAL FAST_FORWARD FOR
        SELECT OBJECT_NAME(fk.parent_object_id), fk.name
        FROM sys.foreign_keys fk
        JOIN sys.foreign_key_columns k ON k.constraint_object_id = fk.object_id
        JOIN sys.columns col ON col.object_id = k.parent_object_id AND col.column_id = k.parent_column_id
        WHERE fk.parent_object_id IN (OBJECT_ID('dbo.Fee'), OBJECT_ID('dbo.FeePayment'),
                                      OBJECT_ID('dbo.PosSale'), OBJECT_ID('dbo.Payroll'))
          AND col.name = 'voucherId';
    OPEN colfk;
    FETCH NEXT FROM colfk INTO @t, @c;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @sql2 = N'ALTER TABLE dbo.' + QUOTENAME(@t) + N' DROP CONSTRAINT ' + QUOTENAME(@c) + N';';
        PRINT '    dropping FK ' + @c + ' on ' + @t + '.voucherId (replaced by application-level reference)';
        EXEC (@sql2);
        FETCH NEXT FROM colfk INTO @t, @c;
    END
    CLOSE colfk; DEALLOCATE colfk;

    IF COL_LENGTH('dbo.Fee','voucherId') IS NOT NULL AND COL_LENGTH('dbo.Fee','bookVoucherId') IS NULL
    BEGIN
        EXEC sp_rename 'dbo.Fee.voucherId', 'bookVoucherId', 'COLUMN';
        PRINT '    Fee.voucherId renamed to bookVoucherId';
    END
    IF COL_LENGTH('dbo.FeePayment','voucherId') IS NOT NULL AND COL_LENGTH('dbo.FeePayment','bookVoucherId') IS NULL
    BEGIN
        EXEC sp_rename 'dbo.FeePayment.voucherId', 'bookVoucherId', 'COLUMN';
        PRINT '    FeePayment.voucherId renamed to bookVoucherId';
    END
    IF COL_LENGTH('dbo.PosSale','voucherId') IS NOT NULL AND COL_LENGTH('dbo.PosSale','bookVoucherId') IS NULL
    BEGIN
        EXEC sp_rename 'dbo.PosSale.voucherId', 'bookVoucherId', 'COLUMN';
        PRINT '    PosSale.voucherId renamed to bookVoucherId';
    END
    IF COL_LENGTH('dbo.Payroll','voucherId') IS NOT NULL AND COL_LENGTH('dbo.Payroll','bookVoucherId') IS NULL
    BEGIN
        EXEC sp_rename 'dbo.Payroll.voucherId', 'bookVoucherId', 'COLUMN';
        PRINT '    Payroll.voucherId renamed to bookVoucherId';
    END
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'04_migrate_legacy_vouchers';
    THROW;
END CATCH
GO

-- Final verification + Success marker
DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'03_create_book_tables', @self = N'04_migrate_legacy_vouchers', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    04 already applied, skipping.'; RETURN; END
BEGIN TRY
    IF OBJECT_ID('dbo.Fee') IS NOT NULL AND COL_LENGTH('dbo.Fee','bookVoucherId') IS NULL
        THROW 51030, 'verification failed: Fee.bookVoucherId missing', 1;
    IF OBJECT_ID('dbo.Payroll') IS NOT NULL AND COL_LENGTH('dbo.Payroll','bookVoucherId') IS NULL
        THROW 51030, 'verification failed: Payroll.bookVoucherId missing', 1;
    IF OBJECT_ID('dbo.Voucher') IS NOT NULL AND OBJECT_ID('dbo.charts') IS NOT NULL
        THROW 51030, 'verification failed: legacy Voucher still present after migration', 1;

    EXEC dbo.__mig_Done @self = N'04_migrate_legacy_vouchers';
    IF @@TRANCOUNT > 0 COMMIT TRAN;
    PRINT '=== 04 done ===';
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'04_migrate_legacy_vouchers';
    THROW;
END CATCH
GO

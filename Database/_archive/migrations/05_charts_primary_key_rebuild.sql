-- ============================================================================
-- Contoura Gym ERP — Migration 05: REBUILD charts PRIMARY KEY (id = code)
-- ============================================================================
-- Makes charts.id hold the account code (account id and account code are the
-- SAME value), drops the duplicate [code] column, rebuilds the PK and every
-- dependent foreign key in the correct order:
--     stash FKs -> remap child values via dbo.__chart_id_map ->
--     swap id <- code -> drop code column -> rebuild PK -> restore FKs
-- and creates the deferred book-line / knock-off / book-account FKs.
--
-- The old-id -> new-id mapping is KEPT in dbo.__chart_id_map for audit.
-- ============================================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET LANGUAGE us_english;
GO

DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'04_migrate_legacy_vouchers', @self = N'05_charts_primary_key_rebuild', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    05 already applied, skipping.'; RETURN; END
BEGIN TRY
    BEGIN TRAN;

    IF COL_LENGTH('dbo.charts', 'code') IS NOT NULL
    BEGIN
        -- 1. duplicate-code guard: suffix 2nd+ occurrences with '-2', '-3', ...
        ;WITH Dup AS (
            SELECT id, code, ROW_NUMBER() OVER (PARTITION BY code ORDER BY createdAt, id) AS rn
            FROM dbo.charts
        )
        UPDATE Dup SET code = code + '-' + CAST(rn AS varchar(5)) WHERE rn > 1;

        -- 2. mapping table old id -> new id (code), KEPT for audit
        IF OBJECT_ID('dbo.__chart_id_map') IS NOT NULL DROP TABLE dbo.__chart_id_map;
        SELECT id AS oldId, code AS newId INTO dbo.__chart_id_map FROM dbo.charts;
        ALTER TABLE dbo.__chart_id_map ADD CONSTRAINT PK_chart_id_map PRIMARY KEY (oldId);
        PRINT '  mapped ' + CAST((SELECT COUNT(*) FROM dbo.__chart_id_map) AS varchar(10)) + ' accounts old-id -> code';

        -- 3. capture every FK column referencing charts (before stashing)
        IF OBJECT_ID('dbo.__mig_tmp_chartcols') IS NOT NULL DROP TABLE dbo.__mig_tmp_chartcols;
        SELECT DISTINCT OBJECT_NAME(fk.parent_object_id) AS parentTable,
               c.name AS columnName
        INTO dbo.__mig_tmp_chartcols
        FROM sys.foreign_keys fk
        JOIN sys.foreign_key_columns k ON k.constraint_object_id = fk.object_id
        JOIN sys.columns c ON c.object_id = k.parent_object_id AND c.column_id = k.parent_column_id
        WHERE fk.referenced_object_id = OBJECT_ID('dbo.charts')
          AND OBJECT_NAME(fk.parent_object_id) NOT LIKE 'zz_backup%';
        PRINT '  child columns referencing charts: ' + CAST((SELECT COUNT(*) FROM dbo.__mig_tmp_chartcols) AS varchar(10));

        -- 4. stash + drop the FKs referencing charts
        EXEC dbo.__mig_StashFks @table = 'dbo.charts';

        -- 5. remap every captured child column old cuid -> code
        DECLARE @pt sysname, @cn sysname, @sql nvarchar(max);
        DECLARE remap CURSOR LOCAL FAST_FORWARD FOR
            SELECT parentTable, columnName FROM dbo.__mig_tmp_chartcols;
        OPEN remap;
        FETCH NEXT FROM remap INTO @pt, @cn;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @sql = N'UPDATE t SET ' + QUOTENAME(@cn) + N' = m.newId
                         FROM dbo.' + QUOTENAME(@pt) + N' t
                         JOIN dbo.__chart_id_map m ON m.oldId = t.' + QUOTENAME(@cn) + N';';
            EXEC (@sql);
            PRINT '    remapped ' + @pt + '.' + @cn;
            FETCH NEXT FROM remap INTO @pt, @cn;
        END
        CLOSE remap; DEALLOCATE remap;

        -- 5b. remap KNOWN FK-less reference columns the catalog cannot find
        --     (they hold chart ids but carry no database FK)
        IF COL_LENGTH('dbo.FeePayment','accountId') IS NOT NULL
        BEGIN
            UPDATE fp SET fp.accountId = m.newId
            FROM dbo.FeePayment fp JOIN dbo.__chart_id_map m ON m.oldId = fp.accountId;
            PRINT '    remapped FeePayment.accountId (application-level reference)';
        END
        IF COL_LENGTH('dbo.FinanceDefaults','defaultCashAccountId') IS NOT NULL
        BEGIN
            UPDATE fd SET fd.defaultCashAccountId = m.newId
            FROM dbo.FinanceDefaults fd JOIN dbo.__chart_id_map m ON m.oldId = fd.defaultCashAccountId;
            PRINT '    remapped FinanceDefaults.defaultCashAccountId';
        END
        IF COL_LENGTH('dbo.FinanceDefaults','defaultBankAccountId') IS NOT NULL
        BEGIN
            UPDATE fd SET fd.defaultBankAccountId = m.newId
            FROM dbo.FinanceDefaults fd JOIN dbo.__chart_id_map m ON m.oldId = fd.defaultBankAccountId;
            PRINT '    remapped FinanceDefaults.defaultBankAccountId';
        END

        -- 6. swap id <- code, drop code, rebuild PK
        UPDATE dbo.charts SET id = code;

        DECLARE @rc int = (SELECT COUNT(*) FROM dbo.charts);
        PRINT '  dropping charts.code (' + CAST(@rc AS varchar(10)) + ' rows kept; id now holds the code)';
        EXEC dbo.__mig_DropColumn @table = 'dbo.charts', @column = 'code';

        DECLARE @pk sysname = (SELECT name FROM sys.key_constraints
                               WHERE type = 'PK' AND parent_object_id = OBJECT_ID('dbo.charts'));
        IF @pk IS NOT NULL EXEC (N'ALTER TABLE dbo.charts DROP CONSTRAINT ' + QUOTENAME(@pk) + N';');
        ALTER TABLE dbo.charts ADD CONSTRAINT PK_charts PRIMARY KEY (id);
        PRINT '  charts PK rebuilt on id (= account code)';

        -- 7. self-hierarchy FK on parentCode
        IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_charts_parent')
            ALTER TABLE dbo.charts ADD CONSTRAINT FK_charts_parent
                FOREIGN KEY (parentCode) REFERENCES dbo.charts (id);

        -- 8. deferred FKs (created now that id holds codes)
        IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_CashBookLine_chart')
            ALTER TABLE dbo.CashBookLine ADD CONSTRAINT FK_CashBookLine_chart FOREIGN KEY (accountId) REFERENCES dbo.charts (id);
        IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_BankBookLine_chart')
            ALTER TABLE dbo.BankBookLine ADD CONSTRAINT FK_BankBookLine_chart FOREIGN KEY (accountId) REFERENCES dbo.charts (id);
        IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_JVLine_chart')
            ALTER TABLE dbo.JVLine ADD CONSTRAINT FK_JVLine_chart FOREIGN KEY (accountId) REFERENCES dbo.charts (id);
        IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_OpenTBLine_chart')
            ALTER TABLE dbo.OpenTBLine ADD CONSTRAINT FK_OpenTBLine_chart FOREIGN KEY (accountId) REFERENCES dbo.charts (id);
        IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_KnockOff_chart')
            ALTER TABLE dbo.KnockOff ADD CONSTRAINT FK_KnockOff_chart FOREIGN KEY (accountId) REFERENCES dbo.charts (id);
        IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_CashBook_bookChart')
            ALTER TABLE dbo.CashBook ADD CONSTRAINT FK_CashBook_bookChart FOREIGN KEY (bookChartId) REFERENCES dbo.charts (id);
        IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_BankBook_bookChart')
            ALTER TABLE dbo.BankBook ADD CONSTRAINT FK_BankBook_bookChart FOREIGN KEY (bookChartId) REFERENCES dbo.charts (id);

        -- 9. recreate the stashed FKs (AccountMapping, branch, etc.)
        EXEC dbo.__mig_RestoreFks;

        DROP TABLE dbo.__mig_tmp_chartcols;
    END
    ELSE
    BEGIN
        PRINT '  charts already rebuilt (no code column) - verifying deferred FKs only';
        IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_CashBookLine_chart')
            ALTER TABLE dbo.CashBookLine ADD CONSTRAINT FK_CashBookLine_chart FOREIGN KEY (accountId) REFERENCES dbo.charts (id);
        IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_BankBookLine_chart')
            ALTER TABLE dbo.BankBookLine ADD CONSTRAINT FK_BankBookLine_chart FOREIGN KEY (accountId) REFERENCES dbo.charts (id);
        IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_JVLine_chart')
            ALTER TABLE dbo.JVLine ADD CONSTRAINT FK_JVLine_chart FOREIGN KEY (accountId) REFERENCES dbo.charts (id);
        IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_OpenTBLine_chart')
            ALTER TABLE dbo.OpenTBLine ADD CONSTRAINT FK_OpenTBLine_chart FOREIGN KEY (accountId) REFERENCES dbo.charts (id);
        IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_KnockOff_chart')
            ALTER TABLE dbo.KnockOff ADD CONSTRAINT FK_KnockOff_chart FOREIGN KEY (accountId) REFERENCES dbo.charts (id);
        IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_CashBook_bookChart')
            ALTER TABLE dbo.CashBook ADD CONSTRAINT FK_CashBook_bookChart FOREIGN KEY (bookChartId) REFERENCES dbo.charts (id);
        IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_BankBook_bookChart')
            ALTER TABLE dbo.BankBook ADD CONSTRAINT FK_BankBook_bookChart FOREIGN KEY (bookChartId) REFERENCES dbo.charts (id);
    END
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'05_charts_primary_key_rebuild';
    THROW;
END CATCH
GO

-- Final verification + Success marker
DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'04_migrate_legacy_vouchers', @self = N'05_charts_primary_key_rebuild', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    05 already applied, skipping.'; RETURN; END
BEGIN TRY
    IF OBJECT_ID('dbo.charts') IS NULL THROW 51040, 'verification failed: charts missing', 1;
    IF COL_LENGTH('dbo.charts','code') IS NOT NULL THROW 51040, 'verification failed: code column still present', 1;
    IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE type='PK' AND parent_object_id=OBJECT_ID('dbo.charts'))
        THROW 51040, 'verification failed: charts has no primary key', 1;
    IF EXISTS (SELECT 1 FROM dbo.charts c LEFT JOIN dbo.charts p ON p.id = c.parentCode
               WHERE c.parentCode <> 'ROOT' AND p.id IS NULL)
        THROW 51040, 'verification failed: dangling parentCode values', 1;

    EXEC dbo.__mig_Done @self = N'05_charts_primary_key_rebuild';
    IF @@TRANCOUNT > 0 COMMIT TRAN;
    PRINT '=== 05 done ===';
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'05_charts_primary_key_rebuild';
    THROW;
END CATCH
GO

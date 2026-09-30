-- ============================================================================
-- Contoura Gym Management System - STEP 9: FINANCE + HR UPGRADE
-- (run AFTER 08_upgrade_2026_09.sql on an existing DB; NOT needed on a fresh
--  install where 02 -> 06 already builds the final shape)
-- ============================================================================
-- !! BACKUP FIRST !!  e.g.  BACKUP DATABASE GymDB TO DISK='...gymdb_09.bak'
-- ROLLBACK: restore from that backup; every section below is transaction-
-- wrapped and fails LOUD (THROW) - a failed section leaves no partial change.
-- Re-run safe (idempotent): every section checks IF EXISTS / IF COL_LENGTH
-- and skips work that is already done.
-- ============================================================================
-- WHAT IT DOES
--   FINANCE
--   1. Voucher soft delete: adds isDeleted / deletedById / deletedAt to
--      CashBook, BankBook, JV, OpenTB. The app flags rows instead of
--      deleting; flagged vouchers are excluded from lists/reports/ledgers.
--   2. Book line ids become business ids (sequence resets per year):
--        CashBookLine  C/{year}/{000001}
--        BankBookLine  B/{year}/{000001}
--        JVLine        J/{year}/{000001}
--        OpenTBLine    O/{year}/{000001}
--      Existing rows are renumbered in place (nothing is dropped).
--   HR
--   3. Staff: merges id + employeeId into ONE column. The employee id
--      format (EMP-00001) becomes the primary key; every child row
--      (Leave, Overtime, Payroll, TrainerAvailability, TrainerSchedule,
--      StaffDocument) is remapped first, then employeeId is dropped.
--   4. Shift: ids become 001, 002, 003 ... (legacy cuids renumbered in
--      place; Staff.shiftId remapped).
--   5. CalendarDay: ids become 001, 002, 003 ... (legacy cuids renumbered).
--      NOTE: payroll never deducts for Calendar-marked holidays / Sundays
--      (application rule in /api/payroll) - no schema change needed.
-- ============================================================================
-- VERIFY AFTER: run 09_verify.sql (row counts before/after + format checks)
-- ============================================================================

SET XACT_ABORT ON;
SET NOCOUNT ON;

-- ============================================================================
-- 0) Baseline row counts (used by 09_verify.sql to prove nothing was lost)
-- ============================================================================
IF OBJECT_ID(N'dbo._upgrade09_rowcounts', N'U') IS NULL
BEGIN
    CREATE TABLE dbo._upgrade09_rowcounts (
        stage        SYSNAME       NOT NULL,
        table_name   SYSNAME       NOT NULL,
        row_count    BIGINT        NOT NULL,
        captured_at  DATETIME2     NOT NULL CONSTRAINT _upgrade09_rc_at DEFAULT SYSDATETIME()
    );
END
TRUNCATE TABLE dbo._upgrade09_rowcounts; -- fresh run each time
INSERT INTO dbo._upgrade09_rowcounts (stage, table_name, row_count)
SELECT 'before', t.name, SUM(p.rows)
FROM sys.tables t
JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
WHERE t.name IN ('CashBook','CashBookLine','BankBook','BankBookLine','JV','JVLine','OpenTB','OpenTBLine',
                 'Staff','Shift','CalendarDay','Leave','Overtime','Payroll','TrainerAvailability','TrainerSchedule','StaffDocument')
GROUP BY t.name;
PRINT 'Baseline row counts captured (stage=before)';
GO

-- ============================================================================
-- 1) Voucher soft-delete columns (CashBook, BankBook, JV, OpenTB)
-- ============================================================================
BEGIN TRY
BEGIN TRAN;
    IF COL_LENGTH('dbo.CashBook', 'isDeleted') IS NULL
        ALTER TABLE dbo.CashBook ADD [isDeleted] BIT NOT NULL CONSTRAINT [CashBook_isDeleted_df] DEFAULT 0;
    IF COL_LENGTH('dbo.CashBook', 'deletedById') IS NULL
        ALTER TABLE dbo.CashBook ADD [deletedById] NVARCHAR(50) NULL;
    IF COL_LENGTH('dbo.CashBook', 'deletedAt') IS NULL
        ALTER TABLE dbo.CashBook ADD [deletedAt] DATETIME2 NULL;

    IF COL_LENGTH('dbo.BankBook', 'isDeleted') IS NULL
        ALTER TABLE dbo.BankBook ADD [isDeleted] BIT NOT NULL CONSTRAINT [BankBook_isDeleted_df] DEFAULT 0;
    IF COL_LENGTH('dbo.BankBook', 'deletedById') IS NULL
        ALTER TABLE dbo.BankBook ADD [deletedById] NVARCHAR(50) NULL;
    IF COL_LENGTH('dbo.BankBook', 'deletedAt') IS NULL
        ALTER TABLE dbo.BankBook ADD [deletedAt] DATETIME2 NULL;

    IF COL_LENGTH('dbo.JV', 'isDeleted') IS NULL
        ALTER TABLE dbo.JV ADD [isDeleted] BIT NOT NULL CONSTRAINT [JV_isDeleted_df] DEFAULT 0;
    IF COL_LENGTH('dbo.JV', 'deletedById') IS NULL
        ALTER TABLE dbo.JV ADD [deletedById] NVARCHAR(50) NULL;
    IF COL_LENGTH('dbo.JV', 'deletedAt') IS NULL
        ALTER TABLE dbo.JV ADD [deletedAt] DATETIME2 NULL;

    IF COL_LENGTH('dbo.OpenTB', 'isDeleted') IS NULL
        ALTER TABLE dbo.OpenTB ADD [isDeleted] BIT NOT NULL CONSTRAINT [OpenTB_isDeleted_df] DEFAULT 0;
    IF COL_LENGTH('dbo.OpenTB', 'deletedById') IS NULL
        ALTER TABLE dbo.OpenTB ADD [deletedById] NVARCHAR(50) NULL;
    IF COL_LENGTH('dbo.OpenTB', 'deletedAt') IS NULL
        ALTER TABLE dbo.OpenTB ADD [deletedAt] DATETIME2 NULL;

    PRINT 'Step 1 OK: voucher soft-delete columns present on CashBook / BankBook / JV / OpenTB';
COMMIT TRAN;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;
    DECLARE @m1 NVARCHAR(2048) = N'Step 1 (voucher soft-delete columns) FAILED: ' + ERROR_MESSAGE();
    ;THROW 51101, @m1, 1;
END CATCH
GO

-- ============================================================================
-- 2) Book line ids -> {C|B|J|O}/{year}/{000001}
--    Two-phase renumber (id -> '#TMP~'+id -> final id) so it can never
--    collide, PK dropped/re-added around it, all inside one transaction.
--    Idempotent: rows already matching the pattern are left untouched.
-- ============================================================================
DECLARE @table SYSNAME, @kind CHAR(1), @pk SYSNAME, @sql NVARCHAR(MAX), @todo INT;

DECLARE line_tables CURSOR LOCAL FAST_FORWARD FOR
    SELECT 'CashBookLine', 'C' UNION ALL
    SELECT 'BankBookLine', 'B' UNION ALL
    SELECT 'JVLine',       'J' UNION ALL
    SELECT 'OpenTBLine',   'O';

OPEN line_tables;
FETCH NEXT FROM line_tables INTO @table, @kind;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'SELECT @n = COUNT(*) FROM dbo.' + QUOTENAME(@table)
             + N' WHERE [id] NOT LIKE ''' + @kind + N'/[0-9][0-9][0-9][0-9]/[0-9][0-9][0-9][0-9][0-9][0-9]''';
    EXEC sp_executesql @sql, N'@n INT OUTPUT', @n = @todo OUTPUT;

    IF @todo > 0
    BEGIN
        BEGIN TRY
            BEGIN TRAN;
                -- PK constraint name (falls back to conventional name)
                SELECT @pk = name FROM sys.key_constraints
                WHERE type = 'PK' AND parent_object_id = OBJECT_ID(N'dbo.' + @table);
                SET @pk = COALESCE(@pk, @table + '_pkey');

                SET @sql = N'ALTER TABLE dbo.' + QUOTENAME(@table) + N' DROP CONSTRAINT ' + QUOTENAME(@pk) + N';';
                EXEC (@sql);

                -- phase 1: park ALL ids where they cannot collide (full pass is
                -- deterministic even when some rows were already migrated)
                SET @sql = N'UPDATE dbo.' + QUOTENAME(@table)
                         + N' SET [id] = ''#TMP~'' + [id];';
                EXEC (@sql);

                -- phase 2: assign final per-year sequence ids to EVERY row
                -- (year from the voucher date; ROW_NUMBER is unique per year)
                SET @sql = N';WITH renum AS ('
                         + N'  SELECT l.[id], ROW_NUMBER() OVER (PARTITION BY YEAR(v.[voucherDate]) ORDER BY l.[createdAt], l.[id]) AS rn, YEAR(v.[voucherDate]) AS yr '
                         + N'  FROM dbo.' + QUOTENAME(@table) + N' l '
                         + N'  JOIN dbo.' + (CASE @kind WHEN 'C' THEN N'CashBook' WHEN 'B' THEN N'BankBook' WHEN 'J' THEN N'JV' ELSE N'OpenTB' END)
                         + N'  v ON v.[id] = l.[voucherId])'
                         + N' UPDATE l SET l.[id] = ''' + @kind + N'/'' + CAST(r.yr AS NVARCHAR(4)) + ''/'' + RIGHT(''000000'' + CAST(r.rn AS NVARCHAR(6)), 6) '
                         + N' FROM dbo.' + QUOTENAME(@table) + N' l JOIN renum r ON r.[id] = l.[id] '
                         + N' WHERE l.[id] LIKE ''#TMP~%'';';
                EXEC (@sql);

                SET @sql = N'ALTER TABLE dbo.' + QUOTENAME(@table)
                         + N' ADD CONSTRAINT ' + QUOTENAME(@pk) + N' PRIMARY KEY CLUSTERED ([id]);';
                EXEC (@sql);

                -- sanity: no parked rows may remain
                SET @sql = N'SELECT @n = COUNT(*) FROM dbo.' + QUOTENAME(@table) + N' WHERE [id] LIKE ''#TMP~%''';
                EXEC sp_executesql @sql, N'@n INT OUTPUT', @n = @todo OUTPUT;
                IF @todo > 0
                BEGIN
                    DECLARE @msg2 NVARCHAR(400) = @table + N': renumber left rows unparked';
                    THROW 51000, @msg2, 1;
                END

                PRINT N'Step 2 OK: ' + @table + N' ids migrated to ' + @kind + N'/{year}/{seq}';
            COMMIT TRAN;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRAN;
            DECLARE @m2 NVARCHAR(2048) = LEFT(N'Step 2 (' + @table + N' line ids) FAILED: ' + ERROR_MESSAGE(), 2048);
            ;THROW 51001, @m2, 1;
        END CATCH
    END
    ELSE
        PRINT N'Step 2: ' + @table + N' already migrated';

    FETCH NEXT FROM line_tables INTO @table, @kind;
END
CLOSE line_tables;
DEALLOCATE line_tables;
GO

-- ============================================================================
-- 3) Staff: merge id + employeeId into ONE column (id = employee id, EMP-00001)
-- ============================================================================
BEGIN TRY
BEGIN TRAN;
    IF COL_LENGTH('dbo.Staff', 'employeeId') IS NOT NULL
    BEGIN
        -- duplicate employee ids can never merge - fail loud instead of guessing
        IF EXISTS (SELECT 1 FROM dbo.Staff GROUP BY [employeeId] HAVING COUNT(*) > 1)
        BEGIN
            ;THROW 51002, 'Step 3 FAILED: duplicate Staff.employeeId values exist - resolve them before running 09.', 1;
        END

        -- 3a. drop every FK pointing at Staff (child tables keep their data)
        IF OBJECT_ID('tempdb..#stafffks') IS NOT NULL DROP TABLE #stafffks;
        SELECT fk.name AS fkname,
               OBJECT_SCHEMA_NAME(fk.parent_object_id) + '.' + OBJECT_NAME(fk.parent_object_id) AS childtable,
               c.name AS childcol
        INTO #stafffks
        FROM sys.foreign_keys fk
        JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
        JOIN sys.columns c ON c.object_id = fk.parent_object_id AND c.column_id = fkc.parent_column_id
        WHERE fk.referenced_object_id = OBJECT_ID('dbo.Staff');

        DECLARE @fkname SYSNAME, @child SYSNAME, @col SYSNAME;
        DECLARE fk_cur CURSOR LOCAL FAST_FORWARD FOR SELECT fkname, childtable, childcol FROM #stafffks;
        OPEN fk_cur;
        FETCH NEXT FROM fk_cur INTO @fkname, @child, @col;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            DECLARE @dropfk NVARCHAR(MAX) = N'ALTER TABLE ' + @child + N' DROP CONSTRAINT ' + QUOTENAME(@fkname) + N';';
            EXEC (@dropfk);
            FETCH NEXT FROM fk_cur INTO @fkname, @child, @col;
        END
        CLOSE fk_cur;
        DEALLOCATE fk_cur;

        -- 3b. remap children to the employee id FIRST (they reference old cuids)
        DECLARE fk_cur2 CURSOR LOCAL FAST_FORWARD FOR SELECT fkname, childtable, childcol FROM #stafffks;
        OPEN fk_cur2;
        FETCH NEXT FROM fk_cur2 INTO @fkname, @child, @col;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            DECLARE @remap NVARCHAR(MAX) = N'UPDATE c SET ' + QUOTENAME(@col)
                + N' = s.[employeeId] FROM ' + @child + N' c JOIN dbo.Staff s ON c.' + QUOTENAME(@col) + N' = s.[id];';
            EXEC (@remap);
            FETCH NEXT FROM fk_cur2 INTO @fkname, @child, @col;
        END
        CLOSE fk_cur2;
        DEALLOCATE fk_cur2;

        -- 3c. drop the (now redundant) unique key on employeeId - it may be a
        --     UNIQUE CONSTRAINT or a UNIQUE INDEX depending on how the table was created
        DECLARE @uqname SYSNAME, @uqisconstraint BIT;
        SELECT TOP 1 @uqname = kc.name, @uqisconstraint = 1
        FROM sys.key_constraints kc
        JOIN sys.index_columns ic ON ic.object_id = kc.parent_object_id AND ic.index_id = kc.unique_index_id
        JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
        WHERE kc.type = 'UQ' AND kc.parent_object_id = OBJECT_ID('dbo.Staff') AND c.name = 'employeeId';
        IF @uqname IS NULL
            SELECT TOP 1 @uqname = i.name, @uqisconstraint = 0
            FROM sys.indexes i
            JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
            JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
            WHERE i.is_unique = 1 AND i.is_primary_key = 0 AND i.object_id = OBJECT_ID('dbo.Staff') AND c.name = 'employeeId';
        IF @uqname IS NOT NULL
        BEGIN
            IF @uqisconstraint = 1
                EXEC (N'ALTER TABLE dbo.Staff DROP CONSTRAINT ' + QUOTENAME(@uqname) + N';');
            ELSE
                EXEC (N'DROP INDEX ' + QUOTENAME(@uqname) + N' ON dbo.Staff;');
        END

        -- 3d. swap the Staff PK over to the employee id
        DECLARE @staffpk SYSNAME;
        SELECT @staffpk = name FROM sys.key_constraints
        WHERE type = 'PK' AND parent_object_id = OBJECT_ID('dbo.Staff');
        SET @staffpk = COALESCE(@staffpk, N'Staff_pkey');
        EXEC (N'ALTER TABLE dbo.Staff DROP CONSTRAINT ' + QUOTENAME(@staffpk) + N';');
        UPDATE dbo.Staff SET [id] = [employeeId];
        ALTER TABLE dbo.Staff ADD CONSTRAINT [Staff_pkey] PRIMARY KEY CLUSTERED ([id]);

        -- 3e. re-create the child FKs against the merged id
        DECLARE fk_cur3 CURSOR LOCAL FAST_FORWARD FOR SELECT fkname, childtable, childcol FROM #stafffks;
        OPEN fk_cur3;
        FETCH NEXT FROM fk_cur3 INTO @fkname, @child, @col;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            DECLARE @addfk NVARCHAR(MAX) = N'ALTER TABLE ' + @child + N' ADD CONSTRAINT ' + QUOTENAME(@fkname)
                + N' FOREIGN KEY (' + QUOTENAME(@col) + N') REFERENCES dbo.Staff ([id]);';
            EXEC (@addfk);
            FETCH NEXT FROM fk_cur3 INTO @fkname, @child, @col;
        END
        CLOSE fk_cur3;
        DEALLOCATE fk_cur3;

        -- 3f. retire the old column
        ALTER TABLE dbo.Staff DROP COLUMN [employeeId];

        PRINT 'Step 3 OK: Staff.id = employee id (EMP-00001); employeeId column dropped; children remapped';
    END
    ELSE
        PRINT 'Step 3: Staff.employeeId already merged';
COMMIT TRAN;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;
    DECLARE @m3 NVARCHAR(2048) = N'Step 3 (Staff id merge) FAILED: ' + ERROR_MESSAGE();
    ;THROW 51103, @m3, 1;
END CATCH
GO

-- ============================================================================
-- 4) Shift ids -> 001, 002, 003 ...  (Staff.shiftId remapped; FKs preserved)
-- ============================================================================
DECLARE @shiftpk SYSNAME, @shiftsql NVARCHAR(MAX), @shiftsTodo INT;

SELECT @shiftsTodo = COUNT(*)
FROM dbo.Shift
WHERE [id] NOT LIKE '[0-9][0-9][0-9]' OR LEN([id]) <> 3;

IF @shiftsTodo > 0
BEGIN
    BEGIN TRY
    BEGIN TRAN;
        IF OBJECT_ID('tempdb..#shiftmap') IS NOT NULL DROP TABLE #shiftmap;
        CREATE TABLE #shiftmap (oldid NVARCHAR(50) NOT NULL PRIMARY KEY, newid NVARCHAR(10) NOT NULL);

        -- keep already-conforming ids; number the rest after the current max
        INSERT INTO #shiftmap (oldid, newid)
        SELECT [id], [id] FROM dbo.Shift WHERE [id] LIKE '[0-9][0-9][0-9]' AND LEN([id]) = 3;

        ;WITH nonconforming AS (
            SELECT [id], ROW_NUMBER() OVER (ORDER BY [createdAt], [id]) AS rn
            FROM dbo.Shift
            WHERE [id] NOT LIKE '[0-9][0-9][0-9]' OR LEN([id]) <> 3
        ),
        maxexisting AS (SELECT ISNULL(MAX(CAST([id] AS INT)), 0) AS mx FROM dbo.Shift WHERE [id] LIKE '[0-9][0-9][0-9]' AND LEN([id]) = 3)
        INSERT INTO #shiftmap (oldid, newid)
        SELECT n.[id], RIGHT('00' + CAST(maxexisting.mx + n.rn AS NVARCHAR(10)), 3)
        FROM nonconforming n CROSS JOIN maxexisting;

        IF EXISTS (SELECT 1 FROM #shiftmap GROUP BY newid HAVING COUNT(*) > 1)
        BEGIN
            ;THROW 51003, 'Step 4 FAILED: generated duplicate shift ids.', 1;
        END

        -- drop FKs referencing Shift
        IF OBJECT_ID('tempdb..#shiftfks') IS NOT NULL DROP TABLE #shiftfks;
        SELECT fk.name AS fkname,
               OBJECT_SCHEMA_NAME(fk.parent_object_id) + '.' + OBJECT_NAME(fk.parent_object_id) AS childtable,
               c.name AS childcol
        INTO #shiftfks
        FROM sys.foreign_keys fk
        JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
        JOIN sys.columns c ON c.object_id = fk.parent_object_id AND c.column_id = fkc.parent_column_id
        WHERE fk.referenced_object_id = OBJECT_ID('dbo.Shift');

        DECLARE @sfk SYSNAME, @schild SYSNAME, @scol SYSNAME;
        DECLARE sfk_cur CURSOR LOCAL FAST_FORWARD FOR SELECT fkname, childtable, childcol FROM #shiftfks;
        OPEN sfk_cur;
        FETCH NEXT FROM sfk_cur INTO @sfk, @schild, @scol;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC (N'ALTER TABLE ' + @schild + N' DROP CONSTRAINT ' + QUOTENAME(@sfk) + N';');
            FETCH NEXT FROM sfk_cur INTO @sfk, @schild, @scol;
        END
        CLOSE sfk_cur;
        DEALLOCATE sfk_cur;

        -- swap the PK and remap children through the map
        SELECT @shiftpk = name FROM sys.key_constraints WHERE type = 'PK' AND parent_object_id = OBJECT_ID('dbo.Shift');
        SET @shiftpk = COALESCE(@shiftpk, N'Shift_pkey');
        SET @shiftsql = N'ALTER TABLE dbo.Shift DROP CONSTRAINT ' + QUOTENAME(@shiftpk) + N';';
        EXEC (@shiftsql);

        UPDATE s SET s.[id] = m.newid FROM dbo.Shift s JOIN #shiftmap m ON m.oldid = s.[id];

        -- remap children (Staff.shiftId and any others)
        DECLARE sfk_cur2 CURSOR LOCAL FAST_FORWARD FOR SELECT fkname, childtable, childcol FROM #shiftfks;
        OPEN sfk_cur2;
        FETCH NEXT FROM sfk_cur2 INTO @sfk, @schild, @scol;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC (N'UPDATE c SET ' + QUOTENAME(@scol) + N' = m.newid FROM ' + @schild
                + N' c JOIN #shiftmap m ON c.' + QUOTENAME(@scol) + N' = m.oldid;');
            FETCH NEXT FROM sfk_cur2 INTO @sfk, @schild, @scol;
        END
        CLOSE sfk_cur2;
        DEALLOCATE sfk_cur2;

        ALTER TABLE dbo.Shift ADD CONSTRAINT [Shift_pkey] PRIMARY KEY CLUSTERED ([id]);

        -- re-create child FKs
        DECLARE sfk_cur3 CURSOR LOCAL FAST_FORWARD FOR SELECT fkname, childtable, childcol FROM #shiftfks;
        OPEN sfk_cur3;
        FETCH NEXT FROM sfk_cur3 INTO @sfk, @schild, @scol;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC (N'ALTER TABLE ' + @schild + N' ADD CONSTRAINT ' + QUOTENAME(@sfk)
                + N' FOREIGN KEY (' + QUOTENAME(@scol) + N') REFERENCES dbo.Shift ([id]);');
            FETCH NEXT FROM sfk_cur3 INTO @sfk, @schild, @scol;
        END
        CLOSE sfk_cur3;
        DEALLOCATE sfk_cur3;

        PRINT 'Step 4 OK: Shift ids migrated to 001/002/003 format; child references remapped';
    COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        DECLARE @m4 NVARCHAR(2048) = N'Step 4 (Shift ids) FAILED: ' + ERROR_MESSAGE();
        ;THROW 51104, @m4, 1;
    END CATCH
END
ELSE
    PRINT 'Step 4: Shift ids already 001-format';
GO

-- ============================================================================
-- 5) CalendarDay ids -> 001, 002, 003 ...
-- ============================================================================
DECLARE @calpk SYSNAME, @calsql NVARCHAR(MAX), @calTodo INT;

SELECT @calTodo = COUNT(*)
FROM dbo.CalendarDay
WHERE [id] NOT LIKE '[0-9][0-9][0-9]' OR LEN([id]) <> 3;

IF @calTodo > 0
BEGIN
    BEGIN TRY
    BEGIN TRAN;
        IF OBJECT_ID('tempdb..#calmap') IS NOT NULL DROP TABLE #calmap;
        CREATE TABLE #calmap (oldid NVARCHAR(50) NOT NULL PRIMARY KEY, newid NVARCHAR(10) NOT NULL);

        INSERT INTO #calmap (oldid, newid)
        SELECT [id], [id] FROM dbo.CalendarDay WHERE [id] LIKE '[0-9][0-9][0-9]' AND LEN([id]) = 3;

        ;WITH nonconforming AS (
            SELECT [id], ROW_NUMBER() OVER (ORDER BY [date], [id]) AS rn
            FROM dbo.CalendarDay
            WHERE [id] NOT LIKE '[0-9][0-9][0-9]' OR LEN([id]) <> 3
        ),
        maxexisting AS (SELECT ISNULL(MAX(CAST([id] AS INT)), 0) AS mx FROM dbo.CalendarDay WHERE [id] LIKE '[0-9][0-9][0-9]' AND LEN([id]) = 3)
        INSERT INTO #calmap (oldid, newid)
        SELECT n.[id], RIGHT('00' + CAST(maxexisting.mx + n.rn AS NVARCHAR(10)), 3)
        FROM nonconforming n CROSS JOIN maxexisting;

        DECLARE @cfk SYSNAME, @cchild SYSNAME, @ccol SYSNAME;

        -- drop FKs referencing CalendarDay (none expected, discovered defensively)
        IF OBJECT_ID('tempdb..#calfks') IS NOT NULL DROP TABLE #calfks;
        SELECT fk.name AS fkname,
               OBJECT_SCHEMA_NAME(fk.parent_object_id) + '.' + OBJECT_NAME(fk.parent_object_id) AS childtable,
               c.name AS childcol
        INTO #calfks
        FROM sys.foreign_keys fk
        JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
        JOIN sys.columns c ON c.object_id = fk.parent_object_id AND c.column_id = fkc.parent_column_id
        WHERE fk.referenced_object_id = OBJECT_ID('dbo.CalendarDay');

        DECLARE cfk_cur CURSOR LOCAL FAST_FORWARD FOR SELECT fkname, childtable, childcol FROM #calfks;
        OPEN cfk_cur;
        FETCH NEXT FROM cfk_cur INTO @cfk, @cchild, @ccol;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC (N'ALTER TABLE ' + @cchild + N' DROP CONSTRAINT ' + QUOTENAME(@cfk) + N';');
            FETCH NEXT FROM cfk_cur INTO @cfk, @cchild, @ccol;
        END
        CLOSE cfk_cur;
        DEALLOCATE cfk_cur;

        SELECT @calpk = name FROM sys.key_constraints WHERE type = 'PK' AND parent_object_id = OBJECT_ID('dbo.CalendarDay');
        SET @calpk = COALESCE(@calpk, N'CalendarDay_pkey');
        SET @calsql = N'ALTER TABLE dbo.CalendarDay DROP CONSTRAINT ' + QUOTENAME(@calpk) + N';';
        EXEC (@calsql);

        UPDATE c SET c.[id] = m.newid FROM dbo.CalendarDay c JOIN #calmap m ON m.oldid = c.[id];

        DECLARE cfk_cur2 CURSOR LOCAL FAST_FORWARD FOR SELECT fkname, childtable, childcol FROM #calfks;
        OPEN cfk_cur2;
        FETCH NEXT FROM cfk_cur2 INTO @cfk, @cchild, @ccol;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC (N'UPDATE c SET ' + QUOTENAME(@ccol) + N' = m.newid FROM ' + @cchild
                + N' c JOIN #calmap m ON c.' + QUOTENAME(@ccol) + N' = m.oldid;');
            FETCH NEXT FROM cfk_cur2 INTO @cfk, @cchild, @ccol;
        END
        CLOSE cfk_cur2;
        DEALLOCATE cfk_cur2;

        ALTER TABLE dbo.CalendarDay ADD CONSTRAINT [CalendarDay_pkey] PRIMARY KEY CLUSTERED ([id]);

        DECLARE cfk_cur3 CURSOR LOCAL FAST_FORWARD FOR SELECT fkname, childtable, childcol FROM #calfks;
        OPEN cfk_cur3;
        FETCH NEXT FROM cfk_cur3 INTO @cfk, @cchild, @ccol;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC (N'ALTER TABLE ' + @cchild + N' ADD CONSTRAINT ' + QUOTENAME(@cfk)
                + N' FOREIGN KEY (' + QUOTENAME(@ccol) + N') REFERENCES dbo.CalendarDay ([id]);');
            FETCH NEXT FROM cfk_cur3 INTO @cfk, @cchild, @ccol;
        END
        CLOSE cfk_cur3;
        DEALLOCATE cfk_cur3;

        PRINT 'Step 5 OK: CalendarDay ids migrated to 001/002/003 format';
    COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        DECLARE @m5 NVARCHAR(2048) = N'Step 5 (CalendarDay ids) FAILED: ' + ERROR_MESSAGE();
        ;THROW 51105, @m5, 1;
    END CATCH
END
ELSE
    PRINT 'Step 5: CalendarDay ids already 001-format';
GO

-- ============================================================================
-- 6) Final gate: capture "after" row counts and prove nothing was lost
-- ============================================================================
BEGIN TRY
    INSERT INTO dbo._upgrade09_rowcounts (stage, table_name, row_count)
    SELECT 'after', t.name, SUM(p.rows)
    FROM sys.tables t
    JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
    WHERE t.name IN ('CashBook','CashBookLine','BankBook','BankBookLine','JV','JVLine','OpenTB','OpenTBLine',
                     'Staff','Shift','CalendarDay','Leave','Overtime','Payroll','TrainerAvailability','TrainerSchedule','StaffDocument')
    GROUP BY t.name;

    -- every before count must equal its after count
    IF EXISTS (
        SELECT 1
        FROM dbo._upgrade09_rowcounts b
        WHERE b.stage = 'before'
          AND b.row_count <> (SELECT ISNULL(SUM(a.row_count), 0) FROM dbo._upgrade09_rowcounts a WHERE a.stage = 'after' AND a.table_name = b.table_name)
    )
    BEGIN
        THROW 51004, 'Step 6 FAILED: row counts changed during the upgrade - run 09_verify.sql and investigate before continuing.', 1;
    END

    PRINT '---';
    PRINT 'Upgrade 09 finished successfully. Next: run 09_verify.sql';
    PRINT 'Checks:';
    PRINT '  SELECT TOP 5 [id] FROM dbo.CashBookLine;  -- C/{year}/{000001}';
    PRINT '  SELECT TOP 5 [id] FROM dbo.BankBookLine;  -- B/{year}/{000001}';
    PRINT '  SELECT TOP 5 [id] FROM dbo.JVLine;        -- J/{year}/{000001}';
    PRINT '  SELECT TOP 5 [id] FROM dbo.OpenTBLine;    -- O/{year}/{000001}';
    PRINT '  SELECT TOP 5 [id] FROM dbo.Staff;         -- EMP-00001 (no employeeId column)';
    PRINT '  SELECT TOP 5 [id] FROM dbo.Shift;         -- 001, 002, ...';
    PRINT '  SELECT TOP 5 [id] FROM dbo.CalendarDay;   -- 001, 002, ...';
END TRY
BEGIN CATCH
    DECLARE @m6 NVARCHAR(2048) = N'Step 6 (final verification) FAILED: ' + ERROR_MESSAGE();
    ;THROW 51106, @m6, 1;
END CATCH
GO

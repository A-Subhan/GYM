-- ============================================================================
-- Contoura Gym ERP — Migration 01: BOOTSTRAP (history table + helper procs)
-- ============================================================================
-- Creates the dbo.__MigrationHistory control table and the helper objects
-- used by every migration in the chain:
--   dbo.__mig_ScriptGate   : ordering / already-applied / failure gate
--   dbo.__mig_Fail         : record a failed run (called after ROLLBACK)
--   dbo.__mig_Done         : record success (called inside the final COMMIT)
--   dbo.__mig_ClearFailed  : manual recovery — allow a failed script to retry
--   dbo.__mig_fk_stash     : scratch table holding FK definitions
--   dbo.__mig_StashFks     : drop + stash every FK referencing a table
--   dbo.__mig_RestoreFks   : recreate every stashed FK
--   dbo.__mig_DropColumn   : drop a column after dropping its dependent
--                            default/check constraints, indexes and FKs
--
-- The helper objects are application-neutral and can be dropped after the
-- whole chain succeeds (DROP PROC names listed in README.md).
-- ============================================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

PRINT '=== 01: bootstrap history + helpers ===';

IF OBJECT_ID('dbo.__MigrationHistory') IS NULL
BEGIN
    CREATE TABLE dbo.__MigrationHistory (
        ScriptName NVARCHAR(128) NOT NULL CONSTRAINT PK_MigrationHistory PRIMARY KEY,
        Status     NVARCHAR(16)  NOT NULL,          -- Success | Failed
        RunAt      DATETIME2     NOT NULL CONSTRAINT DF_MigHist_RunAt DEFAULT SYSDATETIME(),
        Notes      NVARCHAR(500) NULL
    );
    PRINT '  created dbo.__MigrationHistory';
END
ELSE
    PRINT '  dbo.__MigrationHistory already exists';
GO

IF OBJECT_ID('dbo.__mig_fk_stash') IS NULL
BEGIN
    CREATE TABLE dbo.__mig_fk_stash (
        constraint_name sysname NOT NULL,
        parent_table    sysname NOT NULL,
        parent_cols     nvarchar(max) NOT NULL,
        ref_table       sysname NOT NULL,
        ref_cols        nvarchar(max) NOT NULL,
        del_action      int NOT NULL,
        upd_action      int NOT NULL,
        stashed_at      datetime2 NOT NULL CONSTRAINT DF_fkstash_at DEFAULT SYSDATETIME()
    );
END
GO

CREATE OR ALTER PROCEDURE dbo.__mig_ScriptGate
    @prev   nvarchar(128),   -- previous script name (NULL for the first script)
    @self   nvarchar(128),
    @action varchar(10) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @action = 'Run';

    IF @prev IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM dbo.__MigrationHistory
                       WHERE ScriptName = @prev AND Status = 'Success')
    BEGIN
        THROW 51000, CONCAT('Migration order violation: ', @self,
                            ' requires ', @prev, ' to be recorded as Success. Run the scripts in order.'), 1;
    END

    DECLARE @st nvarchar(16) = (SELECT Status FROM dbo.__MigrationHistory WHERE ScriptName = @self);

    IF @st = 'Success'
    BEGIN
        SET @action = 'Skip';
        RETURN;
    END

    IF @st = 'Failed'
    BEGIN
        THROW 51003, CONCAT('Migration ', @self,
            ' failed on an earlier run and was rolled back. After fixing the cause, run: EXEC dbo.__mig_ClearFailed ''',
            @self, ''' ; then re-run this script (it is safe to re-run).'), 1;
    END
END
GO

CREATE OR ALTER PROCEDURE dbo.__mig_Fail @self nvarchar(128) AS
BEGIN
    SET NOCOUNT ON;
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;              -- leave the DB exactly as found
    IF NOT EXISTS (SELECT 1 FROM dbo.__MigrationHistory WHERE ScriptName = @self)
        INSERT INTO dbo.__MigrationHistory (ScriptName, Status, RunAt, Notes)
        VALUES (@self, 'Failed', SYSDATETIME(), 'rolled back, nothing applied');
    ELSE
        UPDATE dbo.__MigrationHistory SET Status = 'Failed', RunAt = SYSDATETIME(),
               Notes = 'rolled back, nothing applied'
        WHERE ScriptName = @self;
END
GO

CREATE OR ALTER PROCEDURE dbo.__mig_Done @self nvarchar(128) AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.__MigrationHistory WHERE ScriptName = @self)
        INSERT INTO dbo.__MigrationHistory (ScriptName, Status, RunAt, Notes)
        VALUES (@self, 'Success', SYSDATETIME(), NULL);
    ELSE
        UPDATE dbo.__MigrationHistory SET Status = 'Success', RunAt = SYSDATETIME(), Notes = NULL
        WHERE ScriptName = @self;
END
GO

CREATE OR ALTER PROCEDURE dbo.__mig_ClearFailed @self nvarchar(128) AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM dbo.__MigrationHistory WHERE ScriptName = @self AND Status = 'Failed';
    PRINT 'Cleared Failed marker for ' + @self + ' — you can re-run it now.';
END
GO

-- Stash + drop every FK that references @table (they are recreated later by
-- dbo.__mig_RestoreFks, after key rebuilds / data remaps are complete).
CREATE OR ALTER PROCEDURE dbo.__mig_StashFks @table sysname AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @oid int = OBJECT_ID(@table);
    IF @oid IS NULL BEGIN PRINT '  __mig_StashFks: table ' + @table + ' not found - nothing to do.'; RETURN; END

    ;WITH fkcols AS (
        SELECT fk.name, fk.parent_object_id, fk.referenced_object_id,
               fk.delete_referential_action, fk.update_referential_action,
               STUFF((SELECT ',' + c.name
                      FROM sys.foreign_key_columns k
                      JOIN sys.columns c ON c.object_id = k.parent_object_id AND c.column_id = k.parent_column_id
                      WHERE k.constraint_object_id = fk.object_id
                      ORDER BY k.constraint_column_id
                      FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'), 1, 1, '') AS pcols,
               STUFF((SELECT ',' + c.name
                      FROM sys.foreign_key_columns k
                      JOIN sys.columns c ON c.object_id = k.referenced_object_id AND c.column_id = k.referenced_column_id
                      WHERE k.constraint_object_id = fk.object_id
                      ORDER BY k.constraint_column_id
                      FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'), 1, 1, '') AS rcols
        FROM sys.foreign_keys fk
        WHERE fk.referenced_object_id = @oid
          AND OBJECT_NAME(fk.parent_object_id) NOT LIKE 'zz_backup%'   -- archives keep their FKs
          AND OBJECT_NAME(fk.parent_object_id) NOT LIKE '\_\_mig%' ESCAPE '\'
    )
    INSERT INTO dbo.__mig_fk_stash (constraint_name, parent_table, parent_cols, ref_table, ref_cols, del_action, upd_action)
    SELECT name, OBJECT_NAME(parent_object_id), pcols, @table, rcols,
           delete_referential_action, update_referential_action
    FROM fkcols;

    DECLARE @c sysname, @pt sysname, @sql nvarchar(max);
    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT constraint_name, parent_table FROM dbo.__mig_fk_stash WHERE ref_table = @table;
    OPEN cur;
    FETCH NEXT FROM cur INTO @c, @pt;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @sql = N'ALTER TABLE ' + QUOTENAME(OBJECT_SCHEMA_NAME(OBJECT_ID(@pt))) + N'.' + QUOTENAME(@pt)
                 + N' DROP CONSTRAINT ' + QUOTENAME(@c) + N';';
        PRINT '    dropping FK ' + @c + ' (stashed for restore)';
        EXEC (@sql);
        FETCH NEXT FROM cur INTO @c, @pt;
    END
    CLOSE cur; DEALLOCATE cur;
END
GO

-- Recreate every stashed FK, then clear the stash.
CREATE OR ALTER PROCEDURE dbo.__mig_RestoreFks AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @c sysname, @pt sysname, @pc nvarchar(max), @rt sysname, @rc nvarchar(max),
            @da int, @ua int, @sql nvarchar(max);
    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT constraint_name, parent_table, parent_cols, ref_table, ref_cols, del_action, upd_action
        FROM dbo.__mig_fk_stash;
    OPEN cur;
    FETCH NEXT FROM cur INTO @c, @pt, @pc, @rt, @rc, @da, @ua;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @sql = N'ALTER TABLE ' + QUOTENAME(OBJECT_SCHEMA_NAME(OBJECT_ID(@pt))) + N'.' + QUOTENAME(@pt)
                 + N' ADD CONSTRAINT ' + QUOTENAME(@c)
                 + N' FOREIGN KEY (' + @pc + N') REFERENCES ' + QUOTENAME(OBJECT_SCHEMA_NAME(OBJECT_ID(@rt)))
                 + N'.' + QUOTENAME(@rt) + N' (' + @rc + N')'
                 + CASE @da WHEN 1 THEN N' ON DELETE CASCADE' WHEN 2 THEN N' ON DELETE SET NULL'
                            WHEN 3 THEN N' ON DELETE SET DEFAULT' ELSE N'' END
                 + CASE @ua WHEN 1 THEN N' ON UPDATE CASCADE' WHEN 2 THEN N' ON UPDATE SET NULL'
                            WHEN 3 THEN N' ON UPDATE SET DEFAULT' ELSE N'' END + N';';
        PRINT '    restoring FK ' + @c;
        EXEC (@sql);
        FETCH NEXT FROM cur INTO @c, @pt, @pc, @rt, @rc, @da, @ua;
    END
    CLOSE cur; DEALLOCATE cur;
    DELETE FROM dbo.__mig_fk_stash;
END
GO

-- Drop a column together with every object that depends on it (defaults,
-- check constraints, indexes, foreign keys). Names are looked up in the
-- catalog — never hardcoded.
CREATE OR ALTER PROCEDURE dbo.__mig_DropColumn @table sysname, @column sysname AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @oid int = OBJECT_ID(@table), @cid int, @sql nvarchar(max), @n sysname;
    IF @oid IS NULL OR COL_LENGTH(@table, @column) IS NULL
    BEGIN
        PRINT '    column ' + @table + '.' + @column + ' not present - skip drop';
        RETURN;
    END
    SET @cid = (SELECT column_id FROM sys.columns WHERE object_id = @oid AND name = @column);

    DECLARE @deps TABLE (kind sysname, name sysname, sql nvarchar(max));

    INSERT INTO @deps
    SELECT 'FK', fk.name,
           N'ALTER TABLE ' + QUOTENAME(SCHEMA_NAME(fk.schema_id)) + N'.' + QUOTENAME(OBJECT_NAME(fk.parent_object_id))
           + N' DROP CONSTRAINT ' + QUOTENAME(fk.name)
    FROM sys.foreign_keys fk
    WHERE fk.parent_object_id = @oid
      AND EXISTS (SELECT 1 FROM sys.foreign_key_columns k
                  WHERE k.constraint_object_id = fk.object_id AND k.parent_column_id = @cid);

    INSERT INTO @deps
    SELECT 'INDEX', i.name,
           N'DROP INDEX ' + QUOTENAME(i.name) + N' ON ' + QUOTENAME(SCHEMA_NAME(i.schema_id)) + N'.' + QUOTENAME(OBJECT_NAME(i.object_id))
    FROM sys.indexes i
    WHERE i.object_id = @oid AND i.is_primary_key = 0 AND i.is_unique_constraint = 0
      AND EXISTS (SELECT 1 FROM sys.index_columns ic
                  WHERE ic.object_id = @oid AND ic.index_id = i.index_id AND ic.column_id = @cid);

    INSERT INTO @deps
    SELECT 'DEFAULT', dc.name,
           N'ALTER TABLE ' + QUOTENAME(SCHEMA_NAME(dc.schema_id)) + N'.' + QUOTENAME(dc.parent_object_id)
           + N' DROP CONSTRAINT ' + QUOTENAME(dc.name)
    FROM sys.default_constraints dc WHERE dc.parent_object_id = @oid AND dc.parent_column_id = @cid;

    INSERT INTO @deps
    SELECT 'CHECK', cc.name,
           N'ALTER TABLE ' + QUOTENAME(SCHEMA_NAME(cc.schema_id)) + N'.' + QUOTENAME(cc.parent_object_id)
           + N' DROP CONSTRAINT ' + QUOTENAME(cc.name)
    FROM sys.check_constraints cc WHERE cc.parent_object_id = @oid AND cc.parent_column_id = @cid;

    INSERT INTO @deps
    SELECT 'UNIQUE-CONSTRAINT', kc.name,
           N'ALTER TABLE ' + QUOTENAME(SCHEMA_NAME(kc.schema_id)) + N'.' + QUOTENAME(kc.parent_object_id)
           + N' DROP CONSTRAINT ' + QUOTENAME(kc.name)
    FROM sys.key_constraints kc
    WHERE kc.type = 'UQ' AND kc.parent_object_id = @oid
      AND EXISTS (SELECT 1 FROM sys.index_columns ic
                  WHERE ic.object_id = @oid AND ic.index_id = kc.unique_index_id AND ic.column_id = @cid);

    DECLARE @kind sysname;
    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT kind, name, sql FROM @deps;
    OPEN cur;
    FETCH NEXT FROM cur INTO @kind, @n, @sql;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        PRINT '    dropping dependent ' + @kind + ' ' + @n;
        EXEC (@sql);
        FETCH NEXT FROM cur INTO @kind, @n, @sql;
    END
    CLOSE cur; DEALLOCATE cur;

    SET @sql = N'ALTER TABLE ' + QUOTENAME(SCHEMA_NAME((SELECT schema_id FROM sys.tables WHERE object_id = @oid)))
             + N'.' + QUOTENAME(OBJECT_NAME(@oid)) + N' DROP COLUMN ' + QUOTENAME(@column) + N';';
    EXEC (@sql);
    PRINT '    dropped column ' + @table + '.' + @column;
END
GO

PRINT '=== 01 done ===';
GO

-- ============================================================================
-- Contoura Gym ERP — Migration 07: REGENERATE GYM BUSINESS IDs (zero collisions)
-- ============================================================================
-- ID formats (MonthYear = MMMyy UPPERCASE, e.g. SEP26):
--   Member          : {branch}/{MMMyy(joiningDate)}/{00001}   id = business id,
--                     separate memberId column REMOVED
--   MembershipPlan  : {branch}/{MMMyy(createdAt)}/{00001}     id = business id,
--                     separate code column REMOVED; branchId column ADDED
--   Attendance      : {branch}/{MMMyy(date)}/{00001}
--   Fee             : {branch}/{MMMyy(billingPeriodStart)}/{00001}; feeNo REMOVED
--   MembershipFreeze: f-{000001}
--   Prospect        : {branch}/p-{00001}; prospectId merged into id,
--                     preferredBranchId renamed to branchId
--   FollowUp        : {branch}/fw-{000001}
--   ProgressEntry   : {branch}/Pg-{000001}; branchId column ADDED
--   WorkoutPlan     : WO-{000001}
--   DietPlan        : DP-{000001}
--
-- SAFETY (per spec): every entity goes
--     ROW_NUMBER mapping into __idmap_<Entity> (oldId -> newId)
--  -> duplicate check (THROW on any duplicate)
--  -> stash FKs referencing the entity
--  -> repoint child columns via the map
--  -> swap the entity's own id
--  -> drop the duplicate display column (dynamic dependency cleanup)
--  -> restore FKs
-- All inside one transaction; mappings are KEPT for audit.
-- ============================================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET LANGUAGE us_english;
GO

-- ---------------------------------------------------------------------------
-- MEMBER
-- ---------------------------------------------------------------------------
DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'06_init_id_sequences', @self = N'07_regenerate_gym_ids', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    07 already applied, skipping.'; RETURN; END
BEGIN TRY
    BEGIN TRAN;

    IF OBJECT_ID('dbo.__idmap_Member') IS NOT NULL DROP TABLE dbo.__idmap_Member;
    SELECT  m.id AS oldId,
            CONCAT(b.code, '/', UPPER(FORMAT(m.joiningDate, 'MMMyy')), '/',
                   FORMAT(ROW_NUMBER() OVER (PARTITION BY b.code, UPPER(FORMAT(m.joiningDate, 'MMMyy'))
                                             ORDER BY m.joiningDate, m.createdAt, m.id), '00001')) AS newId
    INTO dbo.__idmap_Member
    FROM dbo.Member m
    JOIN dbo.Branch b ON b.id = m.branchId;
    ALTER TABLE dbo.__idmap_Member ADD CONSTRAINT PK_idmap_Member PRIMARY KEY (oldId);

    IF EXISTS (SELECT newId FROM dbo.__idmap_Member GROUP BY newId HAVING COUNT(*) > 1)
        THROW 51060, 'Member ID regeneration produced duplicates - aborted.', 1;
    PRINT '  Member map: ' + CAST((SELECT COUNT(*) FROM dbo.__idmap_Member) AS varchar(10)) + ' rows, no duplicates';

    EXEC dbo.__mig_StashFks @table = 'dbo.Member';

    -- repoint child columns found via FK metadata
    DECLARE @pt sysname, @cn sysname, @sql nvarchar(max);
    DECLARE remap CURSOR LOCAL FAST_FORWARD FOR
        SELECT DISTINCT OBJECT_NAME(fk.parent_object_id) AS parentTable, c.name AS columnName
        FROM sys.foreign_keys fk
        JOIN sys.foreign_key_columns k ON k.constraint_object_id = fk.object_id
        JOIN sys.columns c ON c.object_id = k.parent_object_id AND c.column_id = k.parent_column_id
        WHERE fk.referenced_object_id = OBJECT_ID('dbo.Member')
          AND OBJECT_NAME(fk.parent_object_id) NOT LIKE 'zz_backup%';
    OPEN remap;
    FETCH NEXT FROM remap INTO @pt, @cn;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @sql = N'UPDATE t SET ' + QUOTENAME(@cn) + N' = m.newId
                     FROM dbo.' + QUOTENAME(@pt) + N' t
                     JOIN dbo.__idmap_Member m ON m.oldId = t.' + QUOTENAME(@cn) + N';';
        EXEC (@sql);
        FETCH NEXT FROM remap INTO @pt, @cn;
    END
    CLOSE remap; DEALLOCATE remap;

    -- repoint FK-less member references
    IF COL_LENGTH('dbo.TrainerSchedule','memberId') IS NOT NULL
        UPDATE t SET t.memberId = m.newId
        FROM dbo.TrainerSchedule t JOIN dbo.__idmap_Member m ON m.oldId = t.memberId;
    IF COL_LENGTH('dbo.Prospect','convertedMemberId') IS NOT NULL
        UPDATE p SET p.convertedMemberId = m.newId
        FROM dbo.Prospect p JOIN dbo.__idmap_Member m ON m.oldId = p.convertedMemberId;

    -- swap own id, then remove the duplicate display column
    UPDATE m SET m.id = x.newId FROM dbo.Member m JOIN dbo.__idmap_Member x ON x.oldId = m.id;
    IF COL_LENGTH('dbo.Member','memberId') IS NOT NULL
    BEGIN
        DECLARE @rc int = (SELECT COUNT(*) FROM dbo.Member);
        PRINT '  dropping Member.memberId (' + CAST(@rc AS varchar(10)) + ' rows kept; id holds the business id)';
        EXEC dbo.__mig_DropColumn @table = 'dbo.Member', @column = 'memberId';
    END

    EXEC dbo.__mig_RestoreFks;
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'07_regenerate_gym_ids';
    THROW;
END CATCH
GO

-- ---------------------------------------------------------------------------
-- MEMBERSHIP PLAN (add branchId -> regenerate -> drop code)
-- ---------------------------------------------------------------------------
DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'06_init_id_sequences', @self = N'07_regenerate_gym_ids', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    07 already applied, skipping.'; RETURN; END
BEGIN TRY
    -- add the column in THIS batch; it is referenced only in LATER batches
    IF COL_LENGTH('dbo.MembershipPlan','branchId') IS NULL
        ALTER TABLE dbo.MembershipPlan ADD branchId NVARCHAR(50) NULL;
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'07_regenerate_gym_ids';
    THROW;
END CATCH
GO

-- (separate batch: references branchId created above)
DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'06_init_id_sequences', @self = N'07_regenerate_gym_ids', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    07 already applied, skipping.'; RETURN; END
BEGIN TRY
    IF COL_LENGTH('dbo.MembershipPlan','branchId') IS NOT NULL
       AND EXISTS (SELECT 1 FROM dbo.MembershipPlan WHERE branchId IS NULL)
    BEGIN
        DECLARE @defBranch NVARCHAR(50) = (SELECT TOP 1 id FROM dbo.Branch ORDER BY createdAt);
        UPDATE dbo.MembershipPlan SET branchId = @defBranch WHERE branchId IS NULL;
        ALTER TABLE dbo.MembershipPlan ALTER COLUMN branchId NVARCHAR(50) NOT NULL;
        IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_MembershipPlan_branch')
            ALTER TABLE dbo.MembershipPlan ADD CONSTRAINT FK_MembershipPlan_branch
                FOREIGN KEY (branchId) REFERENCES dbo.Branch (id);
        PRINT '  MembershipPlan.branchId added and backfilled';
    END

    IF COL_LENGTH('dbo.MembershipPlan','code') IS NOT NULL
    BEGIN
        IF OBJECT_ID('dbo.__idmap_MembershipPlan') IS NOT NULL DROP TABLE dbo.__idmap_MembershipPlan;
        SELECT  p.id AS oldId,
                CONCAT(b.code, '/', UPPER(FORMAT(p.createdAt, 'MMMyy')), '/',
                       FORMAT(ROW_NUMBER() OVER (PARTITION BY b.code, UPPER(FORMAT(p.createdAt, 'MMMyy'))
                                                 ORDER BY p.createdAt, p.id), '00001')) AS newId
        INTO dbo.__idmap_MembershipPlan
        FROM dbo.MembershipPlan p
        JOIN dbo.Branch b ON b.id = p.branchId;
        ALTER TABLE dbo.__idmap_MembershipPlan ADD CONSTRAINT PK_idmap_MP PRIMARY KEY (oldId);

        IF EXISTS (SELECT newId FROM dbo.__idmap_MembershipPlan GROUP BY newId HAVING COUNT(*) > 1)
            THROW 51061, 'MembershipPlan ID regeneration produced duplicates - aborted.', 1;

        EXEC dbo.__mig_StashFks @table = 'dbo.MembershipPlan';

        DECLARE @pt sysname, @cn sysname, @sql nvarchar(max);
        DECLARE remap CURSOR LOCAL FAST_FORWARD FOR
            SELECT DISTINCT OBJECT_NAME(fk.parent_object_id), c.name
            FROM sys.foreign_keys fk
            JOIN sys.foreign_key_columns k ON k.constraint_object_id = fk.object_id
            JOIN sys.columns c ON c.object_id = k.parent_object_id AND c.column_id = k.parent_column_id
            WHERE fk.referenced_object_id = OBJECT_ID('dbo.MembershipPlan')
              AND OBJECT_NAME(fk.parent_object_id) NOT LIKE 'zz_backup%';
        OPEN remap;
        FETCH NEXT FROM remap INTO @pt, @cn;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @sql = N'UPDATE t SET ' + QUOTENAME(@cn) + N' = m.newId
                         FROM dbo.' + QUOTENAME(@pt) + N' t
                         JOIN dbo.__idmap_MembershipPlan m ON m.oldId = t.' + QUOTENAME(@cn) + N';';
            EXEC (@sql);
            FETCH NEXT FROM remap INTO @pt, @cn;
        END
        CLOSE remap; DEALLOCATE remap;

        UPDATE p SET p.id = x.newId
        FROM dbo.MembershipPlan p JOIN dbo.__idmap_MembershipPlan x ON x.oldId = p.id;

        DECLARE @rc int = (SELECT COUNT(*) FROM dbo.MembershipPlan);
        PRINT '  dropping MembershipPlan.code (' + CAST(@rc AS varchar(10)) + ' rows kept; id holds the business id)';
        EXEC dbo.__mig_DropColumn @table = 'dbo.MembershipPlan', @column = 'code';

        EXEC dbo.__mig_RestoreFks;
    END
    ELSE
        PRINT '  MembershipPlan ids already regenerated - skipped';
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'07_regenerate_gym_ids';
    THROW;
END CATCH
GO

-- ---------------------------------------------------------------------------
-- ATTENDANCE / FEE
-- ---------------------------------------------------------------------------
DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'06_init_id_sequences', @self = N'07_regenerate_gym_ids', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    07 already applied, skipping.'; RETURN; END
BEGIN TRY
    -- Attendance
    IF OBJECT_ID('dbo.__idmap_Attendance') IS NOT NULL DROP TABLE dbo.__idmap_Attendance;
    SELECT  a.id AS oldId,
            CONCAT(b.code, '/', UPPER(FORMAT(a.date, 'MMMyy')), '/',
                   FORMAT(ROW_NUMBER() OVER (PARTITION BY b.code, UPPER(FORMAT(a.date, 'MMMyy'))
                                             ORDER BY a.date, a.createdAt, a.id), '00001')) AS newId
    INTO dbo.__idmap_Attendance
    FROM dbo.Attendance a
    JOIN dbo.Branch b ON b.id = a.branchId;
    ALTER TABLE dbo.__idmap_Attendance ADD CONSTRAINT PK_idmap_Att PRIMARY KEY (oldId);
    IF EXISTS (SELECT newId FROM dbo.__idmap_Attendance GROUP BY newId HAVING COUNT(*) > 1)
        THROW 51062, 'Attendance ID regeneration produced duplicates - aborted.', 1;
    UPDATE a SET a.id = x.newId FROM dbo.Attendance a JOIN dbo.__idmap_Attendance x ON x.oldId = a.id;
    PRINT '  Attendance ids regenerated';

    -- Fee (children: FeePayment.feeId via FK stash)
    IF COL_LENGTH('dbo.Fee','feeNo') IS NOT NULL
    BEGIN
        IF OBJECT_ID('dbo.__idmap_Fee') IS NOT NULL DROP TABLE dbo.__idmap_Fee;
        SELECT  f.id AS oldId,
                CONCAT(b.code, '/', UPPER(FORMAT(f.billingPeriodStart, 'MMMyy')), '/',
                       FORMAT(ROW_NUMBER() OVER (PARTITION BY b.code, UPPER(FORMAT(f.billingPeriodStart, 'MMMyy'))
                                                 ORDER BY f.billingPeriodStart, f.createdAt, f.id), '00001')) AS newId
        INTO dbo.__idmap_Fee
        FROM dbo.Fee f
        JOIN dbo.Branch b ON b.id = f.branchId;
        ALTER TABLE dbo.__idmap_Fee ADD CONSTRAINT PK_idmap_Fee PRIMARY KEY (oldId);
        IF EXISTS (SELECT newId FROM dbo.__idmap_Fee GROUP BY newId HAVING COUNT(*) > 1)
            THROW 51063, 'Fee ID regeneration produced duplicates - aborted.', 1;

        EXEC dbo.__mig_StashFks @table = 'dbo.Fee';
        UPDATE f SET f.id = x.newId FROM dbo.Fee f JOIN dbo.__idmap_Fee x ON x.oldId = f.id;
        DECLARE @rc int = (SELECT COUNT(*) FROM dbo.Fee);
        PRINT '  dropping Fee.feeNo (' + CAST(@rc AS varchar(10)) + ' rows kept; id holds the business id)';
        EXEC dbo.__mig_DropColumn @table = 'dbo.Fee', @column = 'feeNo';
        EXEC dbo.__mig_RestoreFks;
    END
    ELSE
        PRINT '  Fee ids already regenerated - skipped';
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'07_regenerate_gym_ids';
    THROW;
END CATCH
GO

-- ---------------------------------------------------------------------------
-- MEMBERSHIP FREEZE / PROSPECT / FOLLOW-UP / PROGRESS
-- ---------------------------------------------------------------------------
DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'06_init_id_sequences', @self = N'07_regenerate_gym_ids', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    07 already applied, skipping.'; RETURN; END
BEGIN TRY
    -- MembershipFreeze: f-000001
    IF OBJECT_ID('dbo.__idmap_MembershipFreeze') IS NOT NULL DROP TABLE dbo.__idmap_MembershipFreeze;
    SELECT id AS oldId, CONCAT('f-', FORMAT(ROW_NUMBER() OVER (ORDER BY createdAt, id), '000000')) AS newId
    INTO dbo.__idmap_MembershipFreeze FROM dbo.MembershipFreeze;
    ALTER TABLE dbo.__idmap_MembershipFreeze ADD CONSTRAINT PK_idmap_Frz PRIMARY KEY (oldId);
    IF EXISTS (SELECT newId FROM dbo.__idmap_MembershipFreeze GROUP BY newId HAVING COUNT(*) > 1)
        THROW 51064, 'MembershipFreeze ID regeneration produced duplicates - aborted.', 1;
    UPDATE z SET z.id = x.newId FROM dbo.MembershipFreeze z JOIN dbo.__idmap_MembershipFreeze x ON x.oldId = z.id;
    PRINT '  MembershipFreeze ids regenerated (f-000001)';

    -- Prospect: rename preferredBranchId -> branchId (rename ONLY in this
    -- batch; the new column name is referenced in later batches)
    IF COL_LENGTH('dbo.Prospect','preferredBranchId') IS NOT NULL
    BEGIN
        DECLARE @fk sysname, @sql2 nvarchar(max);
        DECLARE pfk CURSOR LOCAL FAST_FORWARD FOR
            SELECT fk.name FROM sys.foreign_keys fk
            JOIN sys.foreign_key_columns k ON k.constraint_object_id = fk.object_id
            JOIN sys.columns c ON c.object_id = k.parent_object_id AND c.column_id = k.parent_column_id
            WHERE fk.parent_object_id = OBJECT_ID('dbo.Prospect') AND c.name = 'preferredBranchId';
        OPEN pfk;
        FETCH NEXT FROM pfk INTO @fk;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @sql2 = N'ALTER TABLE dbo.Prospect DROP CONSTRAINT ' + QUOTENAME(@fk) + N';';
            EXEC (@sql2);
            FETCH NEXT FROM pfk INTO @fk;
        END
        CLOSE pfk; DEALLOCATE pfk;
        EXEC sp_rename 'dbo.Prospect.preferredBranchId', 'branchId', 'COLUMN';
        PRINT '  Prospect.preferredBranchId renamed to branchId';
    END
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'07_regenerate_gym_ids';
    THROW;
END CATCH
GO

-- (separate batch: recreate FK on the renamed column, backfill, regenerate)
DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'06_init_id_sequences', @self = N'07_regenerate_gym_ids', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    07 already applied, skipping.'; RETURN; END
BEGIN TRY
    IF COL_LENGTH('dbo.Prospect','branchId') IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Prospect_branch')
        ALTER TABLE dbo.Prospect ADD CONSTRAINT FK_Prospect_branch
            FOREIGN KEY (branchId) REFERENCES dbo.Branch (id);

    -- Prospect: backfill branchId, merge prospectId into id
    DECLARE @defBranch2 NVARCHAR(50) = (SELECT TOP 1 id FROM dbo.Branch ORDER BY createdAt);
    UPDATE p SET p.branchId = @defBranch2 WHERE p.branchId IS NULL AND COL_LENGTH('dbo.Prospect','branchId') IS NOT NULL;

    IF COL_LENGTH('dbo.Prospect','prospectId') IS NOT NULL
    BEGIN
        IF OBJECT_ID('dbo.__idmap_Prospect') IS NOT NULL DROP TABLE dbo.__idmap_Prospect;
        SELECT  p.id AS oldId,
                CONCAT(b.code, '/p-',
                       FORMAT(ROW_NUMBER() OVER (PARTITION BY b.code ORDER BY p.inquiryDate, p.createdAt, p.id), '00001')) AS newId
        INTO dbo.__idmap_Prospect
        FROM dbo.Prospect p
        JOIN dbo.Branch b ON b.id = p.branchId;
        ALTER TABLE dbo.__idmap_Prospect ADD CONSTRAINT PK_idmap_Pros PRIMARY KEY (oldId);
        IF EXISTS (SELECT newId FROM dbo.__idmap_Prospect GROUP BY newId HAVING COUNT(*) > 1)
            THROW 51065, 'Prospect ID regeneration produced duplicates - aborted.', 1;

        UPDATE p SET p.id = x.newId FROM dbo.Prospect p JOIN dbo.__idmap_Prospect x ON x.oldId = p.id;

        -- FK-less reference: FollowUp.prospectId
        IF COL_LENGTH('dbo.FollowUp','prospectId') IS NOT NULL
            UPDATE fu SET fu.prospectId = m.newId
            FROM dbo.FollowUp fu JOIN dbo.__idmap_Prospect m ON m.oldId = fu.prospectId;

        DECLARE @rc int = (SELECT COUNT(*) FROM dbo.Prospect);
        PRINT '  dropping Prospect.prospectId (' + CAST(@rc AS varchar(10)) + ' rows kept; id = {branch}/p-00001)';
        EXEC dbo.__mig_DropColumn @table = 'dbo.Prospect', @column = 'prospectId';
    END
    ELSE
        PRINT '  Prospect ids already regenerated - skipped';

    -- FollowUp: backfill branchId, regenerate {branch}/fw-000001
    IF COL_LENGTH('dbo.FollowUp','branchId') IS NOT NULL
    BEGIN
        UPDATE fu SET fu.branchId = m.branchId
        FROM dbo.FollowUp fu JOIN dbo.Member m ON m.id = fu.memberId
        WHERE fu.branchId IS NULL;
        UPDATE fu SET fu.branchId = p.branchId
        FROM dbo.FollowUp fu JOIN dbo.Prospect p ON p.id = fu.prospectId
        WHERE fu.branchId IS NULL;
        UPDATE fu SET fu.branchId = @defBranch2 WHERE fu.branchId IS NULL;
    END

    IF OBJECT_ID('dbo.__idmap_FollowUp') IS NOT NULL DROP TABLE dbo.__idmap_FollowUp;
    SELECT  fu.id AS oldId,
            CONCAT(b.code, '/fw-',
                   FORMAT(ROW_NUMBER() OVER (PARTITION BY b.code ORDER BY fu.date, fu.createdAt, fu.id), '000000')) AS newId
    INTO dbo.__idmap_FollowUp
    FROM dbo.FollowUp fu
    JOIN dbo.Branch b ON b.id = fu.branchId;
    ALTER TABLE dbo.__idmap_FollowUp ADD CONSTRAINT PK_idmap_FU PRIMARY KEY (oldId);
    IF EXISTS (SELECT newId FROM dbo.__idmap_FollowUp GROUP BY newId HAVING COUNT(*) > 1)
        THROW 51066, 'FollowUp ID regeneration produced duplicates - aborted.', 1;
    UPDATE fu SET fu.id = x.newId FROM dbo.FollowUp fu JOIN dbo.__idmap_FollowUp x ON x.oldId = fu.id;
    PRINT '  FollowUp ids regenerated ({branch}/fw-000001)';

    -- ProgressEntry: add branchId in THIS batch (referenced only in later batches)
    IF COL_LENGTH('dbo.ProgressEntry','branchId') IS NULL
        ALTER TABLE dbo.ProgressEntry ADD branchId NVARCHAR(50) NULL;
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'07_regenerate_gym_ids';
    THROW;
END CATCH
GO

-- (separate batch: backfill + NOT NULL + FK on ProgressEntry.branchId)
DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'06_init_id_sequences', @self = N'07_regenerate_gym_ids', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    07 already applied, skipping.'; RETURN; END
BEGIN TRY
    IF COL_LENGTH('dbo.ProgressEntry','branchId') IS NOT NULL
       AND EXISTS (SELECT 1 FROM dbo.ProgressEntry WHERE branchId IS NULL)
    BEGIN
        DECLARE @defBranch3 NVARCHAR(50) = (SELECT TOP 1 id FROM dbo.Branch ORDER BY createdAt);
        UPDATE pe SET pe.branchId = m.branchId
        FROM dbo.ProgressEntry pe JOIN dbo.Member m ON m.id = pe.memberId;
        UPDATE pe SET pe.branchId = @defBranch3 WHERE pe.branchId IS NULL;
        ALTER TABLE dbo.ProgressEntry ALTER COLUMN branchId NVARCHAR(50) NOT NULL;
        IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_ProgressEntry_branch')
            ALTER TABLE dbo.ProgressEntry ADD CONSTRAINT FK_ProgressEntry_branch
                FOREIGN KEY (branchId) REFERENCES dbo.Branch (id);
        PRINT '  ProgressEntry.branchId added and backfilled';
    END

    IF OBJECT_ID('dbo.__idmap_ProgressEntry') IS NOT NULL DROP TABLE dbo.__idmap_ProgressEntry;
    SELECT  pe.id AS oldId,
            CONCAT(b.code, '/Pg-',
                   FORMAT(ROW_NUMBER() OVER (PARTITION BY b.code ORDER BY pe.date, pe.createdAt, pe.id), '000000')) AS newId
    INTO dbo.__idmap_ProgressEntry
    FROM dbo.ProgressEntry pe
    JOIN dbo.Branch b ON b.id = pe.branchId;
    ALTER TABLE dbo.__idmap_ProgressEntry ADD CONSTRAINT PK_idmap_PE PRIMARY KEY (oldId);
    IF EXISTS (SELECT newId FROM dbo.__idmap_ProgressEntry GROUP BY newId HAVING COUNT(*) > 1)
        THROW 51067, 'ProgressEntry ID regeneration produced duplicates - aborted.', 1;
    UPDATE pe SET pe.id = x.newId FROM dbo.ProgressEntry pe JOIN dbo.__idmap_ProgressEntry x ON x.oldId = pe.id;
    PRINT '  ProgressEntry ids regenerated ({branch}/Pg-000001)';
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'07_regenerate_gym_ids';
    THROW;
END CATCH
GO

-- ---------------------------------------------------------------------------
-- WORKOUT PLAN / DIET PLAN
-- ---------------------------------------------------------------------------
DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'06_init_id_sequences', @self = N'07_regenerate_gym_ids', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    07 already applied, skipping.'; RETURN; END
BEGIN TRY
    IF OBJECT_ID('dbo.__idmap_WorkoutPlan') IS NOT NULL DROP TABLE dbo.__idmap_WorkoutPlan;
    SELECT id AS oldId, CONCAT('WO-', FORMAT(ROW_NUMBER() OVER (ORDER BY createdAt, id), '000000')) AS newId
    INTO dbo.__idmap_WorkoutPlan FROM dbo.WorkoutPlan;
    ALTER TABLE dbo.__idmap_WorkoutPlan ADD CONSTRAINT PK_idmap_WP PRIMARY KEY (oldId);
    IF EXISTS (SELECT newId FROM dbo.__idmap_WorkoutPlan GROUP BY newId HAVING COUNT(*) > 1)
        THROW 51068, 'WorkoutPlan ID regeneration produced duplicates - aborted.', 1;

    EXEC dbo.__mig_StashFks @table = 'dbo.WorkoutPlan';
    UPDATE w SET w.id = x.newId FROM dbo.WorkoutPlan w JOIN dbo.__idmap_WorkoutPlan x ON x.oldId = w.id;
    EXEC dbo.__mig_RestoreFks;
    PRINT '  WorkoutPlan ids regenerated (WO-000001)';

    IF OBJECT_ID('dbo.__idmap_DietPlan') IS NOT NULL DROP TABLE dbo.__idmap_DietPlan;
    SELECT id AS oldId, CONCAT('DP-', FORMAT(ROW_NUMBER() OVER (ORDER BY createdAt, id), '000000')) AS newId
    INTO dbo.__idmap_DietPlan FROM dbo.DietPlan;
    ALTER TABLE dbo.__idmap_DietPlan ADD CONSTRAINT PK_idmap_DP PRIMARY KEY (oldId);
    IF EXISTS (SELECT newId FROM dbo.__idmap_DietPlan GROUP BY newId HAVING COUNT(*) > 1)
        THROW 51069, 'DietPlan ID regeneration produced duplicates - aborted.', 1;

    EXEC dbo.__mig_StashFks @table = 'dbo.DietPlan';
    UPDATE d SET d.id = x.newId FROM dbo.DietPlan d JOIN dbo.__idmap_DietPlan x ON x.oldId = d.id;
    EXEC dbo.__mig_RestoreFks;
    PRINT '  DietPlan ids regenerated (DP-000001)';
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'07_regenerate_gym_ids';
    THROW;
END CATCH
GO

-- ---------------------------------------------------------------------------
-- SEED GYM SEQUENCES from the regenerated ids (keys match ids.ts)
-- ---------------------------------------------------------------------------
DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'06_init_id_sequences', @self = N'07_regenerate_gym_ids', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    07 already applied, skipping.'; RETURN; END
BEGIN TRY
    -- MEMBER/{branch}/{MMMyy}
    MERGE dbo.IdSequence AS t
    USING (SELECT 'MEMBER/' + PARSENAME(REPLACE(id,'/','.'),3) + '/' + PARSENAME(REPLACE(id,'/','.'),2) AS [key],
                  MAX(TRY_CAST(PARSENAME(REPLACE(id,'/','.'),1) AS INT)) + 1 AS nxt
           FROM dbo.Member WHERE id LIKE '%/%/%'
           GROUP BY 'MEMBER/' + PARSENAME(REPLACE(id,'/','.'),3) + '/' + PARSENAME(REPLACE(id,'/','.'),2)) s
       ON t.[key] = s.[key]
    WHEN MATCHED AND t.[next] < s.nxt THEN UPDATE SET t.[next] = s.nxt, t.updatedAt = SYSDATETIME()
    WHEN NOT MATCHED THEN INSERT ([key],[next]) VALUES (s.[key], s.[nxt]);

    -- FEE/{branch}/{MMMyy} (fees were regenerated in this script)
    MERGE dbo.IdSequence AS t
    USING (SELECT 'FEE/' + PARSENAME(REPLACE(id,'/','.'),3) + '/' + PARSENAME(REPLACE(id,'/','.'),2) AS [key],
                  MAX(TRY_CAST(PARSENAME(REPLACE(id,'/','.'),1) AS INT)) + 1 AS nxt
           FROM dbo.Fee WHERE id LIKE '%/%/%'
           GROUP BY 'FEE/' + PARSENAME(REPLACE(id,'/','.'),3) + '/' + PARSENAME(REPLACE(id,'/','.'),2)) s
       ON t.[key] = s.[key]
    WHEN MATCHED AND t.[next] < s.nxt THEN UPDATE SET t.[next] = s.nxt, t.updatedAt = SYSDATETIME()
    WHEN NOT MATCHED THEN INSERT ([key],[next]) VALUES (s.[key], s.[nxt]);

    -- PLAN/{branch}/{MMMyy}
    MERGE dbo.IdSequence AS t
    USING (SELECT 'PLAN/' + PARSENAME(REPLACE(id,'/','.'),3) + '/' + PARSENAME(REPLACE(id,'/','.'),2) AS [key],
                  MAX(TRY_CAST(PARSENAME(REPLACE(id,'/','.'),1) AS INT)) + 1 AS nxt
           FROM dbo.MembershipPlan WHERE id LIKE '%/%/%'
           GROUP BY 'PLAN/' + PARSENAME(REPLACE(id,'/','.'),3) + '/' + PARSENAME(REPLACE(id,'/','.'),2)) s
       ON t.[key] = s.[key]
    WHEN MATCHED AND t.[next] < s.nxt THEN UPDATE SET t.[next] = s.nxt, t.updatedAt = SYSDATETIME()
    WHEN NOT MATCHED THEN INSERT ([key],[next]) VALUES (s.[key], s.[nxt]);

    -- ATTENDANCE/{branch}/{MMMyy}
    MERGE dbo.IdSequence AS t
    USING (SELECT 'ATTENDANCE/' + PARSENAME(REPLACE(id,'/','.'),3) + '/' + PARSENAME(REPLACE(id,'/','.'),2) AS [key],
                  MAX(TRY_CAST(PARSENAME(REPLACE(id,'/','.'),1) AS INT)) + 1 AS nxt
           FROM dbo.Attendance WHERE id LIKE '%/%/%'
           GROUP BY 'ATTENDANCE/' + PARSENAME(REPLACE(id,'/','.'),3) + '/' + PARSENAME(REPLACE(id,'/','.'),2)) s
       ON t.[key] = s.[key]
    WHEN MATCHED AND t.[next] < s.nxt THEN UPDATE SET t.[next] = s.nxt, t.updatedAt = SYSDATETIME()
    WHEN NOT MATCHED THEN INSERT ([key],[next]) VALUES (s.[key], s.[nxt]);

    -- PROSPECT/{branch}  (ids {branch}/p-00001)
    MERGE dbo.IdSequence AS t
    USING (SELECT 'PROSPECT/' + PARSENAME(REPLACE(id,'/','.'),2) AS [key],
                  MAX(TRY_CAST(SUBSTRING(PARSENAME(REPLACE(id,'/','.'),1), 3, 20) AS INT)) + 1 AS nxt
           FROM dbo.Prospect WHERE id LIKE '%/p-%'
           GROUP BY 'PROSPECT/' + PARSENAME(REPLACE(id,'/','.'),2)) s
       ON t.[key] = s.[key]
    WHEN MATCHED AND t.[next] < s.nxt THEN UPDATE SET t.[next] = s.nxt, t.updatedAt = SYSDATETIME()
    WHEN NOT MATCHED THEN INSERT ([key],[next]) VALUES (s.[key], s.[nxt]);

    -- FOLLOWUP/{branch}  (ids {branch}/fw-000001)
    MERGE dbo.IdSequence AS t
    USING (SELECT 'FOLLOWUP/' + PARSENAME(REPLACE(id,'/','.'),2) AS [key],
                  MAX(TRY_CAST(SUBSTRING(PARSENAME(REPLACE(id,'/','.'),1), 4, 20) AS INT)) + 1 AS nxt
           FROM dbo.FollowUp WHERE id LIKE '%/fw-%'
           GROUP BY 'FOLLOWUP/' + PARSENAME(REPLACE(id,'/','.'),2)) s
       ON t.[key] = s.[key]
    WHEN MATCHED AND t.[next] < s.nxt THEN UPDATE SET t.[next] = s.nxt, t.updatedAt = SYSDATETIME()
    WHEN NOT MATCHED THEN INSERT ([key],[next]) VALUES (s.[key], s.[nxt]);

    -- PROGRESS/{branch}  (ids {branch}/Pg-000001)
    MERGE dbo.IdSequence AS t
    USING (SELECT 'PROGRESS/' + PARSENAME(REPLACE(id,'/','.'),2) AS [key],
                  MAX(TRY_CAST(SUBSTRING(PARSENAME(REPLACE(id,'/','.'),1), 4, 20) AS INT)) + 1 AS nxt
           FROM dbo.ProgressEntry WHERE id LIKE '%/Pg-%'
           GROUP BY 'PROGRESS/' + PARSENAME(REPLACE(id,'/','.'),2)) s
       ON t.[key] = s.[key]
    WHEN MATCHED AND t.[next] < s.nxt THEN UPDATE SET t.[next] = s.nxt, t.updatedAt = SYSDATETIME()
    WHEN NOT MATCHED THEN INSERT ([key],[next]) VALUES (s.[key], s.[nxt]);

    -- global counters (ISNULL keeps them valid even with zero rows)
    MERGE dbo.IdSequence AS t
    USING (SELECT 'FREEZE' AS [key], ISNULL(MAX(TRY_CAST(SUBSTRING(id, 3, 20) AS INT)), 0) + 1 AS nxt
           FROM dbo.MembershipFreeze WHERE id LIKE 'f-%') s
       ON t.[key] = s.[key]
    WHEN MATCHED AND t.[next] < s.nxt THEN UPDATE SET t.[next] = s.nxt, t.updatedAt = SYSDATETIME()
    WHEN NOT MATCHED THEN INSERT ([key],[next]) VALUES (s.[key], s.[nxt]);

    MERGE dbo.IdSequence AS t
    USING (SELECT 'WORKOUTPLAN' AS [key], ISNULL(MAX(TRY_CAST(SUBSTRING(id, 4, 20) AS INT)), 0) + 1 AS nxt
           FROM dbo.WorkoutPlan WHERE id LIKE 'WO-%') s
       ON t.[key] = s.[key]
    WHEN MATCHED AND t.[next] < s.nxt THEN UPDATE SET t.[next] = s.nxt, t.updatedAt = SYSDATETIME()
    WHEN NOT MATCHED THEN INSERT ([key],[next]) VALUES (s.[key], s.[nxt]);

    MERGE dbo.IdSequence AS t
    USING (SELECT 'DIETPLAN' AS [key], ISNULL(MAX(TRY_CAST(SUBSTRING(id, 4, 20) AS INT)), 0) + 1 AS nxt
           FROM dbo.DietPlan WHERE id LIKE 'DP-%') s
       ON t.[key] = s.[key]
    WHEN MATCHED AND t.[next] < s.nxt THEN UPDATE SET t.[next] = s.nxt, t.updatedAt = SYSDATETIME()
    WHEN NOT MATCHED THEN INSERT ([key],[next]) VALUES (s.[key], s.[nxt]);

    PRINT '  gym sequences seeded (MEMBER/PLAN/ATTENDANCE/PROSPECT/FOLLOWUP/PROGRESS/FREEZE/WORKOUTPLAN/DIETPLAN)';
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'07_regenerate_gym_ids';
    THROW;
END CATCH
GO

-- Final verification + Success marker
DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'06_init_id_sequences', @self = N'07_regenerate_gym_ids', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    07 already applied, skipping.'; RETURN; END
BEGIN TRY
    IF COL_LENGTH('dbo.Member','memberId') IS NOT NULL
        THROW 51070, 'verification failed: Member.memberId still present', 1;
    IF COL_LENGTH('dbo.Fee','feeNo') IS NOT NULL
        THROW 51070, 'verification failed: Fee.feeNo still present', 1;
    IF COL_LENGTH('dbo.Prospect','prospectId') IS NOT NULL
        THROW 51070, 'verification failed: Prospect.prospectId still present', 1;
    IF EXISTS (SELECT 1 FROM dbo.Member WHERE id NOT LIKE '%/%/%')
        THROW 51070, 'verification failed: some Member ids are not in business format', 1;

    EXEC dbo.__mig_Done @self = N'07_regenerate_gym_ids';
    IF @@TRANCOUNT > 0 COMMIT TRAN;
    PRINT '=== 07 done ===';
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'07_regenerate_gym_ids';
    THROW;
END CATCH
GO

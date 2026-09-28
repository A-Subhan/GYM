-- ============================================================================
-- Contoura Gym ERP — Migration 06: INITIALIZE ID SEQUENCES (books + bills)
-- ============================================================================
-- Seeds dbo.IdSequence from the highest existing number per book type /
-- branch / month so application-generated IDs never collide with migrated
-- rows. Keys match Backend/src/lib/ids.ts exactly:
--   book vouchers : {CRV|CPV|BRV|BPV|JV|OTV}/{branchCode}/{MMMyy UPPER}
--   knock-off     : KOFF/{branchCode}
-- Every source table is existence-guarded; re-running only raises counters.
-- Gym / HR sequences are seeded at the end of migrations 07 and 09.
-- ============================================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET LANGUAGE us_english;
GO

DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'05_charts_primary_key_rebuild', @self = N'06_init_id_sequences', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    06 already applied, skipping.'; RETURN; END
BEGIN TRY
    BEGIN TRAN;

    -- 1. Book voucher sequences from the four books
    IF OBJECT_ID('dbo.CashBook') IS NOT NULL
    BEGIN
        ;WITH src AS (
            SELECT PARSENAME(REPLACE(id,'/','.'),1) AS seqPart,
                   PARSENAME(REPLACE(id,'/','.'),3) AS branchCode,
                   PARSENAME(REPLACE(id,'/','.'),2) AS mon,
                   voucherType
            FROM dbo.CashBook
        ), nums AS (
            SELECT voucherType + '/' + branchCode + '/' + mon AS [key],
                   TRY_CAST(REPLACE(seqPart, '-R', '') AS INT) AS seq
            FROM src
        )
        MERGE dbo.IdSequence AS t
        USING (SELECT [key], MAX(seq) + 1 AS nxt FROM nums WHERE seq IS NOT NULL GROUP BY [key]) AS s
           ON t.[key] = s.[key]
        WHEN MATCHED AND t.[next] < s.nxt THEN UPDATE SET t.[next] = s.nxt, t.updatedAt = SYSDATETIME()
        WHEN NOT MATCHED THEN INSERT ([key],[next]) VALUES (s.[key], s.[nxt]);
        PRINT '  CashBook sequences seeded';
    END

    IF OBJECT_ID('dbo.BankBook') IS NOT NULL
    BEGIN
        ;WITH src AS (
            SELECT PARSENAME(REPLACE(id,'/','.'),1) AS seqPart,
                   PARSENAME(REPLACE(id,'/','.'),3) AS branchCode,
                   PARSENAME(REPLACE(id,'/','.'),2) AS mon,
                   voucherType
            FROM dbo.BankBook
        ), nums AS (
            SELECT voucherType + '/' + branchCode + '/' + mon AS [key],
                   TRY_CAST(REPLACE(seqPart, '-R', '') AS INT) AS seq
            FROM src
        )
        MERGE dbo.IdSequence AS t
        USING (SELECT [key], MAX(seq) + 1 AS nxt FROM nums WHERE seq IS NOT NULL GROUP BY [key]) AS s
           ON t.[key] = s.[key]
        WHEN MATCHED AND t.[next] < s.nxt THEN UPDATE SET t.[next] = s.nxt, t.updatedAt = SYSDATETIME()
        WHEN NOT MATCHED THEN INSERT ([key],[next]) VALUES (s.[key], s.[nxt]);
        PRINT '  BankBook sequences seeded';
    END

    IF OBJECT_ID('dbo.JV') IS NOT NULL
    BEGIN
        MERGE dbo.IdSequence AS t
        USING (SELECT PARSENAME(REPLACE(id,'/','.'),3) + '/' + PARSENAME(REPLACE(id,'/','.'),2) AS branchMon,
                      MAX(TRY_CAST(REPLACE(PARSENAME(REPLACE(id,'/','.'),1), '-R', '') AS INT)) + 1 AS nxt
               FROM dbo.JV
               WHERE id LIKE 'JV/%/%/%'
               GROUP BY PARSENAME(REPLACE(id,'/','.'),3) + '/' + PARSENAME(REPLACE(id,'/','.'),2)) AS s
           ON t.[key] = s.[key]
        WHEN MATCHED AND t.[next] < s.nxt THEN UPDATE SET t.[next] = s.nxt, t.updatedAt = SYSDATETIME()
        WHEN NOT MATCHED THEN INSERT ([key],[next]) VALUES (s.[key], s.[nxt]);
        PRINT '  JV sequences seeded';
    END

    IF OBJECT_ID('dbo.OpenTB') IS NOT NULL
    BEGIN
        MERGE dbo.IdSequence AS t
        USING (SELECT PARSENAME(REPLACE(id,'/','.'),3) + '/' + PARSENAME(REPLACE(id,'/','.'),2) AS branchMon,
                      MAX(TRY_CAST(REPLACE(PARSENAME(REPLACE(id,'/','.'),1), '-R', '') AS INT)) + 1 AS nxt
               FROM dbo.OpenTB
               WHERE id LIKE 'OTV/%/%/%'
               GROUP BY PARSENAME(REPLACE(id,'/','.'),3) + '/' + PARSENAME(REPLACE(id,'/','.'),2)) AS s
           ON t.[key] = s.[key]
        WHEN MATCHED AND t.[next] < s.nxt THEN UPDATE SET t.[next] = s.nxt, t.updatedAt = SYSDATETIME()
        WHEN NOT MATCHED THEN INSERT ([key],[next]) VALUES (s.[key], s.[nxt]);
        PRINT '  OpenTB sequences seeded';
    END

    -- 2. Knock-off bill sequences: OTB-{branch}/{0000001}
    IF OBJECT_ID('dbo.KnockOff') IS NOT NULL
    BEGIN
        MERGE dbo.IdSequence AS t
        USING (SELECT 'KOFF/' + SUBSTRING(billId, 5, LEN(billId) - 11) AS [key],
                      MAX(TRY_CAST(RIGHT(billId, 7) AS INT)) + 1 AS nxt
               FROM dbo.KnockOff
               WHERE billId LIKE 'OTB-%/%' AND LEN(billId) > 11
               GROUP BY SUBSTRING(billId, 5, LEN(billId) - 11)) AS s
           ON t.[key] = s.[key]
        WHEN MATCHED AND t.[next] < s.nxt THEN UPDATE SET t.[next] = s.nxt, t.updatedAt = SYSDATETIME()
        WHEN NOT MATCHED THEN INSERT ([key],[next]) VALUES (s.[key], s.[nxt]);
        PRINT '  KnockOff sequences seeded';
    END

    -- 3. every live branch gets a zeroed knock-off counter so first use works
    IF OBJECT_ID('dbo.Branch') IS NOT NULL
        INSERT INTO dbo.IdSequence ([key], [next])
        SELECT 'KOFF/' + b.code, 1
        FROM dbo.Branch b
        WHERE NOT EXISTS (SELECT 1 FROM dbo.IdSequence WHERE [key] = 'KOFF/' + b.code);
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'06_init_id_sequences';
    THROW;
END CATCH
GO

-- Final verification + Success marker
DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'05_charts_primary_key_rebuild', @self = N'06_init_id_sequences', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    06 already applied, skipping.'; RETURN; END
BEGIN TRY
    IF OBJECT_ID('dbo.IdSequence') IS NULL THROW 51050, 'verification failed: IdSequence missing', 1;
    IF EXISTS (SELECT 1 FROM dbo.IdSequence WHERE [next] < 1)
        THROW 51050, 'verification failed: invalid sequence counters', 1;

    EXEC dbo.__mig_Done @self = N'06_init_id_sequences';
    IF @@TRANCOUNT > 0 COMMIT TRAN;
    PRINT '=== 06 done ===';
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'06_init_id_sequences';
    THROW;
END CATCH
GO

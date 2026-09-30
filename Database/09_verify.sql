-- ============================================================================
-- Contoura Gym Management System - STEP 9 VERIFY
-- Run AFTER 09_upgrade_finance_hr.sql. Compares live row counts against the
-- "before"/"after" baselines captured by 09 (dbo._upgrade09_rowcounts) so you
-- can confirm NO DATA WAS LOST, then checks every new id format.
-- Safe to run any number of times - read-only.
-- ============================================================================

SET NOCOUNT ON;

PRINT '================ 1) ROW COUNTS: before vs after vs live ================';

IF OBJECT_ID(N'dbo._upgrade09_rowcounts', N'U') IS NULL
BEGIN
    PRINT 'NOTE: baseline table dbo._upgrade09_rowcounts not found - run 09_upgrade_finance_hr.sql first.';
    PRINT '      Live counts are still printed below.';
END

SELECT b.table_name,
       MAX(CASE WHEN b.stage = 'before' THEN b.row_count END) AS [before],
       MAX(CASE WHEN b.stage = 'after' THEN b.row_count END) AS [after],
       l.live_count,
       CASE
           WHEN l.live_count IS NULL THEN 'TABLE MISSING!'
           WHEN MAX(CASE WHEN b.stage = 'before' THEN b.row_count END) = l.live_count THEN 'OK - unchanged'
           ELSE 'DIFFERS - investigate!'
       END AS [status]
FROM dbo._upgrade09_rowcounts b
LEFT JOIN (
    SELECT t.name AS table_name, SUM(p.rows) AS live_count
    FROM sys.tables t
    JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
    WHERE t.name IN ('CashBook','CashBookLine','BankBook','BankBookLine','JV','JVLine','OpenTB','OpenTBLine',
                     'Staff','Shift','CalendarDay','Leave','Overtime','Payroll','TrainerAvailability','TrainerSchedule','StaffDocument')
    GROUP BY t.name
) l ON l.table_name = b.table_name
GROUP BY b.table_name, l.live_count
ORDER BY b.table_name;

-- live counts even without the baseline table
SELECT t.name AS table_name, SUM(p.rows) AS live_count
FROM sys.tables t
JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
WHERE t.name IN ('CashBook','CashBookLine','BankBook','BankBookLine','JV','JVLine','OpenTB','OpenTBLine',
                 'Staff','Shift','CalendarDay','Leave','Overtime','Payroll','TrainerAvailability','TrainerSchedule','StaffDocument')
GROUP BY t.name
ORDER BY t.name;

PRINT '';
PRINT '================ 2) FINANCE: soft-delete columns ======================';
SELECT t.name AS table_name,
       CASE WHEN COL_LENGTH('dbo.' + t.name, 'isDeleted')   IS NOT NULL THEN 'yes' ELSE 'MISSING' END AS isDeleted,
       CASE WHEN COL_LENGTH('dbo.' + t.name, 'deletedById') IS NOT NULL THEN 'yes' ELSE 'MISSING' END AS deletedById,
       CASE WHEN COL_LENGTH('dbo.' + t.name, 'deletedAt')   IS NOT NULL THEN 'yes' ELSE 'MISSING' END AS deletedAt
FROM sys.tables t
WHERE t.name IN ('CashBook', 'BankBook', 'JV', 'OpenTB')
ORDER BY t.name;

PRINT '';
PRINT '================ 3) FINANCE: line id formats ==========================';

-- orphan check: every line must still belong to an existing voucher
SELECT 'CashBookLine orphans' AS [check], COUNT(*) AS problems
FROM dbo.CashBookLine l LEFT JOIN dbo.CashBook v ON v.id = l.voucherId WHERE v.id IS NULL
UNION ALL
SELECT 'BankBookLine orphans', COUNT(*)
FROM dbo.BankBookLine l LEFT JOIN dbo.BankBook v ON v.id = l.voucherId WHERE v.id IS NULL
UNION ALL
SELECT 'JVLine orphans', COUNT(*)
FROM dbo.JVLine l LEFT JOIN dbo.JV v ON v.id = l.voucherId WHERE v.id IS NULL
UNION ALL
SELECT 'OpenTBLine orphans', COUNT(*)
FROM dbo.OpenTBLine l LEFT JOIN dbo.OpenTB v ON v.id = l.voucherId WHERE v.id IS NULL;

-- format check: all ids must match K/{year}/{000001}
SELECT 'CashBookLine bad ids' AS [check], COUNT(*) AS problems
FROM dbo.CashBookLine WHERE [id] NOT LIKE 'C/[0-9][0-9][0-9][0-9]/[0-9][0-9][0-9][0-9][0-9][0-9]'
UNION ALL
SELECT 'BankBookLine bad ids', COUNT(*)
FROM dbo.BankBookLine WHERE [id] NOT LIKE 'B/[0-9][0-9][0-9][0-9]/[0-9][0-9][0-9][0-9][0-9][0-9]'
UNION ALL
SELECT 'JVLine bad ids', COUNT(*)
FROM dbo.JVLine WHERE [id] NOT LIKE 'J/[0-9][0-9][0-9][0-9]/[0-9][0-9][0-9][0-9][0-9][0-9]'
UNION ALL
SELECT 'OpenTBLine bad ids', COUNT(*)
FROM dbo.OpenTBLine WHERE [id] NOT LIKE 'O/[0-9][0-9][0-9][0-9]/[0-9][0-9][0-9][0-9][0-9][0-9]';

-- sample of the new ids (one per table)
SELECT TOP 5 'CashBookLine' AS [table], [id] FROM dbo.CashBookLine ORDER BY [id];
SELECT TOP 5 'BankBookLine' AS [table], [id] FROM dbo.BankBookLine ORDER BY [id];
SELECT TOP 5 'JVLine'       AS [table], [id] FROM dbo.JVLine ORDER BY [id];
SELECT TOP 5 'OpenTBLine'   AS [table], [id] FROM dbo.OpenTBLine ORDER BY [id];

PRINT '';
PRINT '================ 4) HR: staff / shift / calendar id formats ===========';

SELECT 'Staff.employeeId column still present' AS [check], COUNT(*) AS problems
FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Staff') AND name = 'employeeId';

SELECT 'Staff ids not EMP-format' AS [check], COUNT(*) AS problems
FROM dbo.Staff WHERE [id] NOT LIKE 'EMP-%';

SELECT 'Leave.staffId without a Staff parent' AS [check], COUNT(*) AS problems
FROM dbo.Leave l LEFT JOIN dbo.Staff s ON s.id = l.staffId WHERE s.id IS NULL
UNION ALL
SELECT 'Overtime.staffId without a Staff parent', COUNT(*)
FROM dbo.Overtime o LEFT JOIN dbo.Staff s ON s.id = o.staffId WHERE s.id IS NULL
UNION ALL
SELECT 'Payroll.staffId without a Staff parent', COUNT(*)
FROM dbo.Payroll p LEFT JOIN dbo.Staff s ON s.id = p.staffId WHERE s.id IS NULL
UNION ALL
SELECT 'StaffDocument.staffId without a Staff parent', COUNT(*)
FROM dbo.StaffDocument d LEFT JOIN dbo.Staff s ON s.id = d.staffId WHERE s.id IS NULL
UNION ALL
SELECT 'TrainerAvailability.staffId without a Staff parent', COUNT(*)
FROM dbo.TrainerAvailability ta LEFT JOIN dbo.Staff s ON s.id = ta.staffId WHERE s.id IS NULL
UNION ALL
SELECT 'TrainerSchedule.staffId without a Staff parent', COUNT(*)
FROM dbo.TrainerSchedule ts LEFT JOIN dbo.Staff s ON s.id = ts.staffId WHERE s.id IS NULL;

SELECT 'Shift bad ids' AS [check], COUNT(*) AS problems
FROM dbo.Shift WHERE [id] NOT LIKE '[0-9][0-9][0-9]' OR LEN([id]) <> 3
UNION ALL
SELECT 'CalendarDay bad ids', COUNT(*)
FROM dbo.CalendarDay WHERE [id] NOT LIKE '[0-9][0-9][0-9]' OR LEN([id]) <> 3
UNION ALL
SELECT 'Staff.shiftId pointing at a missing Shift', COUNT(*)
FROM dbo.Staff s LEFT JOIN dbo.Shift sh ON sh.id = s.shiftId WHERE s.shiftId IS NOT NULL AND sh.id IS NULL;

SELECT TOP 10 'Staff' AS [table], [id] FROM dbo.Staff ORDER BY [id];
SELECT TOP 10 'Shift' AS [table], [id], [name] FROM dbo.Shift ORDER BY [id];
SELECT TOP 10 'CalendarDay' AS [table], [id], [date], [dayType] FROM dbo.CalendarDay ORDER BY [date];

PRINT '';
PRINT '================ 5) SUMMARY ===========================================';
-- All problems columns above must be 0 and every [status] must be
-- 'OK - unchanged'. Then the upgrade is fully verified.
PRINT 'Review each result set above:';
PRINT '  - [status] must be OK - unchanged for every table (no data lost)';
PRINT '  - every [problems] count must be 0 (no orphans, all id formats correct)';
PRINT '  - the sample ids must match C|B|J|O/{year}/{000001}, EMP-00001, 001 ...';
GO

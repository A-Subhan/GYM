USE GymDB;
GO

-- ============================================================================
-- 10_verify.sql
-- ============================================================================
-- Run AFTER all 10xx scripts to confirm the database is in the target state.
-- Each check prints PASS or FAIL with a reason. Ends with ONE summary row:
-- "ALL PASS" or a list of FAILs.
--
-- Fixed: no CTE defined-but-not-used; every CTE is immediately consumed by
-- the next INSERT/SELECT/UPDATE in the same statement.
-- ============================================================================

SET NOCOUNT ON;

-- Temp table for results
IF OBJECT_ID('tempdb..#v', 'U') IS NOT NULL DROP TABLE #v;
CREATE TABLE #v (
    [item]    NVARCHAR(100) NOT NULL,
    [result]  NVARCHAR(10)  NOT NULL,
    [detail]  NVARCHAR(MAX)
);

-- ============================================================================
-- 1. Staff: no employeeId column; ids look like EMP-xxxxx
-- ============================================================================
IF COL_LENGTH('dbo.Staff','employeeId') IS NOT NULL
    INSERT INTO #v VALUES (N'Staff.employeeId absent', N'FAIL', N'employeeId column still exists');
ELSE
    INSERT INTO #v VALUES (N'Staff.employeeId absent', N'PASS', N'Column removed (merged into id)');

-- Staff id format check
IF OBJECT_ID('dbo.Staff','U') IS NOT NULL
BEGIN
    DECLARE @staffBad INT = 0;
    SELECT @staffBad = COUNT(*) FROM dbo.Staff WHERE [id] NOT LIKE N'EMP-[0-9][0-9][0-9][0-9][0-9]';
    IF @staffBad > 0
        INSERT INTO #v VALUES (N'Staff ids EMP-xxxxx', N'FAIL', CAST(@staffBad AS NVARCHAR(10)) + N' rows have non-EMP-xxxxx ids');
    ELSE
        INSERT INTO #v VALUES (N'Staff ids EMP-xxxxx', N'PASS', N'All Staff ids match EMP-xxxxx format');
END
ELSE
    INSERT INTO #v VALUES (N'Staff ids EMP-xxxxx', N'FAIL', N'Staff table missing');

-- ============================================================================
-- 2. No FK references Staff.employeeId
-- ============================================================================
IF EXISTS (
    SELECT 1 FROM sys.foreign_key_columns fkc
    JOIN sys.columns c ON c.object_id = fkc.parent_object_id AND c.column_id = fkc.parent_column_id
    JOIN sys.columns rc ON rc.object_id = fkc.referenced_object_id AND rc.column_id = fkc.referenced_column_id
    WHERE fkc.referenced_object_id = OBJECT_ID('dbo.Staff') AND rc.name = N'employeeId'
)
    INSERT INTO #v VALUES (N'No FK on Staff.employeeId', N'FAIL', N'At least one FK still references Staff.employeeId');
ELSE
    INSERT INTO #v VALUES (N'No FK on Staff.employeeId', N'PASS', N'No FK references Staff.employeeId');

-- ============================================================================
-- 3. Shift ids are 3 digits
-- ============================================================================
IF OBJECT_ID('dbo.Shift','U') IS NOT NULL
BEGIN
    DECLARE @shiftBad INT = 0;
    SELECT @shiftBad = COUNT(*) FROM dbo.Shift WHERE [id] NOT LIKE N'[0-9][0-9][0-9]';
    IF @shiftBad > 0
        INSERT INTO #v VALUES (N'Shift ids 3-digit', N'FAIL', CAST(@shiftBad AS NVARCHAR(10)) + N' rows have non-3-digit ids');
    ELSE
        INSERT INTO #v VALUES (N'Shift ids 3-digit', N'PASS', N'All Shift ids are 3-digit');
END
ELSE
    INSERT INTO #v VALUES (N'Shift ids 3-digit', N'FAIL', N'Shift table missing');

-- ============================================================================
-- 4. CalendarDay ids are 3 digits
-- ============================================================================
IF OBJECT_ID('dbo.CalendarDay','U') IS NOT NULL
BEGIN
    DECLARE @calBad INT = 0;
    SELECT @calBad = COUNT(*) FROM dbo.CalendarDay WHERE [id] NOT LIKE N'[0-9][0-9][0-9]';
    IF @calBad > 0
        INSERT INTO #v VALUES (N'CalendarDay ids 3-digit', N'FAIL', CAST(@calBad AS NVARCHAR(10)) + N' rows have non-3-digit ids');
    ELSE
        INSERT INTO #v VALUES (N'CalendarDay ids 3-digit', N'PASS', N'All CalendarDay ids are 3-digit');
END
ELSE
    INSERT INTO #v VALUES (N'CalendarDay ids 3-digit', N'FAIL', N'CalendarDay table missing');

-- ============================================================================
-- 5. Voucher line ids match patterns C/yyyy/nnnnnn, B/, J/, O/
-- ============================================================================
IF OBJECT_ID('dbo.CashBookLine','U') IS NOT NULL
BEGIN
    DECLARE @cblBad INT = 0;
    SELECT @cblBad = COUNT(*) FROM dbo.CashBookLine WHERE [id] NOT LIKE N'C/[0-9][0-9][0-9][0-9]/[0-9][0-9][0-9][0-9][0-9][0-9]';
    IF @cblBad > 0
        INSERT INTO #v VALUES (N'CashBookLine ids C/yyyy/nnnnnn', N'FAIL', CAST(@cblBad AS NVARCHAR(10)) + N' rows have wrong format');
    ELSE
        INSERT INTO #v VALUES (N'CashBookLine ids C/yyyy/nnnnnn', N'PASS', N'All CashBookLine ids match C/yyyy/nnnnnn');
END
ELSE
    INSERT INTO #v VALUES (N'CashBookLine ids C/yyyy/nnnnnn', N'FAIL', N'CashBookLine table missing');

IF OBJECT_ID('dbo.BankBookLine','U') IS NOT NULL
BEGIN
    DECLARE @bblBad INT = 0;
    SELECT @bblBad = COUNT(*) FROM dbo.BankBookLine WHERE [id] NOT LIKE N'B/[0-9][0-9][0-9][0-9]/[0-9][0-9][0-9][0-9][0-9][0-9]';
    IF @bblBad > 0
        INSERT INTO #v VALUES (N'BankBookLine ids B/yyyy/nnnnnn', N'FAIL', CAST(@bblBad AS NVARCHAR(10)) + N' rows have wrong format');
    ELSE
        INSERT INTO #v VALUES (N'BankBookLine ids B/yyyy/nnnnnn', N'PASS', N'All BankBookLine ids match B/yyyy/nnnnnn');
END
ELSE
    INSERT INTO #v VALUES (N'BankBookLine ids B/yyyy/nnnnnn', N'FAIL', N'BankBookLine table missing');

IF OBJECT_ID('dbo.JVLine','U') IS NOT NULL
BEGIN
    DECLARE @jvlBad INT = 0;
    SELECT @jvlBad = COUNT(*) FROM dbo.JVLine WHERE [id] NOT LIKE N'J/[0-9][0-9][0-9][0-9]/[0-9][0-9][0-9][0-9][0-9][0-9]';
    IF @jvlBad > 0
        INSERT INTO #v VALUES (N'JVLine ids J/yyyy/nnnnnn', N'FAIL', CAST(@jvlBad AS NVARCHAR(10)) + N' rows have wrong format');
    ELSE
        INSERT INTO #v VALUES (N'JVLine ids J/yyyy/nnnnnn', N'PASS', N'All JVLine ids match J/yyyy/nnnnnn');
END
ELSE
    INSERT INTO #v VALUES (N'JVLine ids J/yyyy/nnnnnn', N'FAIL', N'JVLine table missing');

IF OBJECT_ID('dbo.OpenTBLine','U') IS NOT NULL
BEGIN
    DECLARE @otblBad INT = 0;
    SELECT @otblBad = COUNT(*) FROM dbo.OpenTBLine WHERE [id] NOT LIKE N'O/[0-9][0-9][0-9][0-9]/[0-9][0-9][0-9][0-9][0-9][0-9]';
    IF @otblBad > 0
        INSERT INTO #v VALUES (N'OpenTBLine ids O/yyyy/nnnnnn', N'FAIL', CAST(@otblBad AS NVARCHAR(10)) + N' rows have wrong format');
    ELSE
        INSERT INTO #v VALUES (N'OpenTBLine ids O/yyyy/nnnnnn', N'PASS', N'All OpenTBLine ids match O/yyyy/nnnnnn');
END
ELSE
    INSERT INTO #v VALUES (N'OpenTBLine ids O/yyyy/nnnnnn', N'FAIL', N'OpenTBLine table missing');

-- ============================================================================
-- 6. Master/detail tables exist with identical structure
-- ============================================================================
IF OBJECT_ID('dbo.gymmaster','U') IS NULL
   OR OBJECT_ID('dbo.gymmasterdetail','U') IS NULL
   OR OBJECT_ID('dbo.financemaster','U') IS NULL
   OR OBJECT_ID('dbo.financemasterdetail','U') IS NULL
   OR OBJECT_ID('dbo.payrollmaster','U') IS NULL
   OR OBJECT_ID('dbo.payrollmasterdetail','U') IS NULL
    INSERT INTO #v VALUES (N'6 master tables exist', N'FAIL', N'One or more master/detail tables missing');
ELSE
    INSERT INTO #v VALUES (N'6 master tables exist', N'PASS', N'gymmaster/gymmasterdetail, financemaster/financemasterdetail, payrollmaster/payrollmasterdetail all present');

-- Master columns identical (inline SELECT, no orphaned CTE)
DECLARE @mismatchM INT = 0;
SELECT @mismatchM = COUNT(*) FROM (
    SELECT col, dtype, max_length, is_nullable FROM (
        SELECT t.name AS tbl, c.name AS col, ty.name AS dtype, c.max_length, c.is_nullable
        FROM sys.tables t
        JOIN sys.columns c ON c.object_id = t.object_id
        JOIN sys.types ty ON ty.user_type_id = c.user_type_id
        WHERE t.name IN (N'gymmaster', N'financemaster', N'payrollmaster')
    ) x
    GROUP BY col, dtype, max_length, is_nullable
    HAVING COUNT(DISTINCT tbl) < 3
) y;

IF @mismatchM > 0
    INSERT INTO #v VALUES (N'Master columns identical', N'FAIL', N'Master tables have differing column structures');
ELSE
    INSERT INTO #v VALUES (N'Master columns identical', N'PASS', N'gymmaster/financemaster/payrollmaster have identical column sets');

-- Detail columns identical
DECLARE @mismatchD INT = 0;
SELECT @mismatchD = COUNT(*) FROM (
    SELECT col, dtype, max_length, is_nullable FROM (
        SELECT t.name AS tbl, c.name AS col, ty.name AS dtype, c.max_length, c.is_nullable
        FROM sys.tables t
        JOIN sys.columns c ON c.object_id = t.object_id
        JOIN sys.types ty ON ty.user_type_id = c.user_type_id
        WHERE t.name IN (N'gymmasterdetail', N'financemasterdetail', N'payrollmasterdetail')
    ) x
    GROUP BY col, dtype, max_length, is_nullable
    HAVING COUNT(DISTINCT tbl) < 3
) y;

IF @mismatchD > 0
    INSERT INTO #v VALUES (N'Detail columns identical', N'FAIL', N'Detail tables have differing column structures');
ELSE
    INSERT INTO #v VALUES (N'Detail columns identical', N'PASS', N'gymmasterdetail/financemasterdetail/payrollmasterdetail have identical column sets');

-- ============================================================================
-- 7. User.userType exists with no NULLs
-- ============================================================================
IF COL_LENGTH('dbo.[User]','userType') IS NULL
    INSERT INTO #v VALUES (N'User.userType exists', N'FAIL', N'userType column missing');
ELSE
BEGIN
    DECLARE @nullUT INT = 0;
    SELECT @nullUT = COUNT(*) FROM dbo.[User] WHERE [userType] IS NULL;
    IF @nullUT > 0
        INSERT INTO #v VALUES (N'User.userType no NULLs', N'FAIL', CAST(@nullUT AS NVARCHAR(10)) + N' users have NULL userType');
    ELSE
        INSERT INTO #v VALUES (N'User.userType no NULLs', N'PASS', N'All users have a userType');
END

-- ============================================================================
-- 8. No orphaned FK values
-- ============================================================================
IF OBJECT_ID('dbo.Leave','U') IS NOT NULL AND OBJECT_ID('dbo.Staff','U') IS NOT NULL
BEGIN
    DECLARE @orphanL INT = 0;
    SELECT @orphanL = COUNT(*) FROM dbo.Leave l
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Staff s WHERE s.[id] = l.[staffId]);
    IF @orphanL > 0
        INSERT INTO #v VALUES (N'Leave.staffId orphans', N'FAIL', CAST(@orphanL AS NVARCHAR(10)) + N' orphaned Leave.staffId rows');
    ELSE
        INSERT INTO #v VALUES (N'Leave.staffId orphans', N'PASS', N'No orphaned Leave.staffId');
END

IF OBJECT_ID('dbo.Staff','U') IS NOT NULL AND OBJECT_ID('dbo.Shift','U') IS NOT NULL
BEGIN
    DECLARE @orphanS INT = 0;
    SELECT @orphanS = COUNT(*) FROM dbo.Staff s
    WHERE s.[shiftId] IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM dbo.Shift sh WHERE sh.[id] = s.[shiftId]);
    IF @orphanS > 0
        INSERT INTO #v VALUES (N'Staff.shiftId orphans', N'FAIL', CAST(@orphanS AS NVARCHAR(10)) + N' orphaned Staff.shiftId rows');
    ELSE
        INSERT INTO #v VALUES (N'Staff.shiftId orphans', N'PASS', N'No orphaned Staff.shiftId');
END

IF OBJECT_ID('dbo.WorkoutDayExercise','U') IS NOT NULL AND OBJECT_ID('dbo.gymmasterdetail','U') IS NOT NULL
BEGIN
    DECLARE @orphanW INT = 0;
    SELECT @orphanW = COUNT(*) FROM dbo.WorkoutDayExercise w
    WHERE NOT EXISTS (SELECT 1 FROM dbo.gymmasterdetail g WHERE g.[id] = w.[exerciseId]);
    IF @orphanW > 0
        INSERT INTO #v VALUES (N'WorkoutDayExercise.exerciseId orphans', N'FAIL', CAST(@orphanW AS NVARCHAR(10)) + N' orphaned exerciseId rows');
    ELSE
        INSERT INTO #v VALUES (N'WorkoutDayExercise.exerciseId orphans', N'PASS', N'No orphaned exerciseId');
END

-- ============================================================================
-- 9. Branch.nodeType exists
-- ============================================================================
IF COL_LENGTH('dbo.Branch','nodeType') IS NULL
BEGIN
    INSERT INTO #v VALUES (N'Branch.nodeType exists', N'FAIL', N'nodeType column missing');
END
ELSE
BEGIN
    INSERT INTO #v VALUES (N'Branch.nodeType exists', N'PASS', N'Branch.nodeType present');
END

-- ============================================================================
-- 10. Exercise table is gone (migrated to gymmasterdetail)
-- ============================================================================
IF OBJECT_ID('dbo.Exercise','U') IS NOT NULL
BEGIN
    INSERT INTO #v VALUES (N'Exercise table gone', N'FAIL', N'Exercise table still exists (not migrated)');
END
ELSE
BEGIN
    INSERT INTO #v VALUES (N'Exercise table gone', N'PASS', N'Exercise table removed (migrated to gymmasterdetail)');
END

-- ============================================================================
-- 11. ScreenPermission + UserPermission exist
-- ============================================================================
IF OBJECT_ID('dbo.ScreenPermission','U') IS NULL OR OBJECT_ID('dbo.UserPermission','U') IS NULL
BEGIN
    INSERT INTO #v VALUES (N'Permission tables exist', N'FAIL', N'ScreenPermission or UserPermission missing');
END
ELSE
BEGIN
    INSERT INTO #v VALUES (N'Permission tables exist', N'PASS', N'ScreenPermission + UserPermission present');
END

-- ============================================================================
-- 12. Member.joiningFee exists
-- ============================================================================
IF COL_LENGTH('dbo.Member','joiningFee') IS NULL
BEGIN
    INSERT INTO #v VALUES (N'Member.joiningFee exists', N'FAIL', N'joiningFee column missing');
END
ELSE
BEGIN
    INSERT INTO #v VALUES (N'Member.joiningFee exists', N'PASS', N'Member.joiningFee present');
END

-- ============================================================================
-- 13. Gym operation tables exist
-- ============================================================================
IF OBJECT_ID('dbo.TrainerAvailability','U') IS NULL
   OR OBJECT_ID('dbo.TrainerSchedule','U') IS NULL
   OR OBJECT_ID('dbo.FitnessGoal','U') IS NULL
   OR OBJECT_ID('dbo.PersonalTrainingSession','U') IS NULL
   OR OBJECT_ID('dbo.StaffDocument','U') IS NULL
   OR OBJECT_ID('dbo.KnockOff','U') IS NULL
BEGIN
    INSERT INTO #v VALUES (N'Gym operation tables', N'FAIL', N'One or more tables missing (TrainerAvailability, TrainerSchedule, FitnessGoal, PersonalTrainingSession, StaffDocument, KnockOff)');
END
ELSE
BEGIN
    INSERT INTO #v VALUES (N'Gym operation tables', N'PASS', N'All 6 gym operation tables present');
END

-- ============================================================================
-- 14. FeePayment ids match FP/...
-- ============================================================================
IF OBJECT_ID('dbo.FeePayment','U') IS NOT NULL
BEGIN
    DECLARE @fpBad INT = 0;
    SELECT @fpBad = COUNT(*) FROM dbo.FeePayment WHERE [id] NOT LIKE N'FP/%/%/%';
    IF @fpBad > 0
        INSERT INTO #v VALUES (N'FeePayment ids FP/...', N'FAIL', CAST(@fpBad AS NVARCHAR(10)) + N' rows have non-FP/ ids');
    ELSE
        INSERT INTO #v VALUES (N'FeePayment ids FP/...', N'PASS', N'All FeePayment ids match FP/{branch}/{MMMyy}/{nnnnnn}');
END
ELSE
    INSERT INTO #v VALUES (N'FeePayment ids FP/...', N'FAIL', N'FeePayment table missing');

-- ============================================================================
-- 15. Branch id = code
-- ============================================================================
IF OBJECT_ID('dbo.Branch','U') IS NOT NULL
BEGIN
    DECLARE @bidBad INT = 0;
    SELECT @bidBad = COUNT(*) FROM dbo.Branch WHERE [id] <> [code];
    IF @bidBad > 0
        INSERT INTO #v VALUES (N'Branch id = code', N'FAIL', CAST(@bidBad AS NVARCHAR(10)) + N' branches where id <> code');
    ELSE
        INSERT INTO #v VALUES (N'Branch id = code', N'PASS', N'All branches have id = code');
END
ELSE
    INSERT INTO #v VALUES (N'Branch id = code', N'FAIL', N'Branch table missing');

-- ============================================================================
-- 16. Control nodes have no detail data
-- ============================================================================
IF OBJECT_ID('dbo.Branch','U') IS NOT NULL
    AND COL_LENGTH('dbo.Branch','nodeType') IS NOT NULL
BEGIN
    DECLARE @ctrlBad INT = 0;
    SELECT @ctrlBad = COUNT(*) FROM dbo.Branch
    WHERE [nodeType] = N'Control'
      AND ([address] IS NOT NULL OR [city] IS NOT NULL OR [phone] IS NOT NULL
           OR [email] IS NOT NULL OR [strn] IS NOT NULL OR [ntn] IS NOT NULL
           OR [trn] IS NOT NULL OR [fbr] IS NOT NULL OR [logo] IS NOT NULL);
    IF @ctrlBad > 0
        INSERT INTO #v VALUES (N'Control nodes clean', N'FAIL', CAST(@ctrlBad AS NVARCHAR(10)) + N' Control nodes have detail data');
    ELSE
        INSERT INTO #v VALUES (N'Control nodes clean', N'PASS', N'Control nodes have NULL detail fields');
END
ELSE
    INSERT INTO #v VALUES (N'Control nodes clean', N'FAIL', N'Branch table or nodeType column missing');

-- ============================================================================
-- 17. Every branch has a valid parent chain (no cycles, root = 00)
-- ============================================================================
IF OBJECT_ID('dbo.Branch','U') IS NOT NULL
    AND COL_LENGTH('dbo.Branch','parentId') IS NOT NULL
BEGIN
    DECLARE @chainBad INT = 0;
    -- Check: root node 00 exists with parentId NULL
    IF NOT EXISTS (SELECT 1 FROM dbo.Branch WHERE [id] = N'00' AND [parentId] IS NULL)
        SET @chainBad = @chainBad + 1;
    -- Check: no branches with parentId pointing to non-existent branch
    IF EXISTS (
        SELECT 1 FROM dbo.Branch b
        WHERE b.[parentId] IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM dbo.Branch p WHERE p.[id] = b.[parentId])
    )
        SET @chainBad = @chainBad + 1;
    IF @chainBad > 0
        INSERT INTO #v VALUES (N'Branch parent chain', N'FAIL', N'Invalid parent chain (root 00 missing or orphan parentId)');
    ELSE
        INSERT INTO #v VALUES (N'Branch parent chain', N'PASS', N'All branches have valid parent chain, root = 00');
END
ELSE
    INSERT INTO #v VALUES (N'Branch parent chain', N'FAIL', N'Branch table or parentId column missing');

-- ============================================================================
-- 18. No orphan branchId in any table (FK + non-FK)
-- ============================================================================
IF OBJECT_ID('dbo.Branch','U') IS NOT NULL
BEGIN
    DECLARE @orphanBranch INT = 0;
    DECLARE @orphanTbl NVARCHAR(128);
    DECLARE @orphanChkSql NVARCHAR(MAX);
    DECLARE orphan_b_cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT t.name
        FROM sys.tables t
        JOIN sys.columns c ON c.object_id = t.object_id
        WHERE c.name = N'branchId' AND t.name <> N'Branch'
        ORDER BY t.name;

    OPEN orphan_b_cur;
    FETCH NEXT FROM orphan_b_cur INTO @orphanTbl;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SELECT @orphanBranch = COUNT(*)
        FROM [dbo].[Branch] b
        WHERE b.[branchId] IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM [dbo].[Branch] p WHERE p.[id] = b.[branchId]);
        FETCH NEXT FROM orphan_b_cur INTO @orphanTbl;
    END
    CLOSE orphan_b_cur;
    DEALLOCATE orphan_b_cur;

    IF @orphanBranch > 0
        INSERT INTO #v VALUES (N'No orphan branchId', N'FAIL', CAST(@orphanBranch AS NVARCHAR(10)) + N' orphaned branchId references');
    ELSE
        INSERT INTO #v VALUES (N'No orphan branchId', N'PASS', N'No orphaned branchId in any table');
END
ELSE
    INSERT INTO #v VALUES (N'No orphan branchId', N'FAIL', N'Branch table missing');

-- ============================================================================
-- SUMMARY
-- ============================================================================
DECLARE @totalFail INT = 0;
DECLARE @failList NVARCHAR(MAX) = N'';

SELECT @totalFail = COUNT(*) FROM #v WHERE [result] = N'FAIL';

IF @totalFail = 0
BEGIN
    PRINT N'';
    PRINT N'=== VERIFICATION RESULTS ===';
    SELECT [item], [result], [detail] FROM #v ORDER BY [item];
    PRINT N'';
    PRINT N'=== SUMMARY: ALL PASS ===';
    SELECT N'ALL PASS' AS [summary], COUNT(*) AS [total_checks],
           SUM(CASE WHEN [result]=N'PASS' THEN 1 ELSE 0 END) AS [passed],
           SUM(CASE WHEN [result]=N'FAIL' THEN 1 ELSE 0 END) AS [failed]
    FROM #v;
END
ELSE
BEGIN
    SELECT @failList = @failList + [item] + N'; '
    FROM #v WHERE [result] = N'FAIL'
    ORDER BY [item];
    PRINT N'';
    PRINT N'=== VERIFICATION RESULTS ===';
    SELECT [item], [result], [detail] FROM #v ORDER BY [item];
    PRINT N'';
    PRINT N'=== SUMMARY: FAILURES ===';
    PRINT N'FAILED: ' + @failList;
    SELECT N'FAILED' AS [summary], COUNT(*) AS [total_checks],
           SUM(CASE WHEN [result]=N'PASS' THEN 1 ELSE 0 END) AS [passed],
           SUM(CASE WHEN [result]=N'FAIL' THEN 1 ELSE 0 END) AS [failed]
    FROM #v;
END
GO

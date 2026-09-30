USE GymDB;
GO

-- ============================================================================
-- 10_zz_summary.sql
-- ============================================================================
-- Final status: reads dbo._UpgradeLog and compares to the list of expected
-- step names. Prints "SUCCESS" only if EVERY expected step is logged as
-- OK or SKIPPED. Any missing step or any FAILED step => "FAILED: <items>".
-- ============================================================================

SET NOCOUNT ON;

PRINT N'=== STEP SUMMARY ===';

-- Expected step names (must match the names used in each 10xx script).
-- This is the authoritative list of steps the upgrade MUST have attempted.
DECLARE @expected TABLE (step NVARCHAR(100) NOT NULL);
INSERT INTO @expected (step) VALUES
    (N'1a-userType'),
    (N'1b-roleId'),
    (N'1c-userType-data'),
    (N'2-joiningFee'),
    (N'3a-gymmaster'),
    (N'3b-gymmasterdetail'),
    (N'3c-financemaster'),
    (N'3d-financemasterdetail'),
    (N'3e-payrollmaster'),
    (N'3f-payrollmasterdetail'),
    (N'3g-idx-gymmasterdetail'),
    (N'3g-idx-financemasterdetail'),
    (N'3g-idx-payrollmasterdetail'),
    (N'3h-fk-gmd-master'),
    (N'3h-fk-fmd-master'),
    (N'3h-fk-pmd-master'),
    (N'4a2-Exercise-migrate'),
    (N'4b-MasterFile-finance'),
    (N'4c-payrollmasterfile'),
    (N'4d-gymmasterfile'),
    (N'5-Staff-merge'),
    (N'6-Shift-renumber'),
    (N'7-CalendarDay-renumber'),
    (N'9a-ScreenPermission'),
    (N'9b-UserPermission'),
    (N'9c-TrainerAvailability'),
    (N'9d-TrainerSchedule'),
    (N'9e-FitnessGoal'),
    (N'9f-PersonalTrainingSession'),
    (N'9g-StaffDocument'),
    (N'9h-KnockOff'),
    (N'9i-Staff-isDeleted'),
    (N'9j-Member-softdelete'),
    (N'10-Branch-nodeType'),
    (N'11a-IdSequence'),
    (N'11b-FeePayment-format');

-- Check for missing steps (logged by no entry at all)
DECLARE @missing INT = 0;
SELECT @missing = COUNT(*)
FROM @expected e
WHERE NOT EXISTS (SELECT 1 FROM dbo._UpgradeLog l WHERE l.step = e.step);

-- Check for failed steps
DECLARE @failed INT = 0;
SELECT @failed = COUNT(*)
FROM dbo._UpgradeLog l
WHERE l.status = N'FAILED';

-- Check for skipped steps (these count as OK)
DECLARE @skipped INT = 0;
SELECT @skipped = COUNT(*)
FROM dbo._UpgradeLog l
WHERE l.status = N'SKIPPED';

-- Check for OK steps
DECLARE @ok INT = 0;
SELECT @ok = COUNT(*)
FROM dbo._UpgradeLog l
WHERE l.status = N'OK';

-- Build the failure list
DECLARE @fail_list NVARCHAR(MAX) = N'';

IF @missing > 0
BEGIN
    SELECT @fail_list = @fail_list + N'MISSING: ' + e.step + N'; '
    FROM @expected e
    WHERE NOT EXISTS (SELECT 1 FROM dbo._UpgradeLog l WHERE l.step = e.step)
    ORDER BY e.step;
END

IF @failed > 0
BEGIN
    SELECT @fail_list = @fail_list + N'FAILED: ' + l.step + N' (' + LEFT(l.message, 80) + N'); '
    FROM dbo._UpgradeLog l
    WHERE l.status = N'FAILED'
    ORDER BY l.step;
END

-- Final verdict
IF @missing = 0 AND @failed = 0
BEGIN
    PRINT N'';
    PRINT N'=== UPGRADE RESULT ===';
    PRINT N'SUCCESS';
    PRINT N'(OK: ' + CAST(@ok AS NVARCHAR(10)) + N', Skipped: ' + CAST(@skipped AS NVARCHAR(10)) + N', Failed: 0, Missing: 0)';
    PRINT N'';
    PRINT N'Step details (from dbo._UpgradeLog):';
    SELECT [step], [status], [message], [at] FROM dbo._UpgradeLog ORDER BY [at];
END
ELSE
BEGIN
    PRINT N'';
    PRINT N'=== UPGRADE RESULT ===';
    PRINT N'FAILED - ' + @fail_list;
    PRINT N'(OK: ' + CAST(@ok AS NVARCHAR(10)) + N', Skipped: ' + CAST(@skipped AS NVARCHAR(10)) + N', Failed: ' + CAST(@failed AS NVARCHAR(10)) + N', Missing: ' + CAST(@missing AS NVARCHAR(10)) + N')';
    PRINT N'';
    PRINT N'Step details (from dbo._UpgradeLog):';
    SELECT [step], [status], [message], [at] FROM dbo._UpgradeLog ORDER BY [at];
END
GO

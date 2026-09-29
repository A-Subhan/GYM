-- ============================================================================
-- Contoura Gym ERP — Migration 11: REMOVE MODULES (rename to zz_backup)
-- ============================================================================
-- Removes (by RENAMING to zz_backup_<name>_<yyyymmdd> — never a hard drop):
--   Classes module          : dbo.GymClass, dbo.ClassEnrollment
--   Member Documents module : dbo.MemberDocument
--   Fitness Assessments     : dbo.FitnessAssessment
-- NOT touched: FitnessGoal, WorkoutAssignment, DietAssignment,
--              TrainerAvailability, TrainerSchedule, PersonalTrainingSession.
-- Permission catalog rows for the removed screens are purged (the seed
-- re-creates the remaining ones).
-- ============================================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET LANGUAGE us_english;
GO

DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'10_admin_defaults_security', @self = N'11_remove_removed_modules', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    11 already applied, skipping.'; RETURN; END
BEGIN TRY
    BEGIN TRAN;

    DECLARE @d sysname = CONVERT(varchar(8), GETDATE(), 112);
    DECLARE @t sysname, @new sysname, @rc int;

    -- obsolete reporting object on a removed table
    IF OBJECT_ID('dbo.vw_ClassEnrollmentSummary', 'V') IS NOT NULL
    BEGIN
        DROP VIEW dbo.vw_ClassEnrollmentSummary;
        PRINT '  dropped view vw_ClassEnrollmentSummary (module removed)';
    END

    DECLARE mods CURSOR LOCAL FAST_FORWARD FOR
        SELECT name FROM sys.tables
        WHERE schema_id = SCHEMA_ID('dbo')
          AND name IN ('GymClass', 'ClassEnrollment', 'FitnessAssessment', 'MemberDocument');
    OPEN mods;
    FETCH NEXT FROM mods INTO @t;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @rc = (SELECT SUM(p.rows) FROM sys.partitions p
                   WHERE p.object_id = OBJECT_ID('dbo.' + @t) AND p.index_id IN (0, 1));
        SET @new = 'zz_backup_' + @t + '_' + @d;
        IF OBJECT_ID('dbo.' + @new) IS NULL
        BEGIN
            EXEC sp_rename 'dbo.' + @t, @new;
            PRINT '  renamed dbo.' + @t + ' -> dbo.' + @new + ' (' + CAST(ISNULL(@rc, 0) AS varchar(10)) + ' rows preserved)';
        END
        ELSE
            PRINT '  dbo.' + @new + ' already exists - skipped';
        FETCH NEXT FROM mods INTO @t;
    END
    CLOSE mods; DEALLOCATE mods;

    -- purge permission catalog rows of removed screens
    IF OBJECT_ID('dbo.Permission') IS NOT NULL AND OBJECT_ID('dbo.RolePermission') IS NOT NULL
    BEGIN
        DECLARE @removed TABLE (id NVARCHAR(50));
        DELETE FROM dbo.Permission
        OUTPUT deleted.id INTO @removed
        WHERE [module] IN ('classes', 'classEnrollments', 'fitnessAssessments', 'memberDocuments')
           OR [code] LIKE 'classes.%' OR [code] LIKE 'classEnrollments.%'
           OR [code] LIKE 'fitnessAssessments.%' OR [code] LIKE 'memberDocuments.%';
        DELETE rp FROM dbo.RolePermission rp JOIN @removed r ON r.id = rp.permissionId;
        PRINT '  removed-module permissions purged';
    END
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'11_remove_removed_modules';
    THROW;
END CATCH
GO

-- Final verification + Success marker
DECLARE @g varchar(10);
EXEC dbo.__mig_ScriptGate @prev = N'10_admin_defaults_security', @self = N'11_remove_removed_modules', @action = @g OUTPUT;
IF @g = 'Skip' BEGIN PRINT '    11 already applied, skipping.'; RETURN; END
BEGIN TRY
    IF OBJECT_ID('dbo.GymClass') IS NOT NULL
        THROW 51110, 'verification failed: GymClass still present (should be renamed)', 1;
    IF OBJECT_ID('dbo.ClassEnrollment') IS NOT NULL
        THROW 51110, 'verification failed: ClassEnrollment still present (should be renamed)', 1;
    IF OBJECT_ID('dbo.FitnessAssessment') IS NOT NULL
        THROW 51110, 'verification failed: FitnessAssessment still present (should be renamed)', 1;
    IF OBJECT_ID('dbo.MemberDocument') IS NOT NULL
        THROW 51110, 'verification failed: MemberDocument still present (should be renamed)', 1;
    IF OBJECT_ID('dbo.FitnessGoal') IS NULL
        THROW 51110, 'verification failed: FitnessGoal must NOT be touched', 1;
    IF OBJECT_ID('dbo.PersonalTrainingSession') IS NULL
        THROW 51110, 'verification failed: PersonalTrainingSession must NOT be touched', 1;

    EXEC dbo.__mig_Done @self = N'11_remove_removed_modules';
    IF @@TRANCOUNT > 0 COMMIT TRAN;
    PRINT '=== 11 done ===';
END TRY
BEGIN CATCH
    EXEC dbo.__mig_Fail @self = N'11_remove_removed_modules';
    THROW;
END CATCH
GO

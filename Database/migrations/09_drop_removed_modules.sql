-- =====================================================================
-- Contoura Gym ERP — Migration 09 of 10
-- Drop removed modules: Gym Classes, Class Enrollments, Fitness
-- Assessments, Member Documents, legacy LeaveType table. Purge related
-- permission catalog rows (app seed re-creates the remaining ones).
-- Idempotent.
-- =====================================================================
SET NOCOUNT ON;
GO
PRINT '=== 09: drop removed modules ===';

IF OBJECT_ID('dbo.trg_ClassEnrollment_touchUpdatedAt','TR') IS NOT NULL DROP TRIGGER [dbo].[trg_ClassEnrollment_touchUpdatedAt];
GO
IF OBJECT_ID('dbo.ClassEnrollment') IS NOT NULL
    DROP TABLE [dbo].[ClassEnrollment];
IF OBJECT_ID('dbo.GymClass') IS NOT NULL
    DROP TABLE [dbo].[GymClass];
IF OBJECT_ID('dbo.FitnessAssessment') IS NOT NULL
    DROP TABLE [dbo].[FitnessAssessment];
IF OBJECT_ID('dbo.MemberDocument') IS NOT NULL
    DROP TABLE [dbo].[MemberDocument];
IF OBJECT_ID('dbo.LeaveType') IS NOT NULL
    DROP TABLE [dbo].[LeaveType];
GO
-- Remove permission codes belonging to removed screens (seed re-adds the rest)
IF OBJECT_ID('dbo.RolePermission') IS NOT NULL AND OBJECT_ID('dbo.Permission') IS NOT NULL
BEGIN
    DECLARE @removed TABLE ([id] NVARCHAR(50));
    DELETE FROM [dbo].[Permission]
    OUTPUT deleted.[id] INTO @removed
    WHERE [module] IN ('classes','classEnrollments','fitnessAssessments','memberDocuments')
       OR [code] LIKE 'classes.%' OR [code] LIKE 'classEnrollments.%'
       OR [code] LIKE 'fitnessAssessments.%' OR [code] LIKE 'memberDocuments.%';
    DELETE rp FROM [dbo].[RolePermission] rp JOIN @removed r ON r.[id] = rp.[permissionId];
    PRINT '  removed-module permissions purged.';
END
GO
PRINT '=== 09 done ===';

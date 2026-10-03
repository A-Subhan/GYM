-- ============================================================================
-- Contoura Gym Management System - STEP 11b (OPTIONAL): Overtime permissions
-- ============================================================================
-- The overtime API routes require 'overtime.edit' and 'overtime.delete'
-- permissions, but those two rows do not exist in [Permission] (and are not
-- granted to any role). Super Admin is fixed by app code (PERMISSION_CODES),
-- but non-admin roles can never be granted edit/delete on Overtime until
-- these rows exist.
--
-- Run ONLY if you want DB-level parity with the app's permission list.
-- Idempotent: re-running inserts nothing new.
-- Failure => transaction rollback + dbo._UpgradeLog FAILED row.
-- ============================================================================

USE [GymDB];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);

BEGIN TRY
    BEGIN TRAN;

    -- Permission rows (deterministic ids keep the script idempotent)
    IF NOT EXISTS (SELECT 1 FROM dbo.[Permission] WHERE [code] = N'overtime.edit')
        INSERT INTO dbo.[Permission] ([id], [module], [action], [code], [description])
        VALUES (N'perm-overtime-edit', N'overtime', N'edit', N'overtime.edit', N'Edit overtime entries');

    IF NOT EXISTS (SELECT 1 FROM dbo.[Permission] WHERE [code] = N'overtime.delete')
        INSERT INTO dbo.[Permission] ([id], [module], [action], [code], [description])
        VALUES (N'perm-overtime-delete', N'overtime', N'delete', N'overtime.delete', N'Delete overtime entries');

    -- Grant both to Super Admin so the DB matches the app's Super Admin set
    IF NOT EXISTS (SELECT 1 FROM dbo.[RolePermission]
                   WHERE [roleId] = N'cmud5j3ud003ztznciorwbydo'
                     AND [permissionId] = N'perm-overtime-edit')
        INSERT INTO dbo.[RolePermission] ([roleId], [permissionId])
        VALUES (N'cmud5j3ud003ztznciorwbydo', N'perm-overtime-edit');

    IF NOT EXISTS (SELECT 1 FROM dbo.[RolePermission]
                   WHERE [roleId] = N'cmud5j3ud003ztznciorwbydo'
                     AND [permissionId] = N'perm-overtime-delete')
        INSERT INTO dbo.[RolePermission] ([roleId], [permissionId])
        VALUES (N'cmud5j3ud003ztznciorwbydo', N'perm-overtime-delete');

    COMMIT TRAN;

    INSERT INTO dbo._UpgradeLog (step, status, message)
    VALUES (N'11b-overtime-permissions', N'OK', N'overtime.edit/delete permission rows + Super Admin grants ensured');
    PRINT N'  11b-overtime-permissions: OK';
END TRY
BEGIN CATCH
    SET @eNum = ERROR_NUMBER();
    SET @eLine = ERROR_LINE();
    SET @eMsg = ERROR_MESSAGE();
    IF XACT_STATE() <> 0 ROLLBACK TRAN;
    INSERT INTO dbo._UpgradeLog (step, status, message)
    VALUES (N'11b-overtime-permissions', N'FAILED',
            N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
    PRINT N'  11b-overtime-permissions: FAILED - Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg;
END CATCH
GO

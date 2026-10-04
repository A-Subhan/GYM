-- ============================================================================
-- Contoura Gym Management System - STEP 12c: missing permission rows
-- (payroll.delete + leaves.edit)
-- ============================================================================
-- API routes require these permission codes but the rows do not exist in
-- [Permission] (and are not granted to any role):
--   payroll.delete — PayrollRoute DELETE (draft payroll runs) — hard check:
--                    without it NOBODY can delete a draft payroll run.
--   leaves.edit    — LeaveRoute PATCH — soft check (leaves.approve also
--                    passes), but non-admin roles can never be granted it
--                    until the row exists.
-- Super Admin is fixed by app code (PERMISSION_CODES), the grants below give
-- the DB parity. Pattern matches 11b.
--
-- Idempotent: re-running inserts nothing new.
-- Failure => transaction rollback + dbo._UpgradeLog FAILED row.
-- ============================================================================

USE [GymDB];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

DECLARE @eNum INT, @eLine INT, @eMsg NVARCHAR(MAX);

BEGIN TRY
    BEGIN TRAN;

    -- Permission rows (deterministic ids keep the script idempotent)
    IF NOT EXISTS (SELECT 1 FROM dbo.[Permission] WHERE [code] = N'payroll.delete')
        INSERT INTO dbo.[Permission] ([id], [module], [action], [code], [description])
        VALUES (N'perm-payroll-delete', N'payroll', N'delete', N'payroll.delete', N'Delete draft payroll runs');

    IF NOT EXISTS (SELECT 1 FROM dbo.[Permission] WHERE [code] = N'leaves.edit')
        INSERT INTO dbo.[Permission] ([id], [module], [action], [code], [description])
        VALUES (N'perm-leaves-edit', N'leaves', N'edit', N'leaves.edit', N'Edit pending leaves');

    -- Grant both to Super Admin so the DB matches the app's Super Admin set
    IF NOT EXISTS (SELECT 1 FROM dbo.[RolePermission]
                   WHERE [roleId] = N'cmud5j3ud003ztznciorwbydo'
                     AND [permissionId] = N'perm-payroll-delete')
        INSERT INTO dbo.[RolePermission] ([roleId], [permissionId])
        VALUES (N'cmud5j3ud003ztznciorwbydo', N'perm-payroll-delete');

    IF NOT EXISTS (SELECT 1 FROM dbo.[RolePermission]
                   WHERE [roleId] = N'cmud5j3ud003ztznciorwbydo'
                     AND [permissionId] = N'perm-leaves-edit')
        INSERT INTO dbo.[RolePermission] ([roleId], [permissionId])
        VALUES (N'cmud5j3ud003ztznciorwbydo', N'perm-leaves-edit');

    COMMIT TRAN;

    INSERT INTO dbo._UpgradeLog (step, status, message)
    VALUES (N'12c-payroll-permissions', N'OK', N'payroll.delete + leaves.edit permission rows + Super Admin grants ensured');
    PRINT N'  12c-payroll-permissions: OK';
END TRY
BEGIN CATCH
    SET @eNum = ERROR_NUMBER();
    SET @eLine = ERROR_LINE();
    SET @eMsg = ERROR_MESSAGE();
    IF XACT_STATE() <> 0 ROLLBACK TRAN;
    INSERT INTO dbo._UpgradeLog (step, status, message)
    VALUES (N'12c-payroll-permissions', N'FAILED',
            N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
    PRINT N'  12c-payroll-permissions: FAILED - Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg;
END CATCH
GO

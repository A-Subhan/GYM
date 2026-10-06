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
-- FRESH-INSTALL SAFE: this script looks up the Super Admin role by NAME
-- (N'Super Admin') and the permission rows by CODE, so it works on a fresh
-- install (where role id is ROL-001 and permission ids are PRM-####) as
-- well as on a live DB that has already run the legacy 11b/12c with cuid
-- role ids. New permission rows get the next free PRM-#### id by scanning
-- existing PRM-#### ids + 1.
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

    -- Resolve the Super Admin role id by NAME (works on both fresh installs
    -- with ROL-001 and legacy DBs with cuid role ids).
    DECLARE @superAdminRoleId NVARCHAR(50) = N'';
    SELECT @superAdminRoleId = [id] FROM dbo.[Role] WHERE [name] = N'Super Admin';
    IF @superAdminRoleId IS NULL OR @superAdminRoleId = N''
    BEGIN
        -- Fresh install seed uses 'Super Admin'; legacy seeds use the same
        -- name. If neither exists, this script is a no-op for the grants
        -- but we still insert the permission rows.
        RAISERROR(N'Super Admin role not found by name; permission rows will be inserted but grants skipped', 10, 1);
        SET @superAdminRoleId = N'';
    END

    -- Compute the next free PRM-#### id from existing rows (max + 1).
    -- Returns 1 if no PRM- rows exist yet. Idempotent: re-running finds the
    -- already-inserted rows and inserts nothing new.
    DECLARE @prm_max INT = 0;
    SELECT @prm_max = MAX(CAST(SUBSTRING([id], 5, 20) AS INT))
    FROM dbo.[Permission]
    WHERE [id] LIKE N'PRM-%' AND SUBSTRING([id], 5, 20) NOT LIKE N'%[^0-9]%';
    IF @prm_max IS NULL SET @prm_max = 0;

    -- Permission rows: look up by code so the script is idempotent and
    -- format-agnostic. New rows get the next PRM-#### id.
    DECLARE @next_prm INT = @prm_max;
    DECLARE @new_prm_id NVARCHAR(50);

    IF NOT EXISTS (SELECT 1 FROM dbo.[Permission] WHERE [code] = N'payroll.delete')
    BEGIN
        SET @next_prm = @next_prm + 1;
        SET @new_prm_id = N'PRM-' + RIGHT(N'000' + CAST(@next_prm AS NVARCHAR(10)), 4);
        INSERT INTO dbo.[Permission] ([id], [module], [action], [code], [description])
        VALUES (@new_prm_id, N'payroll', N'delete', N'payroll.delete', N'Delete draft payroll runs');
    END

    IF NOT EXISTS (SELECT 1 FROM dbo.[Permission] WHERE [code] = N'leaves.edit')
    BEGIN
        SET @next_prm = @next_prm + 1;
        SET @new_prm_id = N'PRM-' + RIGHT(N'000' + CAST(@next_prm AS NVARCHAR(10)), 4);
        INSERT INTO dbo.[Permission] ([id], [module], [action], [code], [description])
        VALUES (@new_prm_id, N'leaves', N'edit', N'leaves.edit', N'Edit pending leaves');
    END

    -- Grant both to Super Admin (looked up by NAME) so the DB matches the
    -- app's Super Admin set. Grant by joining on the permission code so we
    -- don't depend on the permission id format.
    IF @superAdminRoleId <> N''
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM dbo.[RolePermission] rp
            JOIN dbo.[Permission] p ON rp.[permissionId] = p.[id]
            WHERE rp.[roleId] = @superAdminRoleId AND p.[code] = N'payroll.delete'
        )
        BEGIN
            DECLARE @payroll_delete_id NVARCHAR(50) = (SELECT [id] FROM dbo.[Permission] WHERE [code] = N'payroll.delete');
            INSERT INTO dbo.[RolePermission] ([roleId], [permissionId])
            VALUES (@superAdminRoleId, @payroll_delete_id);
        END

        IF NOT EXISTS (
            SELECT 1 FROM dbo.[RolePermission] rp
            JOIN dbo.[Permission] p ON rp.[permissionId] = p.[id]
            WHERE rp.[roleId] = @superAdminRoleId AND p.[code] = N'leaves.edit'
        )
        BEGIN
            DECLARE @leaves_edit_id NVARCHAR(50) = (SELECT [id] FROM dbo.[Permission] WHERE [code] = N'leaves.edit');
            INSERT INTO dbo.[RolePermission] ([roleId], [permissionId])
            VALUES (@superAdminRoleId, @leaves_edit_id);
        END
    END

    COMMIT TRAN;

    INSERT INTO dbo._UpgradeLog (step, status, message)
    VALUES (N'12c-payroll-permissions', N'OK', N'payroll.delete + leaves.edit permission rows + Super Admin grants ensured (role by name, perms by code)');
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

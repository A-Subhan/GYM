-- ============================================================================
-- Contoura Gym Management System — STEP 5: Triggers
-- ============================================================================
-- updatedAt maintenance, payroll audit trail. NOTE: there is deliberately NO balance-check trigger on the book tables - OpenTB must allow unbalanced saves.
-- Matches the FINAL schema (charts id = account code; CashBook/BankBook/JV/
-- OpenTB books; bookVoucherId references). Identical to the objects created
-- by Database/migrations/12_views_procedures_rebuild.sql.
-- Safe to re-run (CREATE OR ALTER).
-- ============================================================================

USE [GymDB];
GO

-- NOTE: there is deliberately NO balance-check trigger on the book tables:
-- OpenTB must allow saving an unbalanced trial balance; cash/bank voucher
-- balance rules are enforced by the application.
PRINT '  functions, views, procedures and triggers rebuilt';

-- ---- batch 5: triggers --------------------------------------------------------

CREATE OR ALTER TRIGGER dbo.trg_Member_touchUpdatedAt ON dbo.Member AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    UPDATE m SET updatedAt = GETDATE()
    FROM dbo.Member m
    INNER JOIN inserted i ON i.id = m.id
    INNER JOIN deleted  d ON d.id = i.id
    WHERE i.updatedAt = d.updatedAt;
END
GO

CREATE OR ALTER TRIGGER dbo.trg_Staff_touchUpdatedAt ON dbo.Staff AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    UPDATE s SET updatedAt = GETDATE()
    FROM dbo.Staff s
    INNER JOIN inserted i ON i.id = s.id
    INNER JOIN deleted  d ON d.id = i.id
    WHERE i.updatedAt = d.updatedAt;
END
GO

CREATE OR ALTER TRIGGER dbo.trg_charts_touchUpdatedAt ON dbo.charts AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    UPDATE a SET updatedAt = GETDATE()
    FROM dbo.charts a
    INNER JOIN inserted i ON i.id = a.id
    INNER JOIN deleted  d ON d.id = i.id
    WHERE i.updatedAt = d.updatedAt;
END
GO

CREATE OR ALTER TRIGGER dbo.trg_Fee_touchUpdatedAt ON dbo.Fee AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    UPDATE f SET updatedAt = GETDATE()
    FROM dbo.Fee f
    INNER JOIN inserted i ON i.id = f.id
    INNER JOIN deleted  d ON d.id = i.id
    WHERE i.updatedAt = d.updatedAt;
END
GO

CREATE OR ALTER TRIGGER dbo.trg_InventoryItem_touchUpdatedAt ON dbo.InventoryItem AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    UPDATE it SET updatedAt = GETDATE()
    FROM dbo.InventoryItem it
    INNER JOIN inserted i ON i.id = it.id
    INNER JOIN deleted  d ON d.id = i.id
    WHERE i.updatedAt = d.updatedAt;
END
GO

CREATE OR ALTER TRIGGER dbo.trg_Payroll_Audit ON dbo.Payroll AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.AuditLog (id, userId, action, module, details, ipAddress, location, createdAt)
    SELECT REPLACE(CAST(NEWID() AS NVARCHAR(50)), '-', ''),
           NULL, N'PAYROLL_STATUS', N'payroll',
           N'{"payrollNo":"' + i.payrollNo + N'","from":"' + ISNULL(d.status, N'') + N'","to":"' + ISNULL(i.status, N'') + N'"}',
           NULL, NULL, GETDATE()
    FROM inserted i
    INNER JOIN deleted d ON d.id = i.id
    WHERE ISNULL(d.status, N'') <> ISNULL(i.status, N'');
END

GO
PRINT 'Step 05 complete: final triggers created.';
GO

-- ============================================================================
-- Contoura Gym Management System — STEP 5: Triggers
-- ============================================================================
-- 1. updatedAt maintenance for key transactional tables
-- 2. Voucher integrity guard (a posted voucher must balance)
-- 3. Audit logging for payroll status changes
--
-- NOTE: triggers intentionally do NOT adjust InventoryItem.quantity — the
-- backend application already maintains stock levels when stock movements
-- are recorded, and double-adjusting would corrupt stock.
-- Safe to re-run (CREATE OR ALTER).
-- ============================================================================

USE [GymDB];
GO

-- ================================================================
-- 1) updatedAt maintenance (only when the row actually changed)
-- ================================================================

GO
CREATE OR ALTER TRIGGER dbo.trg_Member_touchUpdatedAt ON dbo.[Member] AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    UPDATE m SET updatedAt = GETDATE()
    FROM dbo.[Member] m
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

CREATE OR ALTER TRIGGER dbo.trg_Account_touchUpdatedAt ON dbo.[Account] AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    UPDATE a SET updatedAt = GETDATE()
    FROM dbo.[Account] a
    INNER JOIN inserted i ON i.id = a.id
    INNER JOIN deleted  d ON d.id = i.id
    WHERE i.updatedAt = d.updatedAt;
END
GO

CREATE OR ALTER TRIGGER dbo.trg_Voucher_touchUpdatedAt ON dbo.Voucher AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    UPDATE v SET updatedAt = GETDATE()
    FROM dbo.Voucher v
    INNER JOIN inserted i ON i.id = v.id
    INNER JOIN deleted  d ON d.id = i.id
    WHERE i.updatedAt = d.updatedAt;
END
GO

CREATE OR ALTER TRIGGER dbo.trg_Fee_touchUpdatedAt ON dbo.[Fee] AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    UPDATE f SET updatedAt = GETDATE()
    FROM dbo.[Fee] f
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

-- ================================================================
-- 2) Voucher integrity: posted vouchers must balance (Dr == Cr)
-- ================================================================

GO
CREATE OR ALTER TRIGGER dbo.trg_Voucher_BalanceCheck ON dbo.Voucher AFTER INSERT, UPDATE AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT 1
        FROM inserted i
        WHERE i.status = N'Posted'
          AND EXISTS (SELECT 1 FROM dbo.VoucherLine l WHERE l.voucherId = i.id)
          AND ISNULL(i.totalDebit, 0) <> ISNULL(i.totalCredit, 0)
    )
    BEGIN
        ROLLBACK TRAN;
        ;THROW 51001, 'A posted voucher must have totalDebit equal to totalCredit.', 1;
    END
END
GO

-- ================================================================
-- 3) Audit logging for payroll status changes (additive, safe)
-- ================================================================

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

PRINT 'Step 05 complete: triggers created.';
GO

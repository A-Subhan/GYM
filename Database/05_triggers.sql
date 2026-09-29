-- ============================================================================
-- Contoura Gym Management System - STEP 5: Triggers (FINAL design)
-- ============================================================================
-- * updatedAt maintenance triggers for the hot tables
-- * payroll status audit trail
-- * trg_Defaults_CompanyNameLock - Defaults.companyName is WRITE-ONCE
--   (documented in Backend/prisma/schema.prisma): once a company name is set
--   it cannot be changed or cleared. First INSERT may set it freely.
--
-- There is deliberately NO balance-check trigger on the book tables:
--   OpenTB must allow saving an unbalanced trial balance; cash/bank voucher
--   balance rules are enforced by the application.
--
-- Every CREATE TRIGGER statement is the first statement in its own batch (GO).
-- Safe to re-run (CREATE OR ALTER).
-- Run after 02_schema_tables.sql.
-- ============================================================================

USE [GymDB];
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ---------------------------------------------------------------------------
-- updatedAt maintenance
-- ---------------------------------------------------------------------------

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

-- ---------------------------------------------------------------------------
-- Payroll status audit trail
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- Admin Defaults: companyName is WRITE-ONCE
-- (Backend/prisma/schema.prisma - model Defaults, see trg_Defaults_CompanyNameLock)
-- ---------------------------------------------------------------------------
CREATE OR ALTER TRIGGER dbo.trg_Defaults_CompanyNameLock ON dbo.Defaults AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT 1
        FROM inserted i
        INNER JOIN deleted d ON d.id = i.id
        WHERE d.companyName IS NOT NULL            -- a name was already set
          AND (i.companyName IS NULL               -- ... and is being cleared
               OR i.companyName <> d.companyName)  -- ... or is being changed
    )
    BEGIN
        ;THROW 55100, 'Company Name is locked by Admin Defaults: it cannot be changed once set.', 1;
    END
END
GO

PRINT 'Step 05 complete: final triggers created (updatedAt touch, payroll audit, Defaults company-name lock).';
GO

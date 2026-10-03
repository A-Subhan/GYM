-- ============================================================================
-- Contoura Gym Management System - STEP 04b: vw_BookLedger excludes deleted
-- vouchers (FRESH-INSTALL companion to 12a)
-- ============================================================================
-- 03_views_functions.sql creates dbo.vw_BookLedger WITHOUT an isDeleted
-- filter (executed script, left untouched by design). This file applies the
-- same CREATE OR ALTER VIEW that 12a applies on the live database, so a
-- fresh install (01, 02, 03, 04, 04b, 05, ...) ends in the same state.
--
-- Idempotent: re-running re-creates the same definition.
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
    EXEC (N'CREATE OR ALTER VIEW dbo.vw_BookLedger
AS
SELECT ''CASHBOOK'' AS bookType, cl.id AS lineId, cl.voucherId, cb.voucherType, cb.voucherDate,
       cb.branchId, cl.accountId, c.name AS accountName, c.accountType,
       cl.debit, cl.credit, cl.amount, cl.taxPercent, cl.taxAmount, cl.total,
       cl.billType, cl.chequeNo, cl.chequeAmount, cl.lineDescription, cl.status AS lineStatus, cb.status AS voucherStatus
FROM dbo.CashBook cb JOIN dbo.CashBookLine cl ON cl.voucherId = cb.id
JOIN dbo.charts c ON c.id = cl.accountId
WHERE cb.isDeleted = 0
UNION ALL
SELECT ''BANKBOOK'', bl.id, bl.voucherId, bb.voucherType, bb.voucherDate,
       bb.branchId, bl.accountId, c.name, c.accountType,
       bl.debit, bl.credit, bl.amount, bl.taxPercent, bl.taxAmount, bl.total,
       bl.billType, bl.chequeNo, bl.chequeAmount, bl.lineDescription, bl.status, bb.status
FROM dbo.BankBook bb JOIN dbo.BankBookLine bl ON bl.voucherId = bb.id
JOIN dbo.charts c ON c.id = bl.accountId
WHERE bb.isDeleted = 0
UNION ALL
SELECT ''JV'', jl.id, jl.voucherId, j.voucherType, j.voucherDate,
       j.branchId, jl.accountId, c.name, c.accountType,
       jl.debit, jl.credit, jl.amount, jl.taxPercent, jl.taxAmount, jl.total,
       NULL, NULL, NULL, jl.lineDescription, jl.status, j.status
FROM dbo.JV j JOIN dbo.JVLine jl ON jl.voucherId = j.id
JOIN dbo.charts c ON c.id = jl.accountId
WHERE j.isDeleted = 0
UNION ALL
SELECT ''OTB'', ol.id, ol.voucherId, o.voucherType, o.voucherDate,
       o.branchId, ol.accountId, c.name, c.accountType,
       ol.debit, ol.credit, ol.amount, NULL, NULL, NULL,
       NULL, NULL, NULL, ol.lineDescription, ol.status, o.status
FROM dbo.OpenTB o JOIN dbo.OpenTBLine ol ON ol.voucherId = o.id
JOIN dbo.charts c ON c.id = ol.accountId
WHERE o.isDeleted = 0;');

    INSERT INTO dbo._UpgradeLog (step, status, message)
    VALUES (N'04b-fix-ledger-view', N'OK', N'vw_BookLedger (re)created excluding vouchers with isDeleted = 1');
    PRINT N'  04b-fix-ledger-view: OK';
END TRY
BEGIN CATCH
    SET @eNum = ERROR_NUMBER();
    SET @eLine = ERROR_LINE();
    SET @eMsg = ERROR_MESSAGE();
    IF XACT_STATE() <> 0 ROLLBACK TRAN;
    INSERT INTO dbo._UpgradeLog (step, status, message)
    VALUES (N'04b-fix-ledger-view', N'FAILED',
            N'Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg);
    PRINT N'  04b-fix-ledger-view: FAILED - Err ' + CAST(@eNum AS NVARCHAR(10)) + N' at line ' + CAST(@eLine AS NVARCHAR(10)) + N': ' + @eMsg;
END CATCH
GO

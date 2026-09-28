-- =====================================================================
-- Contoura Gym ERP — Migration 03 of 10
-- Initialize IdSequence counters from existing data (per branch & period)
-- so new IDs never collide with legacy rows. Keys follow Backend/src/lib/ids.ts.
-- Idempotent: only inserts missing keys.
-- =====================================================================
SET NOCOUNT ON;
GO
PRINT '=== 03: init sequences ===';

-- Book voucher sequences: {TYPE}/{branchCode}/{MMMyy}
INSERT INTO [dbo].[IdSequence] ([key], [next])
SELECT t.[key], MAX(t.[seq]) + 1
FROM (
    SELECT CONCAT(v.[voucherType], '/', b.[code], '/', UPPER(FORMAT(v.[voucherDate], 'MMMyy')), '/',
                  RIGHT(v.[voucherNo], 6)) AS dummy,
           CONCAT(v.[voucherType], '/', b.[code], '/', UPPER(FORMAT(v.[voucherDate], 'MMMyy'))) AS [key],
           CAST(RIGHT(v.[voucherNo], 6) AS INT) AS [seq]
    FROM [dbo].[Voucher] v
    JOIN [dbo].[Branch] b ON b.[id] = v.[branchId]
    WHERE v.[voucherNo] LIKE '%\_____%' ESCAPE '\'  -- legacy format TYPE-YY-00001 handled below
) t
WHERE TRY_CAST(t.[seq] AS INT) IS NOT NULL
GROUP BY t.[key]
EXCEPT
SELECT [key], [next] FROM [dbo].[IdSequence];
GO
-- Legacy numbering (TYPE-YY-00001): seed the new-format key with the legacy count
INSERT INTO [dbo].[IdSequence] ([key], [next])
SELECT CONCAT([voucherType], '/', b.[code], '/', UPPER(FORMAT([voucherDate], 'MMMyy'))), COUNT(*) + 1
FROM [dbo].[Voucher] v
JOIN [dbo].[Branch] b ON b.[id] = v.[branchId]
GROUP BY [voucherType], b.[code], UPPER(FORMAT([voucherDate], 'MMMyy'))
EXCEPT
SELECT [key], [next] FROM [dbo].[IdSequence];
GO

-- Member sequences: {branchCode}/{MMMyy}/{00001}
INSERT INTO [dbo].[IdSequence] ([key], [next])
SELECT CONCAT('MEMBER/', b.[code], '/', UPPER(FORMAT(m.[joiningDate], 'MMMyy'))), COUNT(*) + 1
FROM [dbo].[Member] m
JOIN [dbo].[Branch] b ON b.[id] = m.[branchId]
GROUP BY b.[code], UPPER(FORMAT(m.[joiningDate], 'MMMyy'))
EXCEPT
SELECT [key], [next] FROM [dbo].[IdSequence];
GO

-- Fee sequences: {branchCode}/{MMMyy}/{00001}
INSERT INTO [dbo].[IdSequence] ([key], [next])
SELECT CONCAT('FEE/', b.[code], '/', UPPER(FORMAT(f.[billingPeriodStart], 'MMMyy'))), COUNT(*) + 1
FROM [dbo].[Fee] f
JOIN [dbo].[Branch] b ON b.[id] = f.[branchId]
GROUP BY b.[code], UPPER(FORMAT(f.[billingPeriodStart], 'MMMyy'))
EXCEPT
SELECT [key], [next] FROM [dbo].[IdSequence];
GO

-- Global entity sequences: prospects, membership plans, equipment, leaves, branches, employees, knock-offs
INSERT INTO [dbo].[IdSequence] ([key], [next])
SELECT 'PROSPECT',      ISNULL(MAX(seq), 0) + 1 FROM (SELECT CAST(SUBSTRING([prospectId], 3, 20) AS INT) AS seq FROM [dbo].[Prospect] WHERE [prospectId] LIKE 'p-%') x
EXCEPT SELECT [key], [next] FROM [dbo].[IdSequence];
INSERT INTO [dbo].[IdSequence] ([key], [next])
SELECT 'MEMBERSHIPPLAN', ISNULL(MAX(seq), 0) + 1 FROM (SELECT CAST(SUBSTRING([code], 4, 20) AS INT) AS seq FROM [dbo].[MembershipPlan] WHERE [code] LIKE 'MP-%') x
EXCEPT SELECT [key], [next] FROM [dbo].[IdSequence];
INSERT INTO [dbo].[IdSequence] ([key], [next])
SELECT 'EQUIPMENT',     ISNULL(MAX(seq), 0) + 1 FROM (SELECT CAST(SUBSTRING([code], 4, 20) AS INT) AS seq FROM [dbo].[Equipment] WHERE [code] LIKE 'EQ-%') x
EXCEPT SELECT [key], [next] FROM [dbo].[IdSequence];
INSERT INTO [dbo].[IdSequence] ([key], [next])
SELECT 'BRANCH',        ISNULL(MAX(seq), 0) + 1 FROM (SELECT CAST(SUBSTRING([code], 4, 20) AS INT) AS seq FROM [dbo].[Branch] WHERE [code] LIKE 'BR-%') x
EXCEPT SELECT [key], [next] FROM [dbo].[IdSequence];
INSERT INTO [dbo].[IdSequence] ([key], [next])
SELECT 'EMPLOYEE',      ISNULL(MAX(seq), 0) + 1 FROM (SELECT CAST(SUBSTRING([employeeId], 5, 20) AS INT) AS seq FROM [dbo].[Staff] WHERE [employeeId] LIKE 'EMP-%') x
EXCEPT SELECT [key], [next] FROM [dbo].[IdSequence];
INSERT INTO [dbo].[IdSequence] ([key], [next])
SELECT 'LEAVE',         ISNULL(MAX(seq), 0) + 1 FROM (SELECT CAST(SUBSTRING([leaveNo], 4, 20) AS INT) AS seq FROM [dbo].[Leave] WHERE [leaveNo] LIKE 'LV-%' AND [leaveNo] IS NOT NULL) x
EXCEPT SELECT [key], [next] FROM [dbo].[IdSequence];
INSERT INTO [dbo].[IdSequence] ([key], [next])
SELECT 'KOFF/{branchCode}', 1 FROM [dbo].[Branch] b
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[IdSequence] WHERE [key] = 'KOFF/' + b.[code]);
GO
PRINT '=== 03 done ===';

-- =====================================================================
-- Contoura Gym ERP — Migration 06 of 10
-- Regenerate business IDs into the confirmed formats:
--   Members / Fees : {branchCode}/{MMMyy}/{00001}
--   Prospects      : p-00001
--   MembershipPlan : MP-0001
--   Equipment      : EQ-00001
-- Old IDs preserved in __biz_id_map for reference/audit.
-- Idempotent: rows already matching the target pattern are skipped.
-- =====================================================================
SET NOCOUNT ON;
GO
PRINT '=== 06: regenerate business IDs ===';

IF OBJECT_ID('dbo.__biz_id_map') IS NOT NULL DROP TABLE [dbo].[__biz_id_map];
CREATE TABLE [dbo].[__biz_id_map] (
    [entity]    NVARCHAR(50) NOT NULL,
    [tablePk]   NVARCHAR(50) NOT NULL,
    [oldId]     NVARCHAR(50) NOT NULL,
    [newId]     NVARCHAR(50) NOT NULL,
    PRIMARY KEY ([entity], [tablePk])
);
GO

-- 1. Members: {branchCode}/{MMMyy}/{00001}
;WITH R AS (
    SELECT m.[id], b.[code] AS branchCode, m.[memberId],
           ROW_NUMBER() OVER (PARTITION BY b.[code], UPPER(FORMAT(m.[joiningDate],'MMMyy'))
                              ORDER BY m.[joiningDate], m.[createdAt]) AS rn
    FROM [dbo].[Member] m JOIN [dbo].[Branch] b ON b.[id] = m.[branchId]
    WHERE m.[memberId] NOT LIKE '[A-Z0-9-]*/[A-Z0-9-]*/[A-Z][a-z][a-z][0-9][0-9]/[0-9]*'
)
INSERT INTO [dbo].[__biz_id_map] ([entity],[tablePk],[oldId],[newId])
SELECT 'Member', id, memberId,
       CONCAT(branchCode, '/', UPPER(FORMAT(CAST(GETDATE() AS date), 'MMMyy')), '/', FORMAT(rn, '00005'))
FROM R;
UPDATE m SET m.[memberId] = x.[newId]
FROM [dbo].[Member] m JOIN [dbo].[__biz_id_map] x ON x.[entity]='Member' AND x.[tablePk] = m.[id];
GO

-- 2. Fees: {branchCode}/{MMMyy}/{00001}
;WITH R AS (
    SELECT f.[id], b.[code] AS branchCode, f.[feeNo],
           ROW_NUMBER() OVER (PARTITION BY b.[code], UPPER(FORMAT(f.[billingPeriodStart],'MMMyy'))
                              ORDER BY f.[billingPeriodStart], f.[createdAt]) AS rn
    FROM [dbo].[Fee] f JOIN [dbo].[Branch] b ON b.[id] = f.[branchId]
    WHERE f.[feeNo] IS NULL OR f.[feeNo] NOT LIKE '%/%'
)
INSERT INTO [dbo].[__biz_id_map] ([entity],[tablePk],[oldId],[newId])
SELECT 'Fee', id, ISNULL(feeNo,''),
       CONCAT(branchCode, '/', UPPER(FORMAT(CAST(GETDATE() AS date), 'MMMyy')), '/', FORMAT(rn, '00005'))
FROM R;
UPDATE f SET f.[feeNo] = x.[newId]
FROM [dbo].[Fee] f JOIN [dbo].[__biz_id_map] x ON x.[entity]='Fee' AND x.[tablePk] = f.[id];
GO

-- 3. Prospects: p-00001
;WITH R AS (
    SELECT [id], [prospectId], ROW_NUMBER() OVER (ORDER BY [inquiryDate], [createdAt]) AS rn
    FROM [dbo].[Prospect] WHERE [prospectId] NOT LIKE 'p-%'
)
INSERT INTO [dbo].[__biz_id_map] ([entity],[tablePk],[oldId],[newId])
SELECT 'Prospect', id, prospectId, CONCAT('p-', FORMAT(rn, '00005')) FROM R;
UPDATE p SET p.[prospectId] = x.[newId]
FROM [dbo].[Prospect] p JOIN [dbo].[__biz_id_map] x ON x.[entity]='Prospect' AND x.[tablePk] = p.[id];
GO

-- 4. Membership plans: MP-0001
;WITH R AS (
    SELECT [id], [code], ROW_NUMBER() OVER (ORDER BY [createdAt]) AS rn
    FROM [dbo].[MembershipPlan] WHERE [code] NOT LIKE 'MP-%'
)
INSERT INTO [dbo].[__biz_id_map] ([entity],[tablePk],[oldId],[newId])
SELECT 'MembershipPlan', id, code, CONCAT('MP-', FORMAT(rn, '0004')) FROM R;
UPDATE mp SET mp.[code] = x.[newId]
FROM [dbo].[MembershipPlan] mp JOIN [dbo].[__biz_id_map] x ON x.[entity]='MembershipPlan' AND x.[tablePk] = mp.[id];
GO

-- 5. Equipment: EQ-00001
;WITH R AS (
    SELECT [id], [code], ROW_NUMBER() OVER (ORDER BY [createdAt]) AS rn
    FROM [dbo].[Equipment] WHERE [code] IS NULL OR [code] NOT LIKE 'EQ-%'
)
INSERT INTO [dbo].[__biz_id_map] ([entity],[tablePk],[oldId],[newId])
SELECT 'Equipment', id, ISNULL(code,''), CONCAT('EQ-', FORMAT(rn, '00005')) FROM R;
UPDATE e SET e.[code] = x.[newId]
FROM [dbo].[Equipment] e JOIN [dbo].[__biz_id_map] x ON x.[entity]='Equipment' AND x.[tablePk] = e.[id];
GO

-- 6. Leaves: LV-0001 (rows created before 07 added leaveNo are handled in 07)
PRINT '=== 06 done ===';

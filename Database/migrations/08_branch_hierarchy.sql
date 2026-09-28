-- =====================================================================
-- Contoura Gym ERP — Migration 08 of 10
-- Branch File hierarchy: parentId + nodeType (Control | Detail).
-- Idempotent.
-- =====================================================================
SET NOCOUNT ON;
GO
PRINT '=== 08: branch hierarchy ===';

IF OBJECT_ID('dbo.Branch') IS NOT NULL
BEGIN
    IF COL_LENGTH('dbo.Branch','parentId') IS NULL
        ALTER TABLE [dbo].[Branch] ADD [parentId] NVARCHAR(50) NULL;
    IF COL_LENGTH('dbo.Branch','nodeType') IS NULL
        ALTER TABLE [dbo].[Branch] ADD [nodeType] NVARCHAR(255) NOT NULL CONSTRAINT DF_Branch_nodeType DEFAULT 'Detail';

    -- The first/oldest branch becomes the root Control node
    DECLARE @root NVARCHAR(50) = (SELECT TOP 1 [id] FROM [dbo].[Branch] ORDER BY [createdAt]);
    IF @root IS NOT NULL
        UPDATE [dbo].[Branch] SET [nodeType]='Control' WHERE [id]=@root AND [nodeType]='Detail';

    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name='FK_Branch_parent')
        ALTER TABLE [dbo].[Branch] ADD CONSTRAINT FK_Branch_parent
            FOREIGN KEY ([parentId]) REFERENCES [dbo].[Branch]([id]);
    PRINT '  branch hierarchy columns ready.';
END
GO
PRINT '=== 08 done ===';

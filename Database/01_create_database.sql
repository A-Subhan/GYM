-- ============================================================================
-- Contoura Gym Management System — STEP 1: Create the GymDB database
-- ============================================================================
-- Run this FIRST (order: 01 → 02 → 03 → 04 → 05 → 06 → 07)
-- Requires: SQL Server 2016+ (works on Express / Developer / Standard)
-- No SQLCMD mode needed — data/log files use the server's default locations.
-- ============================================================================

IF DB_ID(N'GymDB') IS NULL
BEGIN
    CREATE DATABASE [GymDB];
END
GO

ALTER DATABASE [GymDB] SET RECOVERY SIMPLE;
ALTER DATABASE [GymDB] SET AUTO_SHRINK OFF;
ALTER DATABASE [GymDB] SET ANSI_NULLS ON;
ALTER DATABASE [GymDB] SET QUOTED_IDENTIFIER ON;
ALTER DATABASE [GymDB] SET READ_COMMITTED_SNAPSHOT ON;   -- readers don't block writers
GO

USE [GymDB];
GO

PRINT 'Step 01 complete: GymDB database created.';
GO

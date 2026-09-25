# GymDB — SQL Server Database Backup

## Current Backup File

**Location:** `Database/GymDB.bak`
**Size:** 23,187,456 bytes (~22 MB)
**Format:** Microsoft SQL Server backup (NT backup archive, SQL Server format)
**Verified:** `file Database/GymDB.bak` reports `Microsoft SQL Server`

This is a genuine SQL Server backup file extracted from the original project archive (`upload/GYM.rar`).
It was created from the original `GymDB` SQL Server database used by the legacy Contoura Gym system.

## Environment Limitation

**SQL Server is NOT available in this Linux sandbox environment.**
- `sqlcmd` is not installed
- `mssql-tools` is not installed
- No Microsoft SQL Server engine is running

Therefore, a fresh `BACKUP DATABASE` operation cannot be executed in this environment.
The existing `GymDB.bak` file (a real SQL Server backup from the original project) is provided instead.

## How to Generate a Fresh Backup (Windows + SQL Server)

If you have a Windows machine with SQL Server installed, follow these exact steps to generate a fresh `GymDB.bak` from the current schema and data:

### Option A: Using SQL Server Management Studio (SSMS)

1. Open SQL Server Management Studio
2. Connect to your SQL Server instance
3. Create or restore the `GymDB` database:
   ```sql
   CREATE DATABASE GymDB;
   ```
4. Run the schema scripts from `extracted/GYM/Backend-Software/GYM-software/sql/` in order:
   - `01_schema.sql`
   - `02_procedures.sql`
   - `03_triggers.sql`
   - `04_seed.sql`
   - `05_sample.sql` (optional sample data)
   - `06_phase8_procedures.sql` through `16_vouchers_upgrade.sql`
5. Right-click the `GymDB` database → Tasks → Back Up...
6. Set Backup type: Full
7. Set Destination: Disk → `C:\GYM\Database\GymDB.bak`
8. Click OK to create the backup

### Option B: Using T-SQL Commands

Open a New Query window in SSMS (or run via `sqlcmd`) and execute:

```sql
-- Step 1: Create the database
CREATE DATABASE GymDB;
GO

-- Step 2: Switch to the database
USE GymDB;
GO

-- Step 3: Run schema scripts (01_schema.sql through 16_vouchers_upgrade.sql)
-- Execute each script file in order

-- Step 4: Backup the database
BACKUP DATABASE GymDB
TO DISK = 'C:\GYM\Database\GymDB.bak'
WITH FORMAT,
     NAME = 'GymDB Full Backup',
     SKIP,
     NOREWIND,
     NOUNLOAD,
     STATS = 10;
GO
```

### Option C: Using sqlcmd Command Line

```cmd
:: Step 1: Create the database
sqlcmd -S localhost -E -Q "CREATE DATABASE GymDB"

:: Step 2: Run schema scripts
sqlcmd -S localhost -E -d GymDB -i "01_schema.sql"
sqlcmd -S localhost -E -d GymDB -i "02_procedures.sql"
sqlcmd -S localhost -E -d GymDB -i "03_triggers.sql"
sqlcmd -S localhost -E -d GymDB -i "04_seed.sql"
:: ... continue for all SQL scripts

:: Step 3: Backup the database
sqlcmd -S localhost -E -Q "BACKUP DATABASE GymDB TO DISK = 'C:\GYM\Database\GymDB.bak' WITH FORMAT, NAME = 'GymDB Full Backup'"

:: Step 4: Verify the backup
sqlcmd -S localhost -E -Q "RESTORE VERIFYONLY FROM DISK = 'C:\GYM\Database\GymDB.bak'"
```

### Verifying the Backup

To verify that the backup file is valid and restorable:

```sql
RESTORE VERIFYONLY FROM DISK = 'C:\GYM\Database\GymDB.bak';
```

Expected output:
```
The backup set on file 1 is valid.
```

### Restoring the Backup

To restore the database from the backup:

```sql
RESTORE DATABASE GymDB
FROM DISK = 'C:\GYM\Database\GymDB.bak'
WITH MOVE 'GymDB' TO 'C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA\GymDB.mdf',
     MOVE 'GymDB_Log' TO 'C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA\GymDB_log.ldf',
     REPLACE;
```

## Project Structure

The original project structure is:
```
D:\GYM\
├── Frontend\    (React/Vite app — in this repo: extracted/GYM/Contoura_Labs_Gym/)
├── Backend\     (Express API — in this repo: extracted/GYM/Backend-Software/GYM-software/)
└── Database\    (SQL Server database and backups — in this repo: Database/)
    └── GymDB.bak  (SQL Server backup file)
```

The current implementation is a Next.js full-stack rewrite that uses SQLite internally for development,
but the original SQL Server backup is preserved in `Database/GymDB.bak` for production deployment.

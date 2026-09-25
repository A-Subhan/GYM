# GymDB — Database Setup

## Architecture

This project supports **two database backends**:

| Environment | Provider | Schema File | Purpose |
|---|---|---|---|
| Development | SQLite | `prisma/schema.prisma` | Fast local dev, no SQL Server required |
| Production | SQL Server | `prisma/schema-sqlserver.prisma` | Real GymDB on Microsoft SQL Server |

The Prisma schemas are identical in models/relations. Only the `datasource.provider` differs:
- `schema.prisma` → `provider = "sqlite"`
- `schema-sqlserver.prisma` → `provider = "sqlserver"`

## Switching to SQL Server (Production)

1. Set the connection string in `.env`:
   ```
   DATABASE_URL="sqlserver://localhost:1433;database=GymDB;user=sa;password=YourPassword;encrypt=true;trustServerCertificate=true"
   ```
2. Copy the SQL Server schema to the active schema:
   ```bash
   cp prisma/schema-sqlserver.prisma prisma/schema.prisma
   ```
3. Push the schema to SQL Server:
   ```bash
   bun run db:push
   bun run db:generate
   ```
4. Seed initial data:
   ```bash
   bun run scripts/seed.ts
   ```

## Files

```
Database/
├── GymDB.bak          # Real SQL Server backup (23 MB, Microsoft SQL Server format)
├── README.md          # This file
└── sql/               # Original SQL Server schema scripts (for manual setup)
    ├── 01_schema.sql
    ├── 02_procedures.sql
    ├── 03_triggers.sql
    ├── 04_seed.sql
    ├── 05_sample.sql
    ├── 06_phase8_procedures.sql
    ├── 07_fixes.sql
    ├── 08_phase9_changes.sql
    ├── 09_master_files_staff_code.sql
    ├── 10_master_files_module.sql
    ├── 11_finance_schema.sql
    ├── 12_finance_procedures.sql
    ├── 13_finance_permissions_defaults.sql
    ├── 14_finance_rework.sql
    ├── 15_coa_enhancement.sql
    └── 16_vouchers_upgrade.sql
```

## GymDB.bak — Real SQL Server Backup

**File:** `Database/GymDB.bak`
**Size:** 23,187,456 bytes (~22 MB)
**Format:** Microsoft SQL Server backup (verified via `file` command — `Microsoft SQL Server`)

This is a genuine SQL Server backup extracted from the original Contoura Gym project archive.

### SQL Server Availability in This Environment

**SQL Server is NOT installed in this Linux sandbox.**
- `sqlcmd` is not available
- `mssql-tools` is not installed
- No SQL Server engine is running

Therefore, a fresh `BACKUP DATABASE` command cannot be executed here.
The existing `GymDB.bak` (a real SQL Server backup from the original project) is provided.

### Generating a Fresh Backup on Windows + SQL Server

#### Option A: SQL Server Management Studio (SSMS)

1. Open SSMS → connect to your SQL Server instance
2. Create or restore `GymDB`:
   ```sql
   CREATE DATABASE GymDB;
   ```
3. Run the schema scripts from `Database/sql/` in order (01 through 16)
4. Right-click `GymDB` → Tasks → Back Up...
5. Set Backup type: **Full**, Destination: **Disk** → `C:\GYM\Database\GymDB.bak`
6. Click OK

#### Option B: T-SQL Commands

```sql
-- Create database
CREATE DATABASE GymDB;
GO
USE GymDB;
GO

-- Run all schema scripts (01_schema.sql through 16_vouchers_upgrade.sql)

-- Backup
BACKUP DATABASE GymDB
TO DISK = 'C:\GYM\Database\GymDB.bak'
WITH FORMAT,
     NAME = 'GymDB Full Backup',
     STATS = 10;
GO
```

#### Option C: sqlcmd Command Line

```cmd
sqlcmd -S localhost -E -Q "CREATE DATABASE GymDB"
sqlcmd -S localhost -E -d GymDB -i "Database\sql\01_schema.sql"
sqlcmd -S localhost -E -d GymDB -i "Database\sql\02_procedures.sql"
:: ... continue for all 16 scripts
sqlcmd -S localhost -E -Q "BACKUP DATABASE GymDB TO DISK = 'C:\GYM\Database\GymDB.bak' WITH FORMAT, NAME = 'GymDB Full Backup'"
```

### Verifying the Backup

```sql
RESTORE VERIFYONLY FROM DISK = 'C:\GYM\Database\GymDB.bak';
```
Expected: `The backup set on file 1 is valid.`

### Restoring the Backup

```sql
RESTORE DATABASE GymDB
FROM DISK = 'C:\GYM\Database\GymDB.bak'
WITH MOVE 'GymDB' TO 'C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA\GymDB.mdf',
     MOVE 'GymDB_Log' TO 'C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA\GymDB_log.ldf',
     REPLACE;
```

## Project Structure (Local)

The original project structure on Windows is:
```
D:\GYM\
├── Frontend\    (Vite/React — original UI)
├── Backend\     (Express/Node — original API)
└── Database\    (SQL Server database and backups)
    └── GymDB.bak
```

In this repo, the project has been rewritten as a single Next.js fullstack app at the root
(frontend + backend in one app). The `Database/` folder preserves the SQL Server backup
and schema scripts. See the repo root README for the full project layout.
